# Testing XState v5 Machines

Examples use **vitest** (identical API in Jest). Follow Arrange / Act / Assert: create the actor, send events, assert the snapshot.

## Unit testing a machine

The core loop is `createActor` + `send` + `getSnapshot()`. Never test through React — machines are plain logic.

```typescript
import { setup, createActor, assign } from "xstate";
import { test, expect } from "vitest";

const machine = setup({
  types: {
    context: {} as { selected: string | null },
    events: {} as { type: "SELECT"; mesh: string } | { type: "CLEAR" },
  },
}).createMachine({
  initial: "empty",
  context: { selected: null },
  states: {
    empty: { on: { SELECT: { target: "hasSelection", actions: assign({ selected: ({ event }) => event.mesh }) } } },
    hasSelection: { on: { CLEAR: { target: "empty", actions: assign({ selected: null }) } } },
  },
});

test("selection transitions and context", () => {
  const actor = createActor(machine).start(); // Arrange
  expect(actor.getSnapshot().value).toBe("empty");
  actor.send({ type: "SELECT", mesh: "part-1" }); // Act
  expect(actor.getSnapshot().matches("hasSelection")).toBe(true); // Assert
  expect(actor.getSnapshot().context.selected).toBe("part-1");
  actor.send({ type: "CLEAR" });
  expect(actor.getSnapshot().value).toBe("empty");
});
```

- Prefer `snapshot.value` / `snapshot.context` equality for most asserts; use `.matches(...)` when only the state matters. For parallel machines, `.matches({ region: "state" })` takes an object state value.
- ❌ Don't assert intermediate states reached and left by `always` (eventless) transitions in the same step — they are **not observable** in the snapshot. Use `after: { 0: ... }` instead of `always` if a test must see the state.

## Async actors: waitFor

For invoked promises, callbacks, or anything that settles asynchronously, don't `setTimeout`-and-pray — use `waitFor(actor, predicate, options?)`. It resolves with the first snapshot satisfying the predicate (immediately if the current one already does) and rejects on error or `timeout`.

```typescript
import { waitFor } from "xstate";
const snapshot = await waitFor(actor, (s) => s.value === "ready", { timeout: 10_000 });
expect(snapshot.context.user).toBeDefined();
```

## Timers: SimulatedClock

Machines with `after` / delayed `raise` / `sendTo(..., { delay })` need a controllable clock, not real waits. Inject a `SimulatedClock` via `createActor` options (it also covers invoked child machines) and advance it manually:

```typescript
import { createActor, createMachine, SimulatedClock } from "xstate";

const machine = createMachine({
  initial: "waiting",
  states: { waiting: { after: { 5000: "timedOut" } }, timedOut: {} },
});

test("times out after 5s", () => {
  const clock = new SimulatedClock();
  const actor = createActor(machine, { clock }).start();
  expect(actor.getSnapshot().value).toBe("waiting");
  clock.increment(5000); // or clock.set(5000); never travels backwards
  expect(actor.getSnapshot().value).toBe("timedOut");
});
```

## Mocking invoked actors

Declare real actor logic in `setup({ actors })` and reference it by string `src`; in tests, override with `machine.provide({ actors })`. This keeps the machine file production-only.

```typescript
import { setup, createActor, fromPromise } from "xstate";
import { test, expect, vi } from "vitest";

const machine = setup({
  actors: {
    loadPart: fromPromise(async ({ input }: { input: { url: string } }) =>
      fetch(input.url).then((r) => r.json())), // real impl
  },
}).createMachine({
  initial: "loading",
  states: {
    loading: { invoke: { src: "loadPart", input: { url: "/parts/1" }, onDone: "ready", onError: "failed" } }, // string src — overridable
    ready: {},
    failed: {},
  },
});

test("failure path", async () => {
  const mockLoad = vi.fn().mockRejectedValue(new Error("network"));
  const actor = createActor(machine.provide({ actors: { loadPart: fromPromise(mockLoad) } })).start();
  const snapshot = await waitFor(actor, (s) => s.matches("failed"));
  expect(mockLoad).toHaveBeenCalledOnce();
  expect(snapshot.value).toBe("failed");
});
```

## Testing fromCallback actors (Babylon observer scenario)

Test the callback actor through its **parent machine**: fake the Babylon observable, capture the registered handler, fire it, assert the parent transitioned. Also assert the cleanup ran when the actor stops — a missing `remove(observer)` is a GPU/CPU leak.

```typescript
import { setup, createActor, fromCallback } from "xstate";
import { test, expect, vi } from "vitest";

// Production logic: turns scene pointer events into machine events
const pointerSource = fromCallback(({ sendBack, input }: { sendBack: (e: any) => void; input: { scene: any } }) => {
  const observer = input.scene.onPointerObservable.add((info: any) => {
    if (info.type === "POINTERDOWN") sendBack({ type: "POINTER_DOWN", mesh: info.mesh ?? null });
  });
  return () => input.scene.onPointerObservable.remove(observer); // REQUIRED cleanup
});

const machine = setup({ actors: { pointerSource } }).createMachine({
  context: ({ input }: { input: { scene: any } }) => ({ scene: input.scene }),
  initial: "idle",
  invoke: { src: "pointerSource", input: ({ context }) => ({ scene: context.scene }) }, // root invoke: whole lifetime
  states: { idle: { on: { POINTER_DOWN: "dragging" } }, dragging: {} },
});

test("observer events reach the machine; cleanup on stop", () => {
  let handler: ((info: any) => void) | undefined;
  const fakeScene = { onPointerObservable: {
    add: vi.fn((h) => ((handler = h), "observer-token")),
    remove: vi.fn(),
  } };
  const actor = createActor(machine, { input: { scene: fakeScene } } as any).start();
  handler!({ type: "POINTERDOWN", mesh: "part-1" }); // simulate Babylon firing
  expect(actor.getSnapshot().value).toBe("dragging");
  actor.stop();
  expect(fakeScene.onPointerObservable.remove).toHaveBeenCalledWith("observer-token");
});
```

## Model-based testing (optional)

The `@xstate/test` package is deprecated; model-based testing utilities now live in `xstate/graph` (auto-generating paths through a machine). Reach for it only when hand-written tests can't cover the path space — fetch `https://stately.ai/docs/testing` before using it, and keep the rest of the suite on the patterns above.

## Checklist

1. No `interpret(...)` anywhere in tests — always `createActor(machine).start()`.
2. Async assertions via `waitFor`, not `setTimeout` sleeps.
3. `after`/delay tests use `SimulatedClock`, never real time.
4. Invoked actors mocked via `setup` string `src` + `machine.provide`, not by editing the machine file.
5. Every `fromCallback` test asserts cleanup ran after `actor.stop()`.
