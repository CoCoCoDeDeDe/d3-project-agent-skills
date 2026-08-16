---
name: xstate-studio-sync-workflow
description: "Web CAD 项目:XState 状态机实现与 Stately Sketch 可视化同步的工作流(原 Studio 导出流程已废弃)。Use when the user pastes machine code into Stately Sketch for visualization, asks to 可视化/检查状态机图, reports Sketch syntax errors (Cannot use import/export statement, enum parse failure), regenerates the Sketch paste version, adds or renames states/guards/actions/events in the machine, or asks whether the machine and its Sketch diagram are in sync. Also covers legacy Studio export files (tmp-xstate.ts style) if they resurface. Covers the Sketch script-mode constraints, the paste-version generator, and the naming-as-interface contract."
---

# XState Implementation ↔ Stately Sketch Sync Workflow

## Core Principle (current workflow, post-Studio)

**The implementation machine file (e.g. `interactionSystem.machine.ts`) is the single source of truth — AI/user edit it directly.** Stately Sketch is a read-only visualization/review surface: the user pastes a GENERATED paste version into Sketch to inspect the diagram. There is no export file layer and no reverse channel — if the user wants a structural change, edit the implementation, regenerate, re-paste.

Legacy note: if an old Studio-exported file (e.g. `tmp-xstate.ts`) resurfaces, treat it as a read-only snapshot and migrate its structure into the implementation rather than reviving the export workflow.

## Sketch Hard Constraints (why the source file looks the way it does)

Sketch evaluates pasted code as a plain script. Two syntax families therefore can never reach it:

1. **No `import` / `export` statements at all** — including the xstate import and including `import type`. Sketch throws `SyntaxError: Cannot use import statement outside a module` on the FIRST import line.
2. **No TS `enum`** — Sketch's parser rejects it. Use a const object + `as const` + same-name type:
   `export const ToolId = { Orientation: 'orientation', ... } as const; export type ToolId = (typeof ToolId)[keyof typeof ToolId];`

These constraints leak BACK into the source file's conventions, so the paste transform stays mechanical:

- Keep every non-xstate reference behind `deps` injection or type-only imports (type imports are erasable; the generator strips them).
- Never introduce a runtime import from another local module into the machine file.

## Paste-Version Generator

Regenerate after every structural change; never hand-edit the output:

```bash
npm run sketch:interaction-machine   # → out/sketch/interactionSystem.machine.sketch.ts (gitignored)
```

The transform is deliberately dumb: drop `import ...` lines, strip leading `export ` keywords, prepend type stubs (`type Mesh = any` etc.) and ambient fallbacks for xstate helpers (`and`/`not` are reimplemented faithfully; `stateIn` falls back to `() => false`, i.e. "not dragging", so SELECT_TOOL/shortcuts stay operable in simulation). `setup`/`assign` are assumed ambient in Sketch — if Sketch ever reports them undefined, that is a generator concern, not a source-file concern.

## Naming Is the Interface

Sketch shows states, transitions, events, and guard/action NAMES. All business logic lives in the implementation behind those names (guards reading stores via `deps`, actions with scene/store side effects). Consequences:

- A rename on either side must be mirrored immediately, or the diagram silently points at nothing.
- When reviewing a Sketch report of unexpected behavior, first check whether the guard in question reads external state (store via deps) — Sketch simulation has no stores, so such guards behave per the fallbacks, not per real logic. That is a visualization artifact, not a machine bug.

## Consistency Checklist (when asked "does the diagram match the code?")

- Regenerate the paste version FIRST (`npm run sketch:interaction-machine`), then compare — never compare against a stale paste.
- Compare the state tree node by node (parallel regions, child states, `initial`), event type sets, and guard/action name sets.
- Recognize behaviorally-equivalent differences: explicit swallow branches vs. bubble-through fallback, branch order of mutually exclusive guards, implementation narrowing a payload type (`string` → `ToolId | null`) — these are NOT desync.
- Behavior outside the machine (event adapter layer, gesture translation, store-side reconcilers) is out of sync scope.

## Common Failure Modes

| Failure | Consequence | Correct approach |
|---|---|---|
| Hand-editing the generated paste file | Next regeneration overwrites; changes evaporate | Edit the source machine file, regenerate |
| Adding a runtime import or enum to the machine file | Sketch paste breaks with a syntax error | Keep refs behind deps/type-only imports; const object instead of enum |
| Reporting Sketch simulation behavior as a bug | False alarm — Sketch has no stores/deps | Check whether the guard reads external state; verify in the app instead |
| Editing the machine from memory of the diagram | Diagram is a visualization, not the source | Re-Read the machine file before touching anything |

## Red Lines

- NEVER Write/Edit the generated paste file (`out/sketch/*.sketch.ts`).
- NEVER let a runtime non-xstate import or a TS enum into the machine file.
- A name change not reflected in both the code and the next paste = a planted landmine.
