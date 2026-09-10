import type { MessageKey, NamePromptMode } from "../types/index.ts";

/** Title and submit-label keys for each name-dialog mode. */
export const NAME_DIALOG_COPY: Readonly<
  Record<NamePromptMode, { readonly title: MessageKey; readonly submit: MessageKey }>
> = {
  create: { title: "dialog.createTitle", submit: "dialog.createSubmit" },
  join: { title: "dialog.joinTitle", submit: "dialog.joinSubmit" },
  online: { title: "dialog.onlineTitle", submit: "dialog.onlineSubmit" },
  training: { title: "dialog.trainingTitle", submit: "dialog.trainingSubmit" },
};

/**
 * Errors that older peers send as literal Russian text. Newer builds send a
 * key, so this map only has to cover what an old client can still put on the
 * wire; unmatched text is shown as-is.
 */
export const LEGACY_MESSAGE_KEYS: ReadonlyMap<string, MessageKey> = new Map([
  ["Партия прервана: соперник отсутствовал более 30 минут.", "error.peerAbsent"],
  ["Не удалось согласовать сохранённую партию.", "error.restoreMismatch"],
]);
