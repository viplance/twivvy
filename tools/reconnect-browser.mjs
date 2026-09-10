// Run `pnpm build` first, then point PUPPETEER_MODULE at puppeteer-core.
// The local fixture serves Vite's production output; no real user's room is joined.
import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import { signalFixture } from "./signal-fixture.mjs";
const { default: puppeteer } = await import(process.env.PUPPETEER_MODULE || "puppeteer-core");
const root = path.resolve(import.meta.dirname, "../dist");
const fixture = await signalFixture();
let blockedToken = null;
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://local");
    if (url.pathname.startsWith("/api/")) {
      let raw = "";
      for await (const chunk of req) raw += chunk;
      const body = raw ? JSON.parse(raw) : {};
      const token = body.token || url.searchParams.get("token");
      const result = blockedToken && token === blockedToken
        ? { status: 503, body: { error: "Test network outage" } }
        : await fixture.request(req.method, url.pathname + url.search, body);
      res.writeHead(result.status, { "content-type": "application/json" });
      res.end(JSON.stringify(result.body));
      return;
    }
    const file = url.pathname === "/" || /^\/[A-Z0-9]{4,8}$/.test(url.pathname) ? "index.html" : url.pathname.slice(1);
    res.writeHead(200, { "content-type": ({
      ".js": "text/javascript",
      ".css": "text/css",
      ".html": "text/html",
      ".mp3": "audio/mpeg",
    })[path.extname(file)] });
    res.end(await readFile(path.join(root, file)));
  } catch (err) { res.writeHead(500); res.end(err.message); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = process.env.LIVE_ORIGIN || `http://127.0.0.1:${server.address().port}`;
const signalOrigin = process.env.LIVE_ORIGIN
  ? "https://us-central1-enotix.cloudfunctions.net/twivvy-signal" : origin;
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true, protocolTimeout: 20_000,
  args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"],
});
const errors = [];
async function page() {
  const p = await browser.newPage();
  await p.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, "language", { get: () => "ru-RU" });
    Object.defineProperty(navigator, "languages", { get: () => ["ru-RU", "ru"] });
  });
  p.on("pageerror", err => errors.push(err.message));
  p.on("console", msg => { if (msg.type() === "error") console.log("BROWSER", msg.text()); });
  if (process.env.LIVE_ORIGIN) {
    await p.setRequestInterception(true);
    p.on("request", async request => {
      const url = new URL(request.url());
      let token = url.searchParams.get("token");
      try { token ||= JSON.parse(request.postData() || "{}").token; } catch {}
      if (blockedToken && token === blockedToken && request.url().startsWith(signalOrigin)) {
        await request.respond({ status: 503, contentType: "application/json",
          headers: { "access-control-allow-origin": origin }, body: '{"error":"Test network outage"}' });
      } else await request.continue();
    });
  }
  await p.evaluateOnNewDocument(origin => { window.TWIVVY_SIGNAL_URL = origin; window.__TWIVVY_DECIDE_MS = 8000; }, signalOrigin);
  return p;
}
const active = p => p.waitForFunction(() => window.__twivvy?.getSession()?.phase === "decide", { polling: 100, timeout: 45_000 });
const info = p => p.evaluate(() => {
  const x = window.__twivvy, s = x.getSession();
  return { role: x.getConnection().role, token: x.getConnection().token, tick: s.match.tick,
    log: s.match.log, remaining: s.remaining(), selection: s.round.selection,
    phase: s.phase, pausedAt: s.pausedAt, score: s.match.score,
    trays: { top: x.view.collected.top.length, bottom: x.view.collected.bottom.length },
    pauseVisible: !document.getElementById("pause-status").classList.contains("hidden"),
    pauseText: document.getElementById("pause-status").textContent };
});
let cleanup;
try {
  const host = await page(), guest = await page();
  await host.goto(origin);
  await host.evaluate(() => document.getElementById("create").click());
  await host.waitForFunction(() => window.__twivvy?.getConnection()?.code, { polling: 100 });
  const code = await host.evaluate(() => window.__twivvy.getConnection().code);
  cleanup = await host.evaluate(() => {
    const c = window.__twivvy.getConnection();
    return { code: c.code, token: c.token };
  });
  await guest.goto(`${origin}/${code}`);
  await Promise.all([active(host), active(guest)]);
  console.log("PASS initial real WebRTC connection");

  // Get real balls on the board first.
  await host.waitForFunction(() => window.__twivvy.getSession().match.tick >= 1 && window.__twivvy.getSession().phase === "decide", { polling: 100, timeout: 20_000 });
  for (const [name, returning, staying] of [["guest", guest, host], ["host", host, guest]]) {
    await Promise.all([active(host), active(guest)]);
    const before = await info(returning);
    blockedToken = before.token;
    // Refresh while its signalling is unavailable: peer must stay paused.
    await returning.reload();
    await staying.waitForFunction(() => window.__twivvy.getSession().phase === "paused", { polling: 100, timeout: 10_000 });
    const paused = await info(staying);
    assert.equal(paused.pauseVisible, true);
    assert.equal(paused.pauseText, "Соперник отсоединился");
    await delay(1800);
    const frozen = await info(staying);
    assert.equal(frozen.tick, paused.tick);
    assert.equal(frozen.remaining, paused.remaining);
    blockedToken = null;
    await Promise.all([active(returning), active(staying)]);
    const after = await info(returning), other = await info(staying);
    assert.equal(after.role, name);
    assert.equal(after.token, before.token);
    assert.deepEqual(after.log, other.log);
    assert.ok(after.remaining <= paused.remaining + 100);
    assert.deepEqual(after.trays, after.score);
    console.log(`PASS ${name} refresh: pause visible, board/timer frozen, same role/token and log restored`);
  }

  await Promise.all([host.reload(), guest.reload()]);
  await Promise.all([active(host), active(guest)]);
  assert.deepEqual((await info(host)).log, (await info(guest)).log);
  console.log("PASS simultaneous refresh of both players");

  // A silent data channel failure without a refresh must also renegotiate.
  await guest.evaluate(() => window.__twivvy.getConnection().pc.close());
  await host.waitForFunction(() => ["paused", "sync"].includes(window.__twivvy.getSession().phase), { polling: 100, timeout: 10_000 });
  await Promise.all([active(host), active(guest)]);
  assert.deepEqual((await info(host)).log, (await info(guest)).log);
  console.log("PASS closed peer connection automatically rebuilds without refreshing");

  const startTick = (await info(host)).tick;
  await Promise.all([host, guest].map(p => p.waitForFunction(tick => window.__twivvy.getSession().match.tick > tick && window.__twivvy.getSession().phase === "decide", { polling: 100, timeout: 20_000 }, startTick)));
  assert.deepEqual((await info(host)).log, (await info(guest)).log);
  assert.deepEqual(errors, []);
  console.log("PASS gameplay continues after recovery; no JavaScript errors");
  await host.evaluate(() => window.__twivvy.getConnection().close());
} finally {
  if (cleanup) {
    await fetch(signalOrigin + `/api/rooms/${cleanup.code}?token=${encodeURIComponent(cleanup.token)}`, { method: "DELETE" });
    console.log("Own temporary browser-test room cleaned up");
  }
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
