---
name: rwn-xstate-machines
description: "RaywareNative (RWC 3.0) XState machine conventions: parallel-machine shadowing, live-read guards (no mirrors), event mounting levels and swallow interception, and the design questions to ask before changing a machine. Use when editing or reviewing interactionSystem.machine.ts or other XState machines in the RaywareNative repo — adding states/transitions/events/guards, wiring deps, or reviewing machine diffs. NOT for generic XState usage (xstate-interactions) or the Sketch paste/regeneration workflow (xstate-studio-sync-workflow)."
---

# RaywareNative XState Machine Conventions

> Applies only to RaywareNative (RWC 3.0). Generic XState usage lives in `xstate-interactions`; the Stately Sketch paste/visualization workflow (Sketch script-mode constraints, the paste-version generator, naming-as-interface) lives in `xstate-studio-sync-workflow`.

## Parallel-machine shadowing (the most common trap)

RWN's interaction machine root is `type: 'parallel'`. When a region handles an event, the root's own `on` handler does NOT run — it is a mutually exclusive fallback, not "both run".

Consequence: a root-level broadcast cleanup like `LOADING_STARTED: { actions: [cleanup...] }` is shadowed by any same-name transition inside a region. Real bug hit: hover/preselect cleanup was swallowed while the orientation substate was open, leaving the highlight stale for the whole loading phase.

Rules:

- When adding a broadcast-event transition (LOADING_STARTED etc.) to any region, check whether the root-level handler's actions must be repeated on that child transition.
- When reviewing a machine diff, ask of every new substate event transition: "what does it shadow at the root?"
- Regression test: assert the cleanup via `snapshot.context` (precedent: "loading started inside an orientation mode still clears hover and preselect state" in `tests/unit/editToolRegistry.test.ts`).

## Guards read live state, no mirrors

- External state (loading, dragging) is read live in guards (`deps.isLoading()` reads the zustand store) — never mirrored in machine context; a mirror adds reconciliation burden and a stale window.
- Events exist only as edge notifications (LOADING_STARTED for cleanup); the state itself always comes from the store.

## Event mounting levels and swallow interception

- Same-family events (e.g. SELECT_TOOL open/close/switch) mount on the **parent state** once, never duplicated in every substate — entry/exit/interception rules live in one place and new substates need no changes. XState deep matching wins; a substate needing special handling adds one overriding transition inside itself.
- "Forbid X in this state" uses an explicit **swallow branch** (a leading targetless `{ guard: ... }` transition): the event is consumed, the state stays. Do NOT rely on omitting the transition — an implicit ignore is invisible in the diagram and neither review nor Sketch verification can catch it.

## Three design questions before touching a machine

- Does the SAME event need different responses here? → split a state (a state = mutually exclusive behavior modes).
- Is it the same transition, just "allowed right now or not"? → add a guard (read live conditions, not a behavior mode).
- Is it just more data? → put it in context or the external store; do not create a state for it.

## Naming is the interface

- deps guard/action/event names are the interface between the machine file and the implementation layer — both sides stay in sync, including branch order.
- Machine-file Sketch compatibility (runtime imports only from `xstate`, no `enum`, non-xstate references via deps/type-only imports) and regenerating the paste version after structural changes: see `xstate-studio-sync-workflow`.
- **Every deps member needs a consumer**: declare only what the machine's actions/guards (or an
  injected channel the machine names) actually use. A dead member (declared, never invoked) costs
  every test mock forever and misleads the event-flow reading — delete it (edit-supports
  `updateHover` precedent: hover went through the adapter hooks directly, same as orient-base).

## Test conventions

- Machine tests assert with `snapshot.matches(partialValue)` subset matching — one case asserts only the dimension it names (full state-value `toEqual` on parallel machines is forbidden; see `rwn-development` Tests).
- Inert deps are provided in full: when a deps member is added, test mocks must be updated in the same change — `tests/unit/editToolRegistry.test.ts` is the host.
