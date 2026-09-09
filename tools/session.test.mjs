import { test } from "node:test";
import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";

globalThis.window = {};
const { MatchSession, ABSENCE_MS, reconcile } = await import("../js/session.js");
// WebCrypto completes on a native worker, not only the JS microtask queue.
const flush = async () => { for (let i = 0; i < 20; i++) await delay(1); };

class Wire extends EventTarget {
  constructor(role) { super(); this.role = role; this.map = 0; this.connected = true; this.sent = []; }
  saveGame(value) { this.saved = structuredClone(value); }
  send(msg) {
    this.sent.push(structuredClone(msg));
    if (!this.connected || !this.peer?.connected || this.filter?.(msg) === false) return false;
    const target = this.peer;
    queueMicrotask(() => {
      if (this.connected && target.connected) target.dispatchEvent(new CustomEvent("message", { detail: structuredClone(msg) }));
    });
    return true;
  }
  reconnect() { this.connected = false; this.session.pause(); }
  close() { this.closed = true; this.connected = false; }
}

async function pair(t) {
  t.mock.timers.enable({ apis: ["Date", "setInterval"], now: 1_000_000 });
  const host = new Wire("host"), guest = new Wire("guest");
  host.peer = guest; guest.peer = host;
  host.session = new MatchSession(host);
  guest.session = new MatchSession(guest);
  t.after(() => { host.session.dispose(); guest.session.dispose(); });
  host.session.connected(); guest.session.connected();
  await flush();
  assert.equal(host.session.phase, "decide");
  assert.equal(guest.session.phase, "decide");
  return { host, guest };
}

function disconnect(host, guest) {
  host.connected = guest.connected = false;
  host.session.pause(); guest.session.pause();
}

async function connect(host, guest) {
  host.connected = guest.connected = true;
  host.session.connected(); guest.session.connected();
  await flush();
}

test("a lost connection freezes both clock and private choice; resume uses the remaining window", async t => {
  const { host, guest } = await pair(t);
  host.session.choose({ platform: 0, dir: 1 });
  t.mock.timers.tick(7000);
  disconnect(host, guest);
  const saved = host.saved;
  t.mock.timers.tick(120_000);
  assert.equal(host.session.match.tick, 0);
  assert.equal(host.session.remaining(), 23_000);
  assert.deepEqual(host.session.round.selection, { platform: 0, dir: 1 });
  await connect(host, guest);
  assert.equal(host.session.remaining(), 23_000);
  assert.equal(guest.session.remaining(), 23_000);
  assert.equal(host.session.pausedAt, null);
  assert.deepEqual(saved.round.selection, host.session.round.selection);
  for (const msg of host.sent.filter(m => m.type.startsWith("sync"))) {
    assert.equal(JSON.stringify(msg).includes("selection"), false, "sync cannot reveal a private move");
  }
});

for (const role of ["host", "guest", "both"]) {
  test(`refresh of ${role} restores the same board, role, choice and timer`, async t => {
    const { host, guest } = await pair(t);
    t.mock.timers.tick(30_000);
    await flush();
    assert.equal(host.session.match.tick, 1);
    assert.equal(host.session.phase, "decide", JSON.stringify(host.sent.map(m => [m.type, m.state?.log?.length])));
    assert.equal(guest.session.phase, "decide");
    host.session.choose({ platform: 2, dir: -1 });
    guest.session.choose({ platform: 4, dir: 1 });
    t.mock.timers.tick(5000);
    disconnect(host, guest);
    const before = structuredClone(host.session.match);
    for (const wire of [host, guest]) {
      if (role !== "both" && role !== wire.role) continue;
      wire.session.dispose();
      wire.session = new MatchSession(wire, { saved: wire.saved });
    }
    t.mock.timers.tick(45_000);
    await connect(host, guest);
    assert.deepEqual(host.session.match, before);
    assert.deepEqual(guest.session.match, before);
    assert.equal(host.session.side, "bottom");
    assert.equal(guest.session.side, "top");
    assert.equal(host.session.remaining(), 25_000);
    assert.equal(guest.session.remaining(), 25_000);
    t.mock.timers.tick(25_000);
    await flush();
    assert.equal(host.session.match.tick, 2);
    assert.deepEqual(host.session.match, guest.session.match);
    assert.deepEqual(host.session.match.log[1].commands, { top: { platform: 4, dir: 1 }, bottom: { platform: 2, dir: -1 } });
  });
}

test("a refresh after commit keeps the same salt and cannot change the locked move", async t => {
  const { host, guest } = await pair(t);
  host.filter = guest.filter = msg => msg.type !== "reveal";
  host.session.choose({ platform: 1, dir: 1 });
  t.mock.timers.tick(30_000);
  await flush();
  assert.equal(host.session.phase, "exchange");
  const hash = host.session.round.hash, salt = host.session.round.salt;
  disconnect(host, guest);
  host.session.dispose();
  host.session = new MatchSession(host, { saved: host.saved });
  host.session.choose({ platform: 2, dir: -1 });
  host.filter = guest.filter = null;
  await connect(host, guest);
  assert.equal(host.session.match.tick, 1);
  assert.deepEqual(host.session.match, guest.session.match);
  assert.equal(host.session.proofs[0].bottom.hash, hash);
  assert.equal(host.session.proofs[0].bottom.salt, salt);
});

test("one peer resolved before disconnect: replay the committed result once, never drop or double a move", async t => {
  const { host, guest } = await pair(t);
  host.filter = msg => msg.type !== "reveal";
  host.session.choose({ platform: 0, dir: 1 });
  guest.session.choose({ platform: 0, dir: 1 });
  t.mock.timers.tick(30_000);
  await flush();
  assert.equal(host.session.match.tick, 1);
  assert.equal(guest.session.match.tick, 0);
  disconnect(host, guest);
  // Both tabs reload, including the one which has already persisted the result.
  for (const wire of [host, guest]) {
    wire.session.dispose();
    wire.session = new MatchSession(wire, { saved: wire.saved });
  }
  host.filter = null;
  await connect(host, guest);
  assert.equal(host.session.match.tick, 1);
  assert.equal(guest.session.match.tick, 1);
  assert.deepEqual(host.session.match, guest.session.match);
  assert.equal(host.session.match.log[0].rotations[0].quarters, 2);
  assert.equal(guest.session.remaining(), 30_000);
});

test("exchange timeout pauses instead of resolving a null opponent command", async t => {
  const { host, guest } = await pair(t);
  host.filter = guest.filter = msg => !["commit", "reveal"].includes(msg.type);
  t.mock.timers.tick(30_000);
  await flush();
  t.mock.timers.tick(6500);
  assert.equal(host.session.phase, "paused");
  assert.equal(guest.session.phase, "paused");
  assert.equal(host.session.match.tick, 0);
});

test("the 30-minute absence deadline survives reload, then ends the match", async t => {
  const { host, guest } = await pair(t);
  disconnect(host, guest);
  const since = host.session.pausedAt;
  t.mock.timers.tick(29 * 60_000);
  host.session.dispose();
  host.session = new MatchSession(host, { saved: host.saved });
  assert.equal(host.session.pausedAt, since);
  t.mock.timers.tick(59_750);
  assert.equal(host.session.ended, false);
  t.mock.timers.tick(250);
  assert.match(host.session.ended, /30 минут/);
  assert.equal(host.closed, true);
});

test("conflicting remote history is rejected", async t => {
  const { host, guest } = await pair(t);
  t.mock.timers.tick(30_000);
  await flush();
  const invalid = structuredClone(guest.session.publicState());
  invalid.log[0].score.top = 999;
  await assert.rejects(reconcile(host.session.snapshot(), invalid, "bottom"), /Conflicting/);
});

test("all 30 rounds pass the ready barrier and end with identical state", async t => {
  const { host, guest } = await pair(t);
  for (let tick = 1; tick <= 30; tick++) {
    t.mock.timers.tick(30_000);
    await flush();
    assert.equal(host.session.match.tick, tick);
    assert.deepEqual(host.session.match, guest.session.match);
    if (tick < 30) assert.equal(host.session.phase, "decide");
  }
  assert.equal(host.session.ended, true);
  assert.equal(guest.session.ended, true);
});
