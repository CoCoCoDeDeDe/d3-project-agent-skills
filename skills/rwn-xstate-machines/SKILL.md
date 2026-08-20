---
name: rwn-xstate-machines
description: "RaywareNative (RWC 3.0) 的 XState 机器开发规范:parallel 机器的 shadowing 陷阱、守卫实时读 store、Sketch 兼容格式。Use when editing or reviewing interactionSystem.machine.ts or other XState machines in the RaywareNative repo — adding states/transitions/events/guards, wiring deps, or reviewing machine diffs. NOT for generic XState usage (xstate-interactions) or the Sketch paste/再生 workflow (xstate-studio-sync-workflow)."
type: prompt
whenToUse: When editing, extending, or reviewing XState machine files in the RaywareNative repository (graphics/machines/), including adding states/transitions/events, wiring deps implementations, or changing how the machine reads external stores.
---

# RaywareNative XState 机器规范

> 只适用于 RaywareNative(RWC 3.0)。通用 XState 用法见 `xstate-interactions`;Sketch 粘贴版生成与可视化核对流程见 `xstate-studio-sync-workflow`。

## Parallel 机器的 shadowing 陷阱(最容易踩的坑)

RWN 的 interaction machine 根是 `type: 'parallel'`。**某个 region 处理了事件,根节点自己的 `on` handler 就不会执行**——这不是"都会跑",是互斥回落。

后果模式:根级 `LOADING_STARTED: { actions: [清理...] }` 这类"广播清理"会被任何 region 内的同名转换遮蔽。踩过的实际 bug:hover/预选中清理在 orientation 子态打开时被吞掉,高亮残留整个 loading 期间。

规则:

- 给任何 region 加广播类事件(LOADING_STARTED 等)的转换时,**检查根级同名 handler 的 action 是否需要在该子转换上重复**
- review 机器 diff 时,对每个新增的子态事件转换问一句:"它遮蔽了根的什么?"
- 回归测试:`snapshot.context` 断言清理发生(参考 `tests/unit/editToolRegistry.test.ts` 里 "loading started inside an orientation mode still clears hover and preselect state")

## 守卫读实时状态,不做镜像

- loading/dragging 这类外部状态,守卫里**实时读 store**(`deps.isLoading()` 读 zustand),不在 machine context 里维护镜像——镜像会产生 reconciling 负担和过期窗口
- 事件只作为"边沿通知"(如 LOADING_STARTED 用于清理),状态本身永远以 store 为准

## 命名即接口

- deps 的 guard/action/event 名字是 machine 文件与实现层之间的接口,两侧同步(含分支顺序)
- machine 文件保持 Sketch 兼容:runtime import 只有 `xstate`、无 `enum`(const object + `as const`)、非 xstate 引用走 deps 或 type-only import;结构改动后重跑 `npm run sketch:interaction-machine` 生成粘贴版(产物在 `out/`,不提交)

## 测试约定

- 机器测试用 `snapshot.matches(partialValue)` 子集匹配,一个用例只断言它命名的维度
- inert deps 全量提供(新增 deps 成员时测试 mock 要同步补,`editToolRegistry.test.ts` 是宿主)
