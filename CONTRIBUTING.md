# Contributing

本仓库的 Git 开发规范。所有变更(包括维护者本人)都应遵循。

## 分支命名

格式:`<type>/<issue号>-<短描述>`

- `type` 与 Conventional Commits 对齐:`feat` / `fix` / `docs` / `ci` / `chore`
- 有对应 issue 时携带编号,如 `docs/8-contributing`;无 issue 可省略编号
- 短描述:全小写英文、连字符分隔,整个分支名 ≤ 50 字符
- 一分支一 PR,不混装多个不相关变更
- `main` 是唯一常驻分支,不直接向其 push 开发提交
- PR 合并后删除 head 分支(仓库已开启自动删除)

反例:`2026-0730-my-laptop-work`、`new-feature`

## Commit message

- 英文 [Conventional Commits](https://www.conventionalcommits.org/):`type: 描述`,如 `docs: add CONTRIBUTING.md`
- type 取值与分支 type 一致:`feat` / `fix` / `docs` / `ci` / `chore`
- 按进度小步提交,一个逻辑变更一个 commit

## PR 流程

1. 从最新 `main` 切出规范命名的分支
2. 推送分支并创建 PR,标题与分支语义一致
3. CI 全部通过后 squash merge(`ci.yml` 的 validate + compliance、`link-check.yml`)
4. 合并后确认 head 分支已删除

## Skill 文档约定

- **所有 `SKILL.md` 正文与 frontmatter description 一律使用英文**(触发关键词可按需双语,但正文必须英文)
- `babylon-cad` 顶部保留基于 [Curiosity-Ai-BV/Babylonjs-Skill](https://github.com/Curiosity-Ai-BV/Babylonjs-Skill) 改造的出处标注(CI compliance 会检查)
- skill 内容自包含:不引用本地文档路径,跨 skill 用 skill 名交叉引用
- 修改 skill 后需重新安装并 `/reload` 生效

## 发布(Release)

`kimi.plugin.json` 的 `version` 是发版的唯一事实来源:`release.yml` 在 main 上检测到 version 变化时**自动**打附注 tag(`v<version>`)并创建同名 GitHub Release(`--generate-notes`)。只需两步:

1. 合入 main 后,递增 `kimi.plugin.json` 的 `version`(如 0.7.5 → 0.7.6),commit 为 `chore(release): vX.Y.Z`
2. push 到 main(`release.yml` 自动完成 tag + Release)

Kimi Code 插件管理器按 **GitHub Release** 解析更新(`/plugins` 的 Enter 安装 latest release);只推 main 或只打 tag 都不会被用户端看到。

验证:托管目录 `~/.kimi-code/plugins/managed/d3-project-agent-skills/kimi.plugin.json` 的 version 应为新版本。

(2026-08 踩坑记录:v0.6.0 只推了 lightweight tag 未建 Release,重载后仍停在 v0.5.0。)
