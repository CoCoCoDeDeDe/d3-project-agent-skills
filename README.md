# d3-project-agent-skills

个人 AI coding agent skills 仓库,服务于我的 3D 打印 Web CAD 项目。

技术栈:**React 18 + Babylon.js 8 + XState v5**,另有 AWS Lambda 后端。

## Skills

| Skill | 说明 |
| --- | --- |
| `babylon-cad` | Babylon.js 8 开发手册:场景/网格/材质/相机/灯光/GUI/动画/资产加载/性能优化/React 集成,以及面向 CAD 与 3D 打印的参数化建模(CSG2、车削、放样、动画就绪的父子枢轴层级)。 |
| `xstate-interactions` | XState v5 状态机手册:v5-only 语法规则、@xstate/react 集成铁律、Babylon 交互 actor 模式(observers 只发事件,machine actions 只写场景)。 |
| `xstate-studio-sync-workflow` | XState Studio ↔ 代码实现同步工作流:单向流铁律(结构只在 Studio 改,导出文件绝不手改)、命名即接口三层职责、导入丢失规则、双向一致性检查清单。 |
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

也可以直接把 `skills/` 下的目录符号链接到 `~/.kimi-code/skills/` 作为普通 user skills 使用。

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
    ├── xstate-interactions/
    │   ├── SKILL.md
    │   └── references/
    └── xstate-studio-sync-workflow/
        └── SKILL.md
```

## License

[MIT](LICENSE)
