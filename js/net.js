// WebRTC peer connection + commit/reveal command exchange.
//
// The cloud function only relays SDP and ICE; it never sees a command. With no
// authoritative server, each tick commits a salted SHA-256 hash first and
// reveals the command once the opponent's hash is in hand. A reveal that does
// not match its hash is a protocol violation, not a chance to change the move.

const SIGNAL_URL =
  window.TWIVVY_SIGNAL_URL ||
  "https://us-central1-enotix.cloudfunctions.net/twivvy-signal";

export { SIGNAL_URL };

const ICE_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
];

const POLL_MS = 1500;

async function api(path, options = {}) {
  const res = await fetch(SIGNAL_URL + path, {
    signal: AbortSignal.timeout(10_000),
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    const err = new Error(body?.error || `Request failed (${res.status})`);
    err.status = res.status;
    throw err;
  }
  return body;
}

/** Room codes are the alphabet the signalling service allocates from. */
const CODE_RE = /^[A-Z0-9]{4,8}$/;

/**
 * The app's directory, trailing slash included. A room code or index.html is
 * stripped, so links built inside a room still point at the site root.
 */
export function basePath(pathname = window.location.pathname) {
  const parts = pathname.split("/");
  const last = parts[parts.length - 1];
  if (last === "" || last === "index.html" || CODE_RE.test(last.toUpperCase())) {
    parts[parts.length - 1] = "";
  } else {
    parts.push("");
  }
  return parts.join("/");
}

/** Room code carried by the URL, from the path (/KFUEB) or ?game=/?join=. */
export function codeFromLocation(location = window.location) {
  const params = new URLSearchParams(location.search);
  const fromQuery = params.get("game") || params.get("join");
  if (fromQuery && CODE_RE.test(fromQuery.trim().toUpperCase())) {
    return fromQuery.trim().toUpperCase();
  }

  const last = location.pathname.split("/").pop() || "";
  const candidate = last.toUpperCase();
  return CODE_RE.test(candidate) ? candidate : null;
}

export async function sha256Hex(text) {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function randomSalt() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Canonical text form of a command, so both peers hash identical bytes. */
export function encodeCommand(command) {
  if (!command) return "skip";
  return `${command.platform}:${command.dir}`;
}

export function decodeCommand(text) {
  if (text === "skip") return null;
  const match = /^([0-8]):(-?1)$/.exec(text);
  if (!match) return undefined; // malformed
  return { platform: Number(match[1]), dir: Number(match[2]) };
}

export const SESSION_KEY = "twivvy-session-v2:";
export function readSession(code) {
  try { return JSON.parse(sessionStorage.getItem(SESSION_KEY + code)); } catch { return null; }
}

export async function onlinePlayerCount() {
  const state = await api("/api/matchmaking");
  return Math.max(0, Number(state.online) || 0);
}

/** Presence in the public matchmaking pool. The same credentials are reused
 * on retries, so a lost HTTP response cannot enqueue one browser twice. */
export class Matchmaker extends EventTarget {
  constructor() {
    super();
    this.ticket = randomSalt();
    this.token = randomSalt();
    this.closed = false;
    this.match = null;
  }

  _emit(type, detail = {}) {
    this.dispatchEvent(new CustomEvent(type, { detail }));
  }

  async join(name) {
    this.name = name;
    this.closed = false;
    const state = await api("/api/matchmaking", {
      method: "POST",
      body: JSON.stringify({ name, ticket: this.ticket, token: this.token }),
    });
    if (this.closed) {
      this._remove();
      return state;
    }
    this._accept(state);
    this._schedule();
    return state;
  }

  _accept(state) {
    this._emit("count", { online: Math.max(0, Number(state.online) || 0) });
    if (state.match && !this.match) {
      this.match = state.match;
      this._emit("matched", state.match);
    }
  }

  _schedule() {
    clearTimeout(this._timer);
    if (this.closed) return;
    this._timer = setTimeout(() => this._poll(), this.match ? 5000 : POLL_MS);
  }

  async _poll() {
    if (this.closed) return;
    try {
      const state = await api(`/api/matchmaking/${this.ticket}?token=${encodeURIComponent(this.token)}`);
      if (this.closed) return;
      this._accept(state);
    } catch (err) {
      if (this.closed) return;
      // A backgrounded tab ages out of the list: re-enter on the same ticket.
      if (err.status === 404 && !this.match) {
        try {
          const state = await api("/api/matchmaking", {
            method: "POST",
            body: JSON.stringify({ name: this.name, ticket: this.ticket, token: this.token }),
          });
          if (!this.closed) this._accept(state);
        } catch (retryError) {
          if (!this.closed) this._emit("error", { message: retryError.message });
        }
      } else if (!this.match) {
        this._emit("error", { message: err.message });
      }
    }
    this._schedule();
  }

  close(remove = true) {
    if (this.closed) return;
    this.closed = true;
    clearTimeout(this._timer);
    if (remove) this._remove();
  }

  _remove() {
    api(`/api/matchmaking/${this.ticket}?token=${encodeURIComponent(this.token)}`, {
      method: "DELETE",
    }).catch(() => {});
  }
}

/** Signalling remains alive after the data channel opens, so either seat can
 * rebuild its peer connection. All SDP/ICE is scoped to a server epoch. */
export class Connection extends EventTarget {
  constructor() {
    super();
    this.pc = this.channel = null;
    this.role = this.code = this.token = null;
    this.myName = "Игрок";
    this.peerName = null;
    this.map = this.seed = 0;
    this.epoch = -1;
    this.closed = false;
    this._pollGeneration = 0;
    this._pendingCandidates = [];
    this._earlyCandidates = [];
    this._candidateCursor = 0;
    this._remoteSet = false;
    this._openedChannel = null;
    this._lastMessage = Date.now();
    this._lostSince = null;
    this._attempt = null;
    this._lastAttemptAt = 0;
    this._offline = () => this.reconnect();
    this._online = () => this._startPolling();
    this._pagehide = () => this.suspend();
    window.addEventListener?.("offline", this._offline);
    window.addEventListener?.("online", this._online);
    window.addEventListener?.("pagehide", this._pagehide);
    window.addEventListener?.("pageshow", this._online);
  }

  _emit(type, detail = {}) { this.dispatchEvent(new CustomEvent(type, { detail })); }

  saveGame(game) {
    this._game = game;
    this._save();
  }

  _save() {
    if (!this.code || !this.token) return;
    try {
      sessionStorage.setItem(SESSION_KEY + this.code, JSON.stringify({
        code: this.code, token: this.token, role: this.role, seed: this.seed,
        map: this.map, myName: this.myName, peerName: this.peerName,
        game: this._game, savedAt: Date.now(),
      }));
    } catch {
      if (!this._storageWarning) this._emit("storageerror");
      this._storageWarning = true;
    }
  }

  _adopt(room) {
    const role = room.role || this.role;
    Object.assign(this, { code: room.code, token: room.token || this.token,
      role, seed: room.seed ?? this.seed, map: room.map ?? this.map });
    this.myName = room.myName ||
      (role === "host" ? room.hostName : room.guestName) || this.myName;
    this.peerName = room.peerName ||
      (role === "host" ? room.guestName : room.hostName) || this.peerName;
    this._save();
  }

  async host({ seed, map, name }) {
    const room = await api("/api/rooms", { method: "POST", body: JSON.stringify({ seed, map, name, protocol: 2 }) });
    this._adopt({ ...room, role: "host", seed, map });
    await this._negotiate(room.epoch ?? 0);
    this._startPolling();
    return this.code;
  }

  async join(code, { name } = {}) {
    const room = await api(`/api/rooms/${code}/join`, { method: "POST", body: JSON.stringify({ protocol: 2, name }) });
    this._adopt({ ...room, role: "guest" });
    await this._negotiate(room.epoch ?? 0);
    this._startPolling();
    return room;
  }

  async acceptMatch(room) {
    this._adopt(room);
    await this._negotiate(room.epoch ?? 0);
    this._startPolling();
    return room;
  }

  async resume(saved) {
    this._game = saved.game;
    this._adopt(saved);
    // Retry even if the browser reloads while offline; do not claim a new seat.
    this._lostSince = saved.game?.pausedAt || Date.now();
    this._attempt = randomSalt();
    this._startPolling();
  }

  _setupPeer() {
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    this.pc = pc;
    pc.onicecandidate = event => {
      if (this.closed || this.pc !== pc || !event.candidate) return;
      this._pendingCandidates.push(event.candidate.toJSON?.() || {
        candidate: event.candidate.candidate, sdpMid: event.candidate.sdpMid,
        sdpMLineIndex: event.candidate.sdpMLineIndex,
      });
      if (!this._flushTimer) this._flushTimer = setTimeout(() => {
        this._flushTimer = null;
        this._flushCandidates();
      }, 250);
    };
    pc.onconnectionstatechange = () => {
      if (this.closed || this.pc !== pc) return;
      if (["failed", "disconnected", "closed"].includes(pc.connectionState)) this.reconnect();
    };
    pc.ondatachannel = event => {
      if (!this.closed && this.pc === pc) this._bindChannel(event.channel);
    };
    return pc;
  }

  _dropPeer() {
    const pc = this.pc, channel = this.channel;
    this.pc = this.channel = null;
    this._openedChannel = null;
    clearInterval(this._channelWatchTimer);
    clearInterval(this._heartbeat);
    clearTimeout(this._flushTimer);
    this._flushTimer = null;
    this._pendingCandidates = [];
    this._earlyCandidates = [];
    this._candidateCursor = 0;
    this._remoteSet = false;
    try { channel?.close(); pc?.close(); } catch {}
  }

  async _negotiate(epoch) {
    if (this.closed) return;
    this._dropPeer();
    this.epoch = epoch;
    this._lastAttemptAt = Date.now();
    const pc = this._setupPeer();
    if (this.role !== "host") return;
    this._bindChannel(pc.createDataChannel("twivvy", { ordered: true }));
    const offer = await pc.createOffer();
    if (this.pc !== pc) return;
    await pc.setLocalDescription(offer);
    if (this.pc !== pc) return;
    await this._signal({ description: { type: offer.type, sdp: offer.sdp } }, epoch);
  }

  _signal(fields, epoch = this.epoch) {
    return api(`/api/rooms/${this.code}/signal`, {
      method: "POST", body: JSON.stringify({ token: this.token, epoch, ...fields }),
    });
  }

  async _flushCandidates() {
    if (!this._pendingCandidates.length || this.closed) return;
    const epoch = this.epoch;
    const candidates = this._pendingCandidates.splice(0);
    try { await this._signal({ candidates }, epoch); }
    catch {
      if (epoch === this.epoch && !this.closed) this._pendingCandidates.unshift(...candidates);
    }
  }

  async _acceptRemote(description) {
    if (this._remoteSet || !this.pc) return;
    const pc = this.pc, epoch = this.epoch;
    await pc.setRemoteDescription(description);
    if (this.pc !== pc) return;
    this._remoteSet = true;
    for (const candidate of this._earlyCandidates.splice(0)) {
      try { await pc.addIceCandidate(candidate); } catch {}
    }
    if (description.type === "offer") {
      const answer = await pc.createAnswer();
      if (this.pc !== pc) return;
      await pc.setLocalDescription(answer);
      if (this.pc !== pc) return;
      await this._signal({ description: { type: answer.type, sdp: answer.sdp } }, epoch);
    }
  }

  _bindChannel(channel) {
    clearInterval(this._channelWatchTimer);
    this.channel = channel;
    const current = () => !this.closed && channel === this.channel;
    channel.onopen = () => this._notifyChannelOpen(channel);
    this._channelWatchTimer = setInterval(channel.onopen, POLL_MS);
    queueMicrotask(channel.onopen);
    channel.onclose = () => { if (current()) this.reconnect(); };
    channel.onmessage = event => {
      if (!current()) return;
      this._notifyChannelOpen(channel);
      this._lastMessage = Date.now();
      let msg;
      try { msg = JSON.parse(event.data); } catch { return; }
      if (msg?.type === "ping") { this.send({ type: "pong" }); return; }
      if (msg?.type === "pong") return;
      if (msg?.type === "leaving") { this.reconnect(); return; }
      if (typeof msg?.type === "string") this._emit("message", msg);
    };
  }

  _notifyChannelOpen(channel = this.channel) {
    if (this.closed || !channel || channel !== this.channel || channel.readyState !== "open") return false;
    if (this._openedChannel === channel) return true;
    this._openedChannel = channel;
    this._lastMessage = Date.now();
    this._lostSince = null;
    this._attempt = null;
    clearInterval(this._channelWatchTimer);
    clearInterval(this._heartbeat);
    this._heartbeat = setInterval(() => {
      if (Date.now() - this._lastMessage > 5000) this.reconnect();
      else this.send({ type: "ping" });
    }, 1000);
    this._emit("open");
    return true;
  }

  send(message) {
    if (this.closed || this.channel?.readyState !== "open") return false;
    try { this.channel.send(JSON.stringify(message)); return true; }
    catch { this.reconnect(); return false; }
  }

  reconnect() {
    if (this.closed) return;
    this._lostSince ??= Date.now();
    this._emit("peerlost", { since: this._lostSince });
    this._dropPeer();
    this._attempt ??= randomSalt();
    this._startPolling();
  }

  _startPolling() {
    if (this.closed || !this.code) return;
    this._stopPolling();
    const generation = this._pollGeneration;
    const current = () => !this.closed && generation === this._pollGeneration;
    const poll = async () => {
      if (!current()) return;
      try {
        if (this._attempt) {
          const attempt = this._attempt;
          const room = await api(`/api/rooms/${this.code}/resume`, {
            method: "POST", body: JSON.stringify({ token: this.token, attempt }),
          });
          if (!current()) return;
          this._adopt(room);
          this._attempt = null;
          this._lastAttemptAt = Date.now();
          await this._negotiate(room.epoch);
          if (!current()) return;
        }
        const epoch = this.epoch;
        const state = await api(`/api/rooms/${this.code}?token=${encodeURIComponent(this.token)}&since=${this._candidateCursor}&epoch=${epoch}`);
        if (!current()) return;
        if (typeof state.peerName === "string" && state.peerName && state.peerName !== this.peerName) {
          this.peerName = state.peerName;
          this._save();
          this._emit("peername", { name: this.peerName });
        }
        if (state.epoch !== this.epoch) {
          this._lostSince ??= Date.now();
          this._emit("peerlost", { since: this._lostSince });
          this._lastAttemptAt = Date.now();
          await this._negotiate(state.epoch);
          if (!current()) return;
        }
        if (state.peerAbsentAt && this.channel?.readyState !== "open") {
          this._lostSince ??= state.peerAbsentAt;
          this._emit("peerlost", { since: this._lostSince });
        }
        if (state.peerJoined) this._emit("guestjoined");
        if (state.description && !this._remoteSet) await this._acceptRemote(state.description);
        if (!current()) return;
        for (const candidate of state.candidates || []) {
          if (!this._remoteSet) this._earlyCandidates.push(candidate);
          else try { await this.pc.addIceCandidate(candidate); } catch {}
        }
        this._candidateCursor = state.candidateCount || 0;
        await this._flushCandidates();
        // Lost SDP uploads / ICE failure cannot leave a dead negotiation forever.
        if (this.channel?.readyState !== "open" && Date.now() - this._lastAttemptAt > 20_000) {
          this._lastAttemptAt = Date.now();
          this._attempt = randomSalt();
        }
      } catch (err) {
        if (!current()) return;
        if ([403, 404, 410].includes(err.status)) {
          this._emit("expired", { message: "Партия прервана: соперник отсутствовал более 30 минут." });
          this.close(false);
          return;
        }
        // Transient signalling failure must not stop a healthy P2P match.
      }
      if (current()) this._pollTimer = setTimeout(poll, this.channel?.readyState === "open" ? 5000 : POLL_MS);
    };
    this._pollTimer = setTimeout(poll, 200);
  }

  _stopPolling() {
    this._pollGeneration++;
    clearTimeout(this._pollTimer);
  }

  suspend() {
    if (this.closed || !this.token) return;
    this.send({ type: "leaving" });
    this._emit("peerlost", { since: Date.now() });
    this._save();
    fetch(SIGNAL_URL + `/api/rooms/${this.code}/presence`, {
      method: "POST", headers: { "Content-Type": "application/json" }, keepalive: true,
      body: JSON.stringify({ token: this.token, epoch: this.epoch }),
    }).catch(() => {});
    this._dropPeer();
    this._stopPolling();
    this._attempt = randomSalt();
  }

  inviteLink() { return new URL(basePath() + this.code, window.location.href).toString(); }

  close(removeRoom = true) {
    if (this.closed) return;
    if (removeRoom) api(`/api/rooms/${this.code}?token=${encodeURIComponent(this.token)}`, { method: "DELETE" }).catch(() => {});
    this.closed = true;
    this._stopPolling();
    this._dropPeer();
    window.removeEventListener?.("offline", this._offline);
    window.removeEventListener?.("online", this._online);
    window.removeEventListener?.("pagehide", this._pagehide);
    window.removeEventListener?.("pageshow", this._online);
    try { sessionStorage.removeItem(SESSION_KEY + this.code); } catch {}
  }
}
