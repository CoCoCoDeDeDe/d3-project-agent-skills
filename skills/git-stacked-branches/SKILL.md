---
name: git-stacked-branches
description: "Squash 合并 + 栈式分支(-1/-2/-3 系列分支)的协作工作流:父 PR 合入后子分支必然冲突的机理与标准处理、本地/远程分支的 checkout 陷阱。Use when a stacked PR shows conflicts right after its parent merged, when deciding rebase vs merge for stacked branches, or when checkout --track fails with 'branch already exists'."
type: prompt
whenToUse: When working with stacked feature branches (ticket-numbered chains like RWC-1234-foo-1/-2/-3), after a parent PR merges and the child PR shows conflicts, or when local/remote branch checkout behaves unexpectedly.
---

# Squash 合并 × 栈式分支工作流

## 核心事实:父 PR 合入后,子分支 PR 必然临时冲突

机理:squash 合入把父分支内容压成 develop 上**一个全新 commit**;子分支历史里同样的内容以原始 commit 序列存在。子 PR 的 base 自动指向 develop 后,merge-base 停在分叉点,git 看到"两侧改了同样的文件同样的行但来自不同 commit"→ 判冲突。

**内容相同也冲突**:git 合并比较的是两侧的 patch,不做内容等价判断。

## 标准处理(机械操作)

父 PR 合入后,立刻给子分支:

```bash
git checkout <子分支>
git fetch origin
git merge origin/develop   # 内容相同处自动消解;同区编辑可能留小冲突
# 验证(typecheck/test/lint/format)后 push
```

- **不要 rebase**:子分支有 open PR,rebase 改写历史要 force-push,PR 评论锚点丢失,且连锁要求更下游分支全部 rebase
- merge 得到完全相同的树,GitHub 的冲突标记消失
- 多级栈逐级做:第 N 层合入后 merge develop 进第 N+1 层
- 冲突取舍惯例:子分支内容通常是父的超集,`git checkout --ours` 前先用 `git log origin/develop --oneline -3 -- <file>` 核实 develop 侧在 squash 后有没有真实新变化

## 预防选项(团队层面)

- 栈式 PR 改用 merge commit 合入(非 squash)则完全无此问题——代价是 develop 历史保留原始 commit 序列
- 或接受现状,把"父合入 → 子 merge develop"写进流程

## 配套:本地同名分支的 checkout 陷阱

- `git checkout --track origin/X` 的语义是"**新建**本地分支并关联"——本地已有 X 时报 `already exists`
- `git checkout X` 只切换、**不同步**;本地 X 可能落后于 origin/X(切完看 `git status` 的 ahead/behind)
- 本地与远程同点时补关联:`git branch --set-upstream-to=origin/X X`
- 本地分支要丢弃重来:`git checkout -B X origin/X`
