// Three.js presentation layer. Owns no rules: reads match state from rules.js
// and animates resolveTick's events. The local player's receiver is always at
// the bottom — the guest's camera is flipped 180° over the shared grid.

import * as THREE from "three";
import {
  SIZE,
  PLATFORMS,
  SOURCES,
  SPAWN_TICKS,
  platformOrigin,
  platformOf,
  UP,
  RIGHT,
  DOWN,
  LEFT,
} from "./rules.js?v=20260910-turnsound";

const CELL = 1;
const GAP = 0.18; // visible gap between platforms, so groups read as units
const TRACK_R = 0.13;
const BALL_R = 0.17;
// How far a ball noses into a blocked cell before recoiling, as a fraction of
// portOffset (half a cell). Head-on, the two centres close to 0.5 apart —
// clear of touching (2 * BALL_R = 0.34) while the impact still reads.
const LUNGE_REACH = 0.5;
// Nothing blocks a dead end, so the ball reaches where the track stops: centre
// at 0.33, far edge exactly on the 0.5 cell boundary, never past it.
const DEAD_END_REACH = 0.66;

const COLOR = {
  bg: 0x0b1020,
  board: 0x161d33,
  platform: 0x1e2745,
  platformLock: 0x3a3050,
  platformSelected: 0x14483f,
  track: 0x8fa3c8,
  ball: 0xffffff,
  own: 0x2fd6c3, // turquoise — the local player's receiver
  foe: 0xff7a66, // coral — the opponent's
  source: 0xf2c14e, // warm amber — the two fixed ball sources
};

/** World position of the centre of a cell. Platform gaps are added in. */
function cellPosition(row, col) {
  const px = Math.floor(col / 2) * GAP;
  const pz = Math.floor(row / 2) * GAP;
  const spanX = SIZE * CELL + 2 * GAP;
  const spanZ = SIZE * CELL + 2 * GAP;
  return new THREE.Vector3(
    col * CELL + px + CELL / 2 - spanX / 2,
    0,
    row * CELL + pz + CELL / 2 - spanZ / 2,
  );
}

/** Direction vector in world space for a port. Row grows toward +Z (screen down). */
function portOffset(port) {
  switch (port) {
    case UP:
      return new THREE.Vector3(0, 0, -CELL / 2);
    case DOWN:
      return new THREE.Vector3(0, 0, CELL / 2);
    case LEFT:
      return new THREE.Vector3(-CELL / 2, 0, 0);
    default:
      return new THREE.Vector3(CELL / 2, 0, 0);
  }
}

function makeTrackMesh(mask, material) {
  const group = new THREE.Group();
  const ports = [];
  for (let port = 0; port < 4; port++) if (mask & (1 << port)) ports.push(port);

  // A straight piece is one bar; a corner is two half-bars meeting at centre.
  const isStraight =
    (ports[0] === UP && ports[1] === DOWN) ||
    (ports[0] === RIGHT && ports[1] === LEFT);

  if (isStraight) {
    const vertical = ports.includes(UP);
    const geo = new THREE.BoxGeometry(
      vertical ? TRACK_R * 2 : CELL,
      TRACK_R,
      vertical ? CELL : TRACK_R * 2,
    );
    group.add(new THREE.Mesh(geo, material));
  } else {
    for (const port of ports) {
      const off = portOffset(port);
      const horizontal = port === LEFT || port === RIGHT;
      const geo = new THREE.BoxGeometry(
        horizontal ? CELL / 2 + TRACK_R : TRACK_R * 2,
        TRACK_R,
        horizontal ? TRACK_R * 2 : CELL / 2 + TRACK_R,
      );
      const mesh = new THREE.Mesh(geo, material);
      mesh.position.set(off.x / 2, 0, off.z / 2);
      group.add(mesh);
    }
  }
  return group;
}

export class BoardView {
  constructor(canvas, { onPlatformDragStart, onPlatformDrag, onPlatformRelease }) {
    this.canvas = canvas;
    this.onPlatformDragStart = onPlatformDragStart;
    this.onPlatformDrag = onPlatformDrag;
    this.onPlatformRelease = onPlatformRelease;
    this.flipped = false;
    this.ballMeshes = new Map();
    this.platformGroups = [];
    this.cellGroups = [];
    this.animations = new Set(); // in-flight _animate runs, so they can be cancelled
    this.interactionEnabled = false;
    this.drag = null;
    this.preview = null;
    this._previewSnap = null;
    this._previewReturns = new Map();
    this.cooldown = [];

    this._initScene();
    this._initPicking();
  }

  _initScene() {
    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: true,
      alpha: false,
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(COLOR.bg);

    this.camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);

    // The whole board sits in a pivot we rotate 180° for the guest.
    this.pivot = new THREE.Group();
    this.scene.add(this.pivot);

    this.scene.add(new THREE.AmbientLight(0xffffff, 0.55));
    const key = new THREE.DirectionalLight(0xffffff, 1.1);
    key.position.set(4, 9, 3);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x6ea8ff, 0.5);
    rim.position.set(-5, 4, -4);
    this.scene.add(rim);

    this._buildBoard();
    this._resize();
    window.addEventListener("resize", () => this._resize());
  }

  _buildBoard() {
    const spanX = SIZE * CELL + 2 * GAP;
    const spanZ = SIZE * CELL + 2 * GAP;

    const base = new THREE.Mesh(
      new THREE.BoxGeometry(spanX + 0.9, 0.4, spanZ + 1.9),
      new THREE.MeshStandardMaterial({
        color: COLOR.board,
        roughness: 0.85,
        metalness: 0.1,
      }),
    );
    base.position.y = -0.35;
    this.pivot.add(base);

    // Receivers: bottom edge belongs to the "bottom" player, top to "top".
    this.receivers = {};
    for (const side of ["top", "bottom"]) {
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(spanX, 0.22, 0.55),
        new THREE.MeshStandardMaterial({
          color: 0xffffff,
          emissive: 0x000000,
          roughness: 0.4,
        }),
      );
      mesh.position.set(
        0,
        -0.05,
        side === "top" ? -spanZ / 2 - 0.42 : spanZ / 2 + 0.42,
      );
      this.pivot.add(mesh);
      this.receivers[side] = mesh;
    }

    // The tray keeps its delivered balls, so it shows the score itself.
    this.collected = { top: [], bottom: [] };
    this.collectedZ = {
      top: -spanZ / 2 - 0.42,
      bottom: spanZ / 2 + 0.42,
    };

    // Colour them before a match starts, so the menu backdrop looks right.
    this.setPerspective("bottom");

    this.platformMaterials = [];
    for (let p = 0; p < PLATFORMS; p++) {
      const group = new THREE.Group();
      const { row, col } = platformOrigin(p);
      const centre = cellPosition(row, col)
        .add(cellPosition(row + 1, col + 1))
        .multiplyScalar(0.5);
      group.position.copy(centre);
      this.pivot.add(group);
      this.platformGroups.push(group);

      const material = new THREE.MeshStandardMaterial({
        color: COLOR.platform,
        roughness: 0.7,
        metalness: 0.15,
        emissive: 0x000000,
      });
      this.platformMaterials.push(material);

      const plate = new THREE.Mesh(
        new THREE.BoxGeometry(2 * CELL - 0.06, 0.2, 2 * CELL - 0.06),
        material,
      );
      plate.position.y = -0.12;
      plate.userData.platform = p;
      group.add(plate);
    }

    this.trackMaterial = new THREE.MeshStandardMaterial({
      color: COLOR.track,
      roughness: 0.5,
      metalness: 0.35,
    });

    // One group per cell, parented to its platform so rotation carries it.
    for (let row = 0; row < SIZE; row++) {
      this.cellGroups[row] = [];
      for (let col = 0; col < SIZE; col++) {
        const holder = new THREE.Group();
        const platform = platformOf(row, col);
        const group = this.platformGroups[platform];
        const world = cellPosition(row, col);
        holder.position.copy(world).sub(group.position);
        group.add(holder);
        this.cellGroups[row][col] = holder;
      }
    }

    // Wells belong to their platform: the source cells are fixed between turns,
    // but a well must travel with the plate during a preview or resolve.
    this.sourceMarkers = [];
    for (const source of SOURCES) {
      const marker = new THREE.Group();
      marker.visible = false;

      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.3, 0.4, 32),
        new THREE.MeshBasicMaterial({
          color: COLOR.source,
          transparent: true,
          opacity: 0.5,
          side: THREE.DoubleSide,
        }),
      );
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.015;
      marker.add(ring);

      // A recessed well, so the cell reads as an opening the balls rise from.
      const well = new THREE.Mesh(
        new THREE.CircleGeometry(0.3, 32),
        new THREE.MeshBasicMaterial({
          color: COLOR.source,
          transparent: true,
          opacity: 0.14,
        }),
      );
      well.rotation.x = -Math.PI / 2;
      well.position.y = 0.012;
      marker.add(well);

      marker.userData.ring = ring;
      marker.userData.source = { row: source.row, col: source.col };
      this._attachSourceMarker(marker, source);
      this.sourceMarkers.push(marker);
    }

    this.ballMaterial = new THREE.MeshLambertMaterial({
      color: COLOR.ball,
      emissive: 0x556699,
      emissiveIntensity: 0.6,
    });
    this.ballGeometry = new THREE.SphereGeometry(BALL_R, 20, 16);

    // A small flat arrow on the track, pointing toward UP (-Z) by default.
    const arrow = new THREE.Shape();
    arrow.moveTo(-0.025, 0.23);
    arrow.lineTo(0.025, 0.23);
    arrow.lineTo(0.025, 0.32);
    arrow.lineTo(0.085, 0.32);
    arrow.lineTo(0, 0.43);
    arrow.lineTo(-0.085, 0.32);
    arrow.lineTo(-0.025, 0.32);
    arrow.closePath();
    this.ballArrowGeometry = new THREE.ShapeGeometry(arrow);
    this.ballArrowGeometry.rotateX(-Math.PI / 2);
    this.ballArrowMaterial = new THREE.MeshBasicMaterial({
      color: 0x18243b,
      side: THREE.DoubleSide,
    });
  }

  _attachSourceMarker(marker, source) {
    const group = this.platformGroups[platformOf(source.row, source.col)];
    marker.position.copy(cellPosition(source.row, source.col)).sub(group.position);
    group.add(marker);
  }

  /** Guest sees the same grid rotated 180°, so their receiver is at the bottom. */
  setPerspective(side) {
    this.flipped = side === "top";
    this.pivot.rotation.y = this.flipped ? Math.PI : 0;

    const ownSide = side;
    const foeSide = side === "top" ? "bottom" : "top";
    this.receivers[ownSide].material.color.setHex(COLOR.own);
    this.receivers[ownSide].material.emissive.setHex(0x0d5a52);
    this.receivers[foeSide].material.color.setHex(COLOR.foe);
    this.receivers[foeSide].material.emissive.setHex(0x5c2418);
  }

  /** Project the receiver and its outer rim, including room for collected balls. */
  receiverScreenPosition(side) {
    const receiver = this.receivers[side];
    if (!receiver) return null;
    this.scene.updateMatrixWorld(true);
    this.camera.updateMatrixWorld(true);
    const point = new THREE.Vector3();
    receiver.getWorldPosition(point);
    point.project(this.camera);
    const rect = this.canvas.getBoundingClientRect();
    const edgeZ = (side === "top" ? -1 : 1) * (SIZE * CELL + 2 * GAP + 1.9) / 2;
    const ys = [];
    for (const z of [receiver.position.z - 0.275, receiver.position.z + 0.275, edgeZ]) {
      for (const y of [-0.55, 0.5]) {
        const edge = this.pivot.localToWorld(new THREE.Vector3(0, y, z)).project(this.camera);
        ys.push(rect.top + (1 - edge.y) * rect.height / 2);
      }
    }
    return {
      x: rect.left + (point.x + 1) * rect.width / 2,
      y: rect.top + (1 - point.y) * rect.height / 2,
      top: Math.min(...ys),
      bottom: Math.max(...ys),
    };
  }

  _resize() {
    const width = this.canvas.clientWidth || window.innerWidth;
    const height = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(width, height, false);
    // Clear the previous framing before measuring a resized viewport.
    this.camera.clearViewOffset();
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();

    // Board extents including both receivers and a small margin.
    const boardW = SIZE * CELL + 2 * GAP + 0.9;
    const boardD = SIZE * CELL + 2 * GAP + 1.9;

    // Tilted axis: depth is foreshortened by cos(tilt), height adds sin(tilt).
    const tilt = 1.06; // radians from the horizon; ~61°, a readable table view
    const vFov = (this.camera.fov * Math.PI) / 180;
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * this.camera.aspect);

    const apparentDepth = boardD * Math.sin(tilt);
    const distV = apparentDepth / 2 / Math.tan(vFov / 2);
    const distH = boardW / 2 / Math.tan(hFov / 2);

    // Leave a small margin around the board.
    let dist = Math.max(distV, distH) * 1.06;
    const positionCamera = () => {
      this.camera.position.set(0, dist * Math.sin(tilt), dist * Math.cos(tilt));
      this.camera.lookAt(0, 0, 0);
      this.camera.updateMatrixWorld();
    };
    positionCamera();

    const desktop = width >= 900 && height >= 600;
    const lift = desktop ? Math.min(64, height * 0.045) : 8;
    // Fit the projected board with space for both names after lifting it.
    {
      const margin = desktop ? 30 : 12;
      const halfW = width / 2;
      const halfH = height / 2;
      const corners = [];
      for (const x of [-boardW / 2, boardW / 2]) {
        for (const y of [-0.55, 0.5]) {
          for (const z of [-boardD / 2, boardD / 2]) {
            corners.push(new THREE.Vector3(x, y, z));
          }
        }
      }

      const projectedBounds = () => {
        const pixels = corners.map(point => {
          const projected = point.clone().project(this.camera);
          return {
            x: (projected.x + 1) * halfW,
            y: (1 - projected.y) * halfH,
          };
        });
        return {
          minX: Math.min(...pixels.map(point => point.x)),
          maxX: Math.max(...pixels.map(point => point.x)),
          minY: Math.min(...pixels.map(point => point.y)),
          maxY: Math.max(...pixels.map(point => point.y)),
        };
      };
      const fits = ({ minX, maxX, minY, maxY }) =>
        minX >= margin && maxX <= width - margin &&
        minY >= margin + 40 + lift && maxY <= height - margin - 40 + lift;

      if (!fits(projectedBounds())) {
        const lowStart = dist;
        let high = dist;
        do {
          high *= 1.25;
          dist = high;
          positionCamera();
        } while (!fits(projectedBounds()));

        let low = lowStart;
        for (let attempt = 0; attempt < 14; attempt++) {
          dist = (low + high) / 2;
          positionCamera();
          if (fits(projectedBounds())) high = dist;
          else low = dist;
        }
        // A tiny cushion avoids sub-pixel clipping from rasterization.
        dist = high * 1.0005;
        positionCamera();
      }
    }

    // A projection offset moves the board without changing its perspective;
    // raycasting and projected name anchors use this same camera.
    this.camera.setViewOffset(width, height, 0, lift, width, height);
    this.camera.updateProjectionMatrix();
  }

  _initPicking() {
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.boardPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);

    const setRay = (clientX, clientY) => {
      const rect = this.canvas.getBoundingClientRect();
      this.pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      this.pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      this.raycaster.setFromCamera(this.pointer, this.camera);
    };

    const pick = (clientX, clientY) => {
      setRay(clientX, clientY);
      const hits = this.raycaster.intersectObjects(this.platformGroups, true);
      for (const hit of hits) {
        const platform = hit.object.userData.platform;
        if (platform !== undefined) return platform;
      }
      return null;
    };

    this.canvas.addEventListener("pointerdown", (event) => {
      if (!this.interactionEnabled || event.button > 0) return;
      const platform = pick(event.clientX, event.clientY);
      if (platform === null || !this.onPlatformDragStart(platform)) return;

      const startAngle = this._pointerAngle(event.clientX, event.clientY, platform);
      if (startAngle === null) return;

      // Keep the visible angle: a tap animates back on release, a drag continues.
      const samePlatform = this.preview?.platform === platform;
      if (samePlatform) {
        this._previewSnap = null; // Freeze any unfinished snap at its current angle.
      } else {
        if (this.preview) {
          this._previewSnap = null;
          const previous = this.preview;
          this.preview = null;
          this._returnPreview(previous);
        }

        // A quick switch can revisit a platform mid-return: continue from the
        // rendered angle instead of jumping.
        const returning = this._previewReturns?.get(platform);
        if (returning) {
          this._previewReturns.delete(platform);
          this.preview = returning.preview;
        } else {
          const ballStarts = new Map();
          const centre = this.platformGroups[platform].position;
          for (const [id, mesh] of this.ballMeshes) {
            if (this._pointOnPlatform(mesh.position, centre)) {
              ballStarts.set(id, mesh.position.clone());
            }
          }
          this.preview = { platform, angle: 0, ballStarts };
        }
        this._updatePlatformAppearance();
      }

      this.drag = {
        pointerId: event.pointerId, platform, startAngle,
        baseAngle: this.preview.angle,
        startX: event.clientX, startY: event.clientY, moved: false,
        tapResets: samePlatform,
      };
      this.canvas.setPointerCapture(event.pointerId);
      this.canvas.style.cursor = "grabbing";
      event.preventDefault();
    });

    this.canvas.addEventListener("pointermove", (event) => {
      if (!this.drag || event.pointerId !== this.drag.pointerId) return;
      const angle = this._pointerAngle(
        event.clientX,
        event.clientY,
        this.drag.platform,
      );
      if (angle === null) return;

      if (Math.hypot(event.clientX - this.drag.startX, event.clientY - this.drag.startY) >= 5) {
        this.drag.moved = true;
      }
      if (!this.drag.moved) return;

      // Positive rotation.y follows a decreasing polar angle in the XZ plane.
      const delta = normalizeAngle(this.drag.startAngle - angle);
      const limited = Math.max(-Math.PI / 2, Math.min(Math.PI / 2, this.drag.baseAngle + delta));
      this._applyPreviewAngle(limited);
      event.preventDefault();
    });

    const finish = (event, cancelled = false) => {
      if (!this.drag || event.pointerId !== this.drag.pointerId) return;
      this._finishDrag(cancelled, true);
      event.preventDefault();
    };
    this.canvas.addEventListener("pointerup", (event) => finish(event));
    this.canvas.addEventListener("pointercancel", (event) => finish(event, true));
  }

  _pointerAngle(clientX, clientY, platform) {
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    this.raycaster.setFromCamera(this.pointer, this.camera);

    const world = new THREE.Vector3();
    if (!this.raycaster.ray.intersectPlane(this.boardPlane, world)) return null;
    const local = this.pivot.worldToLocal(world);
    const centre = this.platformGroups[platform].position;
    return Math.atan2(local.z - centre.z, local.x - centre.x);
  }

  _pointOnPlatform(point, centre) {
    const half = CELL + GAP * 0.5;
    return (
      Math.abs(point.x - centre.x) < half &&
      Math.abs(point.z - centre.z) < half
    );
  }

  _rotatePointAround(point, centre, angle, target = new THREE.Vector3()) {
    const dx = point.x - centre.x;
    const dz = point.z - centre.z;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    return target.set(
      centre.x + dx * cos + dz * sin,
      point.y,
      centre.z - dx * sin + dz * cos,
    );
  }

  _applyPreviewAngle(angle) {
    if (!this.preview) return;
    this._applyPreviewState(this.preview, angle);
  }

  _applyPreviewState(preview, angle) {
    preview.angle = angle;
    const { platform, ballStarts } = preview;
    const group = this.platformGroups[platform];
    group.rotation.y = angle;
    this._updatePlatformAppearance();
    for (const [id, start] of ballStarts) {
      const mesh = this.ballMeshes.get(id);
      if (mesh) {
        this._rotatePointAround(start, group.position, angle, mesh.position);
        this._syncBallDirection(mesh, angle);
      }
    }
  }

  _returnPreview(preview) {
    this._previewReturns ||= new Map();
    const startAngle = preview.angle;
    const returning = { preview };
    this._previewReturns.set(preview.platform, returning);
    returning.promise = this._animate(240, (t) => {
      // Also stop once a resolve has taken the preview over, or this would keep
      // writing ball positions while playTick rotates the same platform.
      if (this._resolving) return;
      if (this._previewReturns.get(preview.platform) !== returning) return;
      const progress = 1 - Math.pow(1 - t, 3);
      this._applyPreviewState(preview, startAngle * (1 - progress));
    }).then(() => {
      if (this._previewReturns.get(preview.platform) !== returning) return;
      this._applyPreviewState(preview, 0);
      this._previewReturns.delete(preview.platform);
      this._updatePlatformAppearance();
    });
    return returning.promise;
  }

  _finishDrag(cancelled = false, released = false) {
    if (!this.drag || !this.preview) return;
    const { pointerId, platform, tapResets, moved } = this.drag;
    const threshold = Math.PI / 12;
    // Three.js +Y rotation is counter-clockwise here; the rules encode CW as +1.
    const dir =
      cancelled || (tapResets && !moved) || Math.abs(this.preview.angle) < threshold
        ? null
        : -Math.sign(this.preview.angle);

    if (this.canvas.hasPointerCapture(pointerId)) {
      this.canvas.releasePointerCapture(pointerId);
    }
    this.drag = null;
    this.canvas.style.cursor = this.interactionEnabled ? "grab" : "default";

    const preview = this.preview;
    const startAngle = preview.angle;
    const targetAngle = dir === null ? 0 : -dir * Math.PI / 2;
    const snap = {};
    this._previewSnap = snap;
    snap.promise = this._animate(240, (t) => {
      // A new drag/reset may replace this preview before the animation ends,
      // and a resolve may take over the board entirely.
      if (this._resolving) return;
      if (this._previewSnap !== snap || this.preview !== preview) return;
      const progress = 1 - Math.pow(1 - t, 3);
      this._applyPreviewAngle(startAngle + (targetAngle - startAngle) * progress);
    }).then(() => {
      if (this._previewSnap !== snap || this.preview !== preview) return;
      this._previewSnap = null;
      if (dir === null) this.clearPreview();
    });
    // Commit at once, even if the deadline falls during the settling animation.
    this.onPlatformDrag(platform, dir);
    // A reset swings the platform back just as visibly as a commit, so it sounds
    // too; only a cancel or a deadline takeover leaves the board without input.
    if (released && !cancelled && (dir !== null || startAngle !== 0)) {
      this.onPlatformRelease?.();
    }
    return snap.promise;
  }

  setInteractionEnabled(enabled) {
    if (!enabled && this.drag) this._finishDrag();
    this.interactionEnabled = enabled;
    this.canvas.style.cursor = enabled ? "grab" : "default";
  }

  clearPreview() {
    this._previewSnap = null;
    const previews = this.preview ? [this.preview] : [];
    if (this._previewReturns) {
      previews.push(...[...this._previewReturns.values()].map(item => item.preview));
      this._previewReturns.clear();
    }
    this.preview = null;
    this.drag = null;
    for (const preview of previews) this._applyPreviewState(preview, 0);
    this._updatePlatformAppearance();
  }

  /** Rebuild all track meshes from the match grid. */
  syncCells(match) {
    for (let row = 0; row < SIZE; row++) {
      for (let col = 0; col < SIZE; col++) {
        const holder = this.cellGroups[row][col];
        holder.clear();
        holder.rotation.y = 0;
        holder.add(makeTrackMesh(match.cells[row][col], this.trackMaterial));
      }
    }
    // Rotations are baked into the grid, so platform groups return to zero.
    for (const group of this.platformGroups) group.rotation.y = 0;
  }

  _createBall(id) {
    const mesh = new THREE.Mesh(this.ballGeometry, this.ballMaterial.clone());
    const arrow = new THREE.Mesh(this.ballArrowGeometry, this.ballArrowMaterial);
    arrow.visible = false;
    mesh.add(arrow);
    mesh.userData.arrow = arrow;
    this.pivot.add(mesh);
    this.ballMeshes.set(id, mesh);
    return mesh;
  }

  _syncBallDirection(mesh, platformAngle = 0) {
    const arrow = mesh.userData.arrow;
    const scale = mesh.scale.x || 1;
    // Cancel transient scaling (spawn) so the marking keeps a constant size.
    arrow.scale.setScalar(1 / scale);
    arrow.position.y = (TRACK_R / 2 + 0.012 - mesh.position.y) / scale;
    arrow.rotation.y = -mesh.userData.exit * Math.PI / 2 + platformAngle;
    arrow.visible = Number.isInteger(mesh.userData.exit);
  }

  /**
   * Which bounced balls nose forward before recoiling, and how far. Without it
   * a bounce only spins the arrow and the reversal looks arbitrary.
   *
   * - "collision": the cell ahead is occupied, so stop short of it.
   * - "dead-end": nothing is in the way, so reach the cell edge and return.
   *
   * `at` is the post-rotation cell, where the mesh already sits by now.
   */
  _bounceLunges(event, matchBefore) {
    const lunges = [];
    if (!matchBefore) return lunges;

    const headings = new Map(matchBefore.balls.map((b) => [b.id, b]));

    for (const move of event.moves) {
      if (move.kind !== "bounce") continue;
      const reach = move.reason === "dead-end" ? DEAD_END_REACH : LUNGE_REACH;
      const mesh = this.ballMeshes.get(move.id);
      const before = headings.get(move.id);
      if (!mesh || !before || !move.at) continue;

      // It was heading this way on entry; portOffset is half a cell of it.
      const toward = portOffset(before.exit);

      lunges.push({ mesh, toward, reach, base: mesh.position.clone() });
    }
    return lunges;
  }

  /** Empty both receiver trays — a rematch starts from a clean board. */
  restoreMatch(match, selection = null) {
    this.clearPreview();
    this.clearCollected();
    // Rebuild the trays from the deterministic delivery log, not just scores.
    for (const event of match.log) {
      for (const delivered of event.delivered) {
        let mesh = this.ballMeshes.get(delivered.id);
        if (!mesh) mesh = this._createBall(delivered.id);
        mesh.position.copy(this._collectSlot(delivered.side));
        this.ballMeshes.delete(delivered.id);
        this.collected[delivered.side].push(mesh);
        mesh.userData.life = null;
        mesh.userData.arrow.visible = false;
        mesh.material.color.setHex(COLOR.ball);
        mesh.material.emissiveIntensity = 0.7;
        mesh.scale.setScalar(1);
      }
    }
    this.syncCells(match);
    this.syncBalls(match);
    this.setCooldown(match.cooldown);
    this.syncSourceMarkers(match);
    if (selection) {
      const platform = selection.platform;
      const centre = this.platformGroups[platform].position;
      const ballStarts = new Map();
      for (const [id, mesh] of this.ballMeshes) {
        if (this._pointOnPlatform(mesh.position, centre)) ballStarts.set(id, mesh.position.clone());
      }
      this.preview = { platform, angle: 0, ballStarts };
      this._applyPreviewAngle(-selection.dir * Math.PI / 2);
    }
  }

  clearCollected() {
    for (const side of ["top", "bottom"]) {
      for (const mesh of this.collected[side]) this.pivot.remove(mesh);
      this.collected[side] = [];
    }
  }

  /**
   * Where the next ball delivered into `side` rests. They line up from the
   * tray's centre outwards, so the row reads as the score; 12 balls always fit.
   */
  _collectSlot(side) {
    const index = this.collected[side].length;
    const step = 0.42;
    // 0, +1, -1, +2, -2 ... keeps the row centred as it grows.
    const rank = Math.ceil(index / 2) * (index % 2 === 0 ? 1 : -1);
    // Rest ON the tray: its top face is at receiverY + half its height.
    const trayTop = this.receivers[side].position.y + 0.11;
    return new THREE.Vector3(
      rank * step,
      trayTop + BALL_R,
      this.collectedZ[side],
    );
  }

  /** Meshes of `delivered` balls move to the tray instead of being destroyed. */
  syncBalls(match, delivered = []) {
    for (const d of delivered) {
      const mesh = this.ballMeshes.get(d.id);
      if (!mesh) continue;
      this.ballMeshes.delete(d.id);
      this.collected[d.side].push(mesh);
      // Settled in the tray.
      mesh.userData.life = null;
      mesh.userData.arrow.visible = false;
      mesh.material.color.setHex(COLOR.ball);
      mesh.material.emissiveIntensity = 0.7;
      mesh.scale.setScalar(1);
    }

    const seen = new Set();
    for (const ball of match.balls) {
      seen.add(ball.id);
      let mesh = this.ballMeshes.get(ball.id);
      if (!mesh) mesh = this._createBall(ball.id);

      const pos = cellPosition(ball.row, ball.col);
      mesh.position.set(pos.x, 0.16, pos.z);
      // Balls never expire: same size and brightness, never age-dependent.
      mesh.userData.life = null;
      mesh.userData.exit = ball.exit;
      mesh.userData.baseEmissive = 0.7;
      mesh.material.color.setHex(COLOR.ball);
      mesh.material.emissiveIntensity = mesh.userData.baseEmissive;
      mesh.scale.setScalar(1);
      this._syncBallDirection(mesh);
    }
    for (const [id, mesh] of this.ballMeshes) {
      if (!seen.has(id)) {
        this.pivot.remove(mesh);
        this.ballMeshes.delete(id);
      }
    }
  }

  setCooldown(platforms) {
    this.cooldown = [...platforms];
    this._updatePlatformAppearance();
  }

  /** Warn only during the decision window immediately before a spawn. */
  syncSourceMarkers(match) {
    const visible = !match.finished && SPAWN_TICKS.includes(match.tick + 1);
    for (const marker of this.sourceMarkers) marker.visible = visible;
  }

  _updatePlatformAppearance() {
    for (let p = 0; p < PLATFORMS; p++) {
      const locked = this.cooldown.includes(p);
      const returning = this._previewReturns?.get(p)?.preview;
      const selected =
        (this.preview?.platform === p && Math.abs(this.preview.angle) > 0.0001) ||
        (returning && Math.abs(returning.angle) > 0.0001);
      this.platformMaterials[p].emissive.setHex(
        locked ? COLOR.platformLock : selected ? COLOR.platformSelected : 0x000000,
      );
      this.platformMaterials[p].color.setHex(
        locked ? COLOR.platformLock : COLOR.platform,
      );
    }
  }

  /**
   * Animate a resolved tick: platforms turn, then balls slide. Rotation keeps
   * its snappy timing; travel gets the rest, so a ball's route is followable.
   */
  async playTick(event, matchBefore, matchAfter, resolveMs) {
    // Finish a drop at the deadline before adding the opponent's rotation.
    //
    // Re-checked in a loop, not sampled once: _finishDrag commits the move and
    // starts its 240 ms settle in the same breath, so a release right on the
    // deadline can begin settling after this await was set up. Waiting once let
    // that animation keep writing ball positions while the platforms turned.
    // The bound stops a stream of new drags from holding the tick open; anything
    // still running is finished outright below.
    for (let guard = 0; guard < 4; guard++) {
      const settling = [
        this._previewSnap?.promise,
        ...[...(this._previewReturns?.values() || [])].map(item => item.promise),
      ].filter(Boolean);
      if (!settling.length) break;
      await Promise.all(settling);
    }
    // Only one writer from here on: claim the board, then land any straggler on
    // its final state so the rotation starts from a defined angle.
    this._resolving = true;
    this._cancelAnimations();
    try {
      await this._playTickBody(event, matchBefore, matchAfter, resolveMs);
    } finally {
      // Never leave the flag set: it would mute every later preview animation.
      this._resolving = false;
    }
  }

  async _playTickBody(event, matchBefore, matchAfter, resolveMs) {
    const rotateMs = Math.min(330, resolveMs * 0.4);
    const moveMs = resolveMs - rotateMs;
    // Keep the local drag: animate only the rest, mainly the opponent's turn.
    const preview = this.preview;
    this.preview = null;
    this.drag = null;
    this._updatePlatformAppearance();

    // Markers describe the next phase; syncBalls rebuilds them from the result.
    for (const mesh of this.ballMeshes.values()) mesh.userData.arrow.visible = false;

    // New balls rise first, so it is clear they came from the marked cell.
    if (event.spawned.length) {
      // A previewed platform already sits at its angle: treat the new ball as
      // preview-carried so the resolve does not rotate it twice.
      if (preview) {
        for (const spawn of event.spawned) {
          if (platformOf(spawn.row, spawn.col) !== preview.platform) continue;
          const pos = cellPosition(spawn.row, spawn.col);
          preview.ballStarts.set(spawn.id, new THREE.Vector3(pos.x, 0.16, pos.z));
        }
      }
      await this.playSpawn(event.spawned, 420);
    }

    if (event.rotations.length) {
      // A platform carries its balls. Their meshes hang off the pivot, not the
      // platform group, so spin them by hand around the platform centre —
      // otherwise they stand still and then fly across the board.
      const carried = [];
      for (const { platform, quarters } of event.rotations) {
        const group = this.platformGroups[platform];
        const centre = group.position;
        const startAngle = group.rotation.y;
        const logicalTarget = quarters === 3 ? -Math.PI / 2 : quarters * Math.PI / 2;
        const normalizedTarget = -logicalTarget;
        const targetAngle = closestEquivalentAngle(normalizedTarget, startAngle);

        for (const [id, mesh] of this.ballMeshes) {
          const wasPreviewed =
            preview?.platform === platform && preview.ballStarts.has(id);
          const base = wasPreviewed
            ? preview.ballStarts.get(id).clone()
            : mesh.position.clone();
          // Balls standing on this platform before the resolved turn.
          if (!this._pointOnPlatform(base, centre)) continue;
          carried.push({
            mesh,
            centre,
            base,
            startAngle: wasPreviewed ? startAngle : 0,
            targetAngle,
          });
        }
        group.userData.resolvedRotation = { startAngle, targetAngle };
      }

      await this._animate(rotateMs, (t) => {
        const k = ease(t);
        for (const { platform } of event.rotations) {
          const group = this.platformGroups[platform];
          const { startAngle, targetAngle } = group.userData.resolvedRotation;
          group.rotation.y = startAngle + (targetAngle - startAngle) * k;
        }
        for (const { mesh, centre, base, startAngle, targetAngle } of carried) {
          const angle = startAngle + (targetAngle - startAngle) * k;
          this._rotatePointAround(base, centre, angle, mesh.position);
        }
      });

      for (const { platform } of event.rotations) {
        delete this.platformGroups[platform].userData.resolvedRotation;
      }
    }

    // Rotation is now part of the grid, so redraw and reset the visual angle.
    this.syncCells(matchAfter);

    const moving = event.moves.filter((m) => m.kind === "move");
    const bouncing = event.moves.filter((m) => m.kind === "bounce");
    const delivered = event.delivered;
    const bounceTurns = [];
    for (const bounce of bouncing) {
      const mesh = this.ballMeshes.get(bounce.id);
      const ball = matchAfter.balls.find(candidate => candidate.id === bounce.id);
      const arrow = mesh?.userData.arrow;
      if (!arrow || !ball) continue;
      const startAngle = arrow.rotation.y;
      const targetAngle = closestEquivalentAngle(-ball.exit * Math.PI / 2, startAngle);
      bounceTurns.push({ arrow, startAngle, targetAngle });
    }

    // A bounced ball rolls toward the cell it wanted and comes back, so the
    // reversal reads as hitting something rather than a silent flip.
    const lunges = this._bounceLunges(event, matchBefore);

    if (moving.length || delivered.length || bounceTurns.length || lunges.length) {
      const startPositions = new Map();
      for (const [id, mesh] of this.ballMeshes) {
        startPositions.set(id, mesh.position.clone());
      }

      const targets = new Map();
      for (const move of moving) {
        const to = cellPosition(move.to.row, move.to.col);
        targets.set(move.id, new THREE.Vector3(to.x, 0.16, to.z));
      }
      // A delivered ball rolls into its receiver and stays there.
      for (const d of delivered) {
        targets.set(d.id, this._collectSlot(d.side));
      }

      await this._animate(moveMs, (t) => {
        const k = ease(t);
        for (const [id, target] of targets) {
          const mesh = this.ballMeshes.get(id);
          const start = startPositions.get(id);
          if (mesh && start) {
            mesh.position.lerpVectors(start, target, k);
          }
        }
        for (const { arrow, startAngle, targetAngle } of bounceTurns) {
          // Turn during the second half only: the ball still points the way it
          // is travelling on the way out, and swings round as it comes back.
          const turn = ease(Math.max(0, t - 0.5) * 2);
          arrow.rotation.y = startAngle + (targetAngle - startAngle) * turn;
        }
        // Out and back within the same window: peaks at the midpoint, so the
        // ball reaches what stopped it, then retreats the way it came.
        const swing = Math.sin(t * Math.PI);
        for (const { mesh, toward, reach, base } of lunges) {
          const nudge = swing * reach;
          mesh.position.set(
            base.x + toward.x * nudge,
            base.y,
            base.z + toward.z * nudge,
          );
        }
      });

      // Land exactly back on the cell centre, whatever the easing did.
      for (const { mesh, base } of lunges) mesh.position.copy(base);
    }

    this.syncBalls(matchAfter, delivered);
    this.syncCells(matchAfter);
    this.syncSourceMarkers(matchAfter);
  }

  /** Raise new balls from below the board, scaling up, and flash the ring. */
  async playSpawn(spawned, duration) {
    const entries = [];

    for (const spawn of spawned) {
      const sourcePos = cellPosition(spawn.row, spawn.col);
      const marker = this.sourceMarkers.find(m =>
        m.userData.source?.row === spawn.row &&
        m.userData.source?.col === spawn.col
      );
      const pos = marker
        ? this.pivot.worldToLocal(marker.getWorldPosition(new THREE.Vector3()))
        : sourcePos;
      let mesh = this.ballMeshes.get(spawn.id);
      if (!mesh) mesh = this._createBall(spawn.id);

      mesh.position.set(pos.x, -0.25, pos.z);
      mesh.scale.setScalar(0.01);
      entries.push({ mesh, x: pos.x, z: pos.z });

      // Flash the matching source marker.
      if (marker) {
        marker.visible = true;
        this._flashSource(marker, duration);
      }
    }

    try {
      await this._animate(duration, (t) => {
        const k = ease(t);
        for (const { mesh, x, z } of entries) {
          mesh.position.set(x, -0.25 + k * 0.41, z);
          mesh.scale.setScalar(0.01 + k * 0.99);
        }
      });
    } finally {
      for (const marker of this.sourceMarkers) marker.visible = false;
    }
  }

  _flashSource(marker, duration) {
    const ring = marker.userData.ring;
    const start = performance.now();
    const step = () => {
      const t = (performance.now() - start) / duration;
      if (t >= 1) {
        ring.material.opacity = 0.5;
        ring.scale.setScalar(1);
        return;
      }
      ring.material.opacity = 0.5 + 0.5 * Math.sin(t * Math.PI);
      ring.scale.setScalar(1 + 0.35 * Math.sin(t * Math.PI));
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  /**
   * Run `step(0..1)` over `duration`. A hidden tab delivers no frames, so a
   * timer guarantees the final state and an always-settling promise.
   *
   * Every run registers in `this.animations` so it can be cancelled. Two
   * animations writing the same meshes is the bug this prevents: a drag settling
   * at the deadline used to keep moving balls while the resolve turned their
   * platform. `_cancelAnimations` finishes the stragglers before a tick starts.
   */
  _animate(duration, step) {
    return new Promise((resolve) => {
      const start = performance.now();
      let done = false;

      const finish = (applyFinalState = true) => {
        if (done) return;
        done = true;
        clearTimeout(guard);
        this.animations?.delete(running);
        // Land on the final state so a cancelled animation leaves a clean,
        // predictable position rather than whatever mid-frame value it held.
        if (applyFinalState) step(1);
        resolve();
      };

      const frame = (now) => {
        if (done) return;
        const t = Math.min(1, (now - start) / duration);
        step(t);
        if (t < 1) requestAnimationFrame(frame);
        else finish();
      };

      // Cancelling clears the guard too, or it would fire step(1) later and
      // move meshes after something else had taken over.
      const running = { finish };
      this.animations?.add(running);
      const guard = setTimeout(finish, duration + 120);
      requestAnimationFrame(frame);
    });
  }

  /**
   * Settle every animation still running, so only one writer touches the meshes.
   * Each lands on its final state, leaving a defined angle to continue from.
   */
  _cancelAnimations() {
    if (!this.animations) return;
    for (const running of [...this.animations]) running.finish(true);
    this.animations.clear();
  }

  start() {
    const loop = () => {
      this.renderer.render(this.scene, this.camera);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
}

function ease(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

function normalizeAngle(angle) {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}

function closestEquivalentAngle(angle, reference) {
  return reference + normalizeAngle(angle - reference);
}
