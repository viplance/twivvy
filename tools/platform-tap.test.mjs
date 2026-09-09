import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import * as rules from "../js/rules.js";

class Vector3 {
  constructor(x = 0, y = 0, z = 0) { this.set(x, y, z); }
  set(x, y, z) { Object.assign(this, { x, y, z }); return this; }
  copy(v) { return this.set(v.x, v.y, v.z); }
  clone() { return new Vector3(this.x, this.y, this.z); }
}
class Raycaster {
  platform = 0;
  setFromCamera() {}
  intersectObjects() { return [{ object: { userData: { platform: this.platform } } }]; }
}
const source = await readFile(new URL("../js/view.js", import.meta.url), "utf8");
const context = vm.createContext({ ...rules, THREE: { Vector3, Raycaster, Vector2: class {}, Plane: class {} } });
vm.runInContext(source.replace(/^import[\s\S]*?from "[^"\n]+";\n/gm, "").replace("export class BoardView", "class BoardView"), context);
const BoardView = vm.runInContext("BoardView", context);

function fixture(angle) {
  const view = Object.create(BoardView.prototype), handlers = {}, captures = new Set();
  const commands = [], animations = [];
  const base = new Vector3(0.5, 0.16, 0.5), ball = { position: base.clone() };
  Object.assign(view, {
    canvas: {
      style: {}, addEventListener(type, fn) { handlers[type] = fn; },
      getBoundingClientRect: () => ({ left: 0, top: 0, width: 500, height: 500 }),
      setPointerCapture: id => captures.add(id), hasPointerCapture: id => captures.has(id),
      releasePointerCapture: id => captures.delete(id),
    },
    platformGroups: [0, 3].map(x => ({ position: new Vector3(x, 0, 0), rotation: { y: 0 } })),
    ballMeshes: new Map([[1, ball]]), interactionEnabled: true,
    onPlatformDragStart: () => true, onPlatformDrag: (platform, dir) => commands.push({ platform, dir }),
    _syncBallDirection(mesh, angle = 0) { mesh.arrowAngle = angle; },
    _updatePlatformAppearance() { this.highlighted = Math.abs(this.preview?.angle || 0) > 0.0001; },
    _animate(duration, step) {
      return new Promise(resolve => animations.push({ duration, step, finish() { step(1); resolve(); } }));
    },
  });
  view._initPicking();
  view.testAngle = 0;
  view._pointerAngle = () => view.testAngle;
  view.preview = { platform: 0, angle: 0, ballStarts: new Map([[1, base]]) };
  view._applyPreviewAngle(angle);
  const pointer = (type, x = 100, y = 100) => handlers[type]({ pointerId: 1, button: 0, clientX: x, clientY: y, preventDefault() {} });
  return { view, pointer, commands, animations, ball, base };
}

for (const angle of [-Math.PI / 2, Math.PI / 2]) {
  test(`tap returns smoothly from ${angle}, carrying the ball and its arrow backwards`, async () => {
    const { view, pointer, commands, animations, ball, base } = fixture(angle);
    const rotated = ball.position.clone();
    pointer("pointerdown");
    assert.equal(view.preview.angle, angle, "pressing must not reset the preview");
    assert.deepEqual(ball.position, rotated);
    pointer("pointerup");
    assert.equal(view.preview.angle, angle, "release starts from the rendered angle");
    assert.deepEqual(commands, [{ platform: 0, dir: null }], "clear the logical choice immediately");
    const snap = animations.at(-1), pending = view._previewSnap.promise;
    assert.equal(snap.duration, 240);
    snap.step(0.5);
    assert.equal(view.preview.angle, angle / 8);
    assert.equal(ball.arrowAngle, angle / 8);
    assert.equal(view.highlighted, true);
    assert.notDeepEqual(ball.position, rotated);
    assert.notDeepEqual(ball.position, base);
    snap.finish();
    await pending;
    assert.equal(view.preview, null);
    assert.equal(view.platformGroups[0].rotation.y, 0);
    assert.deepEqual(ball.position, base);
    assert.equal(ball.arrowAngle, 0);
    assert.equal(view.highlighted, false);
  });
}

test("small pointer jitter is still a reset tap, not a new rotation", () => {
  const { view, pointer, commands } = fixture(Math.PI / 2);
  pointer("pointerdown");
  view.testAngle = 0.03;
  pointer("pointermove", 102, 101);
  assert.equal(view.preview.angle, Math.PI / 2);
  pointer("pointerup", 102, 101);
  assert.equal(commands[0].dir, null);
});

test("dragging the same platform starts at its visible angle without a jump", () => {
  const { view, pointer, commands } = fixture(Math.PI / 2);
  pointer("pointerdown");
  view.testAngle = 0.4;
  pointer("pointermove", 120, 100);
  assert.equal(view.preview.angle, Math.PI / 2 - 0.4);
  pointer("pointerup", 120, 100);
  assert.equal(commands[0].dir, -1, "a real drag must not be interpreted as a reset tap");
});

test("tapping during an unfinished snap returns from the intermediate angle; stale frames cannot interfere", async () => {
  const { view, pointer, animations } = fixture(0.4);
  view.drag = { pointerId: 1, platform: 0, moved: true };
  const obsolete = view._finishDrag();
  const old = animations.at(-1);
  old.step(0.3);
  const current = view.preview.angle;
  pointer("pointerdown");
  old.finish();
  await obsolete;
  assert.equal(view.preview.angle, current);
  pointer("pointerup");
  const pending = view._previewSnap.promise;
  animations.at(-1).step(0.5);
  assert.ok(Math.abs(view.preview.angle - current / 8) < 1e-12);
  animations.at(-1).finish();
  await pending;
  assert.equal(view.preview, null);
});

test("a decision deadline during a reset tap clears the choice and retains the return animation", () => {
  const { view, pointer, commands, animations } = fixture(-Math.PI / 2);
  pointer("pointerdown");
  view.setInteractionEnabled(false);
  assert.equal(view.preview.angle, -Math.PI / 2);
  assert.equal(commands[0].dir, null);
  assert.equal(animations.length, 1);
  assert.equal(view.drag, null);
});

test("pressing another platform returns the selected platform smoothly", async () => {
  const { view, pointer, animations, ball, base } = fixture(Math.PI / 2);
  const rotated = ball.position.clone();
  view.raycaster.platform = 1;

  pointer("pointerdown");

  assert.equal(view.preview.platform, 1, "the new platform is interactive immediately");
  assert.equal(view.platformGroups[0].rotation.y, Math.PI / 2, "the old platform must not jump");
  assert.deepEqual(ball.position, rotated, "a carried ball must not jump either");

  const returning = animations.at(-1);
  const pending = view._previewReturns.get(0).promise;
  assert.equal(returning.duration, 240);
  returning.step(0.5);
  assert.equal(view.platformGroups[0].rotation.y, Math.PI / 16);
  assert.equal(ball.arrowAngle, Math.PI / 16);
  assert.notDeepEqual(ball.position, rotated);
  assert.notDeepEqual(ball.position, base);

  returning.finish();
  await pending;
  assert.equal(view.platformGroups[0].rotation.y, 0);
  assert.deepEqual(ball.position, base);
  assert.equal(ball.arrowAngle, 0);
});
