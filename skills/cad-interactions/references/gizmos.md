# Gizmos

Babylon's built-in gizmos cover the standard CAD transform handles. This file is about using them without leaking resources or breaking undo.

## Creating and Attaching

```typescript
import { PositionGizmo } from "@babylonjs/core/Gizmos/positionGizmo";
import { RotationGizmo } from "@babylonjs/core/Gizmos/rotationGizmo";
import { ScaleGizmo } from "@babylonjs/core/Gizmos/scaleGizmo";
import { BoundingBoxGizmo } from "@babylonjs/core/Gizmos/boundingBoxGizmo";

const gizmo = new PositionGizmo(utilLayer); // shared UtilityLayerRenderer, see SKILL.md
gizmo.attachedMesh = mesh;   // attach
gizmo.attachedMesh = null;   // ALWAYS detach before attaching elsewhere or disposing
```

Rules that prevent the two most common gizmo bugs:

- **Detach before retarget.** Assigning `attachedMesh` from mesh A to mesh B directly mostly works, but any drag-in-progress state (cached start transforms) carries over. Set `null` first.
- **Detach before dispose.** `gizmo.dispose()` while still attached leaves observers firing against a dead target for one frame. `attachedMesh = null`, then dispose.
- One gizmo instance per active tool, re-targeted across selections — not one gizmo per mesh. Per-mesh gizmos multiply utility layers and observers.

## GizmoManager vs. Bare Gizmos

`GizmoManager` is the convenient route:

```typescript
import { GizmoManager } from "@babylonjs/core/Gizmos/gizmoManager";

const manager = new GizmoManager(scene);
manager.positionGizmoEnabled = true;
manager.attachToMesh(pickedMesh);
```

It auto-attaches on pointer down (disable with `manager.attachToMeshOnPointerDown = false` when you want explicit control) and toggles gizmo kinds by flag.

Choose **GizmoManager** when: you need standard move/rotate/scale with default behavior, prototyping, or internal tools.

Choose **bare gizmos** when (the usual CAD case): you need drag observables to build undo commands, per-axis constraints (e.g. extrude only along a face normal), custom snap behavior, or camera-yield logic on drag start/end. The manager's automation fights these customizations.

## Drag Observables Are the Command Hook Points

A gizmo drag mutates the mesh directly, frame by frame. Undo must therefore capture the **from** transform at drag start and the **to** transform at drag end:

```typescript
let dragStart: { position: Vector3; rotation: Vector3; scaling: Vector3 } | null = null;

positionGizmo.onDragStartObservable.add(() => {
  const m = positionGizmo.attachedMesh;
  if (!m) return;
  dragStart = { position: m.position.clone(), rotation: m.rotation.clone(), scaling: m.scaling.clone() };
  camera.detachControl(); // camera yields for the whole drag
});

positionGizmo.onDragEndObservable.add(() => {
  const m = positionGizmo.attachedMesh;
  if (m && dragStart) {
    // build a SetTransformCommand(mesh.uniqueId, dragStart, current) and
    // push it with pushExecuted — the scene is ALREADY at the end state.
    // See undo-redo.md for pushExecuted and merge.
  }
  dragStart = null;
  camera.attachControl(canvas, true);
});
```

Per-axis access: `positionGizmo.xGizmo`, `.yGizmo`, `.zGizmo` are the individual axis drag behaviors — constrain or restyle them individually (e.g. disable Y for floor-plan editing).

## Snapping on Gizmos

```typescript
positionGizmo.snapDistance = 0.5; // world units; drag output quantizes to multiples
```

`snapDistance` quantizes the gizmo's own drag output, so the value that lands on the mesh — and therefore in the undo command — is already snapped. For rotation and custom snaps not covered by the API, quantize in the drag-end handler before building the command (see drag-and-snapping.md). Never snap only the on-screen label while the mesh keeps the raw value.

## BoundingBoxGizmo Notes

`BoundingBoxGizmo` is the CAD-style "resize via corner/edge handles" option:

```typescript
const bbGizmo = new BoundingBoxGizmo(Color3.Gray(), utilLayer);
bbGizmo.attachedMesh = mesh;
bbGizmo.fixedDragMeshScreenSize = true; // handles stay constant size on screen regardless of zoom
```

Useful options: `fixedDragMeshScreenSize` (constant handle size), `rotationSphereSize` / `scaleBoxSize` (handle visibility by setting to 0), and `enableDragMesh` (drag the whole box). For parametric CAD, prefer driving scale changes back into the part's parameters (rebuild from parameters) rather than leaving a non-uniform `scaling` on the mesh.

## When You Need a Custom Gizmo

Built-ins cover translate/rotate/scale/bbox. Build a custom gizmo (subclass `Gizmo`, compose `AxisDragGizmo`/`PlaneDragGizmo`) only when the interaction itself is non-standard: extrude-along-normal handles, diameter handles on a cylinder, dimension-line dragging. If a constraint can be expressed by disabling axes or snapping, stay with built-ins.

---

Back to [SKILL.md](../SKILL.md)
