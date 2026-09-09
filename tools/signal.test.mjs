import { test } from "node:test";
import assert from "node:assert/strict";
import { signalFixture } from "./signal-fixture.mjs";

async function setup() {
  let clock = 100_000;
  const api = await signalFixture({ now: () => clock });
  const host = (await api.request("POST", "/api/rooms", { protocol: 2, map: 0, seed: 1 })).body;
  const base = `/api/rooms/${host.code}`;
  const guest = (await api.request("POST", base + "/join", { protocol: 2 })).body;
  return { ...api, host, guest, base, advance: ms => { clock += ms; } };
}

test("resume preserves both tokens and invalidates old SDP and ICE atomically", async () => {
  const a = await setup();
  const signal = body => a.request("POST", a.base + "/signal", body);
  assert.equal((await signal({ token: a.host.token, epoch: 1, description: { type: "offer", sdp: "old" } })).status, 200);
  const resumed = await a.request("POST", a.base + "/resume", { token: a.guest.token, attempt: "refresh" });
  assert.equal(resumed.status, 200);
  assert.equal(resumed.body.role, "guest");
  assert.equal(resumed.body.epoch, 2);
  assert.equal((await signal({ token: a.host.token, epoch: 1, description: { type: "offer", sdp: "late" } })).status, 409);
  const polled = await a.request("GET", a.base + `?token=${a.host.token}&epoch=2`);
  assert.equal(polled.body.description, null);
  assert.equal(polled.body.candidateCount, 0);
  const repeated = await a.request("POST", a.base + "/resume", { token: a.guest.token, attempt: "refresh" });
  assert.equal(repeated.body.epoch, 2, "retrying an HTTP request must be idempotent");
  assert.equal((await a.request("POST", a.base + "/resume", { token: a.host.token, attempt: "host-refresh" })).body.role, "host");
});

test("an invite cannot steal a reserved guest seat", async () => {
  const a = await setup();
  assert.equal((await a.request("POST", a.base + "/join", { protocol: 2 })).status, 409);
  assert.equal((await a.request("POST", a.base + "/join")).status, 426);
  assert.equal((await a.request("POST", a.base + "/resume", { token: "stranger", attempt: "x" })).status, 403);
});

test("active rooms live beyond 30 minutes; the missing player's own deadline expires", async () => {
  const a = await setup();
  for (let i = 0; i < 40; i++) {
    a.advance(60_000);
    for (const player of [a.host, a.guest]) assert.equal((await a.request("GET", a.base + `?token=${player.token}&epoch=1`)).status, 200);
  }
  await a.request("POST", a.base + "/presence", { token: a.guest.token, epoch: 1 });
  for (let i = 0; i < 29; i++) {
    a.advance(60_000);
    assert.equal((await a.request("GET", a.base + `?token=${a.host.token}&epoch=1`)).status, 200);
  }
  a.advance(60_000);
  assert.equal((await a.request("GET", a.base + `?token=${a.host.token}&epoch=1`)).status, 410);
  assert.equal((await a.request("POST", a.base + "/resume", { token: a.guest.token, attempt: "too-late" })).status, 410);
});

test("refresh within grace resets presence, and stale pagehide cannot mark the new page absent", async () => {
  const a = await setup();
  await a.request("POST", a.base + "/presence", { token: a.host.token, epoch: 1 });
  a.advance(29 * 60_000);
  await a.request("GET", a.base + `?token=${a.guest.token}&epoch=1`);
  await a.request("POST", a.base + "/resume", { token: a.host.token, attempt: "back" });
  await a.request("POST", a.base + "/presence", { token: a.host.token, epoch: 1 });
  const state = await a.request("GET", a.base + `?token=${a.guest.token}&epoch=2`);
  assert.equal(state.body.peerAbsentAt, null);
  a.advance(2 * 60_000);
  assert.equal((await a.request("GET", a.base + `?token=${a.host.token}&epoch=2`)).status, 200);
});

test("rooms carry both player names through join and signalling", async () => {
  const api = await signalFixture();
  const host = (await api.request("POST", "/api/rooms", {
    protocol: 2, map: 0, seed: 1, name: "Алиса",
  })).body;
  const base = `/api/rooms/${host.code}`;
  const guest = (await api.request("POST", base + "/join", {
    protocol: 2, name: "Боб",
  })).body;
  assert.equal(guest.hostName, "Алиса");
  assert.equal(guest.guestName, "Боб");
  const hostState = await api.request("GET", base + `?token=${host.token}&epoch=1`);
  assert.equal(hostState.body.peerName, "Боб");
});

test("matchmaking pairs the longest-waiting players and keeps one odd player queued", async () => {
  let clock = 200_000;
  const api = await signalFixture({ now: () => clock });
  const credentials = ["a", "b", "c"].map(letter => ({
    ticket: letter.repeat(24), token: letter.toUpperCase().repeat(24),
  }));
  const enter = (index, name) => api.request("POST", "/api/matchmaking", {
    ...credentials[index], name,
  });

  const first = await enter(0, "Первый");
  assert.equal(first.body.online, 1);
  assert.equal(first.body.match, null);
  clock += 10;
  const second = await enter(1, "Второй");
  assert.equal(second.body.match.role, "guest");
  const firstPoll = await api.request("GET",
    `/api/matchmaking/${credentials[0].ticket}?token=${credentials[0].token}`);
  assert.equal(firstPoll.body.match.role, "host");
  assert.equal(firstPoll.body.match.code, second.body.match.code);
  assert.equal(firstPoll.body.match.hostName, "Первый");
  assert.equal(firstPoll.body.match.guestName, "Второй");

  clock += 10;
  const third = await enter(2, "Третий");
  assert.equal(third.body.match, null);
  assert.equal(third.body.online, 3, "two playing users and one waiter are online");
});

test("a matched room remains recoverable after presence drops from the online count", async () => {
  let clock = 300_000;
  const api = await signalFixture({ now: () => clock });
  const first = { ticket: "d".repeat(24), token: "D".repeat(24), name: "Даша" };
  const second = { ticket: "e".repeat(24), token: "E".repeat(24), name: "Егор" };
  await api.request("POST", "/api/matchmaking", first);
  await api.request("POST", "/api/matchmaking", second);
  clock += 20_000;
  assert.equal((await api.request("GET", "/api/matchmaking")).body.online, 0);
  const recovered = await api.request("GET",
    `/api/matchmaking/${first.ticket}?token=${first.token}`);
  assert.equal(recovered.status, 200);
  assert.equal(recovered.body.match.hostName, "Даша");
  assert.equal(recovered.body.online, 1);
});
