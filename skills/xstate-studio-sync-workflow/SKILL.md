---
name: xstate-studio-sync-workflow
description: "Web CAD 项目:XState 状态机实现与 Stately Sketch 可视化同步的工作流(原 Studio 导出流程已废弃)。Use when the user pastes machine code into Stately Sketch for visualization, asks to 可视化/检查状态机图, reports Sketch syntax errors (Cannot use import/export statement, enum parse failure), regenerates the Sketch paste version, adds or renames states/guards/actions/events in the machine, or asks whether the machine and its Sketch diagram are in sync. Also covers legacy Studio export files (tmp-xstate.ts style) if they resurface. Covers the Sketch script-mode constraints, the paste-version generator, and the naming-as-interface contract."
---

# XState 实现 ↔ Stately Sketch 同步工作流

## 核心原则(现工作流,后 Studio 时代)

**实现侧机器文件(如 `interactionSystem.machine.ts`)是唯一事实源——AI/用户直接改它。** Stately Sketch 只是只读的可视化/review 面:用户把**生成的**粘贴版粘进 Sketch 检查图结构。没有导出文件层,也没有反向通道——要改结构就改实现、重新生成、重新粘贴。

遗留说明:如果旧的 Studio 导出文件(如 `tmp-xstate.ts`)再次出现,把它当作只读快照,把其中的结构迁移进实现文件,而不是复活导出工作流。

## Sketch 硬约束(源文件约定为什么是这样)

Sketch 把粘贴的代码当作普通 script 求值,因此有两个语法家族永远到不了它:

1. **没有任何 `import` / `export` 语句**——包括 xstate 的 import,也包括 `import type`。Sketch 在**第一行** import 就抛 `SyntaxError: Cannot use import statement outside a module`。
2. **没有 TS `enum`**——Sketch 的解析器拒绝它。用 const object + `as const` + 同名 type:
   `export const ToolId = { Orientation: 'orientation', ... } as const; export type ToolId = (typeof ToolId)[keyof typeof ToolId];`

这些约束会**反向渗入**源文件的约定,好让粘贴转换保持机械简单:

- 所有非 xstate 引用一律走 `deps` 注入或 type-only import(type import 可擦除,生成器会剥掉)。
- 机器文件里绝不引入来自其他本地模块的 runtime import。

## 粘贴版生成器

每次结构改动后重新生成;绝不手改产物:

```bash
npm run sketch:interaction-machine   # → out/sketch/interactionSystem.machine.sketch.ts(gitignored)
```

转换刻意做得很笨:删掉 `import ...` 行、剥掉行首 `export `、前置类型桩(`type Mesh = any` 等)和 xstate 辅助函数的兜底实现(`and`/`not` 被忠实重实现;`stateIn` 兜底为 `() => false`,即"不在拖拽",这样 SELECT_TOOL/快捷键在模拟里保持可操作)。`setup`/`assign` 假定在 Sketch 里是全局存在的——如果 Sketch 报它们 undefined,那是生成器的问题,不是源文件的问题。

## 命名即接口

Sketch 展示的是 state、transition、event 和 guard/action 的**名字**。所有业务逻辑都藏在这些名字背后的实现里(guard 经 `deps` 读 store、action 做场景/store 副作用)。推论:

- 任何一侧改名必须立刻镜像到另一侧,否则图悄悄指向空气。
- 排查"Sketch 里行为不符合预期"的报告时,先查相关 guard 是否读外部状态(经 deps 读 store)——**Sketch 模拟里没有 store**,这类 guard 按兜底逻辑而非真实逻辑行为。这是可视化假象,不是机器 bug。

## Sketch Simulate 的预期偏差(不要当 bug 报)

Simulate 跑的是粘贴版,deps 不存在,所有读外部状态的 guard 都按兜底行为:

- `stateIn(...)` → 恒 `false`(例如永远"不在拖拽中");
- 自定义 guard(`notLoading`、`notProcessing` 等)→ 按生成器桩的默认返回,**不反映真实 store 状态**。

因此"loading/processing 中某 transition 在 Simulate 里仍然跳得过去"是**预期现象**——拦截逻辑依赖真实 store,只能在应用里验证。Sketch 用来核对的是图结构(状态树、事件、分支),不是 guard 的运行时结果。

## 一致性核对清单(被问"图和代码一致吗"时)

- **先**重新生成粘贴版(`npm run sketch:interaction-machine`)再比对——绝不和过期的粘贴版比。
- 逐节点比对状态树(parallel region、子状态、`initial`)、事件类型集合、guard/action 名字集合。
- 识别行为等价的差异:显式 swallow 分支 vs 冒泡回落、互斥 guard 的分支顺序、实现侧收窄 payload 类型(`string` → `ToolId | null`)——这些**不是**失同步。
- 机器之外的行为(event adapter 层、手势翻译、store 侧 reconciler)不在同步范围内。

## 常见失败模式

| 失败 | 后果 | 正确做法 |
|---|---|---|
| 手改生成的粘贴版 | 下次重新生成被覆盖,改动蒸发 | 改源机器文件,重新生成 |
| 机器文件里加 runtime import 或 enum | Sketch 粘贴报语法错误 | 引用走 deps/type-only import;用 const object 代替 enum |
| 把 Sketch 模拟行为当 bug 报 | 误报——Sketch 没有 store/deps | 先查 guard 是否读外部状态;在应用里验证 |
| 凭对图的记忆改机器 | 图只是可视化,不是事实源 | 动手前重新 Read 机器文件 |

## 红线

- 绝不 Write/Edit 生成的粘贴版(`out/sketch/*.sketch.ts`)。
- 绝不让 runtime 非 xstate import 或 TS enum 进入机器文件。
- 改名没有同时体现在代码和下一次粘贴里 = 埋雷。
