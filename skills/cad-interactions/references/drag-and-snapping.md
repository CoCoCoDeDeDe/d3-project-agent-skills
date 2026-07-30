# Drag Planes and Snapping

Custom drag gestures (moving parts on the ground plane, sliding along a rail, extruding a face) should constrain movement to a construction plane — never to screen axes.

## Dragging on a Construction Plane

Screen-space dragging (`mesh.position.x += event.movementX * k`) breaks the moment the camera rotates. The correct approach: intersect the pointer ray with a mathematical plane.

```typescript
import { Plane } from "@babylonjs/core/Maths/math.plane";
import { Matrix } from "@babylonjs/core/Maths/math.vector";
import { PointerEventTypes } from "@babylonjs/core/Events/pointerEvents";

// Build the plane at drag start: through the picked point, with the
// constraint normal (ground plane: Vector3.Up(); face drag: the face normal)
const dragPlane = Plane.FromPositionAndNormal(hitPoint, planeNormal);

const observer = scene.onPointerObservable.add((info) => {
  if (info.type !== PointerEventTypes.POINTERMOVE) return;
  const ray = scene.createPickingRay(scene.pointerX, scene.pointerY, Matrix.Identity(), camera);
  const dist = ray.intersectsPlane(dragPlane);              // number | null
  if (dist === null) return;                                 // ray parallel to plane — skip this frame
  const point = ray.origin.add(ray.direction.scale(dist));   // world-space drag position
  // apply point (snapped, see below) to the dragged mesh's position
});
// on drag end: scene.onPointerObservable.remove(observer)
```

Notes:

- `ray.intersectsPlane` returns `null` when the ray runs parallel to the plane — keep the last valid point that frame instead of jumping to zero.
- Build the plane once at drag start from `hitPoint` (the initial pick), not every move frame. Rebuilding it from the mesh's current position makes the plane chase the mesh and the drag drifts.
- For axis-constrained drags (a rail), project the plane intersection point onto the axis line instead of using the raw point.

## Camera Yields During the Drag

Pair these exactly once per drag, or the camera either fights the drag or dies permanently:

```typescript
// drag start (POINTERDOWN on a draggable mesh, or gizmo onDragStartObservable):
camera.detachControl();
// drag end (POINTERUP anywhere, or gizmo onDragEndObservable) — ALWAYS, including cancelled drags:
camera.attachControl(canvas, true);
```

Put the re-attach in the same code path that removes the move observer. A drag cancelled by Esc still needs both the observer removed and the camera re-attached.

## Snapping: Snap the Committed Value

Snapping exists so the document ends up with clean numbers. Therefore quantization must hit the value that enters the undo command, not just a HUD label:

```typescript
const grid = 0.5; // from document/scene settings — never hardcode per-gesture
const snapped = Math.round(v / grid) * grid;
```

- **Grid snap**: quantize the world-space plane intersection before applying it to the mesh. Since the mesh position IS the committed value, snapping at apply time covers both display and commit.
- **Angle snap**: quantize rotation deltas to e.g. 15° in the same way.
- **Snap pitch comes from settings**, not from a constant buried in the drag handler — different documents/grid zoom levels want different pitches.
- Floating point: `Math.round` on binary floats gives values like `2.5000000000000004`. Round the committed value to a sane precision (e.g. 1e-6) before storing it in the command, or undo diffs fill with noise.

## POINTERMOVE Performance Rules

POINTERMOVE fires per frame (or faster). The handler runs on the rendering hot path:

- **Only update the display transform in the move handler.** Expensive work — snap computation against many candidates, validation, command construction — belongs in drag end.
- **Never allocate in the handler.** Pre-allocate scratch `Vector3`/`Matrix` objects at drag start and reuse them. `new Vector3()` per frame triggers GC pauses that show up as drag stutter.
- Skip work early: wrong `info.type`, no active drag, or `dist === null` — return before doing math.
- If the drag needs hit-testing against other meshes (snap-to-vertex), throttle that to every N frames or on drag end; `scene.pick` per frame on a dense scene will not hold 60 fps.

## Drag End Commits

The sequence at POINTERUP:

1. Compute the final snapped transform from the last valid plane point.
2. Apply it (or confirm it is already applied by incremental move updates).
3. Build the command with the captured start transform and push via `pushExecuted` (the scene already shows the end state — see undo-redo.md).
4. Remove the move observer, re-attach the camera, clear scratch state.

---

Back to [SKILL.md](../SKILL.md)
