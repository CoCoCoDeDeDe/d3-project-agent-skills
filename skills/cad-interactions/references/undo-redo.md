# Undo/Redo: Command Pattern + XState Bridge

Undo/redo in this architecture is not a layer bolted on afterwards — the `CommandStack` is the single write path to the scene. Every mutation (gizmo drag, shortcut, menu action) goes through it.

## The Command Interface and Stack

```typescript
interface Command {
  readonly label: string;
  execute(): void;
  undo(): void;
  /** Return true to absorb the previous command (e.g. continuous drag). */
  merge?(previous: Command): boolean;
}

class CommandStack {
  private past: Command[] = [];
  private future: Command[] = [];

  /** Push a command that has NOT run yet — executes it. */
  push(cmd: Command): void {
    const top = this.past[this.past.length - 1];
    if (top?.merge && cmd.merge?.(top)) { cmd.execute(); return; } // absorbed
    cmd.execute();
    this.past.push(cmd);
    this.future.length = 0; // new branch: redo history dies
  }

  /** Push a command whose effect is ALREADY applied (e.g. by a gizmo drag). */
  pushExecuted(cmd: Command): void {
    const top = this.past[this.past.length - 1];
    if (top?.merge && cmd.merge?.(top)) return;
    this.past.push(cmd);
    this.future.length = 0;
  }

  undo(): void { const c = this.past.pop(); if (!c) return; c.undo(); this.future.push(c); }
  redo(): void { const c = this.future.pop(); if (!c) return; c.execute(); this.past.push(c); }
  get canUndo(): boolean { return this.past.length > 0; }
  get canRedo(): boolean { return this.future.length > 0; }
}
```

Design points, in order of how often they are gotten wrong:

- **Two stacks, not one list with a cursor.** `past`/`future` makes the "new command kills redo history" rule one line (`future.length = 0`). Cursor-based lists get this wrong under merge.
- **`push` executes; `pushExecuted` does not.** Pick the wrong one and the command either runs twice (push after a gizmo already moved the mesh — visible as a double-offset) or never runs (pushExecuted for a button click — the button appears dead).
- **`merge` absorbs consecutive commands.** The absorbing command updates its own `to` state from `previous` and the stack stays one entry shorter. Without it, one 3-second gizmo drag produces hundreds of undo steps.

## Commands Store Ids, Not References

```typescript
class SetPositionCommand implements Command {
  readonly label = "Move part";
  constructor(
    private readonly scene: Scene,
    private readonly meshId: number,     // mesh.uniqueId — NOT the mesh
    private readonly from: Vector3,
    private readonly to: Vector3,
  ) {}

  execute(): void {
    const mesh = this.scene.getMeshByUniqueId(this.meshId);
    if (mesh) mesh.position.copyFrom(this.to);   // mesh may be gone — skip silently
  }

  undo(): void {
    const mesh = this.scene.getMeshByUniqueId(this.meshId);
    if (mesh) mesh.position.copyFrom(this.from);
  }
}
```

A stored mesh reference crashes or corrupts state after the part is deleted and the user undoes the deletion (the undo of "delete" recreates the mesh as a NEW instance — the old reference points at a disposed object). Ids re-resolve against the current scene every time. The null check is mandatory: history can reference parts that no longer exist (deleted, document reloaded), and skipping is the correct behavior.

The same rule applies to the values: store plain data (cloned `Vector3`s, numbers, ids), never live objects.

## Gizmo Integration: pushExecuted + merge

A gizmo drag mutates the mesh continuously while it runs. The undo entry is therefore created **after** the fact, from the transforms captured at the edges (see gizmos.md for the observer wiring):

```typescript
// onDragStartObservable: capture `from` (position/rotation/scaling clones)
// onDragEndObservable:
const cmd = new SetPositionCommand(scene, mesh.uniqueId, fromTransform, toTransform);
commandStack.pushExecuted(cmd); // scene is ALREADY at `to` — do not re-execute
```

Using `push` here is the classic double-execution bug: the mesh teleports `to + (to - from)`.

For continuous micro-drags (a slider-style interaction that fires many drag-ends), implement `merge` so consecutive commands on the same mesh collapse into one undo step:

```typescript
merge(previous: Command): boolean {
  if (!(previous instanceof SetPositionCommand)) return false;
  if (previous.meshId !== this.meshId) return false;
  previous.to = this.to; // absorb: keep original `from`, take newest `to`
  return true;
}
```

(`to` must be writable for this — drop `readonly` on that field when merging is needed, and re-apply in the stack: the absorbed command's execute keeps the newest value. Note the `push` path above calls `cmd.execute()` after absorbing so the new `to` still lands.)

## XState Bridge: Events Are Commands

When XState orchestrates the interaction layer, the mapping is direct — machine events carry the data commands need:

```typescript
// Event:    { type: "MOVE_PART", id: 42, to: { x: 1, y: 0, z: 2 } }
// Action:   construct SetPositionCommand(scene, event.id, currentPos, event.to)
//           and commandStack.push(cmd) — the action is the ONLY place the
//           command stack is touched from the machine.
```

A minimal history actor sketch:

```typescript
const historyActor = fromCallback(({ sendBack, receive, input }) => {
  const stack: CommandStack = input.stack;
  receive((event) => {
    if (event.type === "UNDO" && stack.canUndo) stack.undo();
    if (event.type === "REDO" && stack.canRedo) stack.redo();
    if (event.type === "COMMAND") stack.push(event.command);
    sendBack({ type: "HISTORY_CHANGED", canUndo: stack.canUndo, canRedo: stack.canRedo });
  });
  return () => {}; // stack is owned by the app, not disposed here
});
```

Toolbar undo/redo buttons subscribe to `HISTORY_CHANGED` for their enabled state; the keyboard shortcut (see shortcuts.md) sends `UNDO`/`REDO` to this actor instead of touching the stack directly. For the machine organization rules around this (one machine per domain, actors stopped with `stopChild`), see the **xstate-interactions** skill — it owns that topic.

## Boundaries: What Does NOT Go in the Stack

- **Camera moves.** Users never expect Ctrl+Z to un-orbit the camera.
- **Selection changes.** Selection is a consequence and a UI concern, not a document mutation (see selection.md).
- **Hover/highlight state.** Purely transient.
- **View/layout settings** (grid pitch, snap on/off). These are preferences, not document edits.

## Capacity and Memory Discipline

Commands hold cloned transforms and id lists — small, but unbounded growth is still a leak in a long CAD session:

- Cap the stack (e.g. 100 entries): on push beyond the cap, drop the oldest entry from the bottom of `past`.
- A command that captures large data (a full document snapshot for "delete all") invalidates the cap's memory assumption — prefer delta commands (store the deleted parts' parameters, not the scene) over snapshots.
- `future.length = 0` on every new push also releases the redo branch's memory — do not "keep it just in case."

---

Back to [SKILL.md](../SKILL.md)
