---
name: xstate-interactions
description: "Web CAD 项目:XState v5 state machines and actor model for production apps, especially orchestrating Babylon.js 3D interactions in React. Use when working with XState, state machines, statecharts, actors, @xstate/react (useActor/useActorRef/useSelector), createMachine, setup(), assign, fromPromise, fromCallback, fromObservable, spawnChild, or when wiring XState to imperative APIs like Babylon observables. Covers v5-only patterns, React integration rules, and the Babylon-interaction actor pattern."
---

# XState v5(通用用法)

> 适用范围:通用 XState v5 + React + Babylon.js 用法。与具体仓库的约定冲突时,以该仓库的专属 skill 为准——RaywareNative(RWC 3.0)见 `rwn-xstate-machines`(该仓库是单台 parallel 根机器、guard 经 deps 实时读 store,与本文件部分通用建议不同)。
> 分发注意:本 skill 的 `references/` 目录需连同 `SKILL.md` 一起获取,单独分发 `SKILL.md` 时文末的 references 链接不可用。

## ⚠️ 只用 v5 —— 禁止混用 v4 语法

本项目用 **XState v5**。AI 训练数据里 v4 示例泛滥——混用是代码跑不起来的头号原因。规则:

- ❌ `interpret(machine).start()` → ✅ `createActor(machine).start()`
- ❌ `machine.withContext(...)` / `machine.withConfig(...)` → ✅ `setup({ ... }).createMachine({ ... })`
- ❌ `assign({ count: (context) => context.count + 1 })` → ✅ `assign({ count: ({ context }) => context.count + 1 })`(解构对象参数)
- ❌ 每帧读 `state.context` / `state.matches` → ✅ 一次性读取用 `actor.getSnapshot()`;React 里用 `useSelector` 订阅(绝不按帧轮询)
- ❌ machine options 里的 `send` → ✅ action 接收 `{ self, system }`;多 action 逻辑用 `enqueueActions`
- ❌ `services` → ✅ `actors`;`invoke: { src: promiseFn }` → ✅ `invoke: { src: fromPromise(...) }`

搜文档时永远搜 "XState v5"。示例里出现 `interpret` 就是 v4——直接丢弃。

## v5 核心速查

```typescript
import { setup, createActor, assign, fromPromise, fromCallback } from "xstate";

const machine = setup({
  types: {
    context: {} as { count: number },
    events: {} as { type: "INC" } | { type: "RESET" },
  },
  actions: {
    increment: assign({ count: ({ context }) => context.count + 1 }),
  },
}).createMachine({
  id: "counter",
  initial: "idle",
  context: { count: 0 },
  states: {
    idle: { on: { INC: { actions: "increment" }, RESET: { actions: assign({ count: 0 }) } } },
  },
});

const actor = createActor(machine).start();
actor.send({ type: "INC" });
const snapshot = actor.getSnapshot(); // 只读一次——不要按帧轮询
```

能防住常见错误的关键事实:

- `context` 是不可变的。修改它的**唯一**方式是 `assign`。在 action 里写 `context.foo = x` 不会报错的失效。
- actor 是万物之源:`fromPromise`(异步操作)、`fromCallback`(事件源)、`fromObservable`(RxJS)、机器本身。用 `spawnChild` / `invoke` 组合。
- 清理:`fromCallback` 接收 `({ sendBack, receive, input })`,**必须**返回一个退订函数;actor 停止时 v5 会调用它。

## React 集成(@xstate/react)—— 硬规则

```typescript
import { useActorRef, useSelector } from "@xstate/react";

const actorRef = useActorRef(machine);                       // 稳定引用,状态迁移不触发重渲染
const count = useSelector(actorRef, (s) => s.context.count); // 只有选中的切片变化才重渲染
```

1. **绝不在 render 期间 `actorRef.send(...)`** —— send 只能出现在事件处理器和 effect 里。render 里 send 在 StrictMode/并发渲染下可能死循环。
2. **`useSelector` 配最窄的 selector**,绝不订阅整个 snapshot —— Babylon 交互机器以指针事件频率迁移;订阅整个 snapshot 会让应用每秒重渲染 60+ 次。
3. 默认每个组件实例一个 `useActorRef`。跨组件树共享 actor 用 context 传递,不要重复创建。
4. 副作用(DOM、Babylon、网络)只放在机器 action / invoked actor 里 —— React 组件只渲染 snapshot 和发送事件。

## Babylon.js 交互模式(本项目的核心用法)

架构原则:**Babylon observer 只发送事件;机器 action 只把状态应用到场景。** observer 里没有业务逻辑,guard 和 reducer 里没有 Babylon API 调用。

### 用 fromCallback 包装 Babylon 事件源

```typescript
import { fromCallback } from "xstate";
import type { Scene } from "@babylonjs/core/scene";
import { PointerEventTypes } from "@babylonjs/core/Events/pointerEvents";

// 把场景指针事件转成机器事件的 actor
const pointerSource = fromCallback(({ sendBack, input }: {
  sendBack: (e: any) => void;
  input: { scene: Scene };
}) => {
  const { scene } = input;
  const observer = scene.onPointerObservable.add((info) => {
    if (info.type === PointerEventTypes.POINTERDOWN) {
      sendBack({ type: "POINTER_DOWN", mesh: info.pickInfo?.pickedMesh?.name ?? null });
    }
  });
  // 必须:v5 会在 actor 停止时调用这个清理函数
  return () => scene.onPointerObservable.remove(observer);
});
```

### 从交互机器里 spawn 它

```typescript
const cadInteractionMachine = setup({
  types: { /* context: hovered/selected mesh ids, drag origin, camera mode */ },
  actors: { pointerSource },
}).createMachine({
  id: "cadInteraction",
  initial: "idle",
  // 示意:getScene 是应用自己的 scene 访问器,不是 XState API
  invoke: { src: "pointerSource", input: ({ system }) => ({ scene: getScene(system) }) },
  states: {
    idle: {
      on: {
        POINTER_DOWN: [
          { guard: ({ event }) => event.mesh !== null, target: "dragging",
            actions: assign({ selected: ({ event }) => event.mesh }) },
          { target: "cameraOrbiting" }, // 点到空处 → 相机手势
        ],
      },
    },
    dragging: {
      on: { POINTER_UP: "idle" /* action 里通过 scene API 应用变换 */ },
    },
    cameraOrbiting: { on: { POINTER_UP: "idle" } },
  },
});
```

### 把状态应用回场景

不纯的 Babylon 调用只出现在**状态边沿的 action** 里,绝不出现在 guard 里:

```typescript
entry: ({ context }) => {
  const mesh = scene.getMeshByName(context.selected!);
  if (mesh) mesh.renderOutline = true;   // 场景修改是 action,不是 guard
},
exit: ({ context }) => { /* 清除描边,dispose 掉 entry 里创建的 gizmo */ },
```

`entry` 里创建的 gizmo、highlight layer、工具网格**必须**在对应的 `exit` 里 dispose——不这么做的机器每次状态迁移都在泄漏 GPU 资源。

## 本项目(通用 Web CAD)约定

- **每个交互域一台机器**(`cadInteraction`、`cameraControl`、`partPlacement`),组合在根 system actor 下——不搞一台巨型机器。(⚠️ RaywareNative 例外:它是单台 parallel 根机器,见 `rwn-xstate-machines`。)
- **actor-per-entity**:每个被放置/拖拽的零件配一个 spawn 出来的子 actor(`spawnChild`);父机器按 mesh id 路由事件。`stopChild` 连同其 Babylon 资源一起销毁。
- 机器文件只导出机器,绝不导出已启动的全局 actor——启动发生在 React(`useActorRef`)或根 system 里。
- 事件名用过去式事实(`POINTER_DOWN`、`PART_PLACED`),不用命令式(`handleClick`)。
- guard 保持纯粹(只看 context + event)。任何碰 `scene`、DOM、时间的函数都应该是 action 或 invoked actor。(⚠️ RaywareNative 例外:guard 经 deps 实时读 store,见 `rwn-xstate-machines`。)

## 参考文件

特定主题的详细模式读这些文件(需连同 `references/` 目录一起获取):

- **[testing.md](references/testing.md)** —— 机器和 actor 的单元/异步测试:`createActor` + `getSnapshot` 断言、`waitFor`、`SimulatedClock` 控制 `after`/延迟、用 `machine.provide` mock invoked actor、`fromCallback`/Babylon observer 测试。**给任何机器写或修测试时读这个。**
- **[parallel-states.md](references/parallel-states.md)** —— `type: "parallel"` region、事件广播、经 context 镜像和 `raise` 的跨区域协调、`onDone` 汇合、parallel-state vs 独立 actor 的抉择规则。**把 selection/drag/camera 建模为 parallel region 之前读这个。**(⚠️ 其中 context 镜像的协调方式不适用于 RaywareNative——RWN 禁止镜像,见 `rwn-xstate-machines`。)
- **[actor-supervision.md](references/actor-supervision.md)** —— v5 的错误处理(没有 Akka 式 supervisor):`invoke` `onError`(`xstate.error.actor.*` 事件)、带指数退避的有限重试、`stopChild` 生命周期与 context 引用清理、在 React 里重建崩溃的 actor、隔离 Babylon observer actor。**处理失败、重试或子 actor 崩溃时读这个。**

## AI 错误自查清单(收尾前逐条核对)

1. 没有 `interpret`、没有 `.withConfig`、没有 v4 的 `assign((context) => ...)` 函数形式。
2. context 没有被直接修改;所有变更走 `assign`。
3. React render 期间没有 `send`;只在 observer/handler/effect 里。
4. `useSelector` 用了窄 selector;高频机器没有整 snapshot 订阅。
5. 每个 `fromCallback` 都返回了移除其 Babylon observer 的清理函数。
6. Babylon API 调用只出现在 action / invoked actor;guard 纯粹(或按仓库约定经 deps 读 store)。
7. `entry` 里创建的资源在 `exit` 里 dispose;spawn 的 actor 用 `stopChild` 停止。

这份卡片之外的完整 API 细节,查官方文档:`https://stately.ai/docs/xstate`(永远是 v5)。
