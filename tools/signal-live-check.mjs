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
let host, base;
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
} finally {
  if (host) {
    assert.equal((await request("DELETE", base + `?token=${host.token}`)).status, 204);
    console.log("Temporary smoke-test room deleted");
  }
}
