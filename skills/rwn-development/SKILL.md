---
name: rwn-development
description: RaywareNative (RWC 3.0) development conventions — verification commands, CI discipline, comment/test rules, no-magic-strings type discipline (closed value sets as enums, shared literals as constants), icon/i18n rules, tool-panel multi-select conflict handling, vendored assets, dual-runtime provider seams, XState Sketch sync. Use ONLY when working in the RaywareNative repository (RWC 3.0 codebase) — coding in renderer/services/stores/tests, before committing or pushing a branch or opening a PR there, or when CI checks (check-formatting / run-eslint / code-review) fail on a RaywareNative PR. NOT for RWC 2.0 / Design-Service or any other project — several rules are RaywareNative-specific.
---

# RaywareNative (RWC 3.0) Development Conventions

> **Scope:** everything in this skill applies only to the **RaywareNative (RWC 3.0)** repository. Its conventions (English-only comments, CI command set, test harness setup, provider seams) are repo-specific — do not generalize them to other projects.

## Repository topology

- RWN is the **RaywareNative repository (RWC 3.0)**. The local checkout is one main repo
  (`RaywareNative/`, tracking `develop`) plus git **worktrees** `RaywareNative-side-1/ -2 -3`
  created from it — not standalone clones. Side worktrees host the developer's stacked feature
  branches, or detached-at-develop checkouts for reviewing colleagues' PRs; all four share one
  object store.
- Worktree gotcha: one branch can be checked out in only one worktree — checking it out
  elsewhere fails with "already used by worktree at …"; detach first or switch to the worktree
  that holds it.
- `refs/Design-Service/` is a **different repository — RWC 2.0 (backend + 2.0 frontend)**,
  analysis reference only. Nothing in this skill applies there (see Scope), and RWN code is
  never judged against its conventions. RWN's native/Electron side and its AWS infrastructure
  still depend on RWC 2.0 libraries (team-confirmed) — that dependency is why the dual-runtime
  provider seams below exist.

## Verification commands (run all before every commit)

See `dev-conventions` for the cross-repo discipline (verification timing, cache traps,
per-language tool mapping); this is RWN's concrete command set. CI runs exactly these — run
them locally and make them pass **before every commit**, with caches cleared by default (don't
wait for CI to catch a stale-cache miss):

```bash
npm run typecheck          # tsc node + web configs
rm -rf out-tests && npm run test:unit    # stale compiled output runs ghost tests
rm -f .eslintcache && npm run lint       # eslint --cache masks newly introduced errors
npx prettier --check src --ignore-unknown   # exact CI command (check-frontend-format.yml)
```

- `npx prettier --check src --ignore-unknown` is the **exact CI command**
  (`check-frontend-format.yml`); CI guards only `src`. When a change also touches
  `tests/`, run `npx prettier --check tests --ignore-unknown` as well — the session
  convention checks both, and a formatting diff in tests is still a review failure.
- **Magic-string scan**: typecheck/lint/prettier never catch semantic string literals — before committing, grep the diff for new handwritten `'...'` discriminator unions and literals repeated across files (closed sets → `enum`, shared literals → `const`). General rule + decision table in `dev-conventions`; RWN instances and scope discipline below.

## CI discipline

- **develop is green.** Any error your branch introduces fails CI — evaluate against the CI commands above, never against "it was already failing on my HEAD". A file your branch adds or touches must leave lint/format checks clean.
- eslint **warnings** don't fail CI, but `prettier --check` fails on any formatting diff. Run `npx prettier --write` on touched files.
- **Flaky CI exists** (e.g. `fatal: shallow file has changed since we read it` on shallow fetches). Re-run the failed job first; only change the workflow if it fails repeatedly.
- Large PRs: call out vendored/bulk files in the PR description so reviewers don't read the raw line count as hand-written code. Prefer reviewing commit-by-commit — keep commits atomic (one logical change per commit, `type(scope): summary`).

## Layout / constraint-chain changes (flex + fixed height + overflow)

Layout bugs evade typecheck/lint/unit tests — the ToolsPanel shrink chain took three review rounds because each level was fixed reactively. Checklist before committing any bounded-container layout change:

- **Draw the size chain first**: which layer is bounded, which layer yields when space runs out, what absorbs the yielded height (scroll region?), and each layer's min-content floor. Example chain: left column → panel → Collapse → MUI wrapper×2 → toolBox → `.options` scroll.
- **Evaluate BOTH scenes**: constrained AND unconstrained. A fix that only satisfies the shrink case once regressed the Figma fixed height in the relaxed case (541px → content height) in the same PR series.
- **Third-party internals before percentages/overrides**: writing `height:100%`, `overflow`, or selector overrides against MUI components → first check the rendered DOM slots and their stock styles (e.g. Collapse's `wrapper`/`wrapperInner` are `height:auto`, so percentages compute to `auto`; entered state sets `overflow:visible`, beat it with a `:global(.MuiCollapse-entered)` specificity bump — precedent `PrintJobFilesPanel.module.scss`).
- **Manual-test the extreme**: shrink the window to the smallest realistic size (e.g. 1366×768 laptop) and look — ten seconds catches what no automated check does.

## Comments

- **English only** (project CLAUDE.md rule; automated review checks it).
- **No ticket numbers or review references** (`RWC-1234`, "review finding X") in code comments — a comment must stand on business/logic alone. 2.0 references with `file:line` stay (they are business context).
- Keep *why* comments: design rationale, gotchas and their root causes, 2.0 references with `file:line`, non-obvious parameter semantics/units, architecture conventions.
- Delete *what* comments that restate the code, decorative section dividers, and stale comments describing removed behavior.

## Component READMEs (public components)

Every shared component under `src/renderer/components/` (incl. `components/ui/`) ships a `README.md` in its folder — precedent format: `Button`/`Chip`/`Select` (short description, usage example, props table, style-override notes, Figma sources).

- **Add it in the same branch that adds the component**, not a follow-up.
- **Sync it before every commit that changes the component** (props, variants, behavior) — a stale README is treated like a stale comment.
- `prettier --check` covers Markdown — write, then `npx prettier --write` the README before committing.
- Business composites under `pages/` are exempt; the rule targets the reusable public surface.

## No magic strings: enums and shared constants

Any string/number literal that carries **semantic meaning** (state ids, kind tags, machine state names, config keys) must not be written inline — a literal scattered across files has no rename safety, no typo protection, and no single source of truth. Two remedies by shape (both reviewer-enforced):

- **Closed value set** (states, kinds, ids, modes) → `enum`, never string-literal union types (RWC-4719 review, applied across RWC-4754 and RWC-4851):
  - Backend-driven ids/values: numeric enums matching the wire values, e.g. `LayerThicknessId { Micron50 = 1, ... }`, `FileSettingMode { Automated = 1, ... }`.
  - Frontend-only state/kind sets: string enums whose values equal the previous literals (zero runtime change), e.g. `PlatformJobLoadPhase { LoadingJob = 'loading-job', ... }`, `EditToolSelectionKind { MultiSame = 'multi-same', ... }`, `TopBarChipKind`, `SceneMaterialKind`, `AlarmKind`, `ReferenceDataStatus`.
  - Members are PascalCase; the value keeps the wire/literal form (`MeshDefect = 'meshDefect'`).
  - Converting a union to a string enum breaks value-position code in ways typecheck catches: `Record<Enum, …>` object literals need computed keys (`[TopBarChipKind.Appliance]: …`), and tests passing bare literals must switch to enum members. Run typecheck first — it enumerates every fix point.
  - Scope discipline: only convert types your branch owns or already touches. Do not sweep pre-existing shared types (e.g. `ApiMethod` in `services/api/types.ts`) into an unrelated PR.
- **Single literal referenced from multiple places** → a shared `const`, not an enum (e.g. `TOOL_REGION_CLOSED = 'closed'` for a machine state id), with a comment naming what it must stay in sync with and which test locks it (RWC-4851 review).
- **Prefer existing domain enums over new ad-hoc ones** — before defining a new enum/const set, check `services/*/(types|constants).ts` for an existing definition to reference (RWC-4851 review: a custom `EditToolPrinterFamily` was rejected in favor of `PrinterPlatform` members).

The general, repo-agnostic rule and the pre-commit scan live in `dev-conventions`; this section keeps the RaywareNative instances and scope discipline.

## Printer vs platform separation (permanent convention)

`PrinterPlatform` in `services/printerPlatform` aggregates printer model + platform kit into one enum (`P23PArch`, `P23PDuo`, `MDSTiTan`…) — that is the **RWC 2.0 legacy shape**. In RWN (3.0) code:

- Treat printer and platform/kit as **separate** concepts; derive the base model with `normalizePrinterPlatform` (kit variants collapse to `P23P`/`MDS`/…) and the kit via `SprintRayPrinterPlatformTypes`.
- Comparisons go through **existing enum members + normalization** (`leg.excludedPrinters.includes(normalizePrinterPlatform(id))`), never through new aggregate discriminators like `'pro2OrMidas'` strings or custom family enums (RWC-4851 review).
- Do not add new members/aggregates that mix the two axes; new conditional logic expresses constraints as sets of existing base-model members.
- **Prefer blacklists for availability conditions** (RWC-4851 review): a future new printer/indication must pass by default with zero code changes — express "hidden on these" (`excludedPrinters: [...]`), not "shown only on these". Whitelists are only acceptable when the feature is inherently "only for these" (e.g. an indication family).

## i18n keys

- Locales (`src/renderer/i18n/locales/*.json`) have fixed top-level namespaces (`date` / `phrase` / `sentence` / `unit`) — **never add a new top-level key** (RWC-4851 review). Short names go to `phrase`, longer/tooltip strings to `sentence`.
- Keys stay **single-level** under each namespace (long-standing team convention): no nested objects. Embed the feature prefix in the camelCase key name instead — `phrase.editToolsOrientationSelectBase`, `phrase.editToolsSupportsStyleBalanced` — so generic words (`scale`, `layout`, `supports`) still can't collide and never become bare keys.
- **Only edit `en.json`** (RWC-4756 convention): English copy is the source of truth; all other locale files are filled by CI/CD translation flow. Never hand-write keys into the other locale JSONs.

## Icons (feature assets)

- **Search before adding**: before importing a new icon, search `src/renderer/assets/generalIcons/` for an existing asset that already matches the intent (same visual, variant, or state). Icon sets grow from Figma exports and duplicates accumulate silently — reusing a same-purpose icon (possibly the mono vs colored variant) beats copying it under a new name (edit-tools panel precedent).
- **Feature-scoped snake_case naming**: new icons live in `assets/generalIcons/<feature>/<icon-name>.svg` with a name describing the icon's visual — `editTools/supports/edit-supports.svg`, `support-style-balanced.svg`, `raft-on.svg` — never a ticket number or a UI label.
- **Figma exports can bake state artifacts**: exported SVGs may carry a baked disabled/hover look (precedent: `redo.svg` shipped a baked 0.2 fill-opacity that was the disabled state, fixed in the edit-supports branch). On export, strip state-specific opacities/colors — the component owns state styling; the asset stays neutral.

## Tests (tests/unit)

- Framework: `node:test` + `assert/strict`, compiled by `tests/tsconfig.unit.json`, path aliases resolved at runtime by `tests/registerPathAlias.mjs`.
- **Test scope discipline** (RWC-4756 convention): do **not** write unit tests for UI components or straight-through logic (prop forwarding, one-line delegations to an existing API, trivial wiring). Only complex logic and services merit tests — e.g. pure functions with branching/clamping, state reconciliation, parsers. If a candidate turns out to be a pass-through on implementation, skip the test.
- **A change that touches covered logic updates its tests in the same commit** — machine states/events/guards, service functions, resolvers included. CI runs the whole suite, but a stale test that still passes (it exercises only an unchanged branch) is a review failure: the assertion no longer describes the behavior being shipped.
- **Import leaf modules, not barrels.** Barrel `index.ts` files can pull in binary assets (e.g. `.webp`) that crash Node test compilation — import the deep module under test directly with relative paths.
- **No `any` in mocks** (`@typescript-eslint/no-explicit-any` is an error in CI). Use minimal structural mock types and cast at the boundary: `as unknown as Mesh`.
- Assert logic and relationships, not tuned aesthetic values (brightness, zoom levels are design-tunable; do not hard-code them in assertions).
- For XState machines: assert with `snapshot.matches(partialValue)` subset matching — one test asserts only the dimension it names; no full state-value `toEqual` on parallel machines.

## Vendored / generated assets

- `src/renderer/graphics/meshes/draco/draco_decoder.js` (and similar vendored bundles): never edit, never format — covered by `.prettierignore` and eslint `ignores`. Add new vendored files to both.

## Dual-runtime (Web/Electron) provider seams

- Every cross-runtime capability = one typed contract + one implementation per runtime + a single runtime branch (`isElectronRuntime()` in the provider module only).
- Unimplemented native endpoints **throw `ServiceNotImplementedError`** — never return mock/empty data. Silent fake data is worse than a loud error.
- DTOs are the contract the native side implements against: mark fields optional when the backend may omit them, matching parser defenses.
- Never bypass the provider: pages/components must not import `services/*/cloud` or `services/*/native` implementations directly.

## Tool panel configuration (permanent convention)

- A tool panel's options are the configuration for the ONE edit request its Save fires — they **never read or prefill from the models' persisted platform metadata**. Initial values are product defaults (e.g. raft defaults Off) or "no selection", never job data. This kills the "multi-selected models hold different values for the same option" display problem at the source.
- Two boundaries: reading persisted data as the **edit target** (e.g. support points rendered in Edit supports) is fine; reading it for **availability gating** (e.g. `isSupported` gates editing) is fine. Forbidden only as option prefill.
- Review check for new options: is the initial value a constant / none, or does it read job data? The latter is always rejected.
- **Forward masked/effective state to Save, never raw state**: a panel that masks raw state into an effective value (composition/availability gates) must have every Save/request path send the EFFECTIVE value. A value a gate hides from the UI must never join a request — it would override persisted per-model state the gate exists to protect (RWC-4764: the style Save forwarded raw `raftChoice`, leaking a crown-gated `true` onto non-crown models).

## Tool panel multi-select conflict handling (permanent convention)

When a tool panel's options are gated by the selected models' composition (different `TreatmentApplianceType` groups expose different option sets), resolve the conflict per option group and keep the configuration visible — do not replace the panel with a generic conflict message. Resolve the effective selection's composition once, then apply one of three escalation rules per option group:

- **Same config, partially compatible options** → show the union of both groups' options, but `disable` the ones that don't apply to every selected group ("show-all, enable-intersection").
- **Options differ only in appearance** (icon; same request payload and semantics) → show the more common appearance.
- **Completely incompatible options** → show both but `disable` all.

Two invariants multi-select handling must not break:
- existing inter-option mutual exclusion (e.g. Support type `None` disables Support raft);
- opt-in groups: any group may be left unselected, and Save then reuses each model's existing value for that group instead of sending a default.

Reference implementation: the RWC-4764 Supports panel (`resolveSupportsPanelComposition` / `resolveRaftAvailability`).

## Business-rule encapsulation (permanent convention)

For availability/limitation/eligibility rules (edit tools, render controls, file actions, print eligibility) — a legacy-heavy business system defeats any pre-defined rule schema:

- **Thin uniform evaluation points**: one signature, one formula per surface (`isEditToolUsable`, machine guards calling injected deps). New tools/rules change registry data, never the evaluators.
- **One full context**: every plausible factor (job types/printer/kit, selection, loading, featureFlags) goes into one context object; rule functions read what they need. A new factor = one new context field, available to all rules on both entry and exit sides.
- **Business complexity lives in functions**: rules are plain `(context) => boolean`; the domain logic behind them is decomposed into named pure helpers (the unit of unit-testing) — never anonymous mega-lambdas, never business logic leaking into components/machines/effects.
- **Declarative data only for genuinely tabular facts**: a rule may be a data table only if the product can state it fully as a table with zero procedural logic (the "Tools per indication" matrix). Anything with "when X, first do Y then Z" semantics is a function. When in doubt, choose a function.
- Do not invent per-feature rule schemas (a `disallowX: boolean` field, a narrow input type) — they break on the next business case. Extend the shared context instead.

## XState machine ↔ Stately Sketch sync

Machine rules (parallel shadowing, live-read guards, naming-as-interface, test conventions) live in the `rwn-xstate-machines` skill; the Sketch paste workflow lives in `xstate-studio-sync-workflow`. The one-line summary: the implementation machine file is the source of truth — edit it directly, keep it Sketch-compatible (runtime imports only from `xstate`, no `enum`), and regenerate the paste version after structural changes.

## Async operation invariants (platform-job store)

Conventions for anything that rides the shared `asyncOperations` registry (the add-print-job-loading guide in the repo covers the lifecycle API):

- **Every slot must have a guaranteed path to a terminal phase** — a stranded Running/Awaiting slot locks the whole workspace (the loading selector drives banner, controls, and machine guards). Running slots get the default deadline; Awaiting slots get the pipeline deadline; if you add a transition path, prove where it terminates.
- **No silent aborts after the UI consumed the action** — if the panel already cleared a selection/mode, aborting must surface (start + immediately fail the operation so the error banner fires), never a bare `return`.
- **Classify outcomes by the rejection shape, not by enumerating success shapes** — success paths multiply (handoffs, fast paths, reloads); the rejection shape is usually singular (an explicit Failed). Inverting the check avoids misclassifying the next newly discovered success path.
- **Heuristic identity markers (TTL windows, timing guesses) are a last resort** — when used, document the misjudgment boundary in a comment. The correct fix for self/remote ambiguity is a correlation id from the backend; push for that instead of stacking frontend layers.

## Visual verification

Rendered visuals (lighting, colors, outlines, transparency artifacts) are verified by a human in the browser. Do not self-verify visuals via screenshots or claim visual correctness from code reading alone.

- **A rendered/visual convention is design-doc truth until the render disproves it**: marking direction, selection colors, materials, transparency — when a review finding or an automated review contradicts a convention the design doc recorded (a「踩坑」section) or one already verified in the browser, do NOT auto-apply the suggestion. Surface the conflict to the human for a visual decision. Code-reading inference has lost to actual render verification before: a review-driven normal-direction flip shipped, was pushed, and was reverted after the human saw the inverted render (红面反了).
- **Rendered-behavior changes need human visual sign-off before push**: any commit that changes what the scene renders (marking/selection colors, materials, transparency, geometry display) is pushed only after the human confirms the render — never on code review alone, whatever CI or an automated reviewer concludes.
- **Lock visual conventions in a pure-function test + a why comment**: the need-support marking direction is guarded by a unit test and the flat-shading flip mechanism is documented in the function's JSDoc, so the convention survives future review pressure instead of depending on one reviewer's reading.
