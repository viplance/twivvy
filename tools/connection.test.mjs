import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

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

async function controllerHarness({ pathname = "/", joinError = null, brokenView = false,
  storedName = null } = {}) {
  const source = await readFile(new URL("../js/main.js", import.meta.url), "utf8");
  const elements = new Map();
  const getElement = (id) => {
    if (!elements.has(id)) {
      const classes = new Set(["lobby", "hud", "over", "name-modal", "player-labels"].includes(id) ? ["hidden"] : []);
      const listeners = new Map();
      const child = { textContent: "" };
      elements.set(id, {
        classList: {
          toggle(name, force) { force ? classes.add(name) : classes.delete(name); },
          contains(name) { return classes.has(name); },
        },
        style: {},
        value: "",
        disabled: false,
        addEventListener(type, callback) {
          if (!listeners.has(type)) listeners.set(type, []);
          listeners.get(type).push(callback);
        },
        dispatch(type, event = {}) {
          for (const callback of listeners.get(type) || []) callback(event);
        },
        querySelector() { return child; },
        focus() {}, setCustomValidity() {}, reportValidity() {},
      });
    }
    return elements.get(id);
  };
  let finishHost;
  let conn;
  let starts = 0;
  let joinedCode = null;
  let sessionCallbacks = null;
  let currentSession = null;
  let hostedName = null;
  let queuedName = null;
  class FakeConnection extends EventTarget {
    constructor() { super(); conn = this; this.code = "TEST"; this.map = 0; }
    host({ name } = {}) {
      this.role = "host";
      this.myName = name;
      hostedName = name;
      return new Promise((resolve) => { finishHost = resolve; });
    }
    async join(code) {
      joinedCode = code;
      this.role = "guest";
      if (joinError) throw joinError;
    }
    inviteLink() { return "https://example.test/TEST"; }
  }
  const sandbox = {
    Connection: FakeConnection,
    Matchmaker: class extends EventTarget {
      async join(name) { queuedName = name; }
      close() {}
    },
    onlinePlayerCount: async () => 0,
    readSession: () => null,
    MatchSession: class {
      constructor(_connection, callbacks) {
        sessionCallbacks = callbacks;
        currentSession = this;
        this.match = { tick: 0 };
        this.decideMs = 30_000;
        this.phase = "decide";
      }
      connected() {}
      dispose() {}
      remaining() { return this.decideMs; }
    },
    BoardView: class {
      start() {}
      setPerspective() { starts++; }
      clearCollected() {}
      syncCells() {}
      syncBalls() {}
      restoreMatch() {}
      syncSourceMarkers() {}
      setCooldown() {}
      clearPreview() { if (brokenView) throw new Error("incompatible renderer"); }
      setInteractionEnabled() {}
    },
    TickExchange: class {},
    createMatch: () => ({ tick: 0, cooldown: [], finished: false }),
    MAPS: [{}], DECIDE_MS: 30_000, RESOLVE_MS: 1200, TICKS: 30,
    basePath: () => "/", codeFromLocation: () => codeFromLocation({ pathname, search: "" }),
    document: { getElementById: getElement },
    window: { addEventListener() {}, innerHeight: 800 }, history: { replaceState() {} },
    localStorage: {
      getItem() { return storedName; },
      setItem(_key, value) { storedName = value; },
    },
    navigator: { clipboard: { writeText: async () => {} } },
    performance: { now: () => 0 }, console: { ...console, error() {} },
    setTimeout: () => 1, clearTimeout() {}, setInterval: () => 1, clearInterval() {},
    requestAnimationFrame: () => 1, cancelAnimationFrame() {},
  };
  // Inject transport/view doubles; execute the real controller and its UI flow.
  vm.createContext(sandbox);
  vm.runInContext(source.replace(/^import[\s\S]*?from "[^"\n]+";\n/gm, ""), sandbox);
  return {
    sandbox, getElement, getConnection: () => conn,
    finishHost: () => finishHost(), getStarts: () => starts,
    getHostedName: () => hostedName,
    getQueuedName: () => queuedName,
    getStoredName: () => storedName,
    getJoinedCode: () => joinedCode,
    dispatch(id, type, event = {}) { getElement(id).dispatch(type, event); },
    activateRound(round) {
      currentSession.match.tick = round - 1;
      sessionCallbacks.active(true);
    },
  };
}

test("room creation asks for a name and pre-fills the saved browser name", async () => {
  const app = await controllerHarness({ storedName: "Сохранённое имя" });
  app.dispatch("create", "click");
  assert.equal(app.getElement("name-modal").classList.contains("hidden"), false);
  assert.equal(app.getElement("player-name").value, "Сохранённое имя");
  app.dispatch("name-form", "submit", { preventDefault() {} });
  assert.equal(app.getHostedName(), "Сохранённое имя");
  app.finishHost();
  await Promise.resolve();
});

test("online play saves the name and enters matchmaking", async () => {
  const app = await controllerHarness();
  app.dispatch("play-online", "click");
  assert.equal(app.getElement("online-count").classList.contains("hidden"), false);
  app.getElement("player-name").value = "  Новый   игрок  ";
  app.dispatch("name-form", "submit", { preventDefault() {} });
  await Promise.resolve();
  assert.equal(app.getQueuedName(), "Новый игрок");
  assert.equal(app.getStoredName(), "Новый игрок");
});

test("late room creation cannot show the lobby over an already-started match", async () => {
  const { sandbox, getElement, getConnection, finishHost, getStarts } = await controllerHarness();
  const creating = vm.runInContext("createRoom()", sandbox);
  const conn = getConnection();
  conn.dispatchEvent(new Event("open"));
  assert.equal(getElement("lobby").classList.contains("hidden"), true);
  finishHost();
  await creating;
  assert.equal(getElement("lobby").classList.contains("hidden"), true);
  assert.equal(getElement("hud").classList.contains("hidden"), false);
  conn.dispatchEvent(new Event("open"));
  assert.equal(getStarts(), 1, "duplicate readiness must not reset a running match");
});

test("HMH9T invitation asks for a name before joining", async () => {
  const app = await controllerHarness({ pathname: "/HMH9T" });
  assert.equal(app.getJoinedCode(), null);
  assert.equal(app.getElement("name-modal").classList.contains("hidden"), false);
  app.getElement("player-name").value = "Алиса";
  app.dispatch("name-form", "submit", { preventDefault() {} });
  await Promise.resolve();
  assert.equal(app.getJoinedCode(), "HMH9T");
  assert.equal(app.getElement("menu").classList.contains("hidden"), true);
  assert.equal(app.getElement("lobby").classList.contains("hidden"), false);
});

test("failed invitation keeps the code and a visible explanation instead of the new-game menu", async () => {
  const error = Object.assign(new Error("Room not found."), { status: 404 });
  const app = await controllerHarness({ pathname: "/HMH9T", joinError: error });
  app.getElement("player-name").value = "Алиса";
  app.dispatch("name-form", "submit", { preventDefault() {} });
  for (let i = 0; i < 5; i++) await Promise.resolve();
  assert.equal(app.getElement("menu").classList.contains("hidden"), true);
  assert.equal(app.getElement("lobby").classList.contains("hidden"), false);
  assert.equal(app.getElement("invite-code").textContent, "HMH9T");
  assert.match(app.getElement("lobby-hint").textContent, /Комната не найдена/);
});

test("startup failure cannot leave a false connecting status or a running match", async () => {
  const app = await controllerHarness({ pathname: "/HMH9T", brokenView: true });
  app.getElement("player-name").value = "Алиса";
  app.dispatch("name-form", "submit", { preventDefault() {} });
  await Promise.resolve();
  app.getConnection().dispatchEvent(new Event("open"));
  assert.equal(vm.runInContext("running", app.sandbox), false);
  assert.match(app.getElement("lobby-hint").textContent, /Не удалось запустить игру/);
  assert.equal(app.getElement("menu").classList.contains("hidden"), true);
});

test("a new decision round shows its three-second centered title", async () => {
  const app = await controllerHarness();
  const creating = vm.runInContext("createRoom()", app.sandbox);
  app.getConnection().dispatchEvent(new Event("open"));
  app.activateRound(5);
  const title = app.getElement("round-title");
  assert.equal(title.textContent, "Раунд 5 из 30");
  assert.equal(title.classList.contains("hidden"), false);
  assert.equal(title.classList.contains("playing"), true);
  app.finishHost();
  await creating;
});
