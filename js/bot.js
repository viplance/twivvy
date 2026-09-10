import { createMatch, cloneMatch, resolveTick, isValidCommand, PLATFORMS, SIZE, DECIDE_MS } from './rules.js?v=20260910-turnsound';

export function legalMoves(match) {
  const moves = [null];
  for (let platform = 0; platform < PLATFORMS; platform++) {
    for (const dir of [-1, 1]) {
      const command = { platform, dir };
      if (isValidCommand(match, command)) moves.push(command);
    }
  }
  return moves;
}

function evaluate(match) {
  return (match.score.top - match.score.bottom) * 100 +
    match.balls.reduce((sum, ball) => sum + (SIZE - 1 - 2 * ball.row) * 0.6, 0);
}

function forecast(match, top, bottom, depth) {
  const future = cloneMatch(match);
  resolveTick(future, top, bottom);
  let score = evaluate(future);
  // Forecast the existing trajectories, rewarding earlier deliveries.
  for (let i = 1; i < depth && !future.finished; i++) {
    resolveTick(future, null, null);
    score += evaluate(future) * (0.8 ** i);
  }
  return score;
}

// Chooses from the public board only, before the human starts choosing.
export function chooseBotMove(match, difficulty = 'medium', random = Math.random) {
  const moves = legalMoves(match);
  if (difficulty === 'easy') return moves[Math.floor(random() * moves.length)];
  let best = -Infinity;
  let chosen = null;
  for (const move of moves) {
    let score;
    if (difficulty === 'hard') {
      const outcomes = moves.map(reply => forecast(match, move, reply, 4));
      // Guard against the strongest reply without assuming perfect opposition.
      score = Math.min(...outcomes) * 0.65 +
        outcomes.reduce((sum, value) => sum + value, 0) / outcomes.length * 0.35;
    } else {
      score = forecast(match, move, null, 3);
    }
    if (score > best) { best = score; chosen = move; }
  }
  return chosen;
}

/** Local match lifecycle: no transport, room, commit/reveal or saved network session. */
export class TrainingSession {
  constructor(connection, callbacks = {}) {
    this.callbacks = callbacks;
    this.difficulty = connection.difficulty;
    this.match = createMatch(connection.map);
    this.decideMs = callbacks.decideMs || DECIDE_MS;
    this.phase = 'idle';
    this.ended = false;
    this.generation = 0;
  }

  connected() { this._begin(); }
  remaining() { return Math.max(0, this.deadline - Date.now()); }
  choose(command) {
    if (this.phase === 'decide') this.selection = isValidCommand(this.match, command) ? command : null;
  }
  _begin() {
    if (this.ended) return;
    if (this.match.finished) {
      this.ended = true;
      this.phase = 'finished';
      this.callbacks.finished?.(null);
      return;
    }
    this.selection = null;
    this.botMove = chooseBotMove(this.match, this.difficulty);
    this.phase = 'decide';
    this.deadline = Date.now() + this.decideMs;
    this.callbacks.active?.(true);
    this.timer = setTimeout(() => this._resolve(), this.decideMs);
  }
  async _resolve() {
    if (this.phase !== 'decide' || this.ended) return;
    const generation = this.generation;
    // Lock settles any drag and records its final selection first.
    this.callbacks.lock?.();
    this.phase = 'animate';
    const before = cloneMatch(this.match);
    const event = resolveTick(this.match, this.botMove, this.selection);
    await this.callbacks.resolved?.(event, before, this.match);
    if (generation === this.generation && !this.ended) this._begin();
  }
  dispose() {
    clearTimeout(this.timer);
    this.generation++;
    this.ended = true;
    this.phase = 'disposed';
  }
}
