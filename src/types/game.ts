/** Domain shapes for the match controller. The rules engine in js/ is the
 *  authority on these; this file names them so the Vue layer can be typed. */

/** Receivers sit at the two ends of the board; the host always plays bottom. */
export type Side = "top" | "bottom";

/** Clockwise is +1 in the rules encoding, counter-clockwise -1. */
export type RotationDir = 1 | -1;

/** Bot strength offered in the training dialog. */
export type Difficulty = "easy" | "medium" | "hard";

/** Which flow the name dialog is collecting a name for. */
export type NamePromptMode = "create" | "join" | "online" | "training";

/** A committed platform turn for one tick. */
export interface Command {
  readonly platform: number;
  readonly dir: RotationDir;
}

export interface Match {
  tick: number;
  cooldown: readonly number[];
  finished: boolean;
  score: Record<Side, number>;
}

export interface DeliveredBall {
  readonly id: number;
  readonly side: Side;
}

/** One resolved tick, as handed to the view for animation. */
export interface TickEvent {
  readonly tick: number;
  readonly commands: Partial<Record<Side, Command | null>>;
  readonly rotations: readonly { platform: number; quarters: number }[];
  readonly delivered: readonly DeliveredBall[];
  readonly spawned: readonly { id: number; row: number; col: number }[];
}

/** A room handed over by the matchmaker. */
export interface MatchedRoom {
  readonly code: string;
  readonly token: string;
  readonly role: "host" | "guest";
  readonly seed: number;
  readonly map: number;
  readonly epoch: number;
  readonly hostName?: string;
  readonly guestName?: string;
}

/** Pending rematch handshake: the match restarts once both sides ask. */
export interface RematchState {
  mine: boolean;
  theirs: boolean;
  /** Chosen by the host only, so the two clients cannot disagree. */
  map: number | null;
}

/** What the name dialog was opened for, plus the code an invite carried. */
export interface NamePrompt {
  readonly mode: NamePromptMode;
  readonly code: string | null;
}
