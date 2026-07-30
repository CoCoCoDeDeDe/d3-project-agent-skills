---
name: cad-interactions
description: "Web CAD 项目:Babylon.js CAD interaction primitives — gizmos, drag planes, snapping, selection, keyboard shortcuts, and undo/redo for React + Babylon.js 8 apps. Use when working with Gizmo, PositionGizmo/RotationGizmo/ScaleGizmo/BoundingBoxGizmo, GizmoManager, UtilityLayerRenderer, 拖拽 drag, drag plane, 吸附 snapping, snapDistance, 框选 box select, 多选 multi-select, HighlightLayer, 快捷键 keyboard shortcuts, undo/redo, 撤销重做, or 命令模式 command pattern. Covers the layering boundary with XState (observers only send events), gizmo attach/detach and dispose discipline, camera-yielding during drags, and command-stack undo with mesh-id-based commands."
---

# CAD Interactions (Babylon.js)

Interaction primitives for a Web CAD built on Babylon.js 8 + React (+ XState v5). This skill covers the **Babylon side** of interactions: gizmos, drag planes, snapping, selection, shortcuts, and undo/redo. For how to organize the state machines that consume these events, see the **xstate-interactions** skill — the two are designed to work together.

## Layering Boundary

Every interaction flows through four layers, in one direction:

```
pointer/keyboard observable  →  XState event  →  Command  →  scene mutation
   (Babylon, no logic)         (facts, past    (execute/    (the ONLY place
                                tense names)     undo)       meshes change)
```

- Babylon observers contain **no business logic** — they translate raw input into events (mesh ids, world positions, key combos).
- Commands are the **only** write path to the scene. A gizmo drag, a shortcut, and a box-select all end up constructing a `Command` — never call `mesh.position = ...` from an event handler directly.
- The XState layer in between routes and guards; it does not call Babylon APIs inside guards or reducers (see xstate-interactions for those rules).

If you find yourself writing `scene.getMeshByName(...)` inside a pointer observer, stop — that logic belongs in a command.

## Resource Discipline

Gizmos, highlight layers, and drag-helper meshes are GPU resources. Every one created must have a planned dispose, paired with the state or component that created it.

Gizmos render on their own `UtilityLayerRenderer` by default — creating several gizmos without sharing one silently allocates several utility layers (extra render passes). Share ONE:

```typescript
import { UtilityLayerRenderer } from "@babylonjs/core/Rendering/utilityLayerRenderer";
import { PositionGizmo } from "@babylonjs/core/Gizmos/positionGizmo";

const utilLayer = new UtilityLayerRenderer(scene); // share ONE across all gizmos
const positionGizmo = new PositionGizmo(utilLayer);
// pass utilLayer to every gizmo constructor; dispose it once on teardown
```

Attach/detach is equally strict: set `gizmo.attachedMesh = null` before attaching to another mesh and before dispose. A gizmo left attached to a disposed mesh throws on the next frame.

## CAD Interaction Conventions

Follow mainstream CAD input conventions so the app feels familiar:

- **Left button**: select / drag parts. **Middle or right button**: camera (orbit/pan). Never both on the same gesture.
- When a part drag begins, the camera must yield: `camera.detachControl()` on drag start, `camera.attachControl(canvas, true)` on drag end. Forgetting the re-attach strands the user with a dead camera; forgetting the detach lets the camera orbit mid-drag.
- Drag operations are constrained to a **construction plane** (ground plane, face plane), not the screen axes — see drag-and-snapping.md.
- Keep pointer-capture in mind: once a drag starts, POINTERMOVE/POINTERUP must keep flowing to the drag handler even when the pointer leaves the original mesh.

## Command Discipline

Undo/redo is not an add-on; it is the write path:

- Every scene mutation is a `Command { execute, undo }` pushed onto a single `CommandStack` (see undo-redo.md).
- Shortcuts and gizmos only **produce** commands — Ctrl+Z pops the stack, Delete builds a delete command.
- Commands reference meshes by `uniqueId` and re-resolve them with `scene.getMeshByUniqueId(id)`. Storing mesh references in the undo stack crashes after the mesh is disposed.
- Selection changes and camera moves are **not** commands — they never enter the stack.

## AI Mistake Checklist (verify before finishing)

1. Gizmo re-targeted without `attachedMesh = null` first, or disposed while still attached.
2. Camera not re-attached after drag end (dead camera), or not detached on drag start (camera orbits mid-drag).
3. Pointer/keyboard observers added but never removed — duplicate handlers after React StrictMode remount or scene rebuild.
4. Undo stack stores mesh references instead of `uniqueId` — crash or stale transforms after delete.
5. Snapping applied only to the displayed value while the committed (command) value stays unsnapped.
6. Each gizmo constructed without a shared `UtilityLayerRenderer` — N extra render passes.
7. Drag positions computed in screen axes instead of intersecting a construction plane.
8. Scene mutated directly in an observer/shortcut handler, bypassing the command stack (undo silently broken).

## Reference Files

Read these files for detailed patterns on specific topics:

- **[gizmos.md](references/gizmos.md)** - Creating, attaching, and disposing Position/Rotation/Scale/BoundingBox gizmos; GizmoManager vs. bare gizmos; drag observables as command hook points. **Read this when adding or debugging any gizmo.**
- **[drag-and-snapping.md](references/drag-and-snapping.md)** - Construction-plane dragging via ray-plane intersection, grid/angle snapping on committed values, camera yield pairing, and POINTERMOVE performance rules. **Read this when implementing any drag gesture.**
- **[selection.md](references/selection.md)** - Selection as a set of mesh uniqueIds, HighlightLayer vs. renderOutline, and box-select via screen-space projection. **Read this when implementing click-select, multi-select, or rubber-band selection.**
- **[shortcuts.md](references/shortcuts.md)** - `scene.onKeyboardObservable` wiring, focus traps, the modifier-key convention table, and shortcuts-as-commands. **Read this when adding keyboard shortcuts.**
- **[undo-redo.md](references/undo-redo.md)** - The `Command` interface and `CommandStack` implementation, id-based commands, gizmo-drag coalescing with `pushExecuted`/`merge`, and the XState history bridge. **Read this when implementing or fixing undo/redo.**
