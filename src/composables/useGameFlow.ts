import { computed, ref, shallowRef } from "vue";
import { codeFromLocation, readSession } from "../../js/net.js";
import type { BoardView } from "../../js/view.js";
import {
  DEFAULT_DIFFICULTY,
  ONLINE_COUNT_POLL_MS,
  TOAST_COOLDOWN_MS,
  TOAST_STORAGE_MS,
  TRAINING_PRESENCE_POLL_MS,
} from "../constants/index.ts";
import { translate } from "../i18n.ts";
import type {
  Difficulty, MatchedRoom, NamePrompt, NamePromptMode, RematchState,
} from "../types/index.ts";
import { useConnection } from "./useConnection.ts";
import { useMatch } from "./useMatch.ts";
import { usePlayerName } from "./usePlayerName.ts";
import { useRoundTitle } from "./useRoundTitle.ts";
import { useToast } from "./useToast.ts";
import { onlinePlayerCount } from "../../js/net.js";

/**
 * The menu → room → match flow. Holds the screen state the components render
 * and owns every transition the old imperative controller performed by hand.
 */
export function useGameFlow() {
  const conn = useConnection();
  const game = useMatch();
  const round = useRoundTitle();
  const { toast } = useToast();
  const { playerName, remember } = usePlayerName();

  const view = shallowRef<BoardView | null>(null);
  const prompt = ref<NamePrompt | null>(null);
  const matchmakingStatus = ref("");
  const dialogBusy = ref(false);
  const lobbyVisible = ref(false);
  const lobbyHint = ref("");
  const lobbyCode = ref("");
  const showCopy = ref(true);
  const showHumanInvite = ref(false);
  const rematch = ref<RematchState>({ mine: false, theirs: false, map: null });

  let onlineCountTimer: ReturnType<typeof setTimeout> | undefined;
  let trainingPollTimer: ReturnType<typeof setTimeout> | undefined;
  let trainingPollGeneration = 0;

  const menuVisible = computed(
    () => !lobbyVisible.value && !game.running.value && !game.finished.value,
  );
  const submitLabel = computed(() => {
    if (!prompt.value) return "";
    if (dialogBusy.value) return translate("status.finding");
    return translate(
      prompt.value.mode === "create" ? "dialog.createSubmit"
        : prompt.value.mode === "join" ? "dialog.joinSubmit"
        : prompt.value.mode === "online" ? "dialog.onlineSubmit"
        : "dialog.trainingSubmit",
    );
  });
  const canRematch = computed(
    () => Boolean(conn.connection.value?.training)
      || conn.connection.value?.channel?.readyState === "open",
  );

  // -------------------------------------------------------------------------
  // Name dialog
  // -------------------------------------------------------------------------

  function openPrompt(mode: NamePromptMode, code: string | null = null): void {
    prompt.value = { mode, code };
    matchmakingStatus.value = "";
    dialogBusy.value = false;
    if (mode === "online") pollOnlineCount();
  }

  function closePrompt(): void {
    stopOnlineCount();
    prompt.value = null;
    dialogBusy.value = false;
  }

  function stopOnlineCount(): void {
    clearTimeout(onlineCountTimer);
    onlineCountTimer = undefined;
  }

  async function pollOnlineCount(): Promise<void> {
    if (prompt.value?.mode !== "online" || conn.matchmaker.value) return;
    await conn.refreshOnlineCount();
    if (prompt.value?.mode === "online" && !conn.matchmaker.value) {
      onlineCountTimer = setTimeout(pollOnlineCount, ONLINE_COUNT_POLL_MS);
    }
  }

  // -------------------------------------------------------------------------
  // Connection wiring
  // -------------------------------------------------------------------------

  function newConnection() {
    const created = conn.create();

    created.addEventListener("error", (event: Event) => {
      if (!conn.isCurrent(created)) return;
      const message = conn.localizeMessage((event as CustomEvent).detail?.message);
      toast(message);
      if (!game.running.value) lobbyHint.value = message;
    });
    created.addEventListener("guestjoined", () => {
      if (!conn.isCurrent(created) || game.running.value) return;
      lobbyHint.value = translate("status.peerFound");
    });
    created.addEventListener("peername", () => {
      if (conn.isCurrent(created)) refreshNames();
    });
    // pause/finish exist only on a networked MatchSession: a training session
    // has no peer, so these events cannot reach it.
    created.addEventListener("peerlost", (event: Event) => {
      if (!conn.isCurrent(created)) return;
      const session = game.session.value;
      if (session && "pause" in session) session.pause((event as CustomEvent).detail?.since);
    });
    created.addEventListener("expired", (event: Event) => {
      if (!conn.isCurrent(created)) return;
      const message = (event as CustomEvent).detail?.message;
      const session = game.session.value;
      if (session && "finish" in session) session.finish(message);
      else lobbyHint.value = conn.localizeMessage(message);
    });
    created.addEventListener("storageerror", () => {
      if (conn.isCurrent(created)) {
        toast(translate("status.storageUnavailable"), TOAST_STORAGE_MS);
      }
    });
    created.addEventListener("open", () => {
      if (!conn.isCurrent(created)) return;
      try {
        if (!game.session.value) beginMatch();
        refreshNames();
        game.session.value?.connected();
      } catch (error) {
        console.error("match startup failed", error);
        game.dispose();
        lobbyVisible.value = true;
        lobbyHint.value = translate("status.startupFailed");
      }
    });
    created.addEventListener("message", (event: Event) => {
      if (!conn.isCurrent(created)) return;
      const message = (event as CustomEvent).detail;
      if (message?.type !== "rematch") return;
      rematch.value.theirs = true;
      if (game.mySide.value === "top") {
        // Guest: the map always comes from the host.
        if (Number.isInteger(message.map)) rematch.value.map = message.map;
      } else if (rematch.value.mine) {
        // Host: the guest asked after us and has no map yet, so resend ours.
        conn.connection.value?.send({ type: "rematch", map: rematch.value.map });
      }
      maybeRematch();
    });

    return created;
  }

  // -------------------------------------------------------------------------
  // Match lifecycle
  // -------------------------------------------------------------------------

  function beginMatch(saved: unknown = null): void {
    if (!view.value || !conn.connection.value) return;
    lobbyVisible.value = false;
    round.reset(saved ? undefined : 0);
    game.start(conn.connection.value, view.value, {
      localizeMessage: conn.localizeMessage,
      announceRound: round.announce,
      onFinished() {
        rematch.value = { mine: false, theirs: false, map: null };
        round.hide();
      },
    }, saved);
    refreshNames();
  }

  function requestRematch(): void {
    const connection = conn.connection.value;
    if (connection?.training) {
      connection.map = conn.randomMap();
      beginMatch();
      game.session.value?.connected();
      return;
    }
    if (rematch.value.mine) return;
    if (connection?.channel?.readyState !== "open") {
      toast(translate("status.peerDisconnected"));
      return;
    }
    rematch.value.mine = true;
    // Only the host chooses the map, so the two clients cannot disagree.
    if (game.mySide.value === "bottom") rematch.value.map = conn.randomMap();
    connection.send({ type: "rematch", map: rematch.value.map });
    maybeRematch();
  }

  function maybeRematch(): void {
    const state = rematch.value;
    if (!state.mine || !state.theirs || state.map === null) return;
    const map = state.map;
    rematch.value = { mine: false, theirs: false, map: null };
    if (conn.connection.value) conn.connection.value.map = map;
    beginMatch();
    game.session.value?.connected();
  }

  // -------------------------------------------------------------------------
  // Player labels
  // -------------------------------------------------------------------------

  const ownName = ref("");
  const opponentName = ref("");

  function refreshNames(): void {
    const connection = conn.connection.value;
    ownName.value = connection?.myName || playerName.value || translate("player.you");
    opponentName.value = connection?.peerName || translate("player.opponent");
  }

  // -------------------------------------------------------------------------
  // Training
  // -------------------------------------------------------------------------

  function stopTrainingPresence(): void {
    trainingPollGeneration++;
    clearTimeout(trainingPollTimer);
    trainingPollTimer = undefined;
    showHumanInvite.value = false;
  }

  async function pollTrainingPresence(generation = trainingPollGeneration): Promise<void> {
    if (!conn.connection.value?.training || generation !== trainingPollGeneration) return;
    let count = 0;
    try {
      count = await onlinePlayerCount();
    } catch {
      // Presence is advisory; a failed poll just retries.
    }
    if (!conn.connection.value?.training || generation !== trainingPollGeneration) return;
    // The public pool pairs players in twos: odd presence means someone waits.
    showHumanInvite.value = count % 2 === 1;
    trainingPollTimer = setTimeout(
      () => pollTrainingPresence(generation),
      TRAINING_PRESENCE_POLL_MS,
    );
  }

  function startTraining(name: string, difficulty: Difficulty): void {
    conn.setConnection({
      training: true,
      role: "host",
      myName: name,
      peerName: translate("player.bot"),
      difficulty: difficulty || DEFAULT_DIFFICULTY,
      map: conn.randomMap(),
      close: () => stopTrainingPresence(),
    });
    conn.clearUrlCode();
    beginMatch();
    game.session.value?.connected();
    stopTrainingPresence();
    pollTrainingPresence();
  }

  function leaveTraining(): void {
    if (!conn.connection.value?.training) return;
    game.dispose();
    conn.closeConnection();
    round.hide();
    view.value?.setInteractionEnabled(false);
    view.value?.clearPreview();
    game.finished.value = false;
  }

  // -------------------------------------------------------------------------
  // Board interaction
  // -------------------------------------------------------------------------

  function onDragStart(platform: number, allow: (value: boolean) => void): void {
    const permitted = game.beginDrag(platform);
    if (!permitted && game.running.value && game.acceptingDrag.value) {
      toast(translate("error.platformCooldown"), TOAST_COOLDOWN_MS);
    }
    allow(permitted);
  }

  return {
    conn, game, round, view, prompt, matchmakingStatus, dialogBusy,
    lobbyVisible, lobbyHint, lobbyCode, showCopy, showHumanInvite, rematch,
    menuVisible, submitLabel, canRematch, ownName, opponentName,
    openPrompt, closePrompt, pollOnlineCount, stopOnlineCount,
    newConnection, beginMatch, requestRematch, maybeRematch, refreshNames,
    startTraining, leaveTraining, stopTrainingPresence, pollTrainingPresence,
    onDragStart, toast, remember, playerName,
    codeFromLocation, readSession,
  };
}
