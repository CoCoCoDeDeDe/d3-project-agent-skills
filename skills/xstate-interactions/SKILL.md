---
name: xstate-interactions
description: "XState v5 state machines and actor model for production apps, especially orchestrating Babylon.js 3D interactions in React. Use when working with XState, state machines, statecharts, actors, @xstate/react (useActor/useActorRef/useSelector), createMachine, setup(), assign, fromPromise, fromCallback, fromObservable, spawnChild, or when wiring XState to imperative APIs like Babylon observables. Covers v5-only patterns, React integration rules, and the Babylon-interaction actor pattern."
---

# XState v5

## ⚠️ v5 ONLY — Never Mix v4 Syntax

This project uses **XState v5**. AI training data is flooded with v4 examples — mixing them is the #1 source of broken code. Rules:

- ❌ `interpret(machine).start()` → ✅ `createActor(machine).start()`
- ❌ `machine.withContext(...)` / `machine.withConfig(...)` → ✅ `setup({ ... }).createMachine({ ... })`
- ❌ `assign({ count: (context) => context.count + 1 })` → ✅ `assign({ count: ({ context }) => context.count + 1 })` (destructured object arg)
- ❌ `state.context` / `state.matches` on every frame → ✅ `actor.getSnapshot()`, and in React `useSelector`
- ❌ `send` in machine options → ✅ actions receive `{ self, system }`; use `enqueueActions` for multi-action logic
- ❌ `services` → ✅ `actors`; `invoke: { src: promiseFn }` → ✅ `invoke: { src: fromPromise(...) }`

When searching docs, always search "XState v5". If an example shows `interpret`, it is v4 — discard it.

## Core v5 Quick Reference

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
const snapshot = actor.getSnapshot(); // read once — do NOT poll every frame
```

Key facts that prevent common mistakes:

- `context` is immutable. The ONLY way to change it is `assign`. Mutating `context.foo = x` inside an action silently does nothing useful.
- Actors are the unit of everything: `fromPromise` (async ops), `fromCallback` (event sources), `fromObservable` (RxJS), machines themselves. Compose with `spawnChild` / `invoke`.
- Cleanup: `fromCallback` receives `({ sendBack, receive, input })` and must return an unsubscribe function; v5 calls it when the actor stops.

## React Integration (@xstate/react) — Hard Rules

```typescript
import { useActorRef, useSelector } from "@xstate/react";

const actorRef = useActorRef(machine);                 // stable ref, no re-render on transitions
const count = useSelector(actorRef, (s) => s.context.count); // re-renders ONLY when selected slice changes
```

1. **Never `actorRef.send(...)` during render** — sends belong in event handlers and effects. A send in render can loop forever under StrictMode/concurrent rendering.
2. **`useSelector` with the narrowest selector**, never subscribe to the whole snapshot — Babylon interaction machines transition at pointer-event frequency; whole-snapshot subscriptions re-render the app 60+ times/sec.
3. One `useActorRef` per component instance is the default. Share an actor across the tree via context, not by recreating it.
4. Side effects (DOM, Babylon, network) live in machine actions/invoked actors — React components only render snapshots and send events.

## Babylon.js Interaction Pattern (this project's core use case)

The architecture: **Babylon observers only SEND events; machine actions only APPLY state to the scene.** No business logic in observers, no Babylon API calls inside guards or reducers.

### Wrap Babylon event sources with fromCallback

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
  // REQUIRED: v5 calls this cleanup when the actor stops
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
  invoke: { src: "pointerSource", input: ({ system }) => ({ scene: getScene(system) }) },
  states: {
    idle: {
      on: {
        POINTER_DOWN: [
          { guard: ({ event }) => event.mesh !== null, target: "dragging",
            actions: assign({ selected: ({ event }) => event.mesh }) },
          { target: "cameraOrbiting" }, // empty space → camera gesture
        ],
      },
    },
    dragging: {
      on: { POINTER_UP: "idle" /* actions apply transform via scene API */ },
    },
    cameraOrbiting: { on: { POINTER_UP: "idle" } },
  },
});
```

### Applying state back to the scene

Impure Babylon calls happen in **actions at state edges**, never in guards:

```typescript
entry: ({ context }) => {
  const mesh = scene.getMeshByName(context.selected!);
  if (mesh) mesh.renderOutline = true;   // scene mutation is an action, not a guard
},
exit: ({ context }) => { /* clear outline, dispose gizmos created in entry */ },
```

Gizmos, highlight layers, and utility meshes created in `entry` MUST be disposed in the corresponding `exit` — machines that don't do this leak GPU resources on every transition.

## Conventions for This Project

- **One machine per interaction domain** (`cadInteraction`, `cameraControl`, `partPlacement`), composed under a root system actor — not one mega-machine.
- **Actor-per-entity**: each placed/dragged part gets a spawned child actor (`spawnChild`); the parent routes events by mesh id. `stopChild` disposes it together with its Babylon resources.
- Machine files export the machine, never a started global actor — starting happens in React (`useActorRef`) or the root system.
- Event names are past-tense facts (`POINTER_DOWN`, `PART_PLACED`), not commands (`handleClick`).
- Guards are pure (context + event only). Any function touching `scene`, DOM, or time is an action or an invoked actor.

## AI Mistake Checklist (verify before finishing)

1. No `interpret`, no `.withConfig`, no v4 `assign((context) => ...)` function form.
2. Context never mutated directly; all changes via `assign`.
3. No `send` during React render; observers/handlers/effects only.
4. `useSelector` used with narrow selectors; no whole-snapshot subscriptions in high-frequency machines.
5. Every `fromCallback` returns a cleanup that removes its Babylon observer.
6. Babylon API calls appear only in actions/invoked actors; guards are pure.
7. Resources created in `entry` are disposed in `exit`; spawned actors stopped with `stopChild`.

For full API details beyond this card, fetch the official docs: `https://stately.ai/docs/xstate` (always v5).
