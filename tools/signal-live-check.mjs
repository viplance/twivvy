// Creates and deletes only its own temporary room; never takes a user's seat.
import assert from "node:assert/strict";
const origin = "https://us-central1-enotix.cloudfunctions.net/twivvy-signal";
async function request(method, path, body) {
  const res = await fetch(origin + path, {
    method, headers: { "Content-Type": "application/json", Origin: "https://twivvy.e-notix.com" },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20_000),
  });
  let data;
  try { data = await res.json(); } catch {}
  return { status: res.status, data };
}
let host, base, matchedRoom;
const matchmaking = [];
try {
  const created = await request("POST", "/api/rooms", { protocol: 2, map: 0, seed: 100 });
  assert.equal(created.status, 201);
  host = created.data;
  base = `/api/rooms/${host.code}`;
  const joined = await request("POST", base + "/join", { protocol: 2 });
  assert.equal(joined.status, 200);
  assert.equal(joined.data.epoch, 1);
  assert.equal((await request("POST", base + "/join", { protocol: 2 })).status, 409);
  const resumed = await request("POST", base + "/resume", { token: host.token, attempt: "live-host-refresh" });
  assert.equal(resumed.status, 200);
  assert.equal(resumed.data.role, "host");
  assert.equal(resumed.data.epoch, 2);
  const repeated = await request("POST", base + "/resume", { token: host.token, attempt: "live-host-refresh" });
  assert.equal(repeated.data.epoch, 2);
  const guestBack = await request("POST", base + "/resume", { token: joined.data.token, attempt: "live-guest-refresh" });
  assert.equal(guestBack.status, 200);
  assert.equal(guestBack.data.role, "guest");
  assert.equal(guestBack.data.epoch, 3);
  const signal = await request("GET", base + `?token=${host.token}&epoch=3`);
  assert.equal(signal.status, 200);
  assert.equal(signal.data.peerJoined, true);
  assert.equal(signal.data.description, null);
  assert.equal(signal.data.candidateCount, 0);
  const stale = await request("POST", base + "/signal", { token: host.token, epoch: 2, description: { type: "offer", sdp: "stale-test" } });
  assert.equal(stale.status, 409);
  console.log("PASS deployed signalling: both roles resume, tokens remain valid, epoch reset, idempotency and reserved-seat protection");

  for (const name of ["Smoke Alice", "Smoke Bob"]) {
    const credentials = { ticket: crypto.randomUUID(), token: crypto.randomUUID() };
    matchmaking.push(credentials);
    const entered = await request("POST", "/api/matchmaking", { ...credentials, name });
    assert.equal(entered.status, 200);
    if (entered.data.match) matchedRoom = entered.data.match;
  }
  const firstMatch = await request("GET",
    `/api/matchmaking/${matchmaking[0].ticket}?token=${matchmaking[0].token}`);
  assert.equal(firstMatch.status, 200);
  assert.equal(firstMatch.data.match.code, matchedRoom.code);
  assert.equal(firstMatch.data.match.hostName, "Smoke Alice");
  assert.equal(firstMatch.data.match.guestName, "Smoke Bob");
  console.log("PASS deployed matchmaking: two FIFO players received one named room");
} finally {
  for (const credentials of matchmaking) {
    await request("DELETE", `/api/matchmaking/${credentials.ticket}?token=${credentials.token}`);
  }
  if (matchedRoom) {
    assert.equal((await request("DELETE",
      `/api/rooms/${matchedRoom.code}?token=${matchedRoom.token}`)).status, 204);
    console.log("Temporary matchmaking room deleted");
  }
  if (host) {
    assert.equal((await request("DELETE", base + `?token=${host.token}`)).status, 204);
    console.log("Temporary smoke-test room deleted");
  }
}
