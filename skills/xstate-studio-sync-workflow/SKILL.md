---
name: xstate-studio-sync-workflow
description: "RaywareNative (RWC 3.0): keeping the interaction machine and its Stately Sketch visualization in sync — Sketch script-mode constraints (no import/export, no TS enum), the paste-version generator (npm run sketch:interaction-machine), naming-as-interface, and the consistency checklist. Use when the user pastes machine code into Stately Sketch, asks to visualize/check the state-machine diagram, reports Sketch syntax errors (Cannot use import/export statement, enum parse failure), regenerates the paste version, adds or renames states/guards/actions/events, or asks whether the machine and its Sketch diagram are in sync. Also covers legacy Studio export files (tmp-xstate.ts style) if they resurface. NOT for generic XState usage (xstate-interactions) or other machine rules (rwn-xstate-machines)."
---

# XState Implementation ↔ Stately Sketch Sync Workflow

## Core principle (current workflow, post-Studio era)

**The implementation machine file (e.g. `interactionSystem.machine.ts`) is the single source of truth — the AI/user edits it directly.** Stately Sketch is only a read-only visualization/review surface: the user pastes the **generated** paste version into Sketch to inspect the diagram. There is no export-file layer and no reverse channel — to change structure, edit the implementation, regenerate, re-paste.

Legacy note: if an old Studio export file (e.g. `tmp-xstate.ts`) resurfaces, treat it as a read-only snapshot and migrate its structure into the implementation file — never revive the export workflow.

## Sketch hard constraints (why the source conventions exist)

Sketch evaluates pasted code as a plain script, so two syntax families never reach it:

1. **No `import` / `export` statements at all** — including xstate imports and `import type`. Sketch throws `SyntaxError: Cannot use import statement outside a module` on the very first import.
2. **No TS `enum`** — Sketch's parser rejects it. Use a const object + `as const` + same-name type:
   `export const ToolId = { Orientation: 'orientation', ... } as const; export type ToolId = (typeof ToolId)[keyof typeof ToolId];`

These constraints bleed back into the source-file conventions so the paste transform stays mechanical:

- Every non-xstate reference goes through `deps` injection or a type-only import (type imports are erasable; the generator strips them).
- The machine file never introduces runtime imports from other local modules.

## Paste-version generator

Regenerate after every structural change; never hand-edit the artifact:

```bash
npm run sketch:interaction-machine   # → out/sketch/interactionSystem.machine.sketch.ts (gitignored)
```

The transform is deliberately dumb: drop `import ...` lines, strip leading `export `, prepend type stubs (`type Mesh = any` etc.) and fallback implementations for xstate helpers (`and`/`not` faithfully reimplemented; `stateIn` falls back to `() => false`, i.e. "not dragging", so SELECT_TOOL and shortcuts stay operable in simulation). `setup`/`assign` are assumed to exist globally in Sketch — if Sketch reports them undefined, that is a generator problem, not a source-file problem.

- **External-type stubs must track the machine's imports**: the generator's header stubs
  (Scene/Mesh/…/ViewAlignOptions) are hard-coded — adding a NEW external type import to the
  machine file requires adding a matching `type X = any;` stub in the same change, or the paste
  version references an undefined type. (Hit with ViewAxis/ViewAlignOptions in the edit-supports
  branch.) ESLint/Prettier cannot catch this cross-file mismatch — only review can. Long-term fix
  under consideration: derive the stubs from the machine's type-only imports instead of
  hand-maintaining them.

## Naming is the interface

Sketch shows the **names** of states, transitions, events, and guard/actions. All business logic hides behind those names (guards read the store via deps; actions mutate the scene/store). Consequences:

- A rename on either side must immediately mirror to the other, or the diagram silently points at air.
- When triaging "behavior in Sketch doesn't match expectations" reports, first check whether the guard reads external state (via deps) — **Sketch simulation has no store**, such guards behave by fallback logic, not real logic. That is a visualization artifact, not a machine bug.

## Expected deviations in Sketch Simulate (do not report as bugs)

Simulate runs the paste version; deps do not exist, so every guard that reads external state behaves by fallback:

- `stateIn(...)` → always `false` (e.g. forever "not dragging");
- custom guards (`notLoading`, `notProcessing`, etc.) → return the generator stub's default, **not the real store state**.

So "a transition gated on loading/processing still fires in Simulate" is **expected** — interception depends on the real store and can only be verified in the app. Sketch is for checking the diagram structure (state tree, events, branches), not guard runtime results.

## Consistency checklist (when asked "is the diagram in sync with the code?")

- **First** regenerate the paste version (`npm run sketch:interaction-machine`) before comparing — never compare against a stale paste.
- Node-by-node compare the state tree (parallel regions, substates, `initial`), the event-type set, and the guard/action name sets.
- Recognize behaviorally-equivalent differences: explicit swallow branches vs bubbling fallback, mutually exclusive guard branch order, payload-type narrowing on the implementation side (`string` → `ToolId | null`) — these are NOT desync.
- Behavior outside the machine (event adapter layer, gesture translation, store-side reconcilers) is out of sync scope.

## Common failure modes

| Failure | Consequence | Correct fix |
|---|---|---|
| Hand-editing the generated paste version | Overwritten on next regeneration; change evaporates | Edit the source machine file, regenerate |
| Runtime import or enum added to the machine file | Sketch paste throws a syntax error | References via deps/type-only imports; const object instead of enum |
| Reporting Sketch simulation behavior as a bug | False positive — Sketch has no store/deps | Check whether the guard reads external state; verify in the app |
| Editing the machine from memory of the diagram | The diagram is a visualization, not the source of truth | Re-read the machine file before touching it |

## Red lines

- Never Write/Edit the generated paste version (`out/sketch/*.sketch.ts`).
- Never let a runtime non-xstate import or a TS enum into the machine file.
- Renaming without reflecting it in both the code and the next paste = planting a landmine.
