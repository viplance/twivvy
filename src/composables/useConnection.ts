import { ref, shallowRef } from "vue";
import { MAPS } from "../../js/rules.js";
import { basePath, Connection, Matchmaker, onlinePlayerCount } from "../../js/net.js";
import { LEGACY_MESSAGE_KEYS } from "../constants/index.ts";
import { translate } from "../i18n.ts";
import type { MatchedRoom, MessageKey } from "../types/index.ts";

/**
 * Peer messages may arrive as literal Russian text from an older build.
 * Map those to keys; anything else is already localized or opaque.
 */
export function localizeMessage(message: unknown): string {
  const key: MessageKey | undefined = LEGACY_MESSAGE_KEYS.get(String(message));
  return key ? translate(key) : String(message);
}

/** Put the room code in the address bar, so the URL itself is the invite. */
export function setUrlCode(code: string): void {
  history.replaceState(null, "", basePath() + code);
}

/** Back to the plain site address when no room is active. */
export function clearUrlCode(): void {
  history.replaceState(null, "", basePath());
}

export function randomMap(): number {
  return Math.floor(Math.random() * MAPS.length);
}

const connection = shallowRef<any>(null);
const matchmaker = shallowRef<InstanceType<typeof Matchmaker> | null>(null);
const onlineCount = ref(0);

export function useConnection() {
  function setConnection(value: any): void {
    connection.value = value;
  }

  function closeConnection(): void {
    connection.value?.close?.();
    connection.value = null;
  }

  function closeMatchmaker(): void {
    matchmaker.value?.close();
    matchmaker.value = null;
  }

  function create(): InstanceType<typeof Connection> {
    return new Connection();
  }

  async function refreshOnlineCount(): Promise<void> {
    try {
      onlineCount.value = Math.max(0, Number(await onlinePlayerCount()) || 0);
    } catch {
      // A failed count just leaves the previous number on screen.
    }
  }

  /** A room is only "ours" while it is still the active connection. */
  function isCurrent(conn: unknown): boolean {
    return connection.value === conn;
  }

  return {
    connection, matchmaker, onlineCount,
    setConnection, closeConnection, closeMatchmaker, create,
    refreshOnlineCount, isCurrent,
    localizeMessage, setUrlCode, clearUrlCode, randomMap,
  };
}

export type { MatchedRoom };
