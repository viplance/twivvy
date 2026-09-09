// Resumable deterministic match. Private choices never enter sync messages.
import { createMatch, resolveTick, isValidCommand, DECIDE_MS, TICKS } from "./rules.js?v=20260909-edge-bounce1";
import { sha256Hex, encodeCommand, decodeCommand } from "./net.js?v=20260909-edge-bounce1";

export const ABSENCE_MS = 30 * 60_000;
const copy = value => JSON.parse(JSON.stringify(value));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const uid = () => crypto.randomUUID();

export function freshRound(remaining) {
  return { remaining, selection: null, locked: false, salt: uid(), hash: null,
    peerHash: null, peerReveal: null };
}

/** Rebuild, don't trust a remote board. History must extend our exact prefix;
 * an interrupted resolve may add at most one committed, verifiable round. */
export async function reconcile(local, remote, side, decideMs = DECIDE_MS) {
  if (!remote || remote.id !== local.id || remote.map !== local.map ||
      !Array.isArray(remote.log) || remote.log.length > TICKS ||
      Math.abs(remote.log.length - local.match.log.length) > 1) throw new Error("Different match history");
  const own = local.match.log;
  for (let i = 0; i < Math.min(own.length, remote.log.length); i++) {
    if (!same(own[i], remote.log[i])) throw new Error("Conflicting match history");
  }
  const ahead = remote.log.length > own.length;
  const log = ahead ? remote.log : own;
  const proofs = ahead ? remote.proofs : local.proofs;
  const match = createMatch(local.map);
  for (let i = 0; i < log.length; i++) {
    const event = log[i];
    if (!event?.commands) throw new Error("Missing commands");
    const replayed = resolveTick(match, event.commands.top, event.commands.bottom);
    if (!same(replayed, event)) throw new Error("Invalid match history");
    if (i >= own.length) {
      const proof = proofs?.[i];
      for (const player of ["top", "bottom"]) {
        const p = proof?.[player];
        if (!p || p.command !== encodeCommand(event.commands[player]) ||
            await sha256Hex(`${i + 1}|${p.command}|${p.salt}`) !== p.hash) throw new Error("Invalid move proof");
      }
      if (!local.round.locked || local.round.hash !== proof[side].hash ||
          (local.round.peerHash && local.round.peerHash !== proof[side === "top" ? "bottom" : "top"].hash)) {
        throw new Error("Resolved move differs from saved commitment");
      }
    }
  }
  const remoteLeft = Number(remote.remaining);
  if (!Number.isFinite(remoteLeft) || remoteLeft < 0 || remoteLeft > decideMs) throw new Error("Invalid timer");
  const round = ahead ? freshRound(remoteLeft) : copy(local.round);
  if (remote.log.length === own.length) round.remaining = Math.min(round.remaining, remoteLeft);
  return { match, proofs: copy(proofs), round };
}

export class MatchSession {
  constructor(connection, options = {}) {
    this.connection = connection;
    this.side = connection.role === "host" ? "bottom" : "top";
    this.decideMs = options.decideMs || DECIDE_MS;
    this.callbacks = options;
    const saved = options.saved;
    this.id = saved?.id || (this.side === "bottom" ? uid() : null);
    this.map = saved?.map ?? connection.map;
    this.match = saved?.match || createMatch(this.map);
    this.proofs = saved?.proofs || [];
    this.round = saved?.round || freshRound(this.decideMs);
    this.pausedAt = saved?.pausedAt ?? (saved ? saved.savedAt : null);
    this.ended = saved?.ended || false;
    this.phase = "paused";
    this.generation = 0;
    this._onMessage = e => this._message(e.detail).catch(err => this._fail(err));
    connection.addEventListener("message", this._onMessage);
    this._watch = setInterval(() => this._watchdog(), 250);
    this._save();
  }

  remaining() {
    return this.phase === "decide" ? Math.max(0, this.deadline - Date.now()) : this.round.remaining;
  }

  snapshot() {
    return copy({ id: this.id, map: this.map, match: this.match, proofs: this.proofs,
      round: { ...this.round, remaining: this.remaining() }, pausedAt: this.pausedAt,
      ended: this.ended, savedAt: Date.now() });
  }

  _save() { this.connection.saveGame(this.snapshot()); }

  publicState() {
    return { id: this.id, map: this.map, log: this.match.log, proofs: this.proofs,
      remaining: this.remaining(), ready: this.phase === "sync" };
  }

  choose(selection) {
    if (this.phase !== "decide" || this.round.locked) return;
    this.round.selection = isValidCommand(this.match, selection) ? selection : null;
    this._save();
  }

  pause(since = Date.now()) {
    if (this.ended) return;
    // Disabling interaction finishes an in-flight drag and persists its choice.
    this.callbacks.lock?.();
    this.round.remaining = this.remaining();
    this.pausedAt ??= since;
    this.phase = "paused";
    this.generation++;
    this._resolving = null;
    this._plan = null;
    this._planning = false;
    this._save();
    this.callbacks.paused?.();
  }

  connected() {
    if (this.ended) { this.callbacks.finished?.(this.ended === true ? null : this.ended); return; }
    this.pause();
    this.phase = "sync";
    this.syncStarted = Date.now();
    this.connection.send({ type: "sync-request" });
    this._sendState();
  }

  _sendState() { this.connection.send({ type: "sync-state", state: this.publicState() }); }

  async _apply(remote) {
    const generation = this.generation;
    const reconciled = await reconcile(this.snapshot(), remote, this.side, this.decideMs);
    if (generation !== this.generation) return false;
    Object.assign(this, reconciled);
    this._save();
    await this.callbacks.restore?.(this.match, this.round.selection);
    return generation === this.generation;
  }

  async _message(msg) {
    if (this.ended) return;
    if (msg.type === "sync-request") { this._sendState(); return; }
    if (msg.type === "sync-state" && msg.state?.ready && this.side === "bottom" && this.phase === "sync" && !this._planning && !this._plan) {
      this._planning = true;
      const generation = this.generation;
      try {
        // A fresh guest learns the host's match identity without seeing choices.
        const state = msg.state?.id === null && !msg.state?.log?.length
          ? { ...msg.state, id: this.id, map: this.map } : msg.state;
        if (!await this._apply(state)) return;
        this._plan = uid();
        this.connection.send({ type: "sync-plan", nonce: this._plan, state: this.publicState() });
      } finally { if (generation === this.generation) this._planning = false; }
      return;
    }
    if (msg.type === "sync-plan" && this.side === "top" && ["sync", "paused"].includes(this.phase)) {
      if (!this.id && !this.match.tick) {
        this.id = msg.state.id;
        this.map = msg.state.map;
        this.match = createMatch(this.map);
      }
      this.phase = "sync";
      if (!await this._apply(msg.state)) return;
      this._plan = msg.nonce;
      this.connection.send({ type: "sync-ready", nonce: this._plan });
      return;
    }
    if (msg.type === "sync-ready" && this.side === "bottom" && this.phase === "sync" && msg.nonce === this._plan) {
      this.connection.send({ type: "sync-go", nonce: this._plan });
      this._go();
      return;
    }
    if (msg.type === "sync-go" && this.side === "top" && this.phase === "sync" && msg.nonce === this._plan) {
      this._go();
      return;
    }
    if (msg.game !== this.id || msg.tick !== this.match.tick + 1) return;
    if (msg.type === "commit") {
      if (typeof msg.hash !== "string" || !/^[a-f0-9]{64}$/.test(msg.hash)) throw new Error("Invalid commitment");
      if (this.round.peerHash && this.round.peerHash !== msg.hash) throw new Error("Changed commitment");
      this.round.peerHash = msg.hash;
      this._save();
      await this._exchange();
    } else if (msg.type === "reveal") {
      if (!this.round.locked || !this.round.peerHash) return;
      this.round.peerReveal = { command: msg.command, salt: msg.salt };
      this._save();
      await this._exchange();
    }
  }

  _go() {
    if (this.match.finished) { this.finish(null); return; }
    this.pausedAt = null;
    this.phase = this.round.locked ? "exchange" : "decide";
    this.deadline = Date.now() + this.round.remaining;
    this.exchangeStarted = Date.now();
    this._save();
    this.callbacks.active?.(!this.round.locked);
    if (this.round.locked) this._commit();
  }

  async _commit() {
    const generation = this.generation, round = this.round;
    this.callbacks.lock?.();
    round.remaining = 0;
    round.locked = true;
    this.phase = "exchange";
    this.exchangeStarted = Date.now();
    this._save(); // Salt and immutable choice survive refresh even during digest.
    round.hash = await sha256Hex(`${this.match.tick + 1}|${encodeCommand(round.selection)}|${round.salt}`);
    if (generation !== this.generation || this.round !== round) return;
    this._save();
    this.connection.send({ type: "commit", game: this.id, tick: this.match.tick + 1, hash: round.hash });
    await this._exchange();
  }

  async _exchange() {
    const round = this.round, generation = this.generation;
    if (this.phase !== "exchange" || !round.hash || !round.peerHash || this._resolving) return;
    this.connection.send({ type: "reveal", game: this.id, tick: this.match.tick + 1,
      command: encodeCommand(round.selection), salt: round.salt });
    if (!round.peerReveal) return;
    const token = {};
    this._resolving = token;
    const peer = round.peerReveal;
    const hash = await sha256Hex(`${this.match.tick + 1}|${peer.command}|${peer.salt}`);
    if (generation !== this.generation || round !== this.round) return;
    const command = decodeCommand(peer.command);
    if (hash !== round.peerHash || command === undefined) throw new Error("Invalid reveal");
    const other = this.side === "top" ? "bottom" : "top";
    const commands = { [this.side]: round.selection, [other]: command };
    const before = copy(this.match);
    const event = resolveTick(this.match, commands.top, commands.bottom);
    this.proofs.push({ [this.side]: { hash: round.hash, salt: round.salt, command: encodeCommand(round.selection) },
      [other]: { ...peer, hash } });
    this.round = freshRound(this.decideMs);
    this.phase = "animate";
    this._save(); // Persist logical result BEFORE any await/animation.
    await this.callbacks.resolved?.(event, before, this.match);
    if (generation !== this.generation) return;
    this._resolving = null;
    // Use the same barrier after every turn: neither peer can start alone.
    this._plan = null;
    this.phase = "sync";
    this.syncStarted = Date.now();
    this._sendState();
    this.connection.send({ type: "sync-request" });
  }

  _watchdog() {
    if (this.ended) return;
    if (this.pausedAt !== null && Date.now() - this.pausedAt >= ABSENCE_MS) {
      this.finish("Партия прервана: соперник отсутствовал более 30 минут.");
      this.connection.close();
      return;
    }
    if (this.phase === "decide") {
      this.callbacks.timer?.(this.remaining() / this.decideMs);
      this._save();
      if (!this.remaining()) this._commit().catch(err => this._fail(err));
    } else if ((this.phase === "exchange" && Date.now() - this.exchangeStarted > 6000) ||
               (this.phase === "sync" && Date.now() - this.syncStarted > 10_000)) {
      // A timeout is a pause, NEVER a skipped opponent move.
      this.connection.reconnect();
    }
  }

  finish(reason) {
    this.ended = reason || true;
    this.phase = "ended";
    this.generation++;
    this._save();
    this.callbacks.finished?.(reason);
  }

  _fail(err) {
    console.error("session protocol", err);
    this.finish("Не удалось согласовать сохранённую партию.");
  }

  dispose() {
    this.generation++;
    clearInterval(this._watch);
    this.connection.removeEventListener("message", this._onMessage);
  }
}
