"use strict";

const functions = require("@google-cloud/functions-framework");
const { Firestore, FieldValue } = require("@google-cloud/firestore");

const DATABASE_ID = process.env.FIRESTORE_DATABASE_ID || "enotix";
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "*").split(",");
const ROOM_TTL_SECONDS = Number(process.env.ROOM_TTL_SECONDS || 1800);
const ROOMS = "twivvy_rooms";
const MATCHMAKING = "twivvy_matchmaking";
const MATCHMAKING_STATE = "state";

const MAX_SDP_LENGTH = 20_000;
const MAX_CANDIDATE_LENGTH = 1_000;
const MAX_CANDIDATES = 60;
const MAX_REQUESTS_PER_MINUTE = 120;
const CODE_ALPHABET = "ACDEFGHJKLMNPQRTUVWXY3479";
const CODE_LENGTH = 5;
const PLAYER_NAME_LENGTH = 24;
const MATCHMAKING_PRESENCE_MS = 15_000;
const MATCHMAKING_ASSIGNMENT_MS = 120_000;
const MAX_MATCHMAKING_PLAYERS = 500;
const MAP_COUNT = 3;

let firestore = null;

function db() {
  if (!firestore) {
    firestore = new Firestore({ databaseId: DATABASE_ID });
  }
  return firestore;
}

const rateLimitMap = new Map();

function isRateLimited(ip) {
  const now = Date.now();
  const windowMs = 60_000;

  let entry = rateLimitMap.get(ip);
  if (!entry || now - entry.start > windowMs) {
    entry = { start: now, count: 0 };
    rateLimitMap.set(ip, entry);
  }
  entry.count++;

  if (rateLimitMap.size > 10_000) {
    for (const [key, val] of rateLimitMap) {
      if (now - val.start > windowMs) rateLimitMap.delete(key);
    }
  }

  return entry.count > MAX_REQUESTS_PER_MINUTE;
}

function getCorsOrigin(requestOrigin) {
  if (ALLOWED_ORIGINS.includes("*")) return "*";
  if (ALLOWED_ORIGINS.includes(requestOrigin)) return requestOrigin;
  return null;
}

function makeCode() {
  const bytes = require("crypto").randomBytes(CODE_LENGTH);
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return code;
}

function makeToken() {
  return require("crypto").randomBytes(24).toString("base64url");
}

function normalizeCode(raw) {
  const code = String(raw || "")
    .trim()
    .toUpperCase();
  if (!/^[A-Z0-9]{4,8}$/.test(code)) return null;
  return code;
}

function normalizePlayerName(raw) {
  const name = String(raw || "").replace(/\s+/g, " ").trim();
  return name ? name.slice(0, PLAYER_NAME_LENGTH) : null;
}

function validMatchmakingCredential(raw) {
  return typeof raw === "string" && /^[A-Za-z0-9_-]{20,80}$/.test(raw);
}

function newRoomFields({ code, seed, map, hostToken, guestToken = null,
  hostName, guestName = null }) {
  return {
    code,
    seed,
    map,
    hostToken,
    guestToken,
    hostName: normalizePlayerName(hostName) || "Игрок",
    guestName: normalizePlayerName(guestName),
    protocol: 2,
    epoch: 0,
    hostSeen: Date.now(),
    guestSeen: guestToken ? Date.now() : null,
    offer: null,
    answer: null,
    hostCandidates: [],
    guestCandidates: [],
    createdAt: FieldValue.serverTimestamp(),
  };
}

function cleanMatchmakingState(raw, now = Date.now()) {
  const present = item => item && Number.isFinite(item.seenAt) &&
    now - item.seenAt < MATCHMAKING_PRESENCE_MS;
  const recoverable = item => item && Number.isFinite(item.seenAt) &&
    now - item.seenAt < MATCHMAKING_ASSIGNMENT_MS;
  return {
    waiting: Array.isArray(raw?.waiting) ? raw.waiting.filter(present) : [],
    assignments: Array.isArray(raw?.assignments) ? raw.assignments.filter(recoverable) : [],
    updatedAt: now,
  };
}

function matchmakingCount(state, now = Date.now()) {
  const activeAssignments = state.assignments.filter(item =>
    now - item.seenAt < MATCHMAKING_PRESENCE_MS).length;
  return state.waiting.length + activeAssignments;
}

function publicAssignment(assignment) {
  if (!assignment) return null;
  const { code, roomToken: token, role, seed, map, epoch, hostName, guestName } = assignment;
  return { code, token, role, seed, map, epoch, hostName, guestName };
}

/** Pair the longest-waiting players. Room creation and both assignments are
 * committed in the same transaction, so no player can be seated twice. */
async function pairWaiting(tx, state) {
  state.waiting.sort((a, b) => a.joinedAt - b.joinedAt || a.ticket.localeCompare(b.ticket));
  while (state.waiting.length >= 2) {
    const host = state.waiting.shift();
    const guest = state.waiting.shift();
    const code = makeCode();
    const seed = require("crypto").randomBytes(2).readUInt16BE(0);
    const map = require("crypto").randomBytes(1)[0] % MAP_COUNT;
    const hostToken = makeToken();
    const guestToken = makeToken();
    const fields = newRoomFields({
      code, seed, map, hostToken, guestToken,
      hostName: host.name, guestName: guest.name,
    });
    await tx.create(db().collection(ROOMS).doc(code), fields);
    for (const [player, role, roomToken] of [
      [host, "host", hostToken],
      [guest, "guest", guestToken],
    ]) {
      state.assignments.push({
        ticket: player.ticket,
        queueToken: player.queueToken,
        seenAt: Date.now(),
        code,
        roomToken,
        role,
        seed,
        map,
        epoch: 0,
        hostName: fields.hostName,
        guestName: fields.guestName,
      });
    }
  }
}

async function matchmakingOverview(req, res) {
  const ref = db().collection(MATCHMAKING).doc(MATCHMAKING_STATE);
  const state = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    const next = cleanMatchmakingState(snap.exists ? snap.data() : null);
    tx.set(ref, next);
    return next;
  });
  return res.status(200).json({ online: matchmakingCount(state) });
}

async function enterMatchmaking(req, res) {
  const name = normalizePlayerName(req.body?.name);
  const ticket = req.body?.ticket;
  const queueToken = req.body?.token;
  if (!name || !validMatchmakingCredential(ticket) || !validMatchmakingCredential(queueToken)) {
    return res.status(400).json({ error: "Invalid matchmaking request." });
  }

  const ref = db().collection(MATCHMAKING).doc(MATCHMAKING_STATE);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    const state = cleanMatchmakingState(snap.exists ? snap.data() : null);
    let assignment = state.assignments.find(item => item.ticket === ticket);
    let waiter = state.waiting.find(item => item.ticket === ticket);
    if ((assignment && assignment.queueToken !== queueToken) ||
        (waiter && waiter.queueToken !== queueToken)) {
      return { status: 403, body: { error: "Invalid matchmaking token." } };
    }
    if (assignment) {
      assignment.seenAt = Date.now();
    } else if (waiter) {
      waiter.name = name;
      waiter.seenAt = Date.now();
    } else {
      if (state.waiting.length + state.assignments.length >= MAX_MATCHMAKING_PLAYERS) {
        return { status: 503, body: { error: "Matchmaking is full." } };
      }
      state.waiting.push({ ticket, queueToken, name, joinedAt: Date.now(), seenAt: Date.now() });
    }
    await pairWaiting(tx, state);
    assignment = state.assignments.find(item => item.ticket === ticket);
    tx.set(ref, state);
    return { status: 200, body: {
      ticket,
      token: queueToken,
      online: matchmakingCount(state),
      match: publicAssignment(assignment),
    } };
  });
  return res.status(result.status).json(result.body);
}

async function pollMatchmaking(req, res, ticket) {
  const queueToken = String(req.query?.token || "");
  if (!validMatchmakingCredential(ticket) || !validMatchmakingCredential(queueToken)) {
    return res.status(400).json({ error: "Invalid matchmaking request." });
  }
  const ref = db().collection(MATCHMAKING).doc(MATCHMAKING_STATE);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    const state = cleanMatchmakingState(snap.exists ? snap.data() : null);
    let assignment = state.assignments.find(item => item.ticket === ticket);
    const waiter = state.waiting.find(item => item.ticket === ticket);
    const player = assignment || waiter;
    if (!player) {
      tx.set(ref, state);
      return { status: 404, body: { error: "Matchmaking ticket expired." } };
    }
    if ((assignment?.queueToken || waiter?.queueToken) !== queueToken) {
      return { status: 403, body: { error: "Invalid matchmaking token." } };
    }
    player.seenAt = Date.now();
    await pairWaiting(tx, state);
    assignment = state.assignments.find(item => item.ticket === ticket);
    tx.set(ref, state);
    return { status: 200, body: {
      online: matchmakingCount(state),
      match: publicAssignment(assignment),
    } };
  });
  return res.status(result.status).json(result.body);
}

async function leaveMatchmaking(req, res, ticket) {
  const queueToken = String(req.query?.token || req.body?.token || "");
  const ref = db().collection(MATCHMAKING).doc(MATCHMAKING_STATE);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    const state = cleanMatchmakingState(snap.exists ? snap.data() : null);
    const all = [...state.waiting, ...state.assignments];
    const player = all.find(item => item.ticket === ticket);
    if (player && player.queueToken !== queueToken) return 403;
    state.waiting = state.waiting.filter(item => item.ticket !== ticket);
    state.assignments = state.assignments.filter(item => item.ticket !== ticket);
    tx.set(ref, state);
    return 204;
  });
  return res.status(result).send("");
}

/** SDP payloads are relayed verbatim, so cap size and shape before storing. */
function validSdp(desc) {
  if (!desc || typeof desc !== "object") return false;
  if (desc.type !== "offer" && desc.type !== "answer") return false;
  if (typeof desc.sdp !== "string") return false;
  if (desc.sdp.length === 0 || desc.sdp.length > MAX_SDP_LENGTH) return false;
  return true;
}

function sanitizeCandidates(list) {
  if (!Array.isArray(list)) return [];
  return list
    .slice(0, MAX_CANDIDATES)
    .filter((c) => c && typeof c === "object" && typeof c.candidate === "string")
    .filter((c) => c.candidate.length <= MAX_CANDIDATE_LENGTH)
    .map((c) => ({
      candidate: c.candidate,
      sdpMid: typeof c.sdpMid === "string" ? c.sdpMid.slice(0, 64) : null,
      sdpMLineIndex:
        Number.isInteger(c.sdpMLineIndex) && c.sdpMLineIndex >= 0
          ? c.sdpMLineIndex
          : null,
    }));
}

function isExpired(room) {
  const created = room.createdAt?.toMillis?.() ?? 0;
  if (room.protocol === 2) {
    // Active games have no absolute lifetime. Each occupied seat has its own
    // grace period; the remaining player's heartbeat cannot extend it.
    const now = Date.now();
    const host = room.hostAbsentAt ?? (room.hostSeen + 10_000);
    const guest = room.guestAbsentAt ?? ((room.guestSeen ?? created) + 10_000);
    return now - host >= ROOM_TTL_SECONDS * 1000 ||
      now - guest >= ROOM_TTL_SECONDS * 1000;
  }
  return Date.now() - created > ROOM_TTL_SECONDS * 1000;
}

function roleFor(room, token) {
  if (token && token === room.hostToken) return "host";
  if (token && token === room.guestToken) return "guest";
  return null;
}

const resetSignals = () => ({ offer: null, answer: null, hostCandidates: [], guestCandidates: [] });

async function resumeRoom(req, res, code) {
  const ref = db().collection(ROOMS).doc(code);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { status: 404, body: { error: "Room not found." } };
    const room = snap.data();
    const role = roleFor(room, req.body?.token);
    if (!role) return { status: 403, body: { error: "Invalid token." } };
    if (isExpired(room)) return { status: 410, body: { error: "Room expired." } };
    const attempt = req.body?.attempt;
    if (typeof attempt !== "string" || attempt.length > 100) {
      return { status: 400, body: { error: "Invalid resume attempt." } };
    }
    const repeated = room[role + "Attempt"] === attempt;
    const epoch = (room.epoch || 0) + (repeated ? 0 : 1);
    tx.update(ref, {
      ...(!repeated ? resetSignals() : {}), epoch,
      [role + "Attempt"]: attempt, [role + "Seen"]: Date.now(),
      [role + "AbsentAt"]: null,
    });
    return { status: 200, body: {
      code, role, seed: room.seed, map: room.map, epoch,
      hostName: room.hostName || "Игрок",
      guestName: room.guestName || "Игрок",
    } };
  });
  return res.status(result.status).json(result.body);
}

async function presence(req, res, code) {
  const ref = db().collection(ROOMS).doc(code);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) return 404;
    const room = snap.data();
    const role = roleFor(room, req.body?.token);
    if (!role) return 403;
    // A delayed pagehide from the old page must not mark the new epoch away.
    if (req.body?.epoch === room.epoch) {
      tx.update(ref, { [role + "AbsentAt"]: room[role + "AbsentAt"] ?? Date.now() });
    }
    return 200;
  });
  return res.status(result).json({ ok: result === 200 });
}

/**
 * POST /api/rooms { seed, map, name }
 * Host creates a room and receives the join code plus its host token.
 */
async function createRoom(req, res) {
  const seed = Number.isInteger(req.body?.seed) ? req.body.seed : 0;
  const map = Number.isInteger(req.body?.map) ? req.body.map : 0;
  const hostName = normalizePlayerName(req.body?.name) || "Игрок";

  const hostToken = makeToken();

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = makeCode();
    const ref = db().collection(ROOMS).doc(code);
    try {
      const fields = newRoomFields({ code, seed, map, hostToken, hostName });
      fields.protocol = req.body?.protocol === 2 ? 2 : 1;
      await ref.create(fields);
      return res.status(201).json({
        code, token: hostToken, role: "host",
        hostName: fields.hostName, guestName: null,
      });
    } catch (err) {
      if (err.code === 6) continue; // ALREADY_EXISTS — try another code
      throw err;
    }
  }

  return res.status(503).json({ error: "Could not allocate a room code." });
}

/**
 * POST /api/rooms/:code/join
 * Guest claims the room. First caller wins; later callers are rejected.
 */
async function joinRoom(req, res, code) {
  const ref = db().collection(ROOMS).doc(code);
  const guestToken = makeToken();
  const guestName = normalizePlayerName(req.body?.name) || "Игрок";

  try {
    const result = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { status: 404, body: { error: "Room not found." } };

      const room = snap.data();
      if (isExpired(room)) {
        return { status: 410, body: { error: "Room expired." } };
      }

      if ((room.protocol === 2) !== (req.body?.protocol === 2)) {
        return { status: 426, body: { error: "Both players must update and create a new room." } };
      }

      if (room.protocol === 2 && room.guestToken) {
        return { status: 409, body: { error: "This seat is reserved. Return using the original browser." } };
      }

      // The seat is reclaimable: a guest who reloaded the page lost their
      // token, and refusing them would make the invite link a one-shot. The
      // newest arrival holds the seat. Their old ICE candidates and answer
      // belong to a dead peer connection, so clear them and ask the host for
      // a fresh offer.
      const rejoin = Boolean(room.guestToken);

      // On a first join everything the host published is still valid, so keep
      // it. Only a rejoin invalidates the handshake: the host will replace the
      // offer and its candidates for the new epoch.
      const reset = rejoin
        ? { answer: null, guestCandidates: [], hostCandidates: [] }
        : {};

      if (room.protocol === 2) Object.assign(reset, resetSignals(), {
        epoch: (room.epoch || 0) + 1, guestSeen: Date.now(), guestAbsentAt: null,
      });

      tx.update(ref, {
        guestToken,
        guestName,
        ...reset,
        // Bumped so the host notices and renegotiates from scratch.
        guestEpoch: (room.guestEpoch || 0) + 1,
      });

      return {
        status: 200,
        body: {
          code,
          token: guestToken,
          role: "guest",
          seed: room.seed,
          map: room.map,
          epoch: reset.epoch ?? room.epoch ?? 0,
          rejoin,
          hostName: room.hostName || "Игрок",
          guestName,
          // A stale offer would carry the previous connection's ICE
          // credentials; the host publishes a new one for this epoch.
          offer: rejoin || room.protocol === 2 ? null : room.offer || null,
        },
      };
    });

    return res.status(result.status).json(result.body);
  } catch (err) {
    console.error("joinRoom failed:", err);
    return res.status(500).json({ error: "Join failed." });
  }
}

/**
 * POST /api/rooms/:code/signal { token, description?, candidates? }
 * Each side pushes its own SDP and ICE candidates into its own slot.
 */
async function postSignal(req, res, code) {
  const token = String(req.body?.token || "");
  const ref = db().collection(ROOMS).doc(code);

  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) return [404, { error: "Room not found." }];
    const room = snap.data();
    const role = roleFor(room, token);
    if (!role) return [403, { error: "Invalid token." }];
    if (isExpired(room)) return [410, { error: "Room expired." }];
    if (room.protocol === 2 && req.body?.epoch !== room.epoch) {
      return [409, { error: "Stale signalling epoch." }];
    }
    const update = {};
    const desc = req.body?.description;
    if (desc !== undefined) {
      if (!validSdp(desc) || desc.type !== (role === "host" ? "offer" : "answer")) {
        return [400, { error: "Invalid session description." }];
      }
      update[role === "host" ? "offer" : "answer"] = { type: desc.type, sdp: desc.sdp };
    }
    const candidates = sanitizeCandidates(req.body?.candidates);
    if (candidates.length) {
      const field = role + "Candidates";
      if ((room[field] || []).length + candidates.length > MAX_CANDIDATES) {
        return [429, { error: "Too many ICE candidates." }];
      }
      update[field] = FieldValue.arrayUnion(...candidates);
    }
    if (Object.keys(update).length) tx.update(ref, update);
    return [200, { ok: true }];
  });
  return res.status(result[0]).json(result[1]);
}

/**
 * GET /api/rooms/:code?token=&since=
 * Poll for the other side's SDP and any ICE candidates beyond `since`.
 */
async function getSignal(req, res, code) {
  const token = String(req.query?.token || "");
  const since = Math.max(0, Number(req.query?.since) || 0);

  const ref = db().collection(ROOMS).doc(code);
  const result = await db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) return [404, { error: "Room not found." }];
    const room = snap.data();
    const role = roleFor(room, token);
    if (!role) return [403, { error: "Invalid token." }];
    if (isExpired(room)) return [410, { error: "Room expired." }];
    const peer = role === "host" ? "guest" : "host";
    if (room.protocol === 2 && Number(req.query?.epoch) === room.epoch) {
      tx.update(ref, { [role + "Seen"]: Date.now(), [role + "AbsentAt"]: null });
    }
    const peerCandidates = room[peer + "Candidates"] || [];
    const sameEpoch = Number(req.query?.epoch) === (room.epoch || 0);
    return [200, {
      code, seed: room.seed, map: room.map,
      hostName: room.hostName || "Игрок",
      guestName: room.guestName || "Игрок",
      peerName: role === "host"
        ? room.guestName || null
        : room.hostName || "Игрок",
      peerJoined: Boolean(room.guestToken), guestEpoch: room.guestEpoch || 0,
      epoch: room.epoch || 0,
      peerAbsentAt: room[peer + "AbsentAt"] ??
        (Date.now() - (room[peer + "Seen"] || Date.now()) > 10_000 ? room[peer + "Seen"] + 10_000 : null),
      description: role === "host" ? room.answer || null : room.offer || null,
      candidates: peerCandidates.slice(sameEpoch || room.protocol !== 2 ? since : 0),
      candidateCount: peerCandidates.length,
    }];
  });
  return res.status(result[0]).json(result[1]);
}

/** DELETE /api/rooms/:code — host tears the room down once connected. */
async function deleteRoom(req, res, code) {
  const token = String(req.query?.token || req.body?.token || "");
  const ref = db().collection(ROOMS).doc(code);

  const snap = await ref.get();
  if (!snap.exists) return res.status(204).send("");

  const room = snap.data();
  if (token !== room.hostToken && token !== room.guestToken) {
    return res.status(403).json({ error: "Invalid token." });
  }

  await ref.delete();
  return res.status(204).send("");
}

functions.http("twivvySignal", async (req, res) => {
  const origin = getCorsOrigin(req.headers.origin);
  if (origin) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.set("Vary", "Origin");
  }

  if (req.method === "OPTIONS") {
    return res.status(204).send("");
  }

  const clientIp =
    req.headers["x-forwarded-for"]?.split(",")[0]?.trim() || req.ip || "unknown";

  if (isRateLimited(clientIp)) {
    return res.status(429).json({ error: "Too many requests. Try again later." });
  }

  const path = (req.path || "/").replace(/\/+$/, "") || "/";

  try {
    if (path === "/health") {
      return res.status(200).json({ ok: true });
    }

    if (path === "/api/rooms" && req.method === "POST") {
      return await createRoom(req, res);
    }

    if (path === "/api/matchmaking") {
      if (req.method === "GET") return await matchmakingOverview(req, res);
      if (req.method === "POST") return await enterMatchmaking(req, res);
    }

    const matchmakingMatch = path.match(/^\/api\/matchmaking\/([^/]+)$/);
    if (matchmakingMatch) {
      const ticket = matchmakingMatch[1];
      if (req.method === "GET") return await pollMatchmaking(req, res, ticket);
      if (req.method === "DELETE") return await leaveMatchmaking(req, res, ticket);
    }

    const roomMatch = path.match(/^\/api\/rooms\/([^/]+)(\/join|\/signal|\/resume|\/presence)?$/);
    if (roomMatch) {
      const code = normalizeCode(roomMatch[1]);
      if (!code) return res.status(400).json({ error: "Invalid room code." });
      const sub = roomMatch[2];

      if (sub === "/resume" && req.method === "POST") return await resumeRoom(req, res, code);
      if (sub === "/presence" && req.method === "POST") return await presence(req, res, code);
      if (sub === "/join" && req.method === "POST") {
        return await joinRoom(req, res, code);
      }
      if (sub === "/signal" && req.method === "POST") {
        return await postSignal(req, res, code);
      }
      if (!sub && req.method === "GET") {
        return await getSignal(req, res, code);
      }
      if (!sub && req.method === "DELETE") {
        return await deleteRoom(req, res, code);
      }
    }

    return res.status(404).json({ error: "Not found." });
  } catch (err) {
    console.error("twivvy-signal error:", err);
    return res.status(500).json({ error: "Internal error." });
  }
});
