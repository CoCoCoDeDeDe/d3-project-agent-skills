# Contributing

本仓库的 Git 开发规范。所有变更（包括维护者本人）都应遵循。

## 分支命名

格式：`<type>/<issue号>-<短描述>`

- `type` 与 Conventional Commits 对齐：`feat` / `fix` / `docs` / `ci` / `chore`
- 有对应 issue 时携带编号，如 `docs/8-contributing`；无 issue 可省略编号
- 短描述：全小写英文、连字符分隔，整个分支名 ≤ 50 字符
- 一分支一 PR，不混装多个不相关变更
- `main` 是唯一常驻分支，不直接向其 push 开发提交
- PR 合并后删除 head 分支（仓库已开启自动删除）

反例：`2026-0730-my-laptop-work`、`new-feature`

## Commit message

- 英文 [Conventional Commits](https://www.conventionalcommits.org/)：`type: 描述`，如 `docs: add CONTRIBUTING.md`
- type 取值与分支 type 一致：`feat` / `fix` / `docs` / `ci` / `chore`
- 按进度小步提交，一个逻辑变更一个 commit

## PR 流程

1. 从最新 `main` 切出规范命名的分支
2. 推送分支并创建 PR，标题与分支语义一致
3. CI 全部通过后 squash merge（`ci.yml` 的 validate + compliance、`link-check.yml`）
4. 合并后确认 head 分支已删除

## Skill 文档约定

- `babylon-cad` 正文使用英文，顶部保留基于 [Curiosity-Ai-BV/Babylonjs-Skill](https://github.com/Curiosity-Ai-BV/Babylonjs-Skill) 改造的出处标注（CI compliance 会检查）
- `xstate-*` 系列 skill 的 description 带 `Web CAD 项目：` 前缀
- 修改 skill 后需重新安装并 `/reload` 生效
