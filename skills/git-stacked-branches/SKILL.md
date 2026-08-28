---
name: git-stacked-branches
description: "Squash-merge + stacked-branch workflow (ticket-numbered chains like RWC-1234-foo-1/-2/-3): why a child PR necessarily conflicts right after its parent merges, the standard handling, and local/remote branch checkout traps. Use when a stacked PR shows conflicts right after its parent merged, when deciding rebase vs merge for stacked branches, or when local/remote branch checkout behaves unexpectedly (including worktree 'already used by worktree')."
---

# Squash Merge × Stacked Branch Workflow

## Core fact: after a parent PR merges, the child PR temporarily conflicts — necessarily

Mechanism: the squash merge collapses the parent branch into ONE brand-new commit on develop; the same content exists in the child's history as the original commit sequence. Once the child PR's base auto-points to develop, the merge-base sits at the fork point and git sees "both sides changed the same files at the same lines, but from different commits" → conflict.

**Identical content still conflicts**: git merge compares both sides' patches; it does not judge content equivalence.

## Standard handling (mechanical)

Right after the parent PR merges, for the child branch:

```bash
git checkout <child-branch>
git fetch origin
git merge origin/develop   # identical content auto-resolves; same-region edits may leave small conflicts
# verify (typecheck/test/lint/format) then push
```

- **Do not rebase**: a child branch with an open PR — rebasing rewrites history and needs a force-push, PR comment anchors are lost, and every further-downstream branch must rebase in turn.
- Merging produces an identical tree; GitHub's conflict markers disappear.
- Do it level by level down a multi-level stack: after level N merges, merge develop into level N+1.
- Conflict-resolution convention: the child branch is usually a superset of the parent — before `git checkout --ours`, verify with `git log origin/develop --oneline -3 -- <file>` whether develop gained any real change on that side after the squash.

## Prevention options (team level)

- Stacked PRs merged with merge commits (not squash) avoid this entirely — at the cost of develop history keeping the original commit sequence.
- Or accept the status quo and bake "parent merged → child merges develop" into the workflow.

## Companion: local same-name branch checkout traps

- `git checkout --track origin/X` semantics is "**create** a local branch and associate it" — when a local X already exists it errors with `already exists`.
- `git checkout X` only switches, does **not** sync; local X may lag origin/X (check the ahead/behind in `git status` after switching).
- Same local/remote commit, missing association: `git branch --set-upstream-to=origin/X X`.
- Discard and recreate a local branch: `git checkout -B X origin/X`.

## Companion: worktree checkout traps

- Worktree setups (main repo + `RaywareNative-side-1/ -2 -3`): one branch can be checked out in only **one** worktree — checking out the same branch from another worktree fails with `already used by worktree at …`. Detach first, or switch to the worktree that holds it.
