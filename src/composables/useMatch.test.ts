import { beforeEach, expect, test, vi } from "vitest";
import type { Match, Side, TickEvent } from "../types/index.ts";

const sounds: string[] = [];

vi.mock("./useSound.ts", () => ({
  useSound: () => ({
    enabled: { value: true },
    play: (name: string) => sounds.push(name),
    setEnabled() {}, toggle() {}, bindUnlockGestures: () => () => {},
  }),
}));

/** A view double: playTick resolves at once so `resolved` runs to completion. */
function fakeView() {
  return {
    setPerspective() {}, clearPreview() {}, restoreMatch() {},
    setInteractionEnabled() {}, setCooldown() {}, syncSourceMarkers() {},
    playTick: async () => {},
  } as any;
}

const hooks = { localizeMessage: (m: string) => m, announceRound() {}, onFinished() {} };

function emptyMatch(): Match {
  return { tick: 0, cooldown: [], finished: false, score: { top: 0, bottom: 0 } };
}

function tickEvent(commands: Partial<Record<Side, unknown>>): TickEvent {
  return { tick: 1, commands, rotations: [], delivered: [], spawned: [] } as TickEvent;
}

let useMatch: typeof import("./useMatch.ts").useMatch;

beforeEach(async () => {
  sounds.length = 0;
  vi.resetModules();
  ({ useMatch } = await import("./useMatch.ts"));
});

const turn = { platform: 0, dir: 1 as const };

/**
 * Start a real (training) match and hand back the session callbacks the
 * composable installed, so a test can drive the true resolve path.
 */
function startHostMatch() {
  const game = useMatch();
  const view = fakeView();
  game.start({ role: "host", map: 0, training: true }, view, hooks);
  const callbacks = (game.session.value as any).callbacks;
  game.match.value = emptyMatch();
  sounds.length = 0;
  return { game, view, callbacks };
}

test("the opponent's turn is heard on resolve; a released own turn is not repeated", async () => {
  // The host plays bottom, so "top" is the opponent.
  for (const [commands, released, expected] of [
    [{ top: turn, bottom: null }, false, ["turn"]],
    [{ top: null, bottom: turn }, true, []],
    // Nobody released it by hand: the deadline committed it, so it sounds now.
    [{ top: null, bottom: turn }, false, ["turn"]],
    [{ top: turn, bottom: turn }, true, ["turn"]],
    [{ top: null, bottom: null }, false, []],
  ] as const) {
    const { game, callbacks } = startHostMatch();
    if (released) {
      game.running.value = true;
      game.acceptingDrag.value = true;
      game.commitDrag(turn.platform, turn.dir);
      game.noteRelease();
      // The release itself sounds; only the resolve is under test here.
      expect(sounds).toEqual(["turn"]);
      sounds.length = 0;
    }
    const after = emptyMatch();
    await callbacks.resolved(tickEvent(commands), emptyMatch(), after);
    expect(sounds, JSON.stringify({ commands, released })).toEqual(expected);
  }
});

test("a delivered ball sounds once, ordinary movement does not", async () => {
  const { callbacks } = startHostMatch();
  const event = { ...tickEvent({}), delivered: [{ id: 1, side: "bottom" as Side }] };
  await callbacks.resolved(event as TickEvent, emptyMatch(), emptyMatch());
  expect(sounds).toEqual(["delivery"]);

  sounds.length = 0;
  await callbacks.resolved(tickEvent({}), emptyMatch(), emptyMatch());
  expect(sounds).toEqual([]);
});

test("training result exposes the final in-place score instead of a cached draw", async () => {
  const { game, callbacks } = startHostMatch();
  const finalMatch = game.match.value!;

  // GameOver stays mounted while hidden, so these computed values are read and
  // cached before the mutable engine reaches the final result.
  expect(game.myScore.value).toBe(0);
  expect(game.foeScore.value).toBe(0);
  expect(game.resultTitle.value).toBe("Draw");

  finalMatch.score.bottom = 5;
  finalMatch.score.top = 2;
  finalMatch.finished = true;
  await callbacks.resolved(tickEvent({}), emptyMatch(), finalMatch);
  callbacks.finished(null);

  expect(game.myScore.value).toBe(5);
  expect(game.foeScore.value).toBe(2);
  expect(game.resultTitle.value).toBe("Victory");
});

test("a reset release still sounds but does not suppress the resolve", () => {
  const game = useMatch();
  game.mySide.value = "bottom";
  game.running.value = true;
  game.acceptingDrag.value = true;

  // dir === null is a reset: it clears the selection but still moves the board.
  game.commitDrag(0, null);
  game.noteRelease();
  expect(sounds).toEqual(["turn"]);
  expect(game.selection.value).toBeNull();
});

test("a drag is refused while a platform is cooling down", () => {
  const game = useMatch();
  game.running.value = true;
  game.acceptingDrag.value = true;
  game.match.value = { ...emptyMatch(), cooldown: [3] };
  expect(game.beginDrag(3)).toBe(false);
  expect(game.beginDrag(4)).toBe(true);
});

test("no drag is accepted before a match is running", () => {
  const game = useMatch();
  game.running.value = false;
  game.acceptingDrag.value = false;
  game.match.value = emptyMatch();
  expect(game.beginDrag(0)).toBe(false);
  game.commitDrag(0, 1);
  expect(game.selection.value).toBeNull();
});
