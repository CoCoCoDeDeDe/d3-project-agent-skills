---
name: rwn-development
description: RaywareNative (RWC 3.0) development conventions — verification commands, CI discipline, comment/test rules, vendored assets, dual-runtime provider seams, XState Studio sync. Use ONLY when working in the RaywareNative repository (RWC 3.0 codebase); NOT for RWC 2.0 / Design-Service or any other project.
type: prompt
whenToUse: When working on code in the RaywareNative (RWC 3.0) repo (renderer, services, stores, tests), before pushing a branch or opening a PR there, or when CI checks (check-formatting / run-eslint / code-review) fail on a RaywareNative PR. Do not apply these conventions to other repositories — several rules are RaywareNative-specific.
---

# RaywareNative (RWC 3.0) Development Conventions

> **Scope:** everything in this skill applies only to the **RaywareNative (RWC 3.0)** repository. Its conventions (English-only comments, CI command set, test harness setup, provider seams) are repo-specific — do not generalize them to other projects.

## Verification commands (run all before pushing)

CI runs exactly these — run them locally and make them pass *before* opening/updating a PR:

```bash
npm run typecheck          # tsc node + web configs
npm run test:unit          # tsc tests/tsconfig.unit.json + node --test
npm run lint               # eslint --cache . — must exit 0
npx prettier --check src --ignore-unknown
```

## CI discipline

- **develop is green.** Any error your branch introduces fails CI — evaluate against the CI commands above, never against "it was already failing on my HEAD". A file your branch adds or touches must leave lint/format checks clean.
- eslint **warnings** don't fail CI, but `prettier --check` fails on any formatting diff. Run `npx prettier --write` on touched files.
- **Flaky CI exists** (e.g. `fatal: shallow file has changed since we read it` on shallow fetches). Re-run the failed job first; only change the workflow if it fails repeatedly.
- Large PRs: call out vendored/bulk files in the PR description so reviewers don't read the raw line count as hand-written code. Prefer reviewing commit-by-commit — keep commits atomic (one logical change per commit, `type(scope): summary`).

## Comments

- **English only** (project CLAUDE.md rule; automated review checks it).
- Keep *why* comments: design rationale, gotchas and their root causes, 2.0 references with `file:line`, non-obvious parameter semantics/units, architecture conventions.
- Delete *what* comments that restate the code, decorative section dividers, and stale comments describing removed behavior.

## No magic strings: enums and shared constants

Any string/number literal that carries **semantic meaning** (state ids, kind tags, machine state names, config keys) must not be written inline — a literal scattered across files has no rename safety, no typo protection, and no single source of truth. Two remedies by shape (both reviewer-enforced):

- **Closed value set** (states, kinds, ids, modes) → `enum`, never string-literal union types (RWC-4719 review, applied across RWC-4754 and RWC-4851):
  - Backend-driven ids/values: numeric enums matching the wire values, e.g. `LayerThicknessId { Micron50 = 1, ... }`, `FileSettingMode { Automated = 1, ... }`.
  - Frontend-only state/kind sets: string enums whose values equal the previous literals (zero runtime change), e.g. `PlatformJobLoadPhase { LoadingJob = 'loading-job', ... }`, `EditToolSelectionKind { MultiSame = 'multi-same', ... }`, `TopBarChipKind`, `SceneMaterialKind`, `AlarmKind`, `ReferenceDataStatus`.
  - Members are PascalCase; the value keeps the wire/literal form (`MeshDefect = 'meshDefect'`).
  - Converting a union to a string enum breaks value-position code in ways typecheck catches: `Record<Enum, …>` object literals need computed keys (`[TopBarChipKind.Appliance]: …`), and tests passing bare literals must switch to enum members. Run typecheck first — it enumerates every fix point.
  - Scope discipline: only convert types your branch owns or already touches. Do not sweep pre-existing shared types (e.g. `ApiMethod` in `services/api/types.ts`) into an unrelated PR.
- **Single literal referenced from multiple places** → a shared `const`, not an enum (e.g. `TOOL_REGION_CLOSED = 'closed'` for a machine state id), with a comment naming what it must stay in sync with and which test locks it (RWC-4851 review).

## i18n keys

- Locales (`src/renderer/i18n/locales/*.json`) have fixed top-level namespaces (`date` / `phrase` / `sentence` / `unit`) — **never add a new top-level key** (RWC-4851 review). Short names go to `phrase`, longer/tooltip strings to `sentence`.
- Feature key groups nest **inside** an existing namespace: `phrase.editTools.orientation`, consumed as `t('phrase.editTools.orientation')`. Do not flatten generic words (`scale`, `layout`, `supports`) as bare `phrase` keys — they will collide.
- Every locale file mirrors the same structure; English copy is the source of truth, other locales follow the team's translation flow.

## Tests (tests/unit)

- Framework: `node:test` + `assert/strict`, compiled by `tests/tsconfig.unit.json`, path aliases resolved at runtime by `tests/registerPathAlias.mjs`.
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

## XState Studio ↔ implementation sync

- State-machine **structure is edited only in XState Studio**; exported files (e.g. `tmp-xstate.ts`) are read-only snapshots — never hand-edit them.
- The implementation registers logic under the **names** from the export (guards/actions/events) — naming is the interface; keep both sides in sync, including branch order.
- Studio import loses guard/action function bodies and Event property schemas — re-add them in Studio after importing, then export-only afterwards.

## Visual verification

Rendered visuals (lighting, colors, outlines, transparency artifacts) are verified by a human in the browser. Do not self-verify visuals via screenshots or claim visual correctness from code reading alone.
