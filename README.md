# d3-project-agent-skills

个人 AI coding agent skills 仓库,服务于我的 3D 打印 Web CAD 项目。

技术栈:**React 18 + Babylon.js 8 + XState v5**,另有 AWS Lambda 后端。

## Skills

| Skill | 说明 |
| --- | --- |
| `babylon-cad` | Babylon.js 8 开发手册:场景/网格/材质/相机/灯光/GUI/动画/资产加载/性能优化/React 集成,以及面向 CAD 与 3D 打印的参数化建模(CSG2、车削、放样、动画就绪的父子枢轴层级)。 |
| `cad-interactions` | Babylon.js CAD 交互原语:gizmo、拖拽平面、吸附、选择、快捷键、undo/redo 命令栈,以及与 XState 的分层边界。 |
| `xstate-interactions` | XState v5 状态机手册:v5-only 语法规则、@xstate/react 集成铁律、Babylon 交互 actor 模式(observers 只发事件,machine actions 只写场景)。 |
| `rwn-xstate-machines` | RaywareNative(RWC 3.0)的 XState 机器开发规范:parallel shadowing 陷阱、守卫实时读 store、swallow 拦截、设计三问。 |
| `xstate-studio-sync-workflow` | RaywareNative 的 XState 实现 ↔ Stately Sketch 同步工作流:Sketch 脚本模式约束、粘贴版生成器、命名即接口、一致性核对清单。 |
| `rwn-development` | RaywareNative(RWC 3.0)开发规范:验证命令集、CI 纪律、注释/测试/icon/i18n 规则、双 runtime seam、XState Sketch 同步。 |
| `dev-conventions` | 跨仓库/跨语言通用开发纪律:commit 前验证、缓存陷阱、各语言检查工具映射。 |
| `git-stacked-branches` | Squash 合并 + 栈式分支工作流:父 PR 合入后子分支冲突机理与处理、本地/远程/worktree checkout 陷阱。 |
| `skill-creator` | Skill creation, evaluation and optimization workflow (create → test → review → improve loop, trigger-description optimization via `kimi -p`). Adapted from [anthropics/skills](https://github.com/anthropics/skills/tree/main/skills/skill-creator) for Kimi Code. |
| `lambda-deploy` | (预留)AWS Lambda 部署工作手册,待实现。 |

## 安装

本仓库是一个 Kimi Code 插件(含 `kimi.plugin.json`):

```sh
# 从 GitHub 安装
/plugins install https://github.com/CoCoCoDeDeDe/d3-project-agent-skills

# 或从本地路径安装
/plugins install <本地路径>/d3-project-agent-skills
```

安装后运行 `/reload` 或 `/new` 生效。

也可以直接把 `skills/` 下的目录符号链接到 `~/.kimi-code/skills/` 作为普通 user skills 使用,或链接到 dsh 的项目技能根(`<项目根>/.dsh/skills/`)在 DeepSeek Harness 中使用。

## 仓库结构

```
d3-project-agent-skills/
├── README.md
├── LICENSE                  # MIT
├── kimi.plugin.json
├── scripts/
│   └── check-doc-urls.sh      # doc-urls.md 死链校验(只需 bash + curl)
└── skills/
    ├── babylon-cad/
    │   ├── SKILL.md
    │   └── references/
    ├── cad-interactions/
    │   ├── SKILL.md
    │   └── references/
    ├── dev-conventions/
    │   └── SKILL.md
    ├── git-stacked-branches/
    │   └── SKILL.md
    ├── rwn-development/
    │   └── SKILL.md
    ├── rwn-xstate-machines/
    │   └── SKILL.md
    ├── skill-creator/
    │   ├── SKILL.md
    │   ├── LICENSE.txt
    │   ├── agents/
    │   ├── assets/
    │   ├── eval-viewer/
    │   ├── references/
    │   └── scripts/
    ├── xstate-interactions/
    │   ├── SKILL.md
    │   └── references/
    └── xstate-studio-sync-workflow/
        └── SKILL.md
```

## License

[MIT](LICENSE)
