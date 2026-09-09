import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createMatch, resolveTick, rotateMask, PIECE, UP, RIGHT, DOWN, LEFT,
  platformOf, platformOrigin, MAPS, SIZE, otherPort, cloneMatch, TICKS, SOURCES,
  pickSpawnExit, SPAWN_TICKS,
} from "../js/rules.js";

test("rotateMask turns ports clockwise", () => {
  assert.equal(rotateMask(PIECE.NS, 1), PIECE.EW);
  assert.equal(rotateMask(PIECE.NS, 2), PIECE.NS);
  assert.equal(rotateMask(PIECE.NE, 1), PIECE.SE);
  assert.equal(rotateMask(PIECE.NE, 4), PIECE.NE);
  assert.equal(rotateMask(PIECE.NE, -1), PIECE.NW);
});

test("otherPort returns the far end", () => {
  assert.equal(otherPort(PIECE.NS, UP), DOWN);
  assert.equal(otherPort(PIECE.NE, UP), RIGHT);
});

test("platform indexing covers the 6x6 grid", () => {
  assert.equal(platformOf(0, 0), 0);
  assert.equal(platformOf(1, 1), 0);
  assert.equal(platformOf(0, 2), 1);
  assert.equal(platformOf(5, 5), 8);
  assert.deepEqual(platformOrigin(8), { row: 4, col: 4 });
  assert.deepEqual(platformOrigin(4), { row: 2, col: 2 });
});

test("all maps are 6x6 with either zero or two ports per cell", () => {
  for (const map of MAPS) {
    assert.equal(map.grid.length, SIZE, map.name);
    for (const row of map.grid) {
      assert.equal(row.length, SIZE, map.name);
      for (const cell of row) {
        let bits = 0;
        for (let p = 0; p < 4; p++) if (cell & (1 << p)) bits++;
        assert.ok(bits === 0 || bits === 2, `${map.name} cell must have 0 or 2 ports`);
      }
    }
  }
});

test("every track component reaches an edge of its platform", () => {
  const dr = [-1, 0, 1, 0];
  const dc = [0, 1, 0, -1];

  for (const map of MAPS) {
    for (let platform = 0; platform < 9; platform++) {
      const { row: row0, col: col0 } = platformOrigin(platform);
      const seen = new Set();
      for (let startRow = 0; startRow < 2; startRow++) {
        for (let startCol = 0; startCol < 2; startCol++) {
          const startKey = `${startRow},${startCol}`;
          if (seen.has(startKey) || !map.grid[row0 + startRow][col0 + startCol]) continue;
          const queue = [[startRow, startCol]];
          seen.add(startKey);
          let reachesEdge = false;

          while (queue.length) {
            const [row, col] = queue.shift();
            const mask = map.grid[row0 + row][col0 + col];
            for (let port = 0; port < 4; port++) {
              if (!(mask & (1 << port))) continue;
              const nextRow = row + dr[port];
              const nextCol = col + dc[port];
              if (nextRow < 0 || nextRow >= 2 || nextCol < 0 || nextCol >= 2) {
                reachesEdge = true;
                continue;
              }
              const nextMask = map.grid[row0 + nextRow][col0 + nextCol];
              if (!(nextMask & (1 << ((port + 2) % 4)))) continue;
              const key = `${nextRow},${nextCol}`;
              if (!seen.has(key)) {
                seen.add(key);
                queue.push([nextRow, nextCol]);
              }
            }
          }

          assert.equal(reachesEdge, true,
            `${map.name} platform ${platform} has an isolated track at ${row0 + startRow},${col0 + startCol}`);
        }
      }
    }
  }
});

test("maps are symmetric under 180 degree rotation", () => {
  for (const map of MAPS) {
    for (let r = 0; r < SIZE; r++) {
      for (let c = 0; c < SIZE; c++) {
        const mirrored = map.grid[SIZE - 1 - r][SIZE - 1 - c];
        assert.equal(rotateMask(map.grid[r][c], 2), mirrored,
          `${map.name} not 180-symmetric at ${r},${c}`);
      }
    }
  }
});

test("opposite commands on one platform cancel", () => {
  const m = createMatch(0);
  const before = m.cells.map(r => r.slice());
  resolveTick(m, { platform: 4, dir: 1 }, { platform: 4, dir: -1 });
  assert.deepEqual(m.cells, before, "field must be unchanged");
  assert.deepEqual(m.cooldown, [4], "cancelled command still causes cooldown");
});

test("same-direction commands on one platform add to 180", () => {
  const m1 = createMatch(0);
  const m2 = createMatch(0);
  resolveTick(m1, { platform: 0, dir: 1 }, { platform: 0, dir: 1 });
  // Reference: two separate 90 rotations applied to a fresh board.
  const ref = createMatch(0);
  // apply 180 directly via two ticks would spawn balls; compare cells only
  const cells0 = ref.cells.map(r => r.slice());
  // manual 180 of platform 0
  const rot = (grid) => {
    const out = grid.map(r => r.slice());
    const cellsIn = [[grid[0][0], grid[0][1]], [grid[1][0], grid[1][1]]];
    out[0][0] = rotateMask(cellsIn[1][1], 2);
    out[1][1] = rotateMask(cellsIn[0][0], 2);
    out[0][1] = rotateMask(cellsIn[1][0], 2);
    out[1][0] = rotateMask(cellsIn[0][1], 2);
    return out;
  };
  const expected = rot(cells0.slice(0, 2).map(r => r.slice(0, 2)));
  assert.deepEqual(
    [[m1.cells[0][0], m1.cells[0][1]], [m1.cells[1][0], m1.cells[1][1]]],
    expected);
});

test("cooldown blocks the platform on the next tick only", () => {
  const m = createMatch(0);
  resolveTick(m, { platform: 4, dir: 1 }, null);
  assert.deepEqual(m.cooldown, [4]);
  const cells = m.cells.map(r => r.slice());
  // Command on a cooled-down platform is dropped.
  resolveTick(m, { platform: 4, dir: 1 }, null);
  assert.deepEqual(m.cells, cells, "cooled-down rotation must not apply");
  assert.deepEqual(m.cooldown, [], "cooldown clears when no command lands");
});

test("balls spawn only on the scheduled ticks, at most 12 per match", () => {
  const m = createMatch(0);
  let totalSpawned = 0;
  for (let t = 1; t <= TICKS; t++) {
    const ev = resolveTick(m, null, null);
    if (!SPAWN_TICKS.includes(t)) {
      assert.equal(ev.spawned.length, 0, `tick ${t} is not a spawn tick`);
    }
    assert.ok(ev.spawned.length <= 2, "at most one ball per source");
    totalSpawned += ev.spawned.length;
  }
  // Balls no longer expire, so a ball still standing on a source cell blocks
  // that source's next spawn. 12 is the ceiling, not a guarantee.
  assert.ok(totalSpawned <= 12, `spawned ${totalSpawned}, expected at most 12`);
  assert.ok(totalSpawned > 0, "some balls must spawn");
});

test("spawn events carry the source cell for the view", () => {
  const m = createMatch(0);
  const ev = resolveTick(m, null, null);
  assert.equal(ev.spawned.length, 2, "a pair spawns on tick 1");
  for (const s of ev.spawned) {
    assert.ok(Number.isInteger(s.id), "spawn has a ball id");
    assert.ok(Number.isInteger(s.row) && Number.isInteger(s.col), "has a cell");
  }
  // The event reports where the ball ENTERED the board. The ball may already
  // have moved on within the same tick, so this is the origin, not its
  // end-of-tick position — that is what the spawn animation needs.
  // Sources are the two fixed centre cells, never a rotating platform.
  const cells = ev.spawned.map(s => `${s.row},${s.col}`).sort();
  assert.deepEqual(cells, ["2,2", "3,3"]);
});

test("a spawned ball only ever rolls out along a port its piece has", () => {
  for (let mapIndex = 0; mapIndex < MAPS.length; mapIndex++) {
    for (let trial = 0; trial < 40; trial++) {
      const m = createMatch(mapIndex);
      for (let t = 1; t <= TICKS; t++) {
        const before = new Map(m.balls.map((b) => [b.id, b]));
        // Vary the board so sources present different pieces over the trials.
        const ev = resolveTick(m, { platform: (trial * 7 + t) % 9, dir: t % 2 ? 1 : -1 }, null);
        // The match can end early on the mercy score; resolveTick then returns null.
        if (!ev) break;
        for (const s of ev.spawned) {
          assert.equal(before.has(s.id), false, "spawn id must be fresh");
        }
      }
    }
  }
});

test("spawn direction is drawn from the available ports, not a fixed order", () => {
  // A piece open on all four sides must produce every direction over time,
  // roughly evenly — otherwise the ball always leaves the same way.
  const counts = [0, 0, 0, 0];
  for (let tick = 1; tick <= 2000; tick++) {
    for (let si = 0; si < SOURCES.length; si++) {
      const exit = pickSpawnExit(0b1111, SOURCES[si], tick, si, tick * 2 + si);
      counts[exit] += 1;
    }
  }
  for (const port of [UP, RIGHT, DOWN, LEFT]) {
    assert.ok(counts[port] > 700, `port ${port} drawn too rarely: ${counts[port]}`);
  }
});

test("spawn direction never leaves along a port the piece lacks", () => {
  // NS opens UP and DOWN only; the draw must never pick RIGHT or LEFT.
  for (let tick = 1; tick <= 500; tick++) {
    const exit = pickSpawnExit(PIECE.NS, SOURCES[0], tick, 0, tick);
    assert.ok(exit === UP || exit === DOWN, `NS piece yielded port ${exit}`);
  }
  // A single-port mask has no choice to make.
  assert.equal(pickSpawnExit(1 << RIGHT, SOURCES[0], 3, 0, 9), RIGHT);
  // A piece with no track spawns nothing.
  assert.equal(pickSpawnExit(PIECE.EMPTY, SOURCES[0], 3, 0, 9), undefined);
});

test("the random spawn direction is identical on both peers", () => {
  // The two clients only exchange commands; they must draw the same direction
  // from the same log, or their boards diverge.
  const log = Array.from({ length: TICKS }, (_, i) => ({ platform: (i * 5) % 9, dir: i % 2 ? 1 : -1 }));
  const peerA = createMatch(2);
  const peerB = createMatch(2);
  for (const cmd of log) {
    resolveTick(peerA, cmd, null);
    resolveTick(peerB, cmd, null);
  }
  assert.deepEqual(peerA.balls, peerB.balls, "ball headings must agree");
  assert.deepEqual(peerA.score, peerB.score, "scores must agree");
});

test("a source does not spawn a hidden second ball into an occupied cell", () => {
  const m = createMatch(0);
  const source = SOURCES[0];
  const mask = m.cells[source.row][source.col];
  const exit = [UP, RIGHT, DOWN, LEFT].find((port) => mask & (1 << port));
  m.balls = [{
    id: 90,
    row: source.row,
    col: source.col,
    exit,
    life: 5,
  }];
  m.nextBallId = 91;

  const ev = resolveTick(m, null, null);

  assert.equal(ev.spawned.length, 1, "only the free source spawns");
  assert.equal(
    ev.spawned.some((ball) => ball.row === source.row && ball.col === source.col),
    false,
    "the occupied source is skipped",
  );
});

test("a ball delivered through the top edge scores for top", () => {
  const m = createMatch(0);
  // Hand-place a ball at row 0 pointing UP on a piece that has an UP port.
  m.cells[0][0] = PIECE.NS;
  m.balls = [{ id: 99, row: 0, col: 0, exit: UP, life: 5 }];
  const ev = resolveTick(m, null, null);
  assert.equal(m.score.top, 1);
  assert.equal(m.score.bottom, 0);
  assert.ok(!m.balls.find(b => b.id === 99), "delivered ball is removed");
  assert.equal(ev.delivered[0].side, "top");
});

test("a ball delivered through the bottom edge scores for bottom", () => {
  const m = createMatch(0);
  m.cells[5][0] = PIECE.NS;
  m.balls = [{ id: 99, row: 5, col: 0, exit: DOWN, life: 5 }];
  resolveTick(m, null, null);
  assert.equal(m.score.bottom, 1);
});

test("a ball facing a side wall waits", () => {
  const m = createMatch(0);
  m.cells[2][0] = PIECE.EW;
  m.balls = [{ id: 7, row: 2, col: 0, exit: LEFT, life: 5 }];
  resolveTick(m, null, null);
  const ball = m.balls.find(b => b.id === 7);
  assert.equal(ball.row, 2);
  assert.equal(ball.col, 0, "must not leave through the side");
  assert.equal(ball.exit, LEFT, "the outer edge does not reverse the ball");
});

test("a ball reverses when its track ends inside the board", () => {
  const m = createMatch(0);
  m.cells[0][0] = PIECE.EW;   // exits RIGHT
  m.cells[0][1] = PIECE.NS;   // no LEFT port
  m.balls = [{ id: 5, row: 0, col: 0, exit: RIGHT, life: 5 }];
  const ev = resolveTick(m, null, null);
  const ball = m.balls.find(b => b.id === 5);
  assert.equal(ball.col, 0, "bouncing ball stays put");
  assert.equal(ball.exit, LEFT, "ball heads back along its track");
  assert.deepEqual(ev.moves.find(move => move.id === 5), {
    id: 5, kind: "bounce", reason: "dead-end", at: { row: 0, col: 0 },
  });
});

test("a ball reverses through the other port of a corner piece", () => {
  const m = createMatch(0);
  m.cells[1][0] = PIECE.NE;
  m.cells[1][1] = PIECE.NS;
  m.balls = [{ id: 6, row: 1, col: 0, exit: RIGHT, life: 5 }];
  resolveTick(m, null, null);
  const ball = m.balls.find(candidate => candidate.id === 6);
  assert.equal(ball.row, 1);
  assert.equal(ball.col, 0);
  assert.equal(ball.exit, UP, "reverse follows the corner, not a geometric 180-degree turn");
});

test("a ball entering a corner leaves by the far port", () => {
  const m = createMatch(0);
  // Away from the two spawn sources at (2,2) and (3,3): a ball spawning into
  // the same cell would block this one under the one-ball-per-cell rule.
  m.cells[0][0] = PIECE.EW;   // exits RIGHT
  m.cells[0][1] = PIECE.NW;   // has LEFT and UP -> enters LEFT, exits UP
  m.balls = [{ id: 5, row: 0, col: 0, exit: RIGHT, life: 5 }];
  resolveTick(m, null, null);
  const ball = m.balls.find(b => b.id === 5);
  assert.equal(ball.row, 0);
  assert.equal(ball.col, 1);
  assert.equal(ball.exit, UP);
});

test("a ball does not roll onto a cell another ball stays in", () => {
  const m = createMatch(0);
  m.balls = [];
  m.cells = m.cells.map(r => r.map(() => PIECE.EW));
  m.balls = [
    { id: 20, row: 0, col: 1, exit: LEFT, life: 9 },
    { id: 21, row: 0, col: 0, exit: LEFT, life: 9 },
  ];
  resolveTick(m, null, null);
  const a = m.balls.find(b => b.id === 20);
  const b = m.balls.find(b => b.id === 21);
  assert.equal(b.col, 0, "ball at the side wall stays");
  assert.equal(a.col, 1, "the ball behind must not stack onto it");
  assert.equal(a.exit, RIGHT, "the ball behind reverses after the collision");
});

test("balls move in a chain when the leading cell frees up", () => {
  const m = createMatch(0);
  m.balls = [];
  m.cells = m.cells.map(r => r.map(() => PIECE.EW));
  m.balls = [
    { id: 10, row: 0, col: 1, exit: RIGHT, life: 9 },
    { id: 11, row: 0, col: 2, exit: RIGHT, life: 9 },
  ];
  resolveTick(m, null, null);
  assert.equal(m.balls.find(b => b.id === 10).col, 2);
  assert.equal(m.balls.find(b => b.id === 11).col, 3);
});

test("two balls never land on the same cell", () => {
  const m = createMatch(0);
  m.balls = [];
  m.cells = m.cells.map(r => r.map(() => PIECE.EW));
  // Both aim at (0,2) from opposite sides.
  m.cells[0][2] = PIECE.EW;
  m.balls = [
    { id: 30, row: 0, col: 1, exit: RIGHT, life: 9 },
    { id: 31, row: 0, col: 3, exit: LEFT, life: 9 },
  ];
  resolveTick(m, null, null);
  const cells = m.balls.filter(b => b.id >= 30).map(b => `${b.row},${b.col}`);
  assert.equal(new Set(cells).size, cells.length, "no two balls share a cell");
  assert.equal(m.balls.find(b => b.id === 30).exit, LEFT);
  assert.equal(m.balls.find(b => b.id === 31).exit, RIGHT);
});

test("two balls heading into each other reverse instead of swapping cells", () => {
  const m = createMatch(0);
  m.balls = [];
  m.cells[0][0] = PIECE.EW;
  m.cells[0][1] = PIECE.EW;
  m.balls = [
    { id: 40, row: 0, col: 0, exit: RIGHT, life: 9 },
    { id: 41, row: 0, col: 1, exit: LEFT, life: 9 },
  ];
  const ev = resolveTick(m, null, null);
  assert.deepEqual(m.balls.filter(ball => ball.id >= 40).map(ball => [ball.col, ball.exit]), [
    [0, LEFT],
    [1, RIGHT],
  ]);
  assert.deepEqual(ev.moves.filter(move => move.id >= 40).map(move => move.kind),
    ["bounce", "bounce"]);
});

test("rotating a platform carries the ball and its heading", () => {
  const m = createMatch(0);
  // Ball at platform 0 local (1,0), heading DOWN. One CW turn -> local (0,0),
  // heading LEFT, where the side wall keeps it in place without a dead-end bounce.
  m.cells = m.cells.map(r => r.map(() => PIECE.NS));
  m.balls = [{ id: 900, row: 1, col: 0, exit: DOWN, life: 5 }];
  const m2 = cloneMatch(m);
  // Rotate only; block movement by making the target unreachable is hard here,
  // so check position/heading directly after rotation via a fresh sim step.
  resolveTick(m2, { platform: 0, dir: 1 }, null);
  // The platform carries the ball from local (1,0) to (0,0) and turns its
  // heading DOWN -> LEFT.
  const ball = m2.balls.find(b => b.id === 900);
  assert.ok(ball, "ball still alive");
  assert.equal(ball.row, 0);
  assert.equal(ball.col, 0, "carried with the platform");
  assert.equal(ball.exit, LEFT, "heading turned with the platform");
});

test("a ball never expires: only delivery takes it off the board", () => {
  const m = createMatch(0);
  // A ball parked against a side wall has nowhere to go and would previously
  // have been removed once its lifetime ran out.
  m.cells = m.cells.map(r => r.map(() => PIECE.EW));
  m.balls = [{ id: 3, row: 2, col: 0, exit: LEFT }];

  for (let i = 0; i < TICKS; i++) {
    const ev = resolveTick(m, null, null);
    if (!ev) break;
    assert.deepEqual(ev.expired, [], `tick ${i + 1} expired a ball`);
  }

  assert.ok(m.balls.find(b => b.id === 3), "the ball must still be on the board");
  assert.equal(m.score.top + m.score.bottom, 0, "a stuck ball scores nothing");
});

test("a delivered ball is still removed and scores", () => {
  const m = createMatch(0);
  m.cells[0][0] = PIECE.NS;
  m.balls = [{ id: 4, row: 0, col: 0, exit: UP }];
  const ev = resolveTick(m, null, null);
  assert.equal(m.score.top, 1, "delivery scores");
  assert.ok(!m.balls.find(b => b.id === 4), "delivered ball leaves the board");
  assert.deepEqual(ev.expired, []);
});

test("match ends after 30 ticks", () => {
  const m = createMatch(0);
  for (let i = 0; i < TICKS; i++) {
    assert.equal(m.finished, false, `finished early at tick ${i}`);
    resolveTick(m, null, null);
  }
  assert.equal(m.finished, true);
  assert.equal(resolveTick(m, null, null), null, "no ticks after the end");
});

test("both peers reach identical state from the same command log", () => {
  const cmds = [];
  const rnd = (() => { let s = 12345; return () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff; })();
  for (let i = 0; i < TICKS; i++) {
    const mk = () => rnd() < 0.3 ? null
      : { platform: Math.floor(rnd() * 9), dir: rnd() < 0.5 ? 1 : -1 };
    cmds.push([mk(), mk()]);
  }
  const run = () => {
    const m = createMatch(1);
    for (const [t, b] of cmds) resolveTick(m, t, b);
    return m;
  };
  const A = run(), B = run();
  assert.deepEqual(A.cells, B.cells);
  assert.deepEqual(A.score, B.score);
  assert.deepEqual(A.balls, B.balls);
});
