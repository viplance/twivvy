# Rendering optimization — 18 October 2026

The original board submitted thousands of small model entities. Each tube used
20 separate rounded boxes for each collar and 36 for its two highlights. A round
also rebuilt every platform, and a full state refresh recreated all hamster rigs.

The optimized renderer:

- Sweeps each collar into one mesh and batches both highlights into one mesh.
  Hollow glass walls, open bores, colored couplings and animated faces remain.
- Culls glass back faces; inner/outer wall surfaces already have opposite winding.
- Shares rounded-box meshes and opaque PBR materials between model instances.
- Retains unchanged platforms by their four tube masks and reuses hamster rigs
  by game ID. Changed platforms are rebuilt after hamsters are detached.
- Removes invisible collision models because selection uses a ray/plane hit test.
- Pauses the renderer, disables its anchor and cancels its scene subscription when
  its SwiftUI host disappears.
  A retained menu model therefore does not keep a hidden laboratory rendering.
  Late offscreen layout callbacks cannot recreate a renderer or steal its anchor
  from the visible host. The same renderer/camera is retained across orientation
  changes and resumed when its scene is shown again.
- Observes countdown changes inside a separate SwiftUI view, so the 10 Hz clock
  does not repeatedly build the entire game UI and project accessibility frames.

## Comparison

Same iPhone 16 Pro Max / iOS 18.6 simulator, Debug configuration, same test scene
with twelve hamsters, two-second warm-up and four-second frame sampling:

| Measurement | Before | After |
|---|---:|---:|
| Model entities | 3,334 | 805 |
| Scene update callbacks / second | 38.7 | 60.0 |
| 95th percentile callback interval | 184.02 ms | 18.60 ms |
| Mean full state refresh, twelve resolved states | 951.00 ms | 24.31 ms |

The refresh measurement times `BoardScene.render` after each resolved state; it
is not the duration of the visible 1.1-second traversal animation. Callback
intervals measure renderer updates rather than GPU presentation timestamps.
Simulator timings depend on host load and do not establish real-device FPS.

`RenderingPerformanceTests.testBusyBoardRenderingBudget` repeats this workload,
prints `RENDER_BENCHMARK` timings and enforces fewer than 1,000 model entities for
the twelve-hamster board. Functional tests verify that unchanged platform/rig
identities survive a round, spawn portals do not duplicate, clearing a preview
cancels rotation, and hidden renderers remain paused until shown again. The UI
suite also samples actual board pixels after a round and orientation change, detecting a blank
render target even when its accessibility elements remain present.

Local comparison reports:

- `/tmp/hamsterlab-perf-before.xcresult`
- `/tmp/hamsterlab-perf-after.xcresult`

The table uses `/tmp/hamsterlab-perf-pause.xcresult` for its final after measurements.
The full suite passed in `/tmp/hamsterlab-perf-verified.xcresult`. The earlier
targeted after run also reached 60 updates/second and a 24 ms state refresh.
The final host-layout regression, menu and orientation UI checks are recorded in
`/tmp/hamsterlab-perf-pause.xcresult`. Its screenshots were visually checked
to confirm the board and hamsters remain visible after a round and rotation.
The final UI run with pixel assertions passed in
`/tmp/hamsterlab-perf-visible.xcresult`.
