import { computed, ref, shallowRef, triggerRef } from "vue";
import { createMatch, matchResult, DECIDE_MS, RESOLVE_MS, TICKS } from "../../js/rules.js";
import { MatchSession } from "../../js/session.js";
import { TrainingSession } from "../../js/bot.js";
import type { BoardView } from "../../js/view.js";
import { GUEST_SIDE, HOST_SIDE, opposite } from "../constants/index.ts";
import { translate } from "../i18n.ts";
import type { Command, Match, RotationDir, Side, TickEvent } from "../types/index.ts";
import { useSound } from "./useSound.ts";

/** Tests drive the clock through this global; production uses the rules value. */
function decideMs(): number {
  return Number(window.__TWIVVY_DECIDE_MS) || DECIDE_MS;
}

/**
 * Two independent classes implementing the same callback contract: MatchSession
 * resolves a tick over the wire, TrainingSession resolves the bot's move
 * locally. The controller only ever uses their shared surface.
 */
type Session = InstanceType<typeof MatchSession> | InstanceType<typeof TrainingSession>;

const match = shallowRef<Match | null>(null);
const session = shallowRef<Session | null>(null);
const selection = shallowRef<Command | null>(null);
const mySide = ref<Side>(HOST_SIDE);
const running = ref(false);
const acceptingDrag = ref(false);
const paused = ref(false);
const timerFraction = ref(0);
const announcedRound = ref(0);
const endedReason = ref<string | null>(null);
const finished = ref(false);

/** Our own release already sounded the turn; the resolve must not repeat it. */
let heardOwnTurn = false;
let animation: Promise<void> = Promise.resolve();
let timerFrame: number | null = null;

export interface MatchHooks {
  /** Localizes a peer message that may be legacy literal text. */
  localizeMessage(message: string): string;
  announceRound(round: number): void;
  onFinished(): void;
}

export function useMatch() {
  const sound = useSound();

  const foeSide = computed(() => opposite(mySide.value));
  const myScore = computed(() => match.value?.score[mySide.value] ?? 0);
  const foeScore = computed(() => match.value?.score[foeSide.value] ?? 0);

  function stopTimerAnimation(): void {
    if (timerFrame !== null) cancelAnimationFrame(timerFrame);
    timerFrame = null;
  }

  /**
   * The session polls the authoritative deadline slowly; the HUD reads that
   * same deadline every frame, so the bar is smooth without affecting timing.
   */
  function animateTimer(): void {
    timerFrame = null;
    const current = session.value;
    if (!running.value || current?.phase !== "decide") return;
    timerFraction.value = clamp(current.remaining() / current.decideMs);
    timerFrame = requestAnimationFrame(animateTimer);
  }

  function startTimerAnimation(): void {
    stopTimerAnimation();
    animateTimer();
  }

  function clamp(value: number): number {
    return Math.max(0, Math.min(1, Number(value) || 0));
  }

  /** Start (or restore) a match on the given connection. */
  function start(connection: any, view: BoardView, hooks: MatchHooks, saved: any = null): void {
    session.value?.dispose();
    stopTimerAnimation();

    mySide.value = connection.role === "host" ? HOST_SIDE : GUEST_SIDE;
    const state: Match = saved?.match || createMatch(connection.map);
    match.value = state;
    announcedRound.value = saved ? state.tick + 1 : 0;
    selection.value = saved?.round?.selection ?? null;
    running.value = true;
    acceptingDrag.value = false;
    paused.value = false;
    finished.value = false;
    endedReason.value = null;
    heardOwnTurn = false;

    view.setPerspective(mySide.value);
    view.clearPreview();
    view.restoreMatch(state, selection.value);
    view.setInteractionEnabled(false);

    const Constructor = connection.training ? TrainingSession : MatchSession;
    const created: Session = new Constructor(connection, {
      saved,
      decideMs: decideMs(),
      lock() {
        stopTimerAnimation();
        timerFraction.value = 0;
        view.setInteractionEnabled(false);
        acceptingDrag.value = false;
      },
      paused() {
        stopTimerAnimation();
        paused.value = true;
        timerFraction.value = clamp((session.value?.remaining() ?? 0) / decideMs());
      },
      async restore(state: Match, command: Command | null) {
        await animation;
        match.value = state;
        selection.value = command ?? null;
        view.restoreMatch(state, command);
      },
      active(canChoose: boolean) {
        paused.value = false;
        acceptingDrag.value = canChoose;
        view.setInteractionEnabled(canChoose);
        const current = session.value;
        if (current) timerFraction.value = clamp(current.remaining() / current.decideMs);
        if (canChoose) {
          hooks.announceRound((current?.match.tick ?? 0) + 1);
          startTimerAnimation();
        }
      },
      timer(fraction: number) {
        // Fallback while animation frames are suspended (tab becoming visible).
        if (timerFrame === null) timerFraction.value = clamp(fraction);
      },
      async resolved(event: TickEvent, before: Match, after: Match) {
        const current = session.value;
        match.value = after;
        // resolveTick mutates the session's Match in place. Because `match` is
        // intentionally shallow, assigning that same object does not notify
        // computed scores or the result title without an explicit trigger.
        triggerRef(match);
        selection.value = null;
        playTurnSound(event);
        animation = view.playTick(event, before, after, RESOLVE_MS);
        await animation;
        if (session.value !== current) return;
        // Both receivers use the same effect, once when the balls arrive.
        if (event.delivered.length) sound.play("delivery");
        view.setCooldown(after.cooldown);
      },
      finished(reason?: string | null) {
        stopTimerAnimation();
        running.value = false;
        end(view, hooks, reason ?? null);
      },
    });
    session.value = created;

    if (created.ended) {
      running.value = false;
      end(view, hooks, created.ended === true ? null : created.ended);
    } else if (saved) {
      paused.value = true;
      timerFraction.value = clamp(created.remaining() / created.decideMs);
    }
  }

  /**
   * The opponent's turn is only ever seen at resolve, so it is only heard here.
   * Our own turn already sounded on release, and repeats only when the deadline
   * committed it instead of a hand release.
   */
  function playTurnSound(event: TickEvent): void {
    const commands = event.commands || {};
    if (commands[foeSide.value] || (commands[mySide.value] && !heardOwnTurn)) {
      sound.play("turn");
    }
    heardOwnTurn = false;
  }

  function end(view: BoardView, hooks: MatchHooks, reason: string | null): void {
    stopTimerAnimation();
    if (match.value) view.syncSourceMarkers({ tick: match.value.tick, finished: true });
    paused.value = false;
    acceptingDrag.value = false;
    view.setInteractionEnabled(false);
    finished.value = true;
    endedReason.value = reason ? hooks.localizeMessage(reason) : null;
    hooks.onFinished();
  }

  /** Title for the end panel: an explicit reason wins over the score. */
  const resultTitle = computed(() => {
    if (endedReason.value) return endedReason.value;
    if (!match.value) return "";
    const result = matchResult(match.value);
    if (result === "draw") return translate("result.draw");
    return result === mySide.value ? translate("result.win") : translate("result.loss");
  });

  function beginDrag(platform: number): boolean {
    if (!running.value || !acceptingDrag.value) return false;
    return !match.value?.cooldown.includes(platform);
  }

  function commitDrag(platform: number, dir: RotationDir | null): void {
    if (!running.value || !acceptingDrag.value) return;
    selection.value = dir === null ? null : { platform, dir };
    session.value?.choose(selection.value);
  }

  /**
   * _finishDrag commits through commitDrag first, so `selection` already says
   * whether this release was a committed turn or a reset back to zero.
   */
  function noteRelease(): void {
    if (selection.value) heardOwnTurn = true;
    sound.play("turn");
  }

  function dispose(): void {
    session.value?.dispose();
    session.value = null;
    stopTimerAnimation();
    running.value = false;
    acceptingDrag.value = false;
    finished.value = false;
  }

  return {
    match, session, selection, mySide, foeSide, running, acceptingDrag, paused,
    timerFraction, finished, endedReason, resultTitle, myScore, foeScore,
    announcedRound, totalRounds: TICKS,
    start, end, dispose, beginDrag, commitDrag, noteRelease,
    stopTimerAnimation, startTimerAnimation,
  };
}
