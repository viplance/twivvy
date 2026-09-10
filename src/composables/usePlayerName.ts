import { ref } from "vue";
import { MAX_PLAYER_NAME_LENGTH, PLAYER_NAME_KEY } from "../constants/index.ts";

/** Collapse whitespace and clamp to what the input accepts. */
export function normalizePlayerName(value: unknown): string {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_PLAYER_NAME_LENGTH);
}

function readStoredName(): string {
  // Storage throws in private modes; an empty name simply prompts for one.
  try {
    return normalizePlayerName(localStorage.getItem(PLAYER_NAME_KEY));
  } catch {
    return "";
  }
}

const playerName = ref(readStoredName());

/** The player's name, remembered across sessions in localStorage. */
export function usePlayerName() {
  function remember(name: string): string {
    playerName.value = normalizePlayerName(name);
    try {
      localStorage.setItem(PLAYER_NAME_KEY, playerName.value);
    } catch {
      // A name that cannot be saved is still usable for this match.
    }
    return playerName.value;
  }

  return { playerName, remember, readStoredName };
}
