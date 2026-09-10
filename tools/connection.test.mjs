// Transport-level tests for the peer connection. The menu and match flow it
// feeds now lives in Vue components and composables, covered by src/**/*.test.ts.
import { test } from "node:test";
import assert from "node:assert/strict";

globalThis.window = { location: { pathname: "/", href: "https://example.test/" } };
const { Connection, codeFromLocation } = await import("../js/net.js");

class Channel {
  constructor(state = "connecting") {
    this.readyState = state;
  }
  close() {
    this.readyState = "closed";
    this.onclose?.();
  }
  send() {}
}

test("an open channel starts the match even when its open event is missed", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  const connection = new Connection();
  const channel = new Channel();
  let starts = 0;
  connection.addEventListener("open", () => starts++);
  connection._bindChannel(channel);
  await Promise.resolve();
  channel.readyState = "open";
  t.mock.timers.tick(1600);
  assert.equal(starts, 1);
});

test("an already-open channel and a queued open event start only one match", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  const connection = new Connection();
  const channel = new Channel("open");
  let starts = 0;
  connection.addEventListener("open", () => starts++);
  connection._bindChannel(channel);
  channel.onopen();
  await Promise.resolve();
  t.mock.timers.tick(1000);
  assert.equal(starts, 1);
});

test("callbacks from a replaced channel cannot start or end the new match", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  const connection = new Connection();
  const old = new Channel("open");
  const current = new Channel();
  const events = [];
  connection.addEventListener("open", () => events.push("open"));
  connection.addEventListener("peerlost", () => events.push("lost"));
  connection._bindChannel(old);
  connection._bindChannel(current);
  old.onopen();
  old.close();
  await Promise.resolve();
  assert.deepEqual(events, []);
  current.readyState = "open";
  current.onopen();
  assert.deepEqual(events, ["open"]);
});

test("an incoming message announces readiness before delivering game data", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  const connection = new Connection();
  const channel = new Channel();
  const events = [];
  connection.addEventListener("open", () => events.push("open"));
  connection.addEventListener("message", () => events.push("message"));
  connection._bindChannel(channel);
  channel.readyState = "open";
  channel.onmessage({ data: JSON.stringify({ type: "commit", tick: 1 }) });
  assert.deepEqual(events, ["open", "message"]);
});

test("a stale HTTP response cannot replace a newer negotiation", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] });
  let respond;
  t.mock.method(globalThis, "fetch", () => new Promise((resolve) => { respond = resolve; }));
  const connection = new Connection();
  connection.role = "host";
  connection.code = "TEST";
  connection.token = "test-token";
  connection.epoch = 1;
  const channel = new Channel();
  connection._bindChannel(channel);
  let offers = 0;
  let lobbyUpdates = 0;
  connection._negotiate = async () => { offers++; };
  connection.addEventListener("guestjoined", () => lobbyUpdates++);
  connection._startPolling();
  t.mock.timers.tick(200);
  connection._stopPolling();
  connection.epoch = 3;
  channel.readyState = "open";
  channel.onopen();
  respond({ ok: true, json: async () => ({ peerJoined: true, epoch: 2 }) });
  // Drain the fetch, JSON parsing and poll continuations.
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(offers, 0);
  assert.equal(lobbyUpdates, 0);
});

test("a matchmaking assignment adopts the room role and both player names", async (t) => {
  const connection = new Connection();
  t.mock.method(connection, "_negotiate", async () => {});
  t.mock.method(connection, "_startPolling", () => {});
  await connection.acceptMatch({
    code: "MATCH",
    token: "room-token",
    role: "guest",
    seed: 12,
    map: 2,
    epoch: 0,
    hostName: "Алиса",
    guestName: "Боб",
  });
  assert.equal(connection.role, "guest");
  assert.equal(connection.myName, "Боб");
  assert.equal(connection.peerName, "Алиса");
});
