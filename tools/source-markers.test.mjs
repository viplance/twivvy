import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import * as rules from "../js/rules.js";

// Exercise the real presentation methods without a GPU or a CDN dependency.
class Vector3 {
  constructor(x = 0, y = 0, z = 0) { this.set(x, y, z); }
  set(x, y, z) { Object.assign(this, { x, y, z }); return this; }
  copy(v) { return this.set(v.x, v.y, v.z); }
  clone() { return new Vector3(this.x, this.y, this.z); }
  sub(v) { return this.set(this.x - v.x, this.y - v.y, this.z - v.z); }
}
const source = await readFile(new URL("../js/view.js", import.meta.url), "utf8");
const context = vm.createContext({ ...rules, THREE: { Vector3 } });
vm.runInContext(source.replace(/^import[\s\S]*?from "[^"\n]+";\n/gm, "").replace("export class BoardView", "class BoardView"), context);
const BoardView = vm.runInContext("BoardView", context);

function viewFixture() {
  const view = Object.create(BoardView.prototype);
  const markerPositions = [-0.5, 0.5];
  Object.assign(view, {
    sourceMarkers: rules.SOURCES.map((source, index) => ({
      visible: false,
      position: new Vector3(markerPositions[index], 0, markerPositions[index]),
      userData: { source: { row: source.row, col: source.col } },
      getWorldPosition(target) { return target.copy(this.position); },
    })),
    pivot: { worldToLocal: point => point },
    ballMeshes: new Map(),
    clearPreview() {}, clearCollected() {}, syncCells() {}, syncBalls() {},
    setCooldown() {}, _updatePlatformAppearance() {}, _flashSource() {},
    _createBall(id) {
      const mesh = { position: new Vector3(), scale: { setScalar() {} } };
      this.ballMeshes.set(id, mesh);
      return mesh;
    },
  });
  return view;
}
const visible = view => view.sourceMarkers.map(m => m.visible);

test("source markers are children of the platform they rotate with", () => {
  const view = viewFixture();
  const children = [];
  view.platformGroups = Array.from({ length: rules.PLATFORMS }, () => ({
    position: new Vector3(),
    add(marker) { children.push(marker); marker.parent = this; },
  }));
  const marker = { position: new Vector3() };
  view._attachSourceMarker(marker, rules.SOURCES[0]);
  const platform = rules.platformOf(rules.SOURCES[0].row, rules.SOURCES[0].col);
  assert.equal(marker.parent, view.platformGroups[platform]);
  assert.deepEqual(children, [marker]);
});

test("source markers warn exactly one turn before every scheduled spawn", () => {
  const view = viewFixture();
  for (let tick = 0; tick <= rules.TICKS; tick++) {
    view.syncSourceMarkers({ tick, finished: false });
    const expected = [0, 4, 8, 12, 16, 20].includes(tick);
    assert.deepEqual(visible(view), [expected, expected], `after turn ${tick}`);
  }
  view.syncSourceMarkers({ tick: 4, finished: true });
  assert.deepEqual(visible(view), [false, false], "no warning in a finished match");
});

test("restoring a paused or refreshed board recalculates the warning from its saved turn", () => {
  const view = viewFixture(), match = rules.createMatch();
  for (const tick of [4, 5, 8, 9, 20, 21, 0]) {
    match.tick = tick;
    view.restoreMatch(match);
    const expected = rules.SPAWN_TICKS.includes(tick + 1);
    assert.deepEqual(visible(view), [expected, expected]);
  }
});

test("source markers stay visible during the spawn animation and hide as soon as it ends", async () => {
  const view = viewFixture();
  let finish;
  view._animate = () => new Promise(resolve => { finish = resolve; });
  const animation = view.playSpawn(rules.SOURCES.map((s, id) => ({ ...s, id })), 420);
  assert.deepEqual(visible(view), [true, true]);
  finish();
  await animation;
  assert.deepEqual(visible(view), [false, false]);
});

test("a ball rises from the marker's rendered position after its platform turns", async () => {
  const view = viewFixture();
  view._animate = async (_duration, step) => step(1);
  const source = rules.SOURCES[0];
  await view.playSpawn([{ ...source, id: 7 }], 420);
  const ball = view.ballMeshes.get(7);
  assert.equal(ball.position.x, view.sourceMarkers[0].position.x);
  assert.equal(ball.position.z, view.sourceMarkers[0].position.z);
  assert.ok(Math.abs(ball.position.y - 0.16) < 1e-12);
});

test("an interrupted spawn animation cannot leave source markers stuck on", async () => {
  const view = viewFixture();
  view._animate = async () => { throw new Error("interrupted"); };
  await assert.rejects(view.playSpawn(rules.SOURCES.map((s, id) => ({ ...s, id })), 420), /interrupted/);
  assert.deepEqual(visible(view), [false, false]);
});

test("the next warning is shown only after the preceding move animation finishes", async () => {
  const view = viewFixture();
  let finish;
  view._animate = () => new Promise(resolve => { finish = resolve; });
  const match = rules.createMatch();
  match.tick = 4;
  const animation = view.playTick({ spawned: [], rotations: [], delivered: [],
    moves: [{ id: 1, kind: "move", to: { row: 0, col: 0 } }] }, null, match, 1200);
  await Promise.resolve();
  assert.deepEqual(visible(view), [false, false]);
  finish();
  await animation;
  assert.deepEqual(visible(view), [true, true]);
});

test("colliding balls lunge toward each other and end back on their cells", async () => {
  const view = viewFixture();
  view._createBall(10);
  view._createBall(11);
  for (const mesh of view.ballMeshes.values()) {
    mesh.userData = { arrow: { rotation: { y: 0 }, position: {}, scale: { setScalar() {} } } };
  }

  // Two balls on adjacent cells of one row, heading into each other. The rules
  // report both as bounced by a collision, at their own (unchanged) cells.
  const match = rules.createMatch();
  match.balls = [
    { id: 10, row: 0, col: 0, exit: rules.RIGHT },
    { id: 11, row: 0, col: 1, exit: rules.LEFT },
  ];
  const before = {
    balls: [
      { id: 10, row: 0, col: 0, exit: rules.RIGHT },
      { id: 11, row: 0, col: 1, exit: rules.LEFT },
    ],
  };
  const event = {
    spawned: [], rotations: [], delivered: [],
    moves: [
      { id: 10, kind: "bounce", reason: "collision", at: { row: 0, col: 0 } },
      { id: 11, kind: "bounce", reason: "collision", at: { row: 0, col: 1 } },
    ],
  };

  // Drive the animation by hand so we can inspect the midpoint.
  const samples = [];
  view._animate = async (duration, step) => {
    for (const t of [0, 0.5, 1]) {
      step(t);
      samples.push([...view.ballMeshes.values()].map(m => m.position.x));
    }
  };

  const meshA = view.ballMeshes.get(10);
  const meshB = view.ballMeshes.get(11);
  meshA.position.set(0, 0.16, 0);
  meshB.position.set(1, 0.16, 0);

  await view.playTick(event, before, match, 1200);

  const [start, middle, end] = samples;
  const gapStart = Math.abs(start[1] - start[0]);
  const gapMiddle = Math.abs(middle[1] - middle[0]);
  assert.ok(gapMiddle < gapStart, `balls must close in: ${gapMiddle} !< ${gapStart}`);
  assert.ok(gapMiddle > 2 * 0.17, `balls must not overlap: gap ${gapMiddle}`);
  // And they return to exactly where they started — a bounce changes no cell.
  assert.equal(meshA.position.x, 0, "ball A back on its cell");
  assert.equal(meshB.position.x, 1, "ball B back on its cell");
});

test("a ball at a dead end rolls up to the missing track and returns", async () => {
  const view = viewFixture();
  view._createBall(20);
  const mesh = view.ballMeshes.get(20);
  mesh.userData = { arrow: { rotation: { y: 0 }, position: {}, scale: { setScalar() {} } } };

  const match = rules.createMatch();
  match.balls = [{ id: 20, row: 0, col: 0, exit: rules.LEFT }];
  const before = { balls: [{ id: 20, row: 0, col: 0, exit: rules.RIGHT }] };
  const event = {
    spawned: [], rotations: [], delivered: [],
    moves: [{ id: 20, kind: "bounce", reason: "dead-end", at: { row: 0, col: 0 } }],
  };

  const xs = [];
  view._animate = async (duration, step) => {
    for (const t of [0, 0.25, 0.5, 0.75, 1]) {
      step(t);
      xs.push(mesh.position.x);
    }
  };

  mesh.position.set(0, 0.16, 0);
  await view.playTick(event, before, match, 1200);

  // It heads RIGHT (+x), reaches furthest at the midpoint, then comes back.
  assert.ok(xs[2] > xs[1], `must still be advancing at the midpoint: ${xs}`);
  assert.ok(xs[3] < xs[2], `must be returning after the midpoint: ${xs}`);
  // Far edge touches the cell boundary (0.5) without crossing it.
  const BALL_R = 0.17;
  assert.ok(xs[2] + BALL_R <= 0.5 + 1e-9, `ball crossed into the next cell: ${xs[2]}`);
  assert.ok(xs[2] > 0.3, `dead-end nose-in too timid to read: ${xs[2]}`);
  // And it ends exactly where it started — a bounce changes no cell.
  assert.equal(mesh.position.x, 0, "ball back on its own cell");
});
