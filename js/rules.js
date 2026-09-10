// Twivvy — deterministic match simulation.
//
// Pure: no DOM, no randomness, no time. Both peers replay it over the same
// command log and must reach identical state. Keep it that way.
//
// 6x6 cells, nine 2x2 platforms. Row 0 is the top player's edge. Ports are
// named by absolute screen direction, never by player perspective.

export const RULES_VERSION = 6;

export const SIZE = 6;
export const PLATFORMS = 9;
export const TICKS = 30;
// 30 s to plan a move rather than react; RESOLVE_MS is the animation budget.
export const DECIDE_MS = 30_000;
export const RESOLVE_MS = 1200;
export const TICK_MS = DECIDE_MS + RESOLVE_MS;
export const SPAWN_TICKS = [1, 5, 9, 13, 17, 21];
export const MERCY_SCORE = 7;

export const UP = 0;
export const RIGHT = 1;
export const DOWN = 2;
export const LEFT = 3;

const DR = [-1, 0, 1, 0];
const DC = [0, 1, 0, -1];

/** Bitmask of the ports a piece connects; EMPTY is a platform cell without a track. */
export const PIECE = {
  EMPTY: 0,
  NS: (1 << UP) | (1 << DOWN),
  EW: (1 << RIGHT) | (1 << LEFT),
  NE: (1 << UP) | (1 << RIGHT),
  SE: (1 << DOWN) | (1 << RIGHT),
  SW: (1 << DOWN) | (1 << LEFT),
  NW: (1 << UP) | (1 << LEFT),
};

/** Rotate a port mask by `quarters` clockwise steps. */
export function rotateMask(mask, quarters) {
  const q = ((quarters % 4) + 4) % 4;
  let out = 0;
  for (let port = 0; port < 4; port++) {
    if (mask & (1 << port)) out |= 1 << ((port + q) % 4);
  }
  return out;
}

export function otherPort(mask, entryPort) {
  for (let port = 0; port < 4; port++) {
    if (port !== entryPort && mask & (1 << port)) return port;
  }
  return entryPort;
}

export function platformOf(row, col) {
  return Math.floor(row / 2) * 3 + Math.floor(col / 2);
}

export function platformOrigin(platform) {
  return { row: Math.floor(platform / 3) * 2, col: (platform % 3) * 2 };
}

/** Rotate a cell within its 2x2 platform: (0,0)->(0,1)->(1,1)->(1,0). */
function rotateCellInPlatform(localRow, localCol, quarters) {
  let r = localRow;
  let c = localCol;
  for (let i = 0; i < (((quarters % 4) + 4) % 4); i++) {
    const nr = c;
    const nc = 1 - r;
    r = nr;
    c = nc;
  }
  return { row: r, col: c };
}

// ---------------------------------------------------------------------------
// Maps
// ---------------------------------------------------------------------------

// Hand-designed maps, each 180°-symmetric so neither edge has an advantage.
const N = PIECE.NS;
const E = PIECE.EW;
const a = PIECE.NE;
const b = PIECE.SE;
const c = PIECE.SW;
const d = PIECE.NW;
const X = PIECE.EMPTY;

// Validated by simulation: even scoring, few scoreless matches, little stalling.
// See tools/validate-maps.mjs.
export const MAPS = [
  {
    name: "Развилка",
    grid: [
      [a, b, E, c, d, a],
      [d, a, c, a, E, E],
      [X, N, d, a, N, d],
      [b, N, c, b, N, X],
      [E, E, c, a, c, b],
      [c, b, a, E, d, c],
    ],
  },
  {
    name: "Ворота",
    grid: [
      [a, c, b, d, X, a],
      [b, E, N, X, c, b],
      [X, a, d, E, d, d],
      [b, b, E, b, c, X],
      [d, a, X, N, E, d],
      [c, X, b, d, a, c],
    ],
  },
  {
    name: "Карта 3",
    grid: [
      [E, E, N, N, a, d],
      [c, N, N, a, c, X],
      [N, c, N, E, c, E],
      [E, a, E, N, a, N],
      [X, a, c, N, N, a],
      [b, c, N, N, E, E],
    ],
  },
];

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/**
 * The two fixed centre cells balls spawn from. `order` only breaks ties; the
 * direction itself is drawn from the ports available — see pickSpawnExit.
 */
export const SOURCES = [
  { row: 2, col: 2, order: [UP, RIGHT, DOWN, LEFT] },
  { row: 3, col: 3, order: [DOWN, LEFT, UP, RIGHT] },
];

/**
 * Stands in for randomness: a real RNG would desync the peers, which exchange
 * only commands. Integer-only mixing, so no platform-dependent rounding.
 */
function spawnNoise(tick, sourceIndex, ballId) {
  let x = (tick * 0x9e3779b1) ^ (sourceIndex * 0x85ebca6b) ^ (ballId * 0xc2b2ae35);
  x = Math.imul(x ^ (x >>> 16), 0x7feb352d);
  x = Math.imul(x ^ (x >>> 15), 0x846ca68b);
  return (x ^ (x >>> 16)) >>> 0;
}

/**
 * Even draw among the ports the piece actually connects. Candidates are
 * collected in fixed port order so both peers index the same list.
 */
export function pickSpawnExit(mask, source, tick, sourceIndex, ballId) {
  const available = [];
  for (let port = 0; port < 4; port++) {
    if (mask & (1 << port)) available.push(port);
  }
  if (available.length === 0) return undefined;
  if (available.length === 1) return available[0];
  return available[spawnNoise(tick, sourceIndex, ballId) % available.length];
}

export function createMatch(mapIndex = 0) {
  const map = MAPS[mapIndex % MAPS.length];
  const cells = map.grid.map((row) => row.slice());

  return {
    rulesVersion: RULES_VERSION,
    map: mapIndex % MAPS.length,
    tick: 0, // becomes 1 on the first resolve
    cells,
    balls: [],
    nextBallId: 1,
    score: { top: 0, bottom: 0 },
    cooldown: [], // platform indices locked for the current decide phase
    finished: false,
    log: [],
  };
}

export function cloneMatch(m) {
  return {
    ...m,
    cells: m.cells.map((row) => row.slice()),
    balls: m.balls.map((ball) => ({ ...ball })),
    score: { ...m.score },
    cooldown: m.cooldown.slice(),
    log: m.log.slice(),
  };
}

/** A command is null (skip) or { platform, dir } where dir is +1 CW / -1 CCW. */
export function isValidCommand(match, command) {
  if (command === null || command === undefined) return true;
  if (typeof command !== "object") return false;
  const { platform, dir } = command;
  if (!Number.isInteger(platform) || platform < 0 || platform >= PLATFORMS) {
    return false;
  }
  if (dir !== 1 && dir !== -1) return false;
  if (match.cooldown.includes(platform)) return false;
  return true;
}

function rotatePlatform(match, platform, quarters) {
  const q = ((quarters % 4) + 4) % 4;
  if (q === 0) return;

  const { row: r0, col: c0 } = platformOrigin(platform);
  const nextCells = [
    [null, null],
    [null, null],
  ];

  for (let lr = 0; lr < 2; lr++) {
    for (let lc = 0; lc < 2; lc++) {
      const to = rotateCellInPlatform(lr, lc, q);
      nextCells[to.row][to.col] = rotateMask(match.cells[r0 + lr][c0 + lc], q);
    }
  }

  for (let lr = 0; lr < 2; lr++) {
    for (let lc = 0; lc < 2; lc++) {
      match.cells[r0 + lr][c0 + lc] = nextCells[lr][lc];
    }
  }

  // The platform carries its balls, and each ball's heading turns with it.
  for (const ball of match.balls) {
    if (platformOf(ball.row, ball.col) !== platform) continue;
    const to = rotateCellInPlatform(ball.row - r0, ball.col - c0, q);
    ball.row = r0 + to.row;
    ball.col = c0 + to.col;
    ball.exit = (ball.exit + q) % 4;
  }
}

function spawnBalls(match) {
  if (!SPAWN_TICKS.includes(match.tick)) return [];

  const spawned = [];
  const occupied = new Set(
    match.balls.map((ball) => `${ball.row},${ball.col}`),
  );
  for (const [sourceIndex, source] of SOURCES.entries()) {
    const cell = `${source.row},${source.col}`;
    if (occupied.has(cell)) continue;

    const mask = match.cells[source.row][source.col];
    // Reserve the id first — the draw uses it, so both sources roll apart.
    const id = match.nextBallId;
    const exit = pickSpawnExit(mask, source, match.tick, sourceIndex, id);
    if (exit === undefined) continue;
    match.nextBallId++;

    const ball = {
      id,
      row: source.row,
      col: source.col,
      exit,
    };
    match.balls.push(ball);
    occupied.add(cell);
    // The view animates the ball rising from this cell.
    spawned.push({ id: ball.id, row: ball.row, col: ball.col });
  }
  return spawned;
}

/** Move every ball one cell at most, read from one snapshot so order cannot matter. */
function moveBalls(match) {
  const moves = [];
  const delivered = [];

  const prepareBounce = (ball, reason) => {
    const mask = match.cells[ball.row][ball.col];
    ball.pendingBounceExit = otherPort(mask, ball.exit);
    ball.pendingBounceReason = reason;
  };

  for (const ball of match.balls) {
    const mask = match.cells[ball.row][ball.col];

    // A ball whose exit no longer exists on its own piece waits in place.
    if (!(mask & (1 << ball.exit))) {
      continue;
    }

    const nr = ball.row + DR[ball.exit];
    const nc = ball.col + DC[ball.exit];

    // Leaving through the top or bottom edge is a delivery.
    if (nr < 0 || nr >= SIZE) {
      const side = nr < 0 ? "top" : "bottom";
      delivered.push({ id: ball.id, side, from: { row: ball.row, col: ball.col } });
      moves.push({ id: ball.id, kind: "deliver", side });
      continue;
    }

    // A closed side wall is still a dead end: recoil rather than wait forever.
    if (nc < 0 || nc >= SIZE) {
      prepareBounce(ball, "dead-end");
      continue;
    }

    const entryPort = (ball.exit + 2) % 4;
    const targetMask = match.cells[nr][nc];

    if (!(targetMask & (1 << entryPort))) {
      // Track ends inside the board: stay put, leave by this piece's other end.
      prepareBounce(ball, "dead-end");
      continue;
    }

    ball.pendingRow = nr;
    ball.pendingCol = nc;
    ball.pendingExit = otherPort(targetMask, entryPort);
  }

  // One ball per cell. Repeated to a fixed point rather than resolved in one
  // pass, so the result cannot depend on array order — both peers must agree.
  // A blocked ball stays put and reverses along its track.
  const deliveredIdSet = new Set(delivered.map((d) => d.id));

  for (let changed = true; changed; ) {
    changed = false;

    // Cells still occupied after this step.
    const occupied = new Set();
    for (const ball of match.balls) {
      if (deliveredIdSet.has(ball.id)) continue;
      if (ball.pendingRow !== undefined) continue;
      occupied.add(`${ball.row},${ball.col}`);
    }

    // Two balls may not land on the same cell either.
    const claims = new Map();
    for (const ball of match.balls) {
      if (ball.pendingRow === undefined) continue;
      const key = `${ball.pendingRow},${ball.pendingCol}`;
      if (!claims.has(key)) claims.set(key, []);
      claims.get(key).push(ball);
    }

    // Adjacent balls heading into each other collide instead of swapping.
    const origins = new Map();
    for (const ball of match.balls) {
      if (!deliveredIdSet.has(ball.id)) origins.set(`${ball.row},${ball.col}`, ball);
    }
    const swaps = new Set();
    for (const ball of match.balls) {
      if (ball.pendingRow === undefined) continue;
      const occupant = origins.get(`${ball.pendingRow},${ball.pendingCol}`);
      if (occupant?.pendingRow === ball.row && occupant?.pendingCol === ball.col) {
        swaps.add(ball.id);
        swaps.add(occupant.id);
      }
    }

    for (const ball of match.balls) {
      if (ball.pendingRow === undefined) continue;
      const key = `${ball.pendingRow},${ball.pendingCol}`;

      const blockedByStaying = occupied.has(key);
      // Contested cell: nobody takes it. A winner would need a tie-break both
      // peers agree on, and standing still is what the rest of the rules do.
      const contested = (claims.get(key) || []).length > 1;
      const swapping = swaps.has(ball.id);

      if (blockedByStaying || contested || swapping) {
        prepareBounce(ball, "collision");
        delete ball.pendingRow;
        delete ball.pendingCol;
        delete ball.pendingExit;
        changed = true;
      }
    }
  }

  // Record what actually happens, now that blocking is settled.
  for (const ball of match.balls) {
    if (deliveredIdSet.has(ball.id)) continue;
    if (ball.pendingRow === undefined) {
      moves.push(ball.pendingBounceExit === undefined
        ? { id: ball.id, kind: "wait" }
        : { id: ball.id, kind: "bounce", reason: ball.pendingBounceReason,
            at: { row: ball.row, col: ball.col } });
    } else {
      moves.push({
        id: ball.id,
        kind: "move",
        from: { row: ball.row, col: ball.col },
        to: { row: ball.pendingRow, col: ball.pendingCol },
      });
    }
  }

  // Apply after every ball has been read.
  for (const ball of match.balls) {
    if (ball.pendingRow !== undefined) {
      ball.row = ball.pendingRow;
      ball.col = ball.pendingCol;
      ball.exit = ball.pendingExit;
      delete ball.pendingRow;
      delete ball.pendingCol;
      delete ball.pendingExit;
    } else if (ball.pendingBounceExit !== undefined) {
      ball.exit = ball.pendingBounceExit;
    }
    delete ball.pendingBounceExit;
    delete ball.pendingBounceReason;
  }

  const deliveredIds = new Set(delivered.map((d) => d.id));
  for (const d of delivered) {
    match.score[d.side] += 1;
  }
  match.balls = match.balls.filter((ball) => !deliveredIds.has(ball.id));

  // No lifetime: a ball leaves only by delivery. `expired` stays in the event
  // shape because the view and the replay still read the field.
  const expired = [];

  return { moves, delivered, expired };
}

/** Resolve one tick; returns an event record for animation and replay. */
export function resolveTick(match, topCommand, bottomCommand) {
  if (match.finished) return null;

  match.tick += 1;

  const commands = { top: topCommand ?? null, bottom: bottomCommand ?? null };

  // Reject anything illegal rather than trusting the peer.
  for (const side of ["top", "bottom"]) {
    if (!isValidCommand(match, commands[side])) commands[side] = null;
  }

  const spawned = spawnBalls(match);

  // Rotations on the same platform add; opposite directions cancel.
  const quarters = new Map();
  for (const side of ["top", "bottom"]) {
    const cmd = commands[side];
    if (!cmd) continue;
    quarters.set(cmd.platform, (quarters.get(cmd.platform) || 0) + cmd.dir);
  }

  // All platforms turn at once.
  for (const [platform, q] of quarters) {
    rotatePlatform(match, platform, q);
  }

  const movement = moveBalls(match);

  // Any platform commanded this tick — even a cancelled one — locks next phase.
  match.cooldown = [...quarters.keys()];

  const event = {
    tick: match.tick,
    commands,
    rotations: [...quarters.entries()].map(([platform, q]) => ({
      platform,
      quarters: ((q % 4) + 4) % 4,
    })),
    spawned,
    ...movement,
    score: { ...match.score },
    cooldown: match.cooldown.slice(),
  };

  match.log.push(event);

  if (
    match.tick >= TICKS ||
    match.score.top >= MERCY_SCORE ||
    match.score.bottom >= MERCY_SCORE
  ) {
    match.finished = true;
  }

  return event;
}

export function matchResult(match) {
  const { top, bottom } = match.score;
  if (top === bottom) return "draw";
  return top > bottom ? "top" : "bottom";
}
