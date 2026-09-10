/** UI timings, in milliseconds. Match timing lives in js/rules.js instead:
 *  these values only affect what is shown, never when a tick resolves. */

/** How long a toast stays up by default. */
export const TOAST_MS = 2600;

/** A cooling-down platform rejects a drag: the hint can be brief. */
export const TOAST_COOLDOWN_MS = 1200;

/** Storage failures need longer — the player has to act on them. */
export const TOAST_STORAGE_MS = 6000;

/** The round banner fades after this long. */
export const ROUND_TITLE_MS = 3000;

/** Online-count refresh while the name dialog is open. */
export const ONLINE_COUNT_POLL_MS = 2500;

/** Presence poll that offers a human opponent during training. */
export const TRAINING_PRESENCE_POLL_MS = 5000;
