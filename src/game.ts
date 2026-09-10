// Match controller: menu flow, invite links, tick loop, UI state.

import {
  createMatch,
  matchResult,
  MAPS,
  DECIDE_MS,
  RESOLVE_MS,
  TICKS,
} from "../js/rules.js";
import { BoardView } from "../js/view.js";
import {
  Connection,
  Matchmaker,
  onlinePlayerCount,
  readSession,
  basePath,
  codeFromLocation,
} from "../js/net.js";

import { MatchSession } from "../js/session.js";
import { GameAudio } from "../js/audio.js";
import { TrainingSession } from "../js/bot.js";
import { translate } from "./i18n";

const $ = (id: string): any => {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing UI element #${id}`);
  return element;
};

let ui;

function bindUi() {
  return {
    menu: $("menu"),
    lobby: $("lobby"),
    hud: $("hud"),
    over: $("over"),
    toast: $("toast"),
    createBtn: $("create"),
    onlineBtn: $("play-online"),
    trainingBtn: $("training"),
    difficulty: $("training-difficulty"),
    trainingControls: $("training-controls"),
    humanInvite: $("human-invite"),
    exitTraining: $("exit-training"),
    joinBtn: $("join"),
    joinCode: $("join-code"),
    joinBlock: $("join-block"),
    copyBtn: $("copy-link"),
    inviteCode: $("invite-code"),
    lobbyHint: $("lobby-hint"),
    cancelBtn: $("cancel"),
    timerFill: $("timer-fill"),
    roundTitle: $("round-title"),
    pause: $("pause-status"),
    overTitle: $("over-title"),
    overScore: $("over-score"),
    againBtn: $("again"),
    menuBtn: $("to-menu"),
    nameModal: $("name-modal"),
    nameForm: $("name-form"),
    nameTitle: $("name-title"),
    nameInput: $("player-name"),
    nameSubmit: $("name-submit"),
    nameCancel: $("name-cancel"),
    onlineCount: $("online-count"),
    onlineCountValue: $("online-count").querySelector("strong"),
    matchmakingStatus: $("matchmaking-status"),
    playerLabels: $("player-labels"),
    ownName: $("own-name"),
    opponentName: $("opponent-name"),
  };
}

const PLAYER_NAME_KEY = "twivvy-player-name";
let view = null;
let sound = null;
let connection = null;
let matchmaker = null;
let match = null;
let mySide = "bottom"; // host plays the bottom receiver
let selection = null; // { platform, dir }
let heardOwnTurn = false; // our own release already played the turn effect
let session = null;
let animation = Promise.resolve();
let running = false;
let acceptingDrag = false;
let timerFrame = null;
let roundTitleTimer = null;
let announcedRound = 0;
let nameAction = null;
let onlineCountTimer = null;
let playerName = readPlayerName();
let trainingPollTimer = null;
let trainingPollGeneration = 0;
// Rematch over the open data channel: restarts once both sides ask. The host
// picks the map so the two cannot disagree.
let rematch = { mine: false, theirs: false, map: null };

function show(el, visible) {
  el.classList.toggle("hidden", !visible);
}

function normalizePlayerName(value) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 24);
}

function readPlayerName() {
  try { return normalizePlayerName(localStorage.getItem(PLAYER_NAME_KEY)); }
  catch { return ""; }
}

function rememberPlayerName(name) {
  playerName = normalizePlayerName(name);
  try { localStorage.setItem(PLAYER_NAME_KEY, playerName); } catch {}
}

function setOnlineCount(count) {
  ui.onlineCountValue.textContent = String(Math.max(0, Number(count) || 0));
}

function stopOnlineCount() {
  clearTimeout(onlineCountTimer);
  onlineCountTimer = null;
}

async function refreshOnlineCount() {
  if (nameAction?.mode !== "online" || matchmaker) return;
  try { setOnlineCount(await onlinePlayerCount()); } catch {}
  if (nameAction?.mode === "online" && !matchmaker) {
    onlineCountTimer = setTimeout(refreshOnlineCount, 2500);
  }
}

function hideNamePrompt() {
  stopOnlineCount();
  show(ui.nameModal, false);
  nameAction = null;
}

function openNamePrompt(mode, code = null) {
  nameAction = { mode, code };
  const copy = {
    create: ["dialog.createTitle", "dialog.createSubmit"],
    join: ["dialog.joinTitle", "dialog.joinSubmit"],
    online: ["dialog.onlineTitle", "dialog.onlineSubmit"],
    training: ["dialog.trainingTitle", "dialog.trainingSubmit"],
  }[mode];
  ui.nameTitle.textContent = translate(copy[0]);
  ui.nameSubmit.textContent = translate(copy[1]);
  ui.nameSubmit.disabled = false;
  ui.nameInput.disabled = false;
  ui.nameInput.setCustomValidity("");
  ui.nameInput.value = readPlayerName();
  ui.matchmakingStatus.textContent = "";
  show(ui.matchmakingStatus, false);
  show(ui.onlineCount, mode === "online");
  show(ui.difficulty, mode === "training");
  // Entering a code belongs to "play with a friend": the other two modes reach
  // an opponent by their own route.
  show(ui.joinBlock, mode === "create");
  ui.joinCode.value = "";
  show(ui.nameModal, true);
  if (mode === "online") refreshOnlineCount();
  setTimeout(() => ui.nameInput.focus(), 0);
}

function positionPlayerNames() {
  if (!view || !connection) return;
  ui.ownName.textContent = connection.myName || playerName || translate("player.you");
  ui.opponentName.textContent = connection.peerName || translate("player.opponent");
  const own = view.receiverScreenPosition?.(mySide);
  const foeSide = mySide === "top" ? "bottom" : "top";
  const foe = view.receiverScreenPosition?.(foeSide);
  const desktop = window.innerWidth >= 900 && window.innerHeight >= 600;
  const gap = desktop ? 12 : 6;
  if (own) {
    ui.ownName.style.left = `${own.x}px`;
    ui.ownName.style.top = `${own.bottom + gap}px`;
  }
  if (foe) {
    ui.opponentName.style.left = `${foe.x}px`;
    ui.opponentName.style.top = `${foe.top - gap + (desktop ? 50 : 0)}px`;
  }
}

/** Put the room code in the address bar, so the URL itself is the invite. */
function setUrlCode(code) {
  history.replaceState(null, "", basePath() + code);
}

/** Back to the plain site address when no room is active. */
function clearUrlCode() {
  history.replaceState(null, "", basePath());
}

let toastTimer: ReturnType<typeof setTimeout> | undefined;

function toast(text, ms = 2600) {
  ui.toast.textContent = text;
  show(ui.toast, true);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => show(ui.toast, false), ms);
}

const LEGACY_MESSAGE_KEYS = new Map([
  ["Партия прервана: соперник отсутствовал более 30 минут.", "error.peerAbsent"],
  ["Не удалось согласовать сохранённую партию.", "error.restoreMismatch"],
]);

function localizeMessage(message) {
  const key = LEGACY_MESSAGE_KEYS.get(String(message));
  return key ? translate(key) : String(message);
}

function setTimerFraction(fraction) {
  const value = Math.max(0, Math.min(1, Number(fraction) || 0));
  ui.timerFill.style.transform = `scaleX(${value})`;
}

function stopTimerAnimation() {
  if (timerFrame !== null) cancelAnimationFrame(timerFrame);
  timerFrame = null;
}

// MatchSession polls the authoritative deadline slowly; the HUD reads the same
// deadline every frame, so the bar is smooth without affecting timing.
function animateTimer() {
  timerFrame = null;
  if (!running || session?.phase !== "decide") return;
  setTimerFraction(session.remaining() / session.decideMs);
  timerFrame = requestAnimationFrame(animateTimer);
}

function startTimerAnimation() {
  stopTimerAnimation();
  animateTimer();
}

function hideRoundTitle() {
  clearTimeout(roundTitleTimer);
  roundTitleTimer = null;
  ui.roundTitle.classList.toggle("playing", false);
  show(ui.roundTitle, false);
}

function announceRound(round) {
  if (round === announcedRound || round < 1 || round > TICKS) return;
  announcedRound = round;
  clearTimeout(roundTitleTimer);
  ui.roundTitle.textContent = translate("status.round", { round, total: TICKS });
  show(ui.roundTitle, true);
  ui.roundTitle.classList.toggle("playing", false);
  // Force reflow so a new round restarts the keyframes mid-cycle.
  void ui.roundTitle.offsetWidth;
  ui.roundTitle.classList.toggle("playing", true);
  roundTitleTimer = setTimeout(hideRoundTitle, 3000);
}

// ---------------------------------------------------------------------------
// Menu and connection
// ---------------------------------------------------------------------------

function newConnection() {
  const conn = new Connection();

  conn.addEventListener("error", (e: CustomEvent<any>) => {
    if (connection !== conn) return;
    const message = localizeMessage(e.detail.message);
    toast(message);
    if (!running) ui.lobbyHint.textContent = message;
  });
  conn.addEventListener("guestjoined", () => {
    if (connection !== conn || running) return;
    ui.lobbyHint.textContent = translate("status.peerFound");
  });
  conn.addEventListener("peername", () => {
    if (connection === conn) positionPlayerNames();
  });
  conn.addEventListener("peerlost", (e: CustomEvent<any>) => {
    if (connection !== conn) return;
    session?.pause(e.detail?.since);
  });
  conn.addEventListener("expired", (e: CustomEvent<any>) => {
    if (connection !== conn) return;
    if (session) session.finish(e.detail.message);
    else ui.lobbyHint.textContent = localizeMessage(e.detail.message);
  });
  conn.addEventListener("storageerror", () => {
    if (connection === conn) toast(translate("status.storageUnavailable"), 6000);
  });
  conn.addEventListener("open", () => {
    if (connection !== conn) return;
    try {
      if (!session) startMatch();
      positionPlayerNames();
      session.connected();
    } catch (err) {
      console.error("match startup failed", err);
      running = false;
      acceptingDrag = false;
      view.setInteractionEnabled?.(false);
      show(ui.hud, false);
      show(ui.menu, false);
      show(ui.lobby, true);
      ui.lobbyHint.textContent = translate("status.startupFailed");
    }
  });

  conn.addEventListener("message", (e: CustomEvent<any>) => {
    if (connection !== conn) return;
    const msg = e.detail;
    if (msg.type !== "rematch") return;
    rematch.theirs = true;

    if (mySide === "top") {
      // Guest: the map always comes from the host.
      if (Number.isInteger(msg.map)) rematch.map = msg.map;
    } else if (rematch.mine) {
      // Host: the guest asked after us and has no map yet, so resend ours.
      connection.send({ type: "rematch", map: rematch.map });
    }
    maybeRematch();
  });

  return conn;
}

/** Ask for a rematch; the match restarts when both sides have asked. */
function requestRematch() {
  if (connection?.training) {
    connection.map = Math.floor(Math.random() * MAPS.length);
    startMatch();
    session.connected();
    return;
  }
  if (rematch.mine) return;
  if (connection?.channel?.readyState !== "open") {
    toast(translate("status.peerDisconnected"));
    return;
  }

  rematch.mine = true;
  // Only the host chooses the map, so the two clients cannot disagree.
  if (mySide === "bottom") {
    rematch.map = Math.floor(Math.random() * MAPS.length);
  }

  connection.send({ type: "rematch", map: rematch.map });

  ui.againBtn.disabled = true;
  ui.againBtn.textContent = translate("status.waitingOpponent");
  maybeRematch();
}

function maybeRematch() {
  if (!rematch.mine || !rematch.theirs) return;
  if (rematch.map === null || rematch.map === undefined) return;

  const map = rematch.map;
  rematch = { mine: false, theirs: false, map: null };

  show(ui.over, false);
  connection.map = map;
  startMatch();
  session.connected();
}

async function beginMatchmaking(name) {
  stopOnlineCount();
  ui.nameInput.disabled = true;
  ui.nameSubmit.disabled = true;
  ui.nameSubmit.textContent = translate("status.finding");
  ui.matchmakingStatus.textContent = translate("status.queued");
  show(ui.matchmakingStatus, true);

  const queue = new Matchmaker();
  matchmaker?.close();
  matchmaker = queue;
  queue.addEventListener("count", (event: CustomEvent<any>) => {
    setOnlineCount(event.detail.online);
    if (!queue.match) {
      ui.matchmakingStatus.textContent = translate("status.queued");
    }
  });
  queue.addEventListener("error", (event: CustomEvent<any>) => {
    if (matchmaker !== queue) return;
    ui.matchmakingStatus.textContent = translate("status.queueRetry");
    if (event.detail?.message) console.warn("matchmaking", event.detail.message);
  });
  queue.addEventListener("matched", (event: CustomEvent<any>) => connectMatched(event.detail, queue));

  try {
    await queue.join(name);
  } catch (err) {
    if (matchmaker !== queue) return;
    console.error("matchmaking startup failed", err);
    queue.close();
    matchmaker = null;
    ui.nameInput.disabled = false;
    ui.nameSubmit.disabled = false;
    ui.nameSubmit.textContent = translate("action.connect");
    ui.matchmakingStatus.textContent = translate("status.queueFailed");
  }
}

async function connectMatched(room, queue) {
  if (matchmaker !== queue || connection) return;
  hideNamePrompt();
  const conn = newConnection();
  connection = conn;
  mySide = room.role === "host" ? "bottom" : "top";
  show(ui.menu, false);
  show(ui.lobby, true);
  show(ui.copyBtn, false);
  ui.inviteCode.textContent = room.code;
  ui.lobbyHint.textContent = translate("status.peerFound");
  setUrlCode(room.code);
  try {
    await conn.acceptMatch(room);
  } catch (err) {
    if (connection !== conn || running) return;
    console.error("matched room connection failed", err);
    conn.close();
    connection = null;
    queue.close();
    matchmaker = null;
    clearUrlCode();
    show(ui.lobby, false);
    show(ui.menu, true);
    show(ui.copyBtn, true);
    toast(translate("error.matchConnect"));
  }
}

async function createRoom(name) {
  ui.createBtn.disabled = true;
  const conn = newConnection();
  connection = conn;
  try {
    mySide = "bottom";
    const mapIndex = Math.floor(Math.random() * MAPS.length);
    await conn.host({ seed: Date.now() & 0xffff, map: mapIndex, name });
    if (connection !== conn) return;

    // The address bar now carries the room, so the URL is itself the invite.
    setUrlCode(connection.code);

    ui.inviteCode.textContent = connection.code;
    // The channel may have opened while the HTTP offer upload was pending.
    if (!running) {
      ui.lobbyHint.textContent = translate("status.waitingOpponent");
      show(ui.menu, false);
      show(ui.lobby, true);
    }

    await copyInvite();
  } catch (err) {
    if (connection !== conn || running) return;
    console.error(err);
    toast(translate("error.createRoom"));
    ui.createBtn.disabled = false;
  }
}

async function copyInvite() {
  const link = connection.inviteLink();
  try {
    await navigator.clipboard.writeText(link);
    toast(translate("status.copied"));
  } catch {
    // Clipboard needs a user gesture in some browsers; offer the raw link.
    ui.lobbyHint.textContent = link;
    toast(translate("status.copyManual"));
  }
}

async function joinRoom(code, name = playerName) {
  const conn = newConnection();
  connection = conn;
  try {
    const saved = readSession(code.toUpperCase());
    mySide = saved?.role === "host" ? "bottom" : "top";
    show(ui.menu, false);
    show(ui.lobby, true);
    ui.lobbyHint.textContent = translate("status.connecting");
    ui.inviteCode.textContent = code.toUpperCase();
    show(ui.copyBtn, false);
    setUrlCode(code.toUpperCase());

    if (saved?.token) {
      // Install the saved match before transport can emit readiness.
      conn.role = saved.role;
      conn.map = saved.map;
      if (saved.myName) rememberPlayerName(saved.myName);
      if (saved.game) startMatch(saved.game);
      await conn.resume(saved);
    } else {
      await conn.join(code, { name });
    }
  } catch (err) {
    if (connection !== conn || running) return;
    console.error(err);
    const key = err.status === 404 || err.status === 410
      ? "error.notFound"
      : err.status === 426
        ? "error.oldVersion"
      : err.status === 409
        ? "error.occupied"
        : "error.connectFailed";
    const message = translate(key);
    ui.lobbyHint.textContent = message;
    toast(message);
    // Keep the code and error visible: dropping to the menu would make a failed
    // join look like a new game.
  }
}

// ---------------------------------------------------------------------------
// Match loop
// ---------------------------------------------------------------------------

function stopTrainingPresence() {
  trainingPollGeneration++;
  clearTimeout(trainingPollTimer);
  show(ui.humanInvite, false);
}

async function pollTrainingPresence(generation = trainingPollGeneration) {
  if (!connection?.training || generation !== trainingPollGeneration) return;
  let count = 0;
  try { count = await onlinePlayerCount(); } catch {}
  if (!connection?.training || generation !== trainingPollGeneration) return;
  // The public pool pairs players in twos; use odd presence as the invitation signal.
  show(ui.humanInvite, count % 2 === 1);
  trainingPollTimer = setTimeout(() => pollTrainingPresence(generation), 5000);
}

function startTraining(name, difficulty) {
  connection = {
    training: true, role: 'host', myName: name, peerName: translate("player.bot"),
    difficulty: ['easy', 'medium', 'hard'].includes(difficulty) ? difficulty : 'medium',
    map: Math.floor(Math.random() * MAPS.length),
    close() { stopTrainingPresence(); },
  };
  clearUrlCode();
  startMatch();
  session.connected();
  stopTrainingPresence();
  pollTrainingPresence();
}

function leaveTraining() {
  if (!connection?.training) return;
  session?.dispose();
  session = null;
  connection.close();
  connection = null;
  running = false;
  acceptingDrag = false;
  stopTimerAnimation();
  hideRoundTitle();
  view.setInteractionEnabled(false);
  view.clearPreview();
  show(ui.trainingControls, false);
  show(ui.hud, false);
  show(ui.playerLabels, false);
  show(ui.over, false);
  show(ui.menu, true);
}

function startMatch(saved = null) {
  session?.dispose();
  stopTimerAnimation();
  hideRoundTitle();
  mySide = connection.role === "host" ? "bottom" : "top";
  match = saved?.match || createMatch(connection.map);
  announcedRound = saved ? match.tick + 1 : 0;
  selection = saved?.round?.selection || null;
  view.setPerspective(mySide);
  view.clearPreview();
  view.restoreMatch(match, selection);
  view.setInteractionEnabled(false);
  running = true;
  acceptingDrag = false;
  heardOwnTurn = false;

  show(ui.lobby, false);
  show(ui.menu, false);
  show(ui.over, false);
  show(ui.hud, true);
  show(ui.playerLabels, true);
  show(ui.trainingControls, Boolean(connection.training));
  positionPlayerNames();
  requestAnimationFrame(positionPlayerNames);

  const Session = connection.training ? TrainingSession : MatchSession;
  session = new Session(connection, {
    saved,
    decideMs: Number(window.__TWIVVY_DECIDE_MS) || DECIDE_MS,
    lock() {
      stopTimerAnimation();
      setTimerFraction(0);
      view.setInteractionEnabled(false);
      acceptingDrag = false;
    },
    paused() {
      stopTimerAnimation();
      show(ui.pause, true);
      ui.pause.textContent = translate("status.peerDisconnected");
      setTimerFraction(session?.remaining() / (Number(window.__TWIVVY_DECIDE_MS) || DECIDE_MS));
    },
    async restore(state, command) {
      await animation;
      match = state;
      selection = command;
      view.restoreMatch(state, command);
    },
    active(canChoose) {
      show(ui.pause, false);
      acceptingDrag = canChoose;
      view.setInteractionEnabled(canChoose);
      setTimerFraction(session.remaining() / session.decideMs);
      if (canChoose) {
        announceRound(session.match.tick + 1);
        startTimerAnimation();
      }
    },
    timer(fraction) {
      // Fallback while animation frames are suspended (tab becoming visible).
      if (timerFrame === null) setTimerFraction(fraction);
    },
    async resolved(event, before, after) {
      const currentSession = session;
      match = after;
      selection = null;
      // The opponent's turn is only ever seen here, so it is only ever heard
      // here. Our own turn already sounded on release, and plays again only if
      // it was taken over by the deadline instead of released by hand.
      const foeSide = mySide === "top" ? "bottom" : "top";
      const turned = event.commands || {};
      if (turned[foeSide] || (turned[mySide] && !heardOwnTurn)) {
        sound?.play('turn');
      }
      heardOwnTurn = false;
      animation = view.playTick(event, before, after, RESOLVE_MS);
      await animation;
      if (session !== currentSession) return;
      // Both receivers use the same effect, once when the balls arrive.
      if (event.delivered.length) sound?.play('delivery');
      view.setCooldown(after.cooldown);
    },
    finished(reason) {
      stopTimerAnimation();
      running = false;
      endMatch(reason);
    },
  });
  if (session.ended) {
    running = false;
    endMatch(session.ended === true ? null : session.ended);
  } else if (saved) {
    show(ui.pause, true);
    ui.pause.textContent = translate("status.peerDisconnected");
    setTimerFraction(session.remaining() / session.decideMs);
  }
}

function endMatch(reason) {
  stopTimerAnimation();
  hideRoundTitle();
  view.syncSourceMarkers({ tick: match.tick, finished: true });
  show(ui.pause, false);
  acceptingDrag = false;
  view.setInteractionEnabled(false);
  show(ui.hud, false);
  show(ui.playerLabels, false);
  show(ui.over, true);

  // A rematch reuses the channel, so the link stays valid while the peer is up.
  rematch = { mine: false, theirs: false, map: null };
  const canRematch = connection?.training || connection?.channel?.readyState === "open";
  show(ui.againBtn, canRematch);
  ui.againBtn.disabled = false;
  ui.againBtn.textContent = translate("action.rematch");

  const foeSide = mySide === "top" ? "bottom" : "top";
  const mine = match.score[mySide];
  const theirs = match.score[foeSide];

  if (reason) {
    ui.overTitle.textContent = localizeMessage(reason);
  } else {
    const result = matchResult(match);
    ui.overTitle.textContent =
      result === "draw" ? translate("result.draw") : result === mySide ? translate("result.win") : translate("result.loss");
  }
  ui.overScore.textContent = `${mine} : ${theirs}`;
}

// ---------------------------------------------------------------------------
// Platform drag interaction
// ---------------------------------------------------------------------------

function beginPlatformDrag(platform) {
  if (!running || !acceptingDrag) return false;
  if (match.cooldown.includes(platform)) {
    toast(translate("error.platformCooldown"), 1200);
    return false;
  }
  return true;
}

function finishPlatformDrag(platform, dir) {
  if (!running || !acceptingDrag) return;
  selection = dir === null ? null : { platform, dir };
  session?.choose(selection);
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

let initialized = false;

export function init() {
  if (initialized) return;
  initialized = true;
  ui = bindUi();
  sound = new GameAudio();
  const soundToggle = $('sound-toggle');
  const updateSoundToggle = () => {
    soundToggle.setAttribute('aria-pressed', String(sound.enabled));
    soundToggle.title = translate(sound.enabled ? "sound.disable" : "sound.enable");
  };
  updateSoundToggle();
  soundToggle.addEventListener('click', () => {
    sound.setEnabled(!sound.enabled);
    updateSoundToggle();
  });
  // Resume synchronously inside a trusted gesture, including Safari's release
  // gesture, so later receiver arrivals can play without another tap.
  for (const type of ['pointerdown', 'pointerup', 'keydown']) {
    window.addEventListener(type, () => sound.unlock(), { capture: true, passive: true });
  }
  view = new BoardView($("scene"), {
    onPlatformDragStart: beginPlatformDrag,
    onPlatformDrag: finishPlatformDrag,
    onPlatformRelease: () => {
      // _finishDrag commits through onPlatformDrag first, so `selection` already
      // says whether this release was a committed turn or a reset back to zero.
      if (selection) heardOwnTurn = true;
      sound.play('turn');
    },
  });
  view.start();

  // Exposed for automated UI tests and for debugging a live match.
  window.__twivvy = {
    view,
    getSelection: () => selection,
    getMatch: () => match,
    getConnection: () => connection,
    getSession: () => session,
  };

  ui.createBtn.addEventListener("click", () => openNamePrompt("create"));
  ui.onlineBtn.addEventListener("click", () => openNamePrompt("online"));
  ui.trainingBtn.addEventListener("click", () => openNamePrompt("training"));
  ui.exitTraining.addEventListener("click", leaveTraining);
  ui.humanInvite.addEventListener("click", () => {
    leaveTraining();
    openNamePrompt("online");
  });
  ui.copyBtn.addEventListener("click", copyInvite);
  // Joining by code now lives in the same modal as creating a room, so the name
  // is already on screen: validate it here rather than reopening the prompt.
  ui.joinBtn.addEventListener("click", () => {
    const code = ui.joinCode.value.trim().toUpperCase();
    if (!code) {
      ui.joinCode.focus();
      return;
    }
    const name = normalizePlayerName(ui.nameInput.value);
    if (!name) {
      ui.nameInput.setCustomValidity(translate("error.nameRequired"));
      ui.nameInput.reportValidity();
      return;
    }
    ui.nameInput.setCustomValidity("");
    rememberPlayerName(name);
    hideNamePrompt();
    joinRoom(code, name);
  });
  ui.joinCode.addEventListener("keydown", (e) => {
    // Enter inside the code field means "join", not "create the room".
    if (e.key === "Enter") {
      e.preventDefault();
      ui.joinBtn.click();
    }
  });

  ui.nameForm.addEventListener("submit", event => {
    event.preventDefault();
    const action = nameAction;
    const name = normalizePlayerName(ui.nameInput.value);
    if (!action || !name) {
      ui.nameInput.setCustomValidity(translate("error.nameRequired"));
      ui.nameInput.reportValidity();
      return;
    }
    ui.nameInput.setCustomValidity("");
    rememberPlayerName(name);
    if (action.mode === "online") {
      beginMatchmaking(name);
      return;
    }
    if (action.mode === "training") {
      const difficulty = ui.difficulty.querySelector('input:checked')?.value || 'medium';
      hideNamePrompt();
      startTraining(name, difficulty);
      return;
    }
    hideNamePrompt();
    if (action.mode === "create") createRoom(name);
    else joinRoom(action.code, name);
  });

  ui.nameInput.addEventListener("input", () => ui.nameInput.setCustomValidity(""));
  ui.nameCancel.addEventListener("click", () => {
    const wasInvite = nameAction?.mode === "join" && Boolean(codeFromLocation());
    matchmaker?.close();
    matchmaker = null;
    hideNamePrompt();
    if (wasInvite) clearUrlCode();
    show(ui.menu, true);
  });

  ui.cancelBtn.addEventListener("click", () => {
    session?.dispose();
    stopTimerAnimation();
    hideRoundTitle();
    session = null;
    running = false;
    connection?.close();
    connection = null;
    matchmaker?.close();
    matchmaker = null;
    show(ui.lobby, false);
    show(ui.playerLabels, false);
    show(ui.menu, true);
    ui.createBtn.disabled = false;
    show(ui.copyBtn, true);
    clearUrlCode();
  });

  ui.menuBtn.addEventListener("click", () => {
    if (connection?.training) { leaveTraining(); return; }
    session?.dispose();
    stopTimerAnimation();
    hideRoundTitle();
    session = null;
    running = false;
    connection?.close();
    connection = null;
    matchmaker?.close();
    matchmaker = null;
    show(ui.over, false);
    show(ui.hud, false);
    show(ui.playerLabels, false);
    show(ui.menu, true);
    ui.createBtn.disabled = false;
    show(ui.copyBtn, true);
    clearUrlCode();
  });

  // The peer connection outlives a match, so the original invite still works.
  ui.againBtn.addEventListener("click", requestRematch);

  // An invite link lands here as /CODE (older links used ?game= or ?join=).
  window.addEventListener("resize", positionPlayerNames);

  const code = codeFromLocation();
  if (code) {
    // The code rides in nameAction, not the input: an invite opens "join" mode,
    // where the code block is hidden.
    const saved = readSession(code);
    if (saved?.token) {
      if (saved.myName) rememberPlayerName(saved.myName);
      joinRoom(code, saved.myName || playerName || translate("player.you"));
    } else {
      openNamePrompt("join", code);
    }
  }
}
