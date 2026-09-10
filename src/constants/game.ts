import type { Difficulty, Side } from "../types/game.ts";

/** Bot strengths, in the order the dialog lists them. */
export const DIFFICULTIES: readonly Difficulty[] = ["easy", "medium", "hard"];

export const DEFAULT_DIFFICULTY: Difficulty = "medium";

/** The host plays the bottom receiver; the guest sees the board rotated. */
export const HOST_SIDE: Side = "bottom";
export const GUEST_SIDE: Side = "top";

/** The other receiver. Used wherever a score or command is read per side. */
export function opposite(side: Side): Side {
  return side === "top" ? "bottom" : "top";
}
