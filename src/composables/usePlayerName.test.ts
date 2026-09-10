import { expect, test } from "vitest";
import { MAX_PLAYER_NAME_LENGTH } from "../constants/index.ts";
import { normalizePlayerName, usePlayerName } from "./usePlayerName.ts";

test("names collapse whitespace and clamp to the input's limit", () => {
  expect(normalizePlayerName("  Новый   игрок  ")).toBe("Новый игрок");
  expect(normalizePlayerName(null)).toBe("");
  expect(normalizePlayerName("a".repeat(50))).toHaveLength(MAX_PLAYER_NAME_LENGTH);
});

test("remembering a name normalizes it and survives storage failure", () => {
  const { playerName, remember } = usePlayerName();
  expect(remember("  Игрок  ")).toBe("Игрок");
  expect(playerName.value).toBe("Игрок");
});

test("a name that cannot be saved is still usable for this match", () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: { setItem() { throw new Error("blocked"); }, getItem() { throw new Error("blocked"); } },
  });
  try {
    const { remember, playerName } = usePlayerName();
    expect(remember("Гость")).toBe("Гость");
    expect(playerName.value).toBe("Гость");
  } finally {
    if (original) Object.defineProperty(globalThis, "localStorage", original);
  }
});
