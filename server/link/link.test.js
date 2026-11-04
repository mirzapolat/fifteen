import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { Registry, normalizeCode, cleanTimer, MAX_MEMBERS, ABANDONED_AFTER_MS } from './groups.js';
import { startServer } from './server.js';

const idle = { phase: 'focus', mode: 'pomodoro', state: 'idle', total: 1500, endsAt: null, pausedRemaining: null, startedAt: null };
const running = { ...idle, state: 'running', endsAt: 2_000_000_000, startedAt: 1_999_998_500 };

test('codes are six letters without I or O', () => {
  const registry = new Registry();
  const { group } = registry.create({ name: 'A', timer: idle });
  assert.match(group.code, /^[A-HJ-NP-Z]{6}$/);
  assert.equal(normalizeCode('kqx-mrt'), 'KQXMRT');
  assert.equal(normalizeCode('KQXMRO'), null);
  assert.equal(normalizeCode('KQX'), null);
});

test('only the timer fields are kept', () => {
  const clean = cleanTimer({ ...idle, intention: 'secret', rating: 5, projectID: 'x' });
  assert.deepEqual(Object.keys(clean).sort(), ['endsAt', 'mode', 'pausedRemaining', 'phase', 'startedAt', 'state', 'total']);
  assert.equal(cleanTimer({ ...idle, phase: 'nap' }), null);
  assert.equal(cleanTimer({ ...idle, total: -1 }), null);
});

test('the first update for a revision wins', () => {
  const registry = new Registry();
  const { group, member: john } = registry.create({ name: 'John', timer: idle });
  const { member: mira } = registry.join(group.code, 'Mira');
  assert.equal(registry.update(group, mira, { timer: running, basedOn: 1 }).accepted, true);
  assert.equal(registry.update(group, john, { timer: { ...idle, total: 600 }, basedOn: 1 }).accepted, false);
  assert.equal(group.timer.state, 'running');
  assert.equal(group.revision, 2);
});

test('the code lasts as long as the group', () => {
  const registry = new Registry();
  const { group, member: john } = registry.create({ name: 'John', timer: idle });
  const { member: mira } = registry.join(group.code, 'Mira');
  registry.leave(group, john);
  const { member: ana } = registry.join(group.code, 'Ana');
  assert.ok(ana, 'still joinable while Mira is in');
  registry.leave(group, mira);
  registry.leave(group, ana);
  assert.equal(registry.join(group.code, 'Late').error, 'noSuchCode');
});

test('groups are full at eight', () => {
  const registry = new Registry();
  const { group } = registry.create({ name: '1', timer: idle });
  for (let i = 2; i <= MAX_MEMBERS; i++) assert.ok(registry.join(group.code, `${i}`).member);
  assert.equal(registry.join(group.code, 'nine').error, 'full');
});

test('tokens bring a device back; abandoned groups are forgotten', () => {
  let now = 0;
  const registry = new Registry({ now: () => now });
  const { group, member } = registry.create({ name: 'John', timer: idle });
  registry.setOnline(group, member, false);
  assert.equal(registry.resume(member.token).member.id, member.id);
  registry.setOnline(group, member, false);
  now = ABANDONED_AFTER_MS + 1;
  registry.sweep();
  assert.equal(registry.resume(member.token).error, 'groupGone');
});

test('a forgotten group comes back under its old code, with its ticket', () => {
  const before = new Registry({ secret: 'same' });
  const ticket = before.ticket('KQXMRT');
  const after = new Registry({ secret: 'same' }); // a restart
  const { group } = after.create({ name: 'John', timer: idle, preferredCode: 'KQXMRT', ticket });
  assert.equal(group.code, 'KQXMRT');
});

test('without the ticket, create never reveals whether a code is taken', () => {
  const registry = new Registry();
  const { group } = registry.create({ name: 'Mira', timer: idle });
  const free = registry.create({ name: 'Eve', timer: idle, preferredCode: 'KQXMRT' }).group.code;
  const taken = registry.create({ name: 'Eve', timer: idle, preferredCode: group.code }).group.code;
  assert.notEqual(free, 'KQXMRT');
  assert.notEqual(taken, group.code);
  const forged = registry.create({ name: 'Eve', timer: idle, preferredCode: 'ABCDEF', ticket: 'x'.repeat(43) });
  assert.notEqual(forged.group.code, 'ABCDEF');
});

// End to end: two devices over real WebSockets.
function client(port) {
  const ws = new WebSocket(`ws://localhost:${port}`);
  const inbox = [];
  const waiters = [];
  ws.on('message', (data) => {
    const message = JSON.parse(data.toString());
    const i = waiters.findIndex((w) => w.type === message.type);
    if (i >= 0) waiters.splice(i, 1)[0].resolve(message); else inbox.push(message);
  });
  return {
    open: new Promise((r) => ws.on('open', r)),
    send: (m) => ws.send(JSON.stringify(m)),
    next: (type) => {
      const i = inbox.findIndex((m) => m.type === type);
      if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve) => waiters.push({ type, resolve }));
    },
    close: () => ws.close(),
  };
}

test('two devices stay in step', async () => {
  const server = await startServer({ port: 0 });
  const john = client(server.port);
  const mira = client(server.port);
  await Promise.all([john.open, mira.open]);

  john.send({ type: 'hello', protocol: 1, name: "John's Mac" });
  await john.next('welcome');
  john.send({ type: 'create', timer: idle });
  const created = await john.next('joined');

  mira.send({ type: 'hello', protocol: 1, name: "Mira's MacBook" });
  await mira.next('welcome');
  mira.send({ type: 'join', code: created.code.toLowerCase() });
  const joined = await mira.next('joined');
  assert.equal(joined.revision, 1);
  assert.deepEqual(joined.members.map((m) => m.name).sort(), ["John's Mac", "Mira's MacBook"]);

  // Mira starts; John hears about it, with who did it.
  mira.send({ type: 'update', timer: running, basedOn: 1, action: 'started focus' });
  const seen = await john.next('state');
  assert.equal(seen.timer.state, 'running');
  assert.equal(seen.by.name, "Mira's MacBook");
  assert.equal(seen.action, 'started focus');
  await mira.next('state'); // her own echo

  // John, a moment too late on the old revision, is turned away and gets the winner.
  john.send({ type: 'update', timer: { ...idle, total: 600 }, basedOn: 1, action: 'set 10 min' });
  const rejected = await john.next('state');
  assert.equal(rejected.rejected, true);
  assert.equal(rejected.timer.state, 'running');

  john.close();
  mira.close();
  await server.close();
});
