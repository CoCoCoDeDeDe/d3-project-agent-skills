---
name: dev-conventions
description: "Cross-repo, cross-language development discipline: verify BEFORE commit rather than before push, clear linter/build caches before verifying (stale caches mask new problems), and the per-language check/format tool mapping. Use when committing code, when CI lint/format checks fail but local checks pass (stale cache), when unsure which formatter/linter a language uses, or when setting up verification habits for a new project. Repo-specific command sets live in that repo's own skill (e.g. rwn-development for RaywareNative) — this skill holds the cross-repo discipline."
---

# General Development Conventions

> Cross-repo, cross-language discipline. Repo-specific command sets live in that repo's own skill/AGENTS.md (e.g. `rwn-development` for RaywareNative); this file only covers the repo-independent part.

## Verification timing: before every commit, not before push

- Run the language's full verification (type check + lint + format) before **every commit**, not accumulated until push / PR time — the earlier you run it, the smaller the problem to localize and the cleaner the commit.
- "Run locally exactly what CI runs": first find out the CI command set and use the same one locally — never a "close enough" substitute.
- eslint **warnings** may not fail CI, but any format diff (prettier --check style) fails — trust the tool's exit code, not feelings.

## Cache traps: clear caches before committing by default

Cached linters/build tools (`eslint --cache`, incremental builds) mask newly introduced problems with stale results. **Default rule: clear caches/stale artifacts before commit verification**, rather than waiting for CI to fail and reworking:

- `rm -f .eslintcache && npm run lint` (real case: `.eslintcache` masked a new react-hooks rule error that only CI, without cache, exposed)
- `rm -rf out-tests && npm run test:unit` (stale compiled output runs ghost tests)

When local passes but CI fails, first suspect "did I verify against a cached result?", not the CI.

- **Stale dev-server modules**: after multi-file changes (especially new exports), a long-running
  dev server can serve a mixed module graph (new consumer + old provider) that throws errors
  absent from the on-disk code. Restart the dev server (or hard-refresh) BEFORE treating the
  error as a code bug — verify against a freshly-started server, then investigate.

## Per-language check and format tools

Pick by language; every commit must pass:

| Language | Type/compile check | Lint | Format |
|---|---|---|---|
| TypeScript / JavaScript | `tsc --noEmit` | ESLint | Prettier |
| C# | `dotnet build` | (analyzers run with the build) | **CSharpier** (`dotnet csharpier check .` / `--write`) |
| Python | `mypy` / `pyright` | Ruff | Ruff format / Black |

- The project's configured tools take precedence over this table (check the repo's CI config, `.prettierrc`, `.editorconfig`, `.csharpier.json`, etc.).
- Before adding code in a new language, confirm that language's check toolchain is in place; if not, add it — never commit bare.
- Format with `--write` mode, never hand-edit formatting.
