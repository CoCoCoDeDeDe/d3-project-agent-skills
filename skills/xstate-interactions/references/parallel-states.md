# Parallel States in XState v5

A parallel state has multiple child states (**regions**) that are all active at the same time. Use `type: "parallel"` on any state node (or the machine root).

- Entering a parallel state enters **all** its regions; exiting it exits all of them.
- Every event received by the parallel state is **broadcast to all regions** — each region independently handles or ignores it.
- The state value is an **object** keyed by region: `{ track: "paused", volume: "muted" }`. Assert with `snapshot.matches({ track: "paused" })`.

## Syntax

```typescript
import { createMachine, createActor } from "xstate";

const playerMachine = createMachine({
  id: "player",
  type: "parallel",
  states: {
    track: {
      initial: "paused",
      states: { paused: { on: { PLAY: "playing" } }, playing: { on: { STOP: "paused" } } },
    },
    volume: {
      initial: "normal",
      states: { normal: { on: { MUTE: "muted" } }, muted: { on: { UNMUTE: "normal" } } },
    },
  },
});

const actor = createActor(playerMachine).start();
actor.send({ type: "MUTE" });
actor.getSnapshot().value; // { track: "paused", volume: "muted" }
```

## Coordinating regions

Regions must be independent — **never target a state in another region**. Coordinate through these channels instead:

1. **Broadcast events.** One event handled by several regions is the primary sync mechanism (see the CAD example: `POINTER_UP` ends both a drag and a camera orbit).
2. **Shared context + `assign`.** All regions share the machine's `context`. A region writes a fact (`assign({ isDragging: true })`), other regions read it in guards.
3. **`raise`.** A region raises an event back into the machine; other regions handle it on the next step. Raised events are processed (FIFO) before any external event.
4. **`onDone` on the parallel state.** When **every** region reaches a `type: "final"` state, the parallel state's own `onDone` transition fires — the built-in "all regions finished" join.

### The guard limitation — and the fix

Guards receive `{ context, event }` only. A guard **cannot read another region's current state value** — there is no `state.matches(...)` inside machine logic. ❌ Don't write guards that try to reach `interaction.value` or similar — it's not there.

✅ Mirror the fact into context at the state edge, then guard on context:

```typescript
// interaction region: dragging: { entry: assign({ isDragging: true }), exit: assign({ isDragging: false }) }
// camera region:
free: {
  on: {
    POINTER_DOWN_EMPTY: {
      target: "orbiting",
      guard: ({ context }) => !context.isDragging, // ✅ context, not region state
    },
  },
},
```

Keep mirrored context minimal — one boolean/flag per coordination need, not a copy of the whole state value.

## Parallel state vs. separate actors — decision rules

Ask: do these concerns **share one event stream and one context**, or **live separate lives**?

**Use a parallel state (one machine) when ALL hold:**

- Regions react to the same events (e.g., one pointer stream drives both selection and camera).
- Coordination is frequent and cheap (guards on shared context, broadcast events).
- Regions share lifecycle — they start and stop together.

**Use separate actors (`invoke` / `spawnChild`) when ANY hold:**

- Independent lifecycles or dynamic count (one actor per placed part).
- Failure isolation matters (a crashing child must not take siblings down — see `actor-supervision.md`).
- Different event sources or domains (network sync vs. pointer gestures).
- Communication is occasional — explicit `sendTo` beats implicit broadcast.

### Applied to this project's CAD interactions

- **Selection + camera in one parallel machine** — YES. Both consume the same pointer events, and "don't orbit while dragging" is a context guard. Classic parallel modeling.
- **Dragging** — usually a *state inside* the selection region, not its own region (it can't overlap `idle`).
- **Per-part actors** — separate spawned actors, always: dynamic count, independent disposal.
- **Autosave / sync** — separate actor: unrelated event source, needs failure isolation.

## Complete example: CAD selection + camera

```typescript
import { createMachine, createActor, assign } from "xstate";

const cadMachine = createMachine({
  id: "cad",
  type: "parallel",
  context: { selectedId: null as string | null, isDragging: false },
  states: {
    interaction: {
      initial: "idle",
      states: {
        idle: {
          on: {
            POINTER_DOWN_MESH: {
              target: "dragging",
              actions: assign({ selectedId: ({ event }) => (event as any).meshId }),
            },
          },
        },
        dragging: {
          entry: assign({ isDragging: true }),
          exit: assign({ isDragging: false }),
          on: { POINTER_UP: "idle" },
        },
      },
    },
    camera: {
      initial: "free",
      states: {
        free: {
          on: {
            POINTER_DOWN_EMPTY: { target: "orbiting", guard: ({ context }) => !context.isDragging }, // no orbit mid-drag
          },
        },
        orbiting: { on: { POINTER_UP: "free" } },
      },
    },
  },
});

const actor = createActor(cadMachine).start();
actor.getSnapshot().value; // { interaction: "idle", camera: "free" }

// Event broadcast: POINTER_UP is handled by BOTH regions if active
actor.send({ type: "POINTER_DOWN_MESH", meshId: "part-1" });
actor.getSnapshot().value; // { interaction: "dragging", camera: "free" }
actor.send({ type: "POINTER_UP" });
actor.getSnapshot().value; // { interaction: "idle", camera: "free" }
```

Note `selectedId` survives the drag (`context` outlives region states) — exit only clears the `isDragging` flag.

## Blocking events across regions (the swallow-edge trap)

A targetless "swallow" transition (`EVENT: {}`) only works **within one region**: a child's swallow shadows the parent's handler for that event. It does **not** stop other regions — broadcast means every region sees the event independently.

❌ The classic breakage: in a non-parallel machine, `dragging` swallows `SELECT_TOOL` to block tool-switching mid-drag. After splitting tools into a parallel `tool` region, that swallow is dead config — the tool region still receives `SELECT_TOOL` and acts on it.

✅ Cross-region blocking = mirror-bit guard on the **handling** region's transition, never a swallow in the other region:

```typescript
// tool region root: ordered guard chain, first match wins
SELECT_TOOL: [
  { guard: ({ context }) => context.isLoading },   // swallow: blocked during loading
  { guard: ({ context }) => context.isDragging },  // swallow: blocked mid-drag (replaces the old swallow edge)
  { target: "#machine.tool.closed", guard: "isCloseTool" },
  { target: "#machine.tool.orientation", guard: "canOpenOrientation" },
  // ...
],
```

### Register shared handlers once at the region root

A transition declared on a region (or any compound state) applies to **all** its child states via bubbling. Register `SELECT_TOOL` once on the tool region — never duplicate the same guarded chain on `closed` + 12 tool states. One place to edit, zero risk of forgetting one child.

### Mirror bits: two assigns, not N

To mirror "region is in any active state vs. the one inactive state", put `entry`/`exit` assigns on the **single inactive state only** — every path in/out crosses it:

```typescript
// tool region: 1 closed state + 12 tool states
closed: {
  entry: assign({ toolOpen: false }), // machine start + any tool → closed
  exit: assign({ toolOpen: true }),   // closed → any tool; tool→tool keeps it true
},
```

Not `entry: assign({ toolOpen: true })` on 12 tool states — 12 places to forget, silent desync when one is missed.

### Global shortcuts live at the machine root

Shortcuts that must work regardless of region state (undo/redo) go on the machine root's `on`, with mirror bits replicating any old swallow semantics:

```typescript
// root on: { KEY_DOWN: [{ guard: "undoShortcut", actions: "undo" }] }
// undoShortcut guard: ... && !context.isLoading && !context.isDragging
// (the dragging state's old KEY_DOWN swallow is replaced by the guard)
```

## Checklist

1. `type: "parallel"` on the parent; regions never transition into each other.
2. State value is an object — asserts and `useSelector` handle `{ region: state }` shape.
3. Cross-region reads go through context mirrors written in `entry`/`exit`, never attempts to read region state from guards.
4. Cross-region *blocking* also goes through mirror-bit guards on the handling region's chain — swallow edges (`EVENT: {}`) only shadow handlers within their own region, never stop a broadcast to sibling regions.
5. Shared handlers registered once at the region root (bubbling covers all children), never duplicated per child state.
6. Mirror an "active vs. inactive" region fact with `entry`/`exit` on the single inactive state, not `entry` on every active state.
7. `onDone` used (not manual event counting) when all regions must reach final states.
8. Concerns with independent lifecycles or failure domains are separate actors, not regions.
