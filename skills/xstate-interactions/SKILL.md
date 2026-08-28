---
name: xstate-interactions
description: "XState v5 state machines and actor model for production apps, especially orchestrating Babylon.js 3D interactions in React. Use when working with XState, state machines, statecharts, actors, @xstate/react (useActor/useActorRef/useSelector), createMachine, setup(), assign, fromPromise, fromCallback, fromObservable, spawnChild, or when wiring XState to imperative APIs like Babylon observables. Covers v5-only patterns, React integration rules, and the Babylon-interaction actor pattern."
---

# XState v5 (generic usage)

> Scope: generic XState v5 + React + Babylon.js usage. When a repo's own conventions conflict, that repo's skill wins — RaywareNative (RWC 3.0) is `rwn-xstate-machines` (a single parallel-root machine with guards reading the store live via deps; some generic advice here does not apply there).
> Distribution note: this skill's `references/` directory must ship together with `SKILL.md`; the reference links at the end are unusable if `SKILL.md` is distributed alone.

## ⚠️ v5 only — never mix in v4 syntax

This project uses **XState v5**. AI training data is full of v4 examples — mixing them is the #1 reason code does not run. Rules:

- ❌ `interpret(machine).start()` → ✅ `createActor(machine).start()`
- ❌ `machine.withContext(...)` / `machine.withConfig(...)` → ✅ `setup({ ... }).createMachine({ ... })`
- ❌ `assign({ count: (context) => context.count + 1 })` → ✅ `assign({ count: ({ context }) => context.count + 1 })` (destructured object param)
- ❌ reading `state.context` / `state.matches` every frame → ✅ one-shot reads via `actor.getSnapshot()`; in React subscribe with `useSelector` (never poll per frame)
- ❌ `send` in machine options → ✅ actions receive `{ self, system }`; multi-action logic uses `enqueueActions`
- ❌ `services` → ✅ `actors`; `invoke: { src: promiseFn }` → ✅ `invoke: { src: fromPromise(...) }`

Always search for "XState v5". If an example contains `interpret`, it is v4 — discard it.

## v5 core cheat sheet

```typescript
import { setup, createActor, assign, fromPromise, fromCallback } from "xstate";

const machine = setup({
  types: {
    context: {} as { count: number },
    events: {} as { type: "INC" } | { type: "RESET" },
  },
  actions: {
    increment: assign({ count: ({ context }) => context.count + 1 }),
  },
}).createMachine({
  id: "counter",
  initial: "idle",
  context: { count: 0 },
  states: {
    idle: { on: { INC: { actions: "increment" }, RESET: { actions: assign({ count: 0 }) } } },
  },
});

const actor = createActor(machine).start();
actor.send({ type: "INC" });
const snapshot = actor.getSnapshot(); // read once — never poll per frame
```

Key facts that prevent common mistakes:

- `context` is immutable. The **only** way to modify it is `assign`. Writing `context.foo = x` inside an action is a silent no-op, not an error.
- Actors are the root of everything: `fromPromise` (async ops), `fromCallback` (event sources), `fromObservable` (RxJS), and machines themselves. Compose with `spawnChild` / `invoke`.
- Cleanup: `fromCallback` receives `({ sendBack, receive, input })` and **must** return an unsubscribe function; v5 calls it when the actor stops.

## React integration (@xstate/react) — hard rules

```typescript
import { useActorRef, useSelector } from "@xstate/react";

const actorRef = useActorRef(machine);                       // stable ref; state changes don't re-render
const count = useSelector(actorRef, (s) => s.context.count); // re-render only when the selected slice changes
```

1. **Never `actorRef.send(...)` during render** — send belongs only in event handlers and effects. Sending in render can loop forever under StrictMode/concurrent rendering.
2. **`useSelector` with the narrowest selector** — never subscribe to the whole snapshot. Babylon interaction machines transition at pointer-event frequency; whole-snapshot subscriptions re-render the app 60+ times per second.
3. By default one `useActorRef` per component instance. Share an actor across the component tree via context — do not create duplicates.
4. Side effects (DOM, Babylon, network) live only in machine actions / invoked actors — React components only render the snapshot and send events.

## Babylon.js interaction pattern (this project's core usage)

Architecture principle: **Babylon observers only send events; machine actions only apply state to the scene.** No business logic in observers; no Babylon API calls in guards or reducers.

### Wrap a Babylon event source with fromCallback

```typescript
import { fromCallback } from "xstate";
import type { Scene } from "@babylonjs/core/scene";
import { PointerEventTypes } from "@babylonjs/core/Events/pointerEvents";

// An actor that turns scene pointer events into machine events
const pointerSource = fromCallback(({ sendBack, input }: {
  sendBack: (e: any) => void;
  input: { scene: Scene };
}) => {
  const { scene } = input;
  const observer = scene.onPointerObservable.add((info) => {
    if (info.type === PointerEventTypes.POINTERDOWN) {
      sendBack({ type: "POINTER_DOWN", mesh: info.pickInfo?.pickedMesh?.name ?? null });
    }
  });
  // required: v5 calls this cleanup when the actor stops
  return () => scene.onPointerObservable.remove(observer);
});
```

### Spawn it from the interaction machine

```typescript
const cadInteractionMachine = setup({
  types: { /* context: hovered/selected mesh ids, drag origin, camera mode */ },
  actors: { pointerSource },
}).createMachine({
  id: "cadInteraction",
  initial: "idle",
  // illustrative: getScene is the app's own scene accessor, not an XState API
  invoke: { src: "pointerSource", input: ({ system }) => ({ scene: getScene(system) }) },
  states: {
    idle: {
      on: {
        POINTER_DOWN: [
          { guard: ({ event }) => event.mesh !== null, target: "dragging",
            actions: assign({ selected: ({ event }) => event.mesh }) },
          { target: "cameraOrbiting" }, // empty-space click → camera gesture
        ],
      },
    },
    dragging: {
      on: { POINTER_UP: "idle" /* action applies the transform via scene API */ },
    },
    cameraOrbiting: { on: { POINTER_UP: "idle" } },
  },
});
```

### Apply state back to the scene

Impure Babylon calls appear only in actions at state edges, never in guards:

```typescript
entry: ({ context }) => {
  const mesh = scene.getMeshByName(context.selected!);
  if (mesh) mesh.renderOutline = true;   // scene mutation is an action, not a guard
},
exit: ({ context }) => { /* clear the outline, dispose gizmos created in entry */ },
```

Gizmos, highlight layers, and helper meshes created in `entry` **must** be disposed in the matching `exit` — a machine that skips this leaks GPU resources on every transition.

## This project (generic Web CAD) conventions

- **One machine per interaction domain** (`cadInteraction`, `cameraControl`, `partPlacement`), composed under a root system actor — no single giant machine. (⚠️ RaywareNative exception: a single parallel-root machine — see `rwn-xstate-machines`.)
- **actor-per-entity**: every placed/dragged part gets a spawned child actor (`spawnChild`); the parent machine routes events by mesh id. `stopChild` destroys its Babylon resources along with it.
- Machine files export only the machine, never a started global actor — starting happens in React (`useActorRef`) or the root system.
- Event names are past-tense facts (`POINTER_DOWN`, `PART_PLACED`), not imperatives (`handleClick`).
- Guards stay pure (context + event only). Anything touching `scene`, DOM, or time belongs in an action or an invoked actor. (⚠️ RaywareNative exception: guards read the store live via deps — see `rwn-xstate-machines`.)

## Reference files

Detailed patterns by topic live in these files (ship together with the `references/` directory):

- **[testing.md](references/testing.md)** — unit/async testing of machines and actors: `createActor` + `getSnapshot` assertions, `waitFor`, `SimulatedClock` for `after`/delays, mocking invoked actors with `machine.provide`, testing `fromCallback`/Babylon observers. **Read when writing or fixing any machine test.**
- **[parallel-states.md](references/parallel-states.md)** — `type: "parallel"` regions, event broadcast, cross-region coordination via context mirrors and `raise`, `onDone` joining, and when to choose parallel states vs separate actors. **Read before modeling selection/drag/camera as parallel regions.** (⚠️ The context-mirror coordination does not apply to RaywareNative — RWN forbids mirrors, see `rwn-xstate-machines`.)
- **[actor-supervision.md](references/actor-supervision.md)** — v5 error handling (no Akka-style supervisor): `invoke` `onError` (`xstate.error.actor.*` events), bounded retries with exponential backoff, `stopChild` lifecycle and context-reference cleanup, rebuilding crashed actors in React, isolating Babylon observer actors. **Read when handling failures, retries, or child-actor crashes.**

## AI mistake checklist (verify item by item before finishing)

1. No `interpret`, no `.withConfig`, no v4 `assign((context) => ...)` function form.
2. Context never mutated directly; all changes go through `assign`.
3. No `send` during React render; only in observers/handlers/effects.
4. `useSelector` uses a narrow selector; no whole-snapshot subscription on high-frequency machines.
5. Every `fromCallback` returns a cleanup that removes its Babylon observer.
6. Babylon API calls appear only in actions / invoked actors; guards are pure (or read the store via deps per repo convention).
7. Resources created in `entry` are disposed in `exit`; spawned actors are stopped with `stopChild`.

For API details beyond this card, check the official docs: `https://stately.ai/docs/xstate` (always v5).
