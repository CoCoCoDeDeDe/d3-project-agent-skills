---
name: dev-conventions
description: "通用开发规范(不限仓库/语言):验证在 commit 前完成而非攒到 push 前、linter 缓存导致本地与 CI 不一致时先清缓存、各语言的格式检查与美化工具映射(TypeScript/ESLint/Prettier、C#/CSharpier 等)。Use when committing code, when CI lint/format checks fail but local checks pass (stale cache), when unsure which formatter/linter a language uses, or when setting up verification habits for a new project. Repo-specific command sets live in that repo's own skill (e.g. rwn-development for RaywareNative) — this skill holds the cross-repo discipline."
---

# 通用开发规范

> 跨仓库、跨语言的通用纪律。具体仓库的命令集由该仓库自己的 skill/AGENTS.md 承载(如 RaywareNative 见 `rwn-development`);本文件只讲与仓库无关的部分。

## 验证时机:commit 前,不是 push 前

- 每次 commit 前跑该语言的完整验证(类型检查 + lint + 格式),**不要攒到 push / 开 PR 前**——越早跑,问题定位越小,commit 越干净。
- "CI 跑什么,本地就跑什么":先弄清 CI 的确切命令集,本地用同一套,不要用"差不多"的替代。
- eslint **warning** 不一定 fail CI,但格式检查(prettier --check 类)有任何 diff 就 fail——以工具的退出码为准,不凭感觉。

## 缓存陷阱:commit 前默认清缓存,不要等 CI

带缓存的 linter/构建工具(`eslint --cache`、各类 incremental build)会用陈旧结果掩盖新引入的问题。**默认规则:commit 前的验证一律先清缓存/陈旧产物再跑**,而不是等 commit 后看 CI 结果再返工。例如:

- `rm -f .eslintcache && npm run lint`(实测案例:`.eslintcache` 掩盖了 `react-hooks` 新规报错,CI 无缓存才暴露)
- `rm -rf out-tests && npm run test:unit`(陈旧编译产物会跑幽灵测试)

本地过了但 CI 挂了,第一反应也是检查"本地是不是跑了缓存结果",而不是怀疑 CI。

## 各语言的格式检查与美化工具

按语言选择对应工具,提交前必须过:

| 语言 | 类型/编译检查 | Lint | 格式化 |
| --- | --- | --- | --- |
| TypeScript / JavaScript | `tsc --noEmit` | ESLint | Prettier |
| C# | `dotnet build` | (分析器随构建) | **CSharpier**(`dotnet csharpier check .` / `--write`) |
| Python | `mypy` / `pyright` | Ruff | Ruff format / Black |

- 项目已配置的工具优先于本表(查仓库的 CI 配置、`.prettierrc`、` .editorconfig`、`.csharpier.json` 等)。
- 新增一种语言的代码前,先确认该语言的检查工具链已就位;没有就补上,不要裸提交。
- 格式化用 `--write` 模式修,不要手改格式。
