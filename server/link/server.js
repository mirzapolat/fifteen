// Fifteen Link relay: WebSocket in, WebSocket out. One JSON message per frame.
//
// → hello  { protocol, name, token? }      ← welcome { serverTime }, then joined | error
// → ping   { t }                           ← pong { t, serverTime }
// → create { timer, preferredCode?, ticket? } ← joined { code, ticket, memberId, token, revision, timer, members }
// → join   { code }                        ← joined …          | error { code: noSuchCode | full | rateLimited }
// → update { timer, basedOn, action }      ← state { revision, timer, by: { id, name }, action }  (to everyone)
//                                           ← state { revision, timer, rejected: true }           (to the sender)
// → rename { name }                        ← members { members }  (to everyone)
// → leave  {}                              ← left {}
//
// Times inside `timer` are Unix seconds on the server's clock; clients convert with `serverTime`.
import http from 'node:http';
import { WebSocketServer } from 'ws';
import { Registry, cleanName } from './groups.js';

export const PROTOCOL = 1;
const PORT = Number(process.env.PORT ?? 8787);
const JOIN_ATTEMPTS = 10;          // wrong codes allowed per address…
const JOIN_WINDOW_MS = 10 * 60e3;  // …in this window
const CREATE_ATTEMPTS = 20;        // new groups allowed per address in the same window

export function startServer({ port = PORT, registry = new Registry(registryOptions()) } = {}) {
  /** code → (memberId → socket) */
  const sockets = new Map();
  /** address → [times of failed joins] */
  const failedJoins = new Map();
  /** address → [times of created groups] */
  const creates = new Map();

  const send = (ws, message) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
  };
  const serverTime = () => Date.now() / 1000;

  const broadcast = (group, message) => {
    for (const ws of sockets.get(group.code)?.values() ?? []) send(ws, message);
  };
  const broadcastMembers = (group) => broadcast(group, { type: 'members', members: registry.members(group) });

  const attach = (ws, group, member) => {
    detach(ws);
    let room = sockets.get(group.code);
    if (!room) sockets.set(group.code, (room = new Map()));
    // The same device connecting twice (a quick reconnect): the newer connection wins.
    const older = room.get(member.id);
    if (older && older !== ws) { older.ctx.group = null; older.ctx.member = null; older.close(4000, 'replaced'); }
    room.set(member.id, ws);
    ws.ctx.group = group;
    ws.ctx.member = member;
    registry.setOnline(group, member, true);
    send(ws, {
      type: 'joined', code: group.code, ticket: registry.ticket(group.code), memberId: member.id, token: member.token,
      revision: group.revision, timer: group.timer, members: registry.members(group),
    });
    broadcastMembers(group);
  };

  function detach(ws, { leaving = false } = {}) {
    const { group, member } = ws.ctx;
    if (!group || !member) return;
    ws.ctx.group = null;
    ws.ctx.member = null;
    const room = sockets.get(group.code);
    if (room?.get(member.id) === ws) room.delete(member.id);
    if (room && room.size === 0) sockets.delete(group.code);
    if (leaving) registry.leave(group, member); else registry.setOnline(group, member, false);
    if (registry.groups.has(group.code)) broadcastMembers(group);
  }

  const recent = (log, address) => {
    const times = (log.get(address) ?? []).filter((t) => Date.now() - t < JOIN_WINDOW_MS);
    log.set(address, times);
    return times;
  };

  const handle = (ws, message) => {
    const { group, member } = ws.ctx;
    switch (message.type) {
      case 'hello': {
        if (message.protocol !== PROTOCOL) return send(ws, { type: 'error', code: 'protocol' });
        ws.ctx.name = cleanName(message.name);
        ws.ctx.hello = true;
        send(ws, { type: 'welcome', serverTime: serverTime() });
        if (message.token) {
          const result = registry.resume(message.token, ws.ctx.name);
          if (result.error) return send(ws, { type: 'error', code: result.error });
          attach(ws, result.group, result.member);
        }
        return;
      }
      case 'ping':
        return send(ws, { type: 'pong', t: message.t, serverTime: serverTime() });
    }
    if (!ws.ctx.hello) return send(ws, { type: 'error', code: 'protocol' });

    switch (message.type) {
      case 'create': {
        const made = recent(creates, ws.ctx.address);
        if (made.length >= CREATE_ATTEMPTS) return send(ws, { type: 'error', code: 'rateLimited' });
        made.push(Date.now());
        detach(ws, { leaving: true });
        const result = registry.create({
          name: ws.ctx.name, timer: message.timer, preferredCode: message.preferredCode, ticket: message.ticket,
        });
        if (result.error) return send(ws, { type: 'error', code: result.error });
        return attach(ws, result.group, result.member);
      }
      case 'join': {
        const failures = recent(failedJoins, ws.ctx.address);
        if (failures.length >= JOIN_ATTEMPTS) return send(ws, { type: 'error', code: 'rateLimited' });
        const result = registry.join(message.code, ws.ctx.name);
        if (result.error) {
          if (result.error === 'noSuchCode') failures.push(Date.now());
          return send(ws, { type: 'error', code: result.error });
        }
        detach(ws, { leaving: true });
        return attach(ws, result.group, result.member);
      }
      case 'update': {
        if (!group) return send(ws, { type: 'error', code: 'notLinked' });
        const result = registry.update(group, member, message);
        if (result.error) return send(ws, { type: 'error', code: result.error });
        if (!result.accepted) {
          return send(ws, { type: 'state', revision: group.revision, timer: group.timer, rejected: true });
        }
        const action = typeof message.action === 'string' ? message.action.slice(0, 60) : '';
        return broadcast(group, {
          type: 'state', revision: group.revision, timer: group.timer,
          by: { id: member.id, name: member.name }, action,
        });
      }
      case 'rename': {
        ws.ctx.name = cleanName(message.name);
        if (!group) return;
        registry.rename(member, message.name);
        return broadcastMembers(group);
      }
      case 'leave': {
        detach(ws, { leaving: true });
        return send(ws, { type: 'left' });
      }
      default:
        return send(ws, { type: 'error', code: 'unknown' });
    }
  };

  const server = http.createServer((req, res) => {
    if (req.url === '/health') { res.writeHead(200).end('ok'); return; }
    res.writeHead(404).end();
  });
  const wss = new WebSocketServer({ server, maxPayload: 8 * 1024 });

  wss.on('connection', (ws, req) => {
    const forwarded = req.headers['x-forwarded-for'];
    ws.ctx = {
      address: (typeof forwarded === 'string' && forwarded.split(',')[0].trim()) || req.socket.remoteAddress,
      hello: false, name: 'A device', group: null, member: null,
    };
    ws.alive = true;
    ws.on('pong', () => { ws.alive = true; });
    ws.on('message', (data) => {
      let message;
      try { message = JSON.parse(data.toString()); } catch { return send(ws, { type: 'error', code: 'badJSON' }); }
      if (message && typeof message === 'object') handle(ws, message);
    });
    ws.on('close', () => detach(ws));
  });

  // Drop connections that stopped answering, and forget long-abandoned groups.
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) { ws.terminate(); continue; }
      ws.alive = false;
      ws.ping();
    }
    registry.sweep();
  }, 30_000);

  return new Promise((resolve) => {
    server.listen(port, () => {
      resolve({
        port: server.address().port,
        close: () => new Promise((done) => {
          clearInterval(heartbeat);
          for (const ws of wss.clients) ws.terminate();
          wss.close();
          server.close(() => done());
        }),
      });
    });
  });
}

function registryOptions() {
  const secret = process.env.LINK_SECRET;
  if (!secret) console.warn('LINK_SECRET is not set: forgotten groups get new codes after a restart.');
  return secret ? { secret } : {};
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { port } = await startServer();
  console.log(`Fifteen Link listening on :${port}`);
}
