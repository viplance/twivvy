import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { effectScope } from "vue";
import { ROUND_TITLE_MS } from "../constants/index.ts";
import { i18n } from "../i18n.ts";
import { useRoundTitle } from "./useRoundTitle.ts";

/** Run a composable inside a scope so onScopeDispose has somewhere to attach. */
function withScope<T>(fn: () => T): T {
  const scope = effectScope();
  const value = scope.run(fn)!;
  scopes.push(scope);
  return value;
}
const scopes: ReturnType<typeof effectScope>[] = [];

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => {
    cb(0);
    return 1;
  });
  i18n.global.locale.value = "ru";
});

afterEach(() => {
  for (const scope of scopes.splice(0)) scope.stop();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

test("a new decision round shows its title, then hides after three seconds", () => {
  const round = withScope(useRoundTitle);
  round.announce(1);
  expect(round.visible.value).toBe(true);
  expect(round.text.value).toContain("1");
  // The class drives the CSS keyframes.
  expect(round.playing.value).toBe(true);

  vi.advanceTimersByTime(ROUND_TITLE_MS);
  expect(round.visible.value).toBe(false);
  expect(round.playing.value).toBe(false);
});

test("the same round is announced only once", () => {
  const round = withScope(useRoundTitle);
  round.announce(2);
  const first = round.text.value;
  vi.advanceTimersByTime(ROUND_TITLE_MS);
  round.announce(2);
  expect(round.visible.value).toBe(false);
  expect(round.text.value).toBe(first);
});

test("rounds outside the match are ignored", () => {
  const round = withScope(useRoundTitle);
  round.announce(0);
  expect(round.visible.value).toBe(false);
  round.announce(9999);
  expect(round.visible.value).toBe(false);
});

test("a later round replaces the banner and restarts its timer", () => {
  const round = withScope(useRoundTitle);
  round.announce(1);
  vi.advanceTimersByTime(ROUND_TITLE_MS - 100);
  round.announce(2);
  expect(round.visible.value).toBe(true);
  expect(round.text.value).toContain("2");
  // The new round gets a full window, not the remainder of the old one.
  vi.advanceTimersByTime(ROUND_TITLE_MS - 100);
  expect(round.visible.value).toBe(true);
  vi.advanceTimersByTime(100);
  expect(round.visible.value).toBe(false);
});
