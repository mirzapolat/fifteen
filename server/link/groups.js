// Groups of linked Fifteen devices, kept in memory. No timer logic lives here: devices send the
// timer's new state together with the revision they based it on, and the first update for a
// revision wins. Later ones are turned away and their sender adopts what won.
import { randomInt, randomBytes, createHmac, timingSafeEqual } from 'node:crypto';

export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I or O
export const CODE_LENGTH = 6;
export const MAX_MEMBERS = 8;
/** A group with nobody connected is forgotten after this long. */
export const ABANDONED_AFTER_MS = 12 * 60 * 60 * 1000;

const PHASES = new Set(['focus', 'shortBreak', 'longBreak']);
const STATES = new Set(['idle', 'running', 'paused', 'finished']);
const MODES = new Set(['pomodoro', 'flowtime']);
const MAX_SECONDS = 13 * 60 * 60;

/** Trims a device name to something sensible to show others. */
export function cleanName(name) {
  const text = typeof name === 'string' ? name.replace(/\s+/g, ' ').trim().slice(0, 40) : '';
  return text || 'A device';
}

/** "kqx-mrt" → "KQXMRT"; anything that can't be a code → null. */
export function normalizeCode(code) {
  if (typeof code !== 'string') return null;
  const letters = code.toUpperCase().replace(/[^A-Z]/g, '');
  if (letters.length !== CODE_LENGTH) return null;
  for (const c of letters) if (!CODE_ALPHABET.includes(c)) return null;
  return letters;
}

const isNumber = (v, max = MAX_SECONDS) => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= max;
const isTime = (v) => v === null || v === undefined || (typeof v === 'number' && Number.isFinite(v) && v > 0);

/** The shared timer: only these fields, checked, so nothing else can ride along. */
export function cleanTimer(timer) {
  if (!timer || typeof timer !== 'object') return null;
  const { phase, mode, state, total, endsAt, pausedRemaining, startedAt } = timer;
  if (!PHASES.has(phase) || !STATES.has(state) || !MODES.has(mode) || !isNumber(total)) return null;
  if (!isTime(endsAt) || !isTime(startedAt)) return null;
  if (pausedRemaining !== null && pausedRemaining !== undefined && !isNumber(pausedRemaining)) return null;
  return {
    phase, mode, state, total,
    endsAt: endsAt ?? null,
    pausedRemaining: pausedRemaining ?? null,
    startedAt: startedAt ?? null,
  };
}

export class Registry {
  /** `secret` signs group tickets. Keep it the same across restarts (LINK_SECRET) so members can
   *  bring a forgotten group back under its old code. */
  constructor({ now = () => Date.now(), secret = randomBytes(32) } = {}) {
    this.now = now;
    this.secret = secret;
    /** code → group */
    this.groups = new Map();
    /** member token → { code, memberId } */
    this.tokens = new Map();
  }

  newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
      if (!this.groups.has(code)) return code;
    }
  }

  addMember(group, name) {
    const member = {
      id: randomBytes(8).toString('hex'),
      token: randomBytes(24).toString('base64url'),
      name: cleanName(name),
      online: true,
      lastSeen: this.now(),
    };
    group.members.set(member.id, member);
    this.tokens.set(member.token, { code: group.code, memberId: member.id });
    return member;
  }

  /** Proof, handed to members, that a code was really theirs. */
  ticket(code) {
    return createHmac('sha256', this.secret).update(`group:${code}`).digest('base64url');
  }

  ownsCode(code, ticket) {
    if (!code || typeof ticket !== 'string') return false;
    const expected = Buffer.from(this.ticket(code));
    const given = Buffer.from(ticket);
    return given.length === expected.length && timingSafeEqual(given, expected);
  }

  /** Starts a group around the creator's current timer. A member of a group the server forgot
   *  (after a restart) can bring it back under the code everyone knows, but only with that
   *  group's ticket; otherwise the answer would reveal which codes are in use. */
  create({ name, timer, preferredCode, ticket }) {
    const clean = cleanTimer(timer);
    if (!clean) return { error: 'badTimer' };
    const wanted = normalizeCode(preferredCode);
    const code = wanted && this.ownsCode(wanted, ticket) && !this.groups.has(wanted) ? wanted : this.newCode();
    const group = { code, revision: 1, timer: clean, members: new Map(), lastActive: this.now() };
    this.groups.set(code, group);
    const member = this.addMember(group, name);
    return { group, member };
  }

  join(code, name) {
    const key = normalizeCode(code);
    const group = key && this.groups.get(key);
    if (!group) return { error: 'noSuchCode' };
    if (group.members.size >= MAX_MEMBERS) return { error: 'full' };
    const member = this.addMember(group, name);
    group.lastActive = this.now();
    return { group, member };
  }

  /** Back in after sleep or a lost connection. */
  resume(token, name) {
    const ref = typeof token === 'string' && this.tokens.get(token);
    const group = ref && this.groups.get(ref.code);
    const member = group && group.members.get(ref.memberId);
    if (!member) return { error: 'groupGone' };
    if (name) member.name = cleanName(name);
    member.online = true;
    member.lastSeen = this.now();
    return { group, member };
  }

  /** First update for a revision wins. */
  update(group, member, { timer, basedOn }) {
    const clean = cleanTimer(timer);
    if (!clean) return { accepted: false, error: 'badTimer' };
    if (basedOn !== group.revision) return { accepted: false };
    group.timer = clean;
    group.revision += 1;
    group.lastActive = this.now();
    member.lastSeen = this.now();
    return { accepted: true };
  }

  rename(member, name) {
    member.name = cleanName(name);
  }

  setOnline(group, member, online) {
    member.online = online;
    member.lastSeen = this.now();
    group.lastActive = this.now();
  }

  leave(group, member) {
    group.members.delete(member.id);
    this.tokens.delete(member.token);
    if (group.members.size === 0) this.groups.delete(group.code);
  }

  members(group) {
    return [...group.members.values()].map(({ id, name, online }) => ({ id, name, online }));
  }

  /** Forgets groups nobody has been connected to for a long time. */
  sweep() {
    const cutoff = this.now() - ABANDONED_AFTER_MS;
    for (const group of this.groups.values()) {
      const anyoneHere = [...group.members.values()].some((m) => m.online);
      if (!anyoneHere && group.lastActive < cutoff) {
        for (const m of group.members.values()) this.tokens.delete(m.token);
        this.groups.delete(group.code);
      }
    }
  }
}
