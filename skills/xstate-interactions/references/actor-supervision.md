# Actor Error Handling & "Supervision" in XState v5

**v5 has no Akka-style built-in supervisor** — no restart strategies, no backoff supervisors, no error-kernel hierarchy. Error handling is explicit, composed from the mechanisms below. ❌ Don't write v4-era `error.platform.*` event guards or expect automatic restarts.

## 1. invoke onError: the primary error channel

When an invoked actor errors (a `fromPromise` rejects or throws), the parent takes the `onError` transition. The event is `{ type: "xstate.error.actor.<id>", error: <rejection reason> }` — the error data lives on `event.error` (v4's `event.data` / `error.platform.*` is gone).

```typescript
import { setup, fromPromise, assign } from "xstate";

const machine = setup({
  types: { context: {} as { part: unknown; error: unknown; url: string } },
  actors: {
    loadPart: fromPromise(async ({ input }: { input: { url: string } }) => {
      const res = await fetch(input.url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    }),
  },
}).createMachine({
  id: "partLoader",
  initial: "loading",
  context: { part: undefined, error: undefined, url: "/parts/1" },
  states: {
    loading: {
      invoke: {
        id: "loadPart",
        src: "loadPart",
        input: ({ context }) => ({ url: context.url }),
        onDone: { target: "ready", actions: assign({ part: ({ event }) => event.output }) },
        onError: { target: "failed", actions: assign({ error: ({ event }) => event.error }) }, // xstate.error.actor.loadPart
      },
    },
    ready: {},
    failed: { on: { RETRY: "loading" } },
  },
});
```

- If a state is exited before the promise settles, its result is **discarded** — no orphan effects.
- If `onError` is **missing**, the error throws out of the actor. The last-resort handler is a subscriber with an `error` callback:

```typescript
actor.subscribe({ error: (err) => reportToMonitoring(err) });
```

### fromCallback caveat

`onError` does **not** catch promise rejections inside a callback body (callbacks can't be `async`). Catch inside and report via `sendBack` as a normal event:

```typescript
const worker = fromCallback(({ sendBack }) => {
  doAsyncWork()
    .then((data) => sendBack({ type: "WORK_DONE", data }))
    .catch((error) => sendBack({ type: "WORK_FAILED", error }));
  return () => cancelWork();
});
```

## 2. Retry pattern: catch state + dynamic delay backoff

Model retry as states, not loops: `onError` → a waiting state → `after` re-invokes. Exponential backoff uses a **delay expression** over `context.attempts`:

```typescript
const machine = setup({
  types: { context: {} as { attempts: number; error: unknown } },
  actors: { loadPart: fromPromise(async () => { /* fetch */ }) },
  delays: {
    backoff: ({ context }) => Math.min(1000 * 2 ** context.attempts, 15_000),
  },
}).createMachine({
  id: "resilientLoader",
  initial: "loading",
  context: { attempts: 0, error: undefined },
  states: {
    loading: {
      invoke: {
        id: "loadPart",
        src: "loadPart",
        onDone: { target: "ready", actions: assign({ attempts: 0 }) },
        onError: [
          {
            target: "waitingToRetry",
            guard: ({ context }) => context.attempts < 3,
            actions: assign({
              attempts: ({ context }) => context.attempts + 1,
              error: ({ event }) => event.error,
            }),
          },
          { target: "failed", actions: assign({ error: ({ event }) => event.error }) },
        ],
      },
    },
    waitingToRetry: { after: { backoff: "loading" } }, // re-entering restarts the invoke
    ready: {},
    failed: {}, // retries exhausted — surface to the user
  },
});
```

Note: re-entering `loading` from a *different* state stops and restarts the invoked actor — that's what makes the retry happen. Cap attempts and always land in an explicit `failed` state; infinite retry loops hide real outages.

## 3. Spawned child lifecycle

Spawned actors (`spawnChild`, or `spawn` inside `assign`) have **no `onDone`/`onError` channel** — those exist only for `invoke`.

- **Stopping:** `stopChild("id")` or `stopChild(({ context }) => context.ref)`. Stopping does NOT remove the ref from context — always pair them:

```typescript
import { stopChild, assign } from "xstate";

on: {
  PART_DELETED: {
    actions: [
      stopChild(({ event }) => (event as any).partId),
      assign({ partRefs: ({ context, event }) => {
        const { [(event as any).partId]: _gone, ...rest } = context.partRefs;
        return rest; // remove the ref — stale refs in context leak actors
      } }),
    ],
  },
}
```

- **Parent awareness:** a spawned child reports completion by *sending an event* — pass the parent ref via `input` and use `sendTo` from the child (preferred over `sendParent`, which couples the child to being spawned). For guaranteed `onDone`/`onError` semantics, use `invoke`, not `spawnChild`.
- **System shutdown:** `actor.stop()` on the root stops the whole system — every child is stopped and every `fromCallback` cleanup runs. Children whose errors are *handled internally* (own `invoke` onError, or catch + `sendBack`) never propagate trouble upward.

## 4. Unrecoverable errors: report + rebuild

When a machine is corrupted beyond a `failed` state (bugs, irrecoverable scene desync):

1. Report via `actor.subscribe({ error })` or a `failed` state's entry action (telemetry, console).
2. `actor.stop()` the old actor.
3. Create a fresh actor. In React the simplest reliable rebuild is a **remount**: bump a React `key` on the component that calls `useActorRef(machine)` — the new mount creates a brand-new actor with clean context. Persist anything worth surviving *before* the crash (`actor.getPersistedSnapshot()` in a subscription), and pass it back as `snapshot` when recreating if resumable.
## 5. Babylon-specific rules

- **One observer actor crashing must not take down the interaction system.** Wrap observer bodies in try/catch and report via `sendBack({ type: "SOURCE_ERROR", error })`; let the parent decide (degrade to `idle`, respawn the source). Never let a Babylon exception escape a `fromCallback` synchronously.
- **Isolate per-entity.** Each placed part is its own spawned actor with its own gizmo/mesh cleanup in `fromCallback` returns and `exit` actions — a bad part actor is stopped with `stopChild` without touching selection or camera actors.
- Keep Babylon API calls out of error paths that run synchronously in guards/reducers; recovery actions (dispose gizmos, detach control) belong in `entry`/`exit` of the recovery state.

## Checklist

1. Every `invoke` of a failable actor has `onError` (or a deliberate `subscribe({ error })` fallback).
2. Error reads use `event.error` — no `error.platform.*`, no v4 `event.data`.
3. Retries are state machines: capped attempts, dynamic delay backoff, terminal `failed` state.
4. `stopChild` is always paired with removing the ref from context.
5. Spawned children report via `sendTo` to a parent ref from `input`; `onDone`/`onError` needs → use `invoke`.
6. Observer actors catch and `sendBack` errors; per-part actors are individually stoppable.
