<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from "vue";
import type { CSSProperties } from "vue";
import GameBoard from "./components/GameBoard.vue";
import GameHud from "./components/GameHud.vue";
import GameLobby from "./components/GameLobby.vue";
import GameOver from "./components/GameOver.vue";
import MainMenu from "./components/MainMenu.vue";
import NameDialog from "./components/NameDialog.vue";
import PlayerLabels from "./components/PlayerLabels.vue";
import RoundTitle from "./components/RoundTitle.vue";
import SoundToggle from "./components/SoundToggle.vue";
import ToastMessage from "./components/ToastMessage.vue";
import TrainingControls from "./components/TrainingControls.vue";
import { Matchmaker } from "../js/net.js";
import { useGameFlow } from "./composables/useGameFlow.ts";
import { useSound } from "./composables/useSound.ts";
import {
  DESKTOP_MIN_HEIGHT, DESKTOP_MIN_WIDTH, LABEL_GAP_DESKTOP, LABEL_GAP_MOBILE,
  OPPONENT_LABEL_DESKTOP_OFFSET,
} from "./constants/index.ts";
import { translate } from "./i18n.ts";
import type { BoardView } from "../js/view.js";
import type { Difficulty, RotationDir } from "./types/index.ts";

const flow = useGameFlow();
const { game, conn, round } = flow;
const sound = useSound();

const ownStyle = reactive<CSSProperties>({});
const opponentStyle = reactive<CSSProperties>({});

const hudVisible = computed(() => game.running.value && !game.finished.value);
const labelsVisible = computed(() => game.running.value && !game.finished.value);

let releaseUnlock: (() => void) | undefined;

function onBoardReady(view: BoardView): void {
  flow.view.value = view;
  positionLabels();
  requestAnimationFrame(positionLabels);
}

/** Place the name labels over each receiver, reading the live 3D projection. */
function positionLabels(): void {
  const view = flow.view.value;
  if (!view?.receiverScreenPosition) return;
  const desktop =
    window.innerWidth >= DESKTOP_MIN_WIDTH && window.innerHeight >= DESKTOP_MIN_HEIGHT;
  const gap = desktop ? LABEL_GAP_DESKTOP : LABEL_GAP_MOBILE;
  const own = view.receiverScreenPosition(game.mySide.value);
  const foe = view.receiverScreenPosition(game.foeSide.value);
  if (own) {
    ownStyle.left = `${own.x}px`;
    ownStyle.top = `${own.bottom + gap}px`;
  }
  if (foe) {
    opponentStyle.left = `${foe.x}px`;
    opponentStyle.top = `${foe.top - gap + (desktop ? OPPONENT_LABEL_DESKTOP_OFFSET : 0)}px`;
  }
}

function onDrag(platform: number, dir: RotationDir | null): void {
  game.commitDrag(platform, dir);
}

function onDialogSubmit({ name, difficulty }: { name: string; difficulty: Difficulty }): void {
  flow.remember(name);
  const mode = flow.prompt.value?.mode;
  if (mode === "online") {
    void beginMatchmaking(name);
    return;
  }
  if (mode === "training") {
    flow.closePrompt();
    flow.startTraining(name, difficulty);
    return;
  }
  const code = flow.prompt.value?.code ?? null;
  flow.closePrompt();
  if (mode === "create") void createRoom(name);
  else if (code) void joinRoom(code, name);
}

function onDialogJoin({ code, name }: { code: string; name: string }): void {
  flow.remember(name);
  flow.closePrompt();
  void joinRoom(code, name);
}

function onDialogCancel(): void {
  const wasInvite = flow.prompt.value?.mode === "join" && Boolean(flow.codeFromLocation());
  conn.closeMatchmaker();
  flow.closePrompt();
  if (wasInvite) conn.clearUrlCode();
}

async function beginMatchmaking(name: string): Promise<void> {
  flow.stopOnlineCount();
  flow.dialogBusy.value = true;
  flow.matchmakingStatus.value = translate("status.queued");

  const queue = new Matchmaker();
  conn.matchmaker.value?.close();
  conn.matchmaker.value = queue;

  queue.addEventListener("count", (event: Event) => {
    conn.onlineCount.value = (event as CustomEvent).detail?.online ?? 0;
    if (!queue.match) flow.matchmakingStatus.value = translate("status.queued");
  });
  queue.addEventListener("error", (event: Event) => {
    if (conn.matchmaker.value !== queue) return;
    flow.matchmakingStatus.value = translate("status.queueRetry");
    const message = (event as CustomEvent).detail?.message;
    if (message) console.warn("matchmaking", message);
  });
  queue.addEventListener("matched", (event: Event) => {
    void connectMatched((event as CustomEvent).detail, queue);
  });

  try {
    await queue.join(name);
  } catch (error) {
    if (conn.matchmaker.value !== queue) return;
    console.error("matchmaking startup failed", error);
    queue.close();
    conn.matchmaker.value = null;
    flow.dialogBusy.value = false;
    flow.matchmakingStatus.value = translate("status.queueFailed");
  }
}

async function connectMatched(room: any, queue: any): Promise<void> {
  if (conn.matchmaker.value !== queue || conn.connection.value) return;
  flow.closePrompt();
  const created = flow.newConnection();
  conn.setConnection(created);
  game.mySide.value = room.role === "host" ? "bottom" : "top";
  flow.lobbyVisible.value = true;
  flow.showCopy.value = false;
  flow.lobbyCode.value = room.code;
  flow.lobbyHint.value = translate("status.peerFound");
  conn.setUrlCode(room.code);
  try {
    await created.acceptMatch(room);
  } catch (error) {
    if (!conn.isCurrent(created) || game.running.value) return;
    console.error("matched room connection failed", error);
    created.close();
    conn.setConnection(null);
    queue.close();
    conn.matchmaker.value = null;
    conn.clearUrlCode();
    flow.lobbyVisible.value = false;
    flow.showCopy.value = true;
    flow.toast(translate("error.matchConnect"));
  }
}

async function createRoom(name: string): Promise<void> {
  const created = flow.newConnection();
  conn.setConnection(created);
  try {
    game.mySide.value = "bottom";
    await created.host({ seed: Date.now() & 0xffff, map: conn.randomMap(), name });
    if (!conn.isCurrent(created)) return;
    // The address bar now carries the room, so the URL is itself the invite.
    conn.setUrlCode(created.code);
    flow.lobbyCode.value = created.code;
    // The channel may have opened while the HTTP offer upload was pending.
    if (!game.running.value) {
      flow.lobbyHint.value = translate("status.waitingOpponent");
      flow.lobbyVisible.value = true;
    }
    await copyInvite();
  } catch (error) {
    if (!conn.isCurrent(created) || game.running.value) return;
    console.error(error);
    flow.toast(translate("error.createRoom"));
  }
}

async function copyInvite(): Promise<void> {
  const link = conn.connection.value?.inviteLink();
  if (!link) return;
  try {
    await navigator.clipboard.writeText(link);
    flow.toast(translate("status.copied"));
  } catch {
    // Clipboard needs a user gesture in some browsers; offer the raw link.
    flow.lobbyHint.value = link;
    flow.toast(translate("status.copyManual"));
  }
}

async function joinRoom(code: string, name = flow.playerName.value): Promise<void> {
  const created = flow.newConnection();
  conn.setConnection(created);
  const upper = code.toUpperCase();
  try {
    const saved = flow.readSession(upper);
    game.mySide.value = saved?.role === "host" ? "bottom" : "top";
    flow.lobbyVisible.value = true;
    flow.lobbyHint.value = translate("status.connecting");
    flow.lobbyCode.value = upper;
    flow.showCopy.value = false;
    conn.setUrlCode(upper);

    if (saved?.token) {
      // Install the saved match before transport can emit readiness.
      created.role = saved.role;
      created.map = saved.map;
      if (saved.myName) flow.remember(saved.myName);
      if (saved.game) flow.beginMatch(saved.game);
      await created.resume(saved);
    } else {
      await created.join(upper, { name });
    }
  } catch (error) {
    if (!conn.isCurrent(created) || game.running.value) return;
    console.error(error);
    const status = (error as { status?: number }).status;
    const key = status === 404 || status === 410 ? "error.notFound"
      : status === 426 ? "error.oldVersion"
      : status === 409 ? "error.occupied"
      : "error.connectFailed";
    const message = translate(key);
    // Keep the code and error visible: dropping to the menu would make a
    // failed join look like a new game.
    flow.lobbyHint.value = message;
    flow.toast(message);
  }
}

function returnToMenu(): void {
  if (conn.connection.value?.training) {
    flow.leaveTraining();
    return;
  }
  game.dispose();
  round.hide();
  conn.closeConnection();
  conn.closeMatchmaker();
  flow.lobbyVisible.value = false;
  flow.showCopy.value = true;
  conn.clearUrlCode();
}

onMounted(() => {
  releaseUnlock = sound.bindUnlockGestures();
  window.addEventListener("resize", positionLabels);

  // An invite link lands here as /CODE (older links used ?game= or ?join=).
  const code = flow.codeFromLocation();
  if (!code) return;
  const saved = flow.readSession(code);
  if (saved?.token) {
    if (saved.myName) flow.remember(saved.myName);
    void joinRoom(code, saved.myName || flow.playerName.value || translate("player.you"));
  } else {
    // The code rides in the prompt, not the input: an invite opens "join" mode,
    // where the code block is hidden.
    flow.openPrompt("join", code);
  }
});

onBeforeUnmount(() => {
  releaseUnlock?.();
  window.removeEventListener("resize", positionLabels);
  flow.stopOnlineCount();
  flow.stopTrainingPresence();
});
</script>

<template>
  <GameBoard
    @ready="onBoardReady"
    @drag-start="flow.onDragStart"
    @drag="onDrag"
    @release="game.noteRelease"
  />

  <SoundToggle />

  <GameHud
    :visible="hudVisible"
    :timer-fraction="game.timerFraction.value"
    :paused="game.paused.value"
  />

  <RoundTitle :text="round.text.value" :visible="round.visible.value" :playing="round.playing.value" />

  <PlayerLabels
    :visible="labelsVisible"
    :own-name="flow.ownName.value"
    :opponent-name="flow.opponentName.value"
    :own-style="ownStyle"
    :opponent-style="opponentStyle"
  />

  <MainMenu :visible="flow.menuVisible.value" @open="flow.openPrompt" />

  <NameDialog
    :prompt="flow.prompt.value"
    :initial-name="flow.playerName.value"
    :online-count="conn.onlineCount.value"
    :status="flow.matchmakingStatus.value"
    :busy="flow.dialogBusy.value"
    :submit-label="flow.submitLabel.value"
    @submit="onDialogSubmit"
    @join="onDialogJoin"
    @cancel="onDialogCancel"
  />

  <GameLobby
    :visible="flow.lobbyVisible.value"
    :code="flow.lobbyCode.value"
    :hint="flow.lobbyHint.value"
    :show-copy="flow.showCopy.value"
    @copy="copyInvite"
    @cancel="returnToMenu"
  />

  <GameOver
    :visible="game.finished.value"
    :title="game.resultTitle.value"
    :my-score="game.myScore.value"
    :foe-score="game.foeScore.value"
    :can-rematch="flow.canRematch.value"
    :rematch-pending="flow.rematch.value.mine"
    @rematch="flow.requestRematch"
    @menu="returnToMenu"
  />

  <ToastMessage />

  <TrainingControls
    :visible="Boolean(conn.connection.value?.training) && game.running.value"
    :show-human-invite="flow.showHumanInvite.value"
    @invite="flow.leaveTraining(); flow.openPrompt('online')"
    @exit="flow.leaveTraining"
  />
</template>
