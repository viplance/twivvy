// Runs the actual deployed HTTP handler against an in-memory Firestore double.
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import crypto from "node:crypto";

export async function signalFixture({ now = () => Date.now() } = {}) {
  const rooms = new Map();
  let handler;
  let queue = Promise.resolve();
  const clone = value => structuredClone(value);
  const snapshot = code => ({ exists: rooms.has(code), data() {
    const room = clone(rooms.get(code));
    if (room?.createdAt) room.createdAt = { toMillis: () => rooms.get(code).createdAt.timestamp };
    return room;
  } });
  const update = (code, fields) => {
    const room = rooms.get(code);
    for (const [key, value] of Object.entries(fields)) {
      if (value?.union) {
        room[key] ||= [];
        for (const item of value.union) if (!room[key].some(x => JSON.stringify(x) === JSON.stringify(item))) room[key].push(clone(item));
      } else room[key] = clone(value);
    }
  };
  const ref = code => ({ code,
    async get() { return snapshot(code); },
    async create(fields) {
      if (rooms.has(code)) throw Object.assign(new Error("exists"), { code: 6 });
      rooms.set(code, clone(fields));
    },
    async set(fields) { rooms.set(code, clone(fields)); },
    async update(fields) { update(code, fields); },
    async delete() { rooms.delete(code); },
  });
  class Firestore {
    collection() { return { doc: ref }; }
    runTransaction(callback) {
      const pending = queue.then(() => callback({
        get: r => r.get(),
        create: (r, fields) => r.create(fields),
        set: (r, fields) => r.set(fields),
        update: (r, fields) => update(r.code, fields),
        delete: r => r.delete(),
      }));
      queue = pending.catch(() => {});
      return pending;
    }
  }
  const source = await readFile(new URL("./signal-server/index.cjs", import.meta.url), "utf8");
  vm.runInNewContext(source, {
    require(name) {
      if (name === "crypto") return crypto;
      if (name.includes("functions-framework")) return { http: (name, fn) => { handler = fn; } };
      if (name.includes("firestore")) return { Firestore, FieldValue: {
        serverTimestamp: () => ({ timestamp: now() }), arrayUnion: (...union) => ({ union }),
      } };
      throw new Error(name);
    },
    process: { env: {} }, console, Date: { now },
  });
  async function request(method, path, body = {}, ip = "test") {
    const url = new URL(path, "http://test");
    let status = 200, result;
    await handler({ method, path: url.pathname, query: Object.fromEntries(url.searchParams), body, headers: {}, ip }, {
      set() {}, status(code) { status = code; return this; },
      json(value) { result = value; }, send(value) { result = value; },
    });
    return { status, body: result };
  }
  return { rooms, request };
}
