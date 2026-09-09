// Match controller: menu flow, invite links, tick loop, UI state.

import {
  createMatch,
  matchResult,
  MAPS,
  DECIDE_MS,
  RESOLVE_MS,
  TICKS,
} from "./rules.js?v=20260909-names-layout2";
import { BoardView } from "./view.js?v=20260909-names-layout2";
import {
  Connection,
  Matchmaker,
  onlinePlayerCount,
  readSession,
  basePath,
  codeFromLocation,
} from "./net.js?v=20260909-names-layout2";

import { MatchSession } from "./session.js?v=20260909-names-layout2";

const $ = (id) => document.getElementById(id);

const ui = {
  menu: $("menu"),
  lobby: $("lobby"),
  hud: $("hud"),
  over: $("over"),
  toast: $("toast"),
  createBtn: $("create"),
  onlineBtn: $("play-online"),
  joinBtn: $("join"),
  joinCode: $("join-code"),
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

const PLAYER_NAME_KEY = "twivvy-player-name";
let view = null;
let connection = null;
let matchmaker = null;
let match = null;
let mySide = "bottom"; // host plays the bottom receiver
let selection = null; // { platform, dir }
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
    create: ["Играть с другом", "Создать комнату"],
    join: ["Войти в игру", "Войти"],
    online: ["Случайный соперник", "Подключиться"],
  }[mode];
  ui.nameTitle.textContent = copy[0];
  ui.nameSubmit.textContent = copy[1];
  ui.nameSubmit.disabled = false;
  ui.nameInput.disabled = false;
  ui.nameInput.setCustomValidity("");
  ui.nameInput.value = readPlayerName();
  ui.matchmakingStatus.textContent = "";
  show(ui.matchmakingStatus, false);
  show(ui.onlineCount, mode === "online");
  show(ui.nameModal, true);
  if (mode === "online") refreshOnlineCount();
  setTimeout(() => ui.nameInput.focus(), 0);
}

function positionPlayerNames() {
  if (!view || !connection) return;
  ui.ownName.textContent = connection.myName || playerName || "Игрок";
  ui.opponentName.textContent = connection.peerName || "Соперник";
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

function toast(text, ms = 2600) {
  ui.toast.textContent = text;
  show(ui.toast, true);
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => show(ui.toast, false), ms);
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
  ui.roundTitle.textContent = `Раунд ${round} из ${TICKS}`;
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

  conn.addEventListener("error", (e) => {
    if (connection !== conn) return;
    toast(e.detail.message);
    if (!running) ui.lobbyHint.textContent = e.detail.message;
  });
  conn.addEventListener("guestjoined", () => {
    if (connection !== conn || running) return;
    ui.lobbyHint.textContent = "Соперник найден, устанавливаем связь…";
  });
  conn.addEventListener("peername", () => {
    if (connection === conn) positionPlayerNames();
  });
  conn.addEventListener("peerlost", e => {
    if (connection !== conn) return;
    session?.pause(e.detail?.since);
  });
  conn.addEventListener("expired", e => {
    if (connection !== conn) return;
    if (session) session.finish(e.detail.message);
    else ui.lobbyHint.textContent = e.detail.message;
  });
  conn.addEventListener("storageerror", () => {
    if (connection === conn) toast("Браузер не разрешает сохранять партию. Не закрывайте эту вкладку.", 6000);
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
      ui.lobbyHint.textContent = "Не удалось запустить игру. Обновите страницу у обоих игроков.";
    }
  });

  conn.addEventListener("message", (e) => {
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
  if (rematch.mine) return;
  if (connection?.channel?.readyState !== "open") {
    toast("Соперник отключился");
    return;
  }

  rematch.mine = true;
  // Only the host chooses the map, so the two clients cannot disagree.
  if (mySide === "bottom") {
    rematch.map = Math.floor(Math.random() * MAPS.length);
  }

  connection.send({ type: "rematch", map: rematch.map });

  ui.againBtn.disabled = true;
  ui.againBtn.textContent = "Ждём соперника…";
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
  ui.nameSubmit.textContent = "Ищем соперника…";
  ui.matchmakingStatus.textContent = "Вы в очереди. Подбираем соперника…";
  show(ui.matchmakingStatus, true);

  const queue = new Matchmaker();
  matchmaker?.close();
  matchmaker = queue;
  queue.addEventListener("count", event => {
    setOnlineCount(event.detail.online);
    if (!queue.match) {
      ui.matchmakingStatus.textContent = "Вы в очереди. Подбираем соперника…";
    }
  });
  queue.addEventListener("error", event => {
    if (matchmaker !== queue) return;
    ui.matchmakingStatus.textContent = "Связь с очередью прервана. Повторяем попытку…";
    if (event.detail?.message) console.warn("matchmaking", event.detail.message);
  });
  queue.addEventListener("matched", event => connectMatched(event.detail, queue));

  try {
    await queue.join(name);
  } catch (err) {
    if (matchmaker !== queue) return;
    console.error("matchmaking startup failed", err);
    queue.close();
    matchmaker = null;
    ui.nameInput.disabled = false;
    ui.nameSubmit.disabled = false;
    ui.nameSubmit.textContent = "Подключиться";
    ui.matchmakingStatus.textContent = "Не удалось войти в очередь. Попробуйте ещё раз.";
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
  ui.lobbyHint.textContent = "Соперник найден, устанавливаем связь…";
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
    toast("Не удалось подключиться к найденному сопернику.");
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
      ui.lobbyHint.textContent = "Ждём соперника…";
      show(ui.menu, false);
      show(ui.lobby, true);
    }

    await copyInvite();
  } catch (err) {
    if (connection !== conn || running) return;
    console.error(err);
    toast("Не удалось создать комнату.");
    ui.createBtn.disabled = false;
  }
}

async function copyInvite() {
  const link = connection.inviteLink();
  try {
    await navigator.clipboard.writeText(link);
    toast("Ссылка скопирована в буфер обмена");
  } catch {
    // Clipboard needs a user gesture in some browsers; offer the raw link.
    ui.lobbyHint.textContent = link;
    toast("Скопируйте ссылку вручную");
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
    ui.lobbyHint.textContent = "Подключаемся…";
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
    const message = err.status === 404 || err.status === 410
      ? "Комната не найдена или срок приглашения истёк. Попросите новую ссылку."
      : err.status === 426
        ? "Игра создана старой версией. Обновите страницу у обоих игроков и создайте новую комнату."
      : err.status === 409
        ? "Место занято. Вернитесь в исходную вкладку игры."
        : "Не удалось подключиться. Обновите страницу, чтобы повторить вход.";
    ui.lobbyHint.textContent = message;
    toast(message);
    // Keep the code and error visible: dropping to the menu would make a failed
    // join look like a new game.
  }
}

// ---------------------------------------------------------------------------
// Match loop
// ---------------------------------------------------------------------------

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

  show(ui.lobby, false);
  show(ui.menu, false);
  show(ui.over, false);
  show(ui.hud, true);
  show(ui.playerLabels, true);
  positionPlayerNames();
  requestAnimationFrame(positionPlayerNames);

  session = new MatchSession(connection, {
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
      ui.pause.textContent = "Соперник отсоединился";
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
      match = after;
      selection = null;
      animation = view.playTick(event, before, after, RESOLVE_MS);
      await animation;
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
    ui.pause.textContent = "Соперник отсоединился";
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
  const canRematch = connection?.channel?.readyState === "open";
  show(ui.againBtn, canRematch);
  ui.againBtn.disabled = false;
  ui.againBtn.textContent = "Реванш";

  const foeSide = mySide === "top" ? "bottom" : "top";
  const mine = match.score[mySide];
  const theirs = match.score[foeSide];

  if (reason) {
    ui.overTitle.textContent = reason;
  } else {
    const result = matchResult(match);
    ui.overTitle.textContent =
      result === "draw" ? "Ничья" : result === mySide ? "Победа" : "Поражение";
  }
  ui.overScore.textContent = `${mine} : ${theirs}`;
}

// ---------------------------------------------------------------------------
// Platform drag interaction
// ---------------------------------------------------------------------------

function beginPlatformDrag(platform) {
  if (!running || !acceptingDrag) return false;
  if (match.cooldown.includes(platform)) {
    toast("Платформа на охлаждении", 1200);
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

function init() {
  view = new BoardView($("scene"), {
    onPlatformDragStart: beginPlatformDrag,
    onPlatformDrag: finishPlatformDrag,
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
  ui.copyBtn.addEventListener("click", copyInvite);
  ui.joinBtn.addEventListener("click", () => {
    const code = ui.joinCode.value.trim();
    if (code) openNamePrompt("join", code.toUpperCase());
  });
  ui.joinCode.addEventListener("keydown", (e) => {
    if (e.key === "Enter") ui.joinBtn.click();
  });

  ui.nameForm.addEventListener("submit", event => {
    event.preventDefault();
    const action = nameAction;
    const name = normalizePlayerName(ui.nameInput.value);
    if (!action || !name) {
      ui.nameInput.setCustomValidity("Введите имя");
      ui.nameInput.reportValidity();
      return;
    }
    ui.nameInput.setCustomValidity("");
    rememberPlayerName(name);
    if (action.mode === "online") {
      beginMatchmaking(name);
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
    ui.joinCode.value = code;
    const saved = readSession(code);
    if (saved?.token) {
      if (saved.myName) rememberPlayerName(saved.myName);
      joinRoom(code, saved.myName || playerName || "Игрок");
    } else {
      openNamePrompt("join", code);
    }
  }
}

init();
