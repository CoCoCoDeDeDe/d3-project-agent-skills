# Selection

Click-select, multi-select, and rubber-band (box) selection for CAD scenes.

## Selection State Model

Selection is a **set of mesh uniqueIds**, not mesh references:

```typescript
const selection = new Set<number>(); // mesh.uniqueId values
```

- Single click: `selection.clear(); selection.add(mesh.uniqueId)`.
- Ctrl/Cmd+click: toggle membership (`has ? delete : add`).
- Click on empty space: `selection.clear()` (unless a modifier is held).
- References die when a part is deleted or the document reloads; ids go stale silently instead of crashing, and stale ids are cheap to filter out when applying operations (`scene.getMeshByUniqueId(id)` returns null).
- Selection is document/UI state, **not** an undoable command — deleting a part is a command; the selection changes that follow are consequences. Keep selection out of the command stack.
- If XState orchestrates interactions, the same set of ids lives in machine context; React reads it with a narrow `useSelector` (see xstate-interactions).

## Highlighting: HighlightLayer vs. renderOutline

Two built-in ways to show selection:

**`mesh.renderOutline = true`** — zero extra render passes, trivially cheap. Limitations: single fixed style per mesh (`outlineColor`, `outlineWidth`), no glow, outline z-fights on thin geometry.

**`HighlightLayer`** — a post-process glow that reads as "selected" in every mainstream CAD tool, handles hundreds of selected meshes with one style:

```typescript
import { HighlightLayer } from "@babylonjs/core/Layers/highlightLayer";
import { Color3 } from "@babylonjs/core/Maths/math.color";

const hl = new HighlightLayer("selection-hl", scene);
hl.addMesh(mesh, Color3.Green());   // on select
hl.removeMesh(mesh);                // on deselect
// teardown: hl.dispose() — one layer for the whole selection, not per mesh
```

Rule of thumb: outline for hover feedback (cheap, transient), HighlightLayer for the committed selection set. One shared HighlightLayer; dispose it with the scene teardown, not per selection change.

## Box Select (Rubber Band)

Three phases:

**1. Drag start** — POINTERDOWN on empty space (nothing picked). Record `startX/startY` from `scene.pointerX/pointerY`. Show a DOM overlay div as the rubber band — absolutely positioned, `pointer-events: none`, updated on move. Do NOT use Babylon GUI or a scene mesh for the rectangle: a DOM div is free, pixel-perfect, and never intersects scene picking.

**2. Drag move** — update the div's `left/top/width/height` from start vs. current pointer. Nothing else; no scene work per frame.

**3. Drag end** — project each candidate mesh into screen space and test rectangle containment:

```typescript
import { Matrix, Vector3 } from "@babylonjs/core/Maths/math.vector";

const viewport = camera.viewport.toGlobal(engine.getRenderWidth(), engine.getRenderHeight());
const transform = scene.getTransformMatrix();

for (const mesh of candidateMeshes) { // pre-filtered, see below
  const center = mesh.getBoundingInfo().boundingBox.centerWorld;
  const screenPos = Vector3.Project(center, Matrix.Identity(), transform, viewport);
  if (screenPos.x >= rectX0 && screenPos.x <= rectX1 &&
      screenPos.y >= rectY0 && screenPos.y <= rectY1) {
    selection.add(mesh.uniqueId);
  }
}
```

Rules:

- **Never per-pixel testing** (readPixels, offscreen render-to-texture id buffers) for a first implementation — projection is O(meshes), readPixels stalls the GPU pipeline.
- **Pre-filter candidates**: skip meshes outside the camera frustum (`mesh.isInFrustum(frustumPlanes)`) and skip helper/gizmo meshes (they live on utility layers — keep a `isPickable = false` discipline on helpers so they never become candidates).
- Center-containment is the cheap standard. If parts are large relative to the rectangle, test all 8 bounding-box corners and include on any-hit instead.
- The result goes through the same channel as click-select: a Set of uniqueIds applied in one update, so highlighting and XState context change exactly once.

## Picking Discipline

- Use `scene.pick(scene.pointerX, scene.pointerY, predicate)` with a predicate that rejects ground planes, grids, and helper meshes — otherwise "clicked empty space" never registers because the ground eats the pick.
- Set `isPickable = false` on every helper/visualization mesh at creation time; audit this whenever a new helper type is introduced.

---

Back to [SKILL.md](../SKILL.md)
