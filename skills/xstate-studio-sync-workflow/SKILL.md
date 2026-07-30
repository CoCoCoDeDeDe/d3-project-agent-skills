---
name: xstate-studio-sync-workflow
description: "Web CAD 项目:XState Studio(stately.ai 图形编辑器)与代码实现双向同步的工作流。Use when the user designs state machines in XState Studio, exports machine code from Studio (setup/createMachine export), asks to sync/verify/对照 a Studio export with the implementation, adds or renames states/guards/actions/events in the machine, mentions tmp-xstate exports, 导入/导出 Studio, or when Studio guard/action source code or Event property schemas disappear after import. Covers the single-direction flow, naming-as-interface contract, and import-loss rules."
---

# XState Studio ↔ 实现 同步工作流

## 核心原则

**结构只在 Studio 改，导出文件绝不手改。** Studio 导出的 `.ts` 文件是只读快照——手改的部分会在下次 Studio 导出时被静默覆盖。实现层只通过「命名」与导出物对接。

**违反单向流 = 改动必然丢失，没有例外。** 需要改结构（状态/事件/转移/guard 名/action 名）时，正确动作是让用户在 Studio 里改并重新导出，不是你编辑导出文件。

## 三层职责（命名即接口）

| 层 | 职责 | 谁编辑 |
|---|---|---|
| Studio 图 | 状态结构、转移、guard/action **命名**、context 派生的简单 guard 逻辑 | 用户（图形界面） |
| Studio 导出物（如 `tmp-xstate.ts`） | 只读快照，结构评审用 | 无人（导出生成） |
| 实现层（如 `interactionSystem.machine.ts`） | 全部业务逻辑：store/scene 副作用的 action、读外部状态的 guard、拖拽上下文等 | 代码仓库 |

两侧靠 **guard/action/事件/状态的命名** 对接：实现层按导出物里的名字注册实现。重命名任何一侧，另一侧必须同步。

## 导入丢失规则（为什么以导出为主）

Studio 从外部 Import 代码后会丢失：

- Guard sources / Action sources 的函数体源码（只剩 `return true` 占位）
- Event property schemas 的自定义配置

因此：**以导出为主、尽量不再导入**。必须导入时，导回前要在 Studio 里手动补回这些源码，否则会丢。

## 同步流程（Studio → 代码）

1. 用户 Studio 改图 → 导出覆盖导出物文件
2. **先读再改**：导出物随时被重新导出，动手前必须重新 Read，不能凭记忆
3. Diff 结构 delta：状态节点、事件类型、转移分支、guard/action 命名（分支顺序差异不算 delta——实现层可能从数组派生）
4. 实现层按命名对齐：新增/重命名 guard、action、状态节点、事件 payload 类型
5. 跑项目测试 + 类型检查，全绿后 commit

## 同步流程（代码 → Studio）

实现层新增的**命名**（guard/action/状态/事件）必须回同步到 Studio 图，否则下次导出实现层会对不上号。流程：提醒用户在 Studio 补同名元素（可先挂占位逻辑），重新导出后再核对。典型漏网：实现层给转移加了新 action（如 `handleDragEnd`），导出物里没有。

## 一致性检查清单（被问"两侧是否同步"时）

- 状态树逐节点比对（含 parallel region、子状态、initial）
- 事件类型集合 + payload 字段（实现层类型收紧不算 delta，如 `string` → `ToolId | null`）
- guard/action 命名集合两侧一致；Studio 里 `return true` 占位是正常的，实现层有真逻辑即可
- 行为等价差异要识别：显式吞噬分支 vs 冒泡兜底、互斥 guard 的分支顺序——这些不算不同步
- 状态机之外的行为（事件适配层、手势翻译、节流抑制）不在同步范围——不要把 adapter 层改动误判为设计稿落后

## 常见失败模式（基线实测）

| 失败 | 后果 | 正确做法 |
|---|---|---|
| 手改 Studio 导出文件"保持同步" | 下次导出静默覆盖，改动蒸发 | 让用户在 Studio 改，重新导出 |
| 只改实现层结构，不回同步 Studio | 双向漂移，导出后命名对不上 | 命名变更必须双向都有 |
| 凭记忆改导出物/实现层 | 用户刚在 Studio 改过，基于旧版本改错 | 动手前重新 Read 导出物 |
| 把 guard 业务逻辑写进 Studio 源码 | 导入丢失，或被占位覆盖 | 业务逻辑只在实现层，Studio 只留命名和 context 派生逻辑 |

## 红线

- 绝不用 Write/Edit 修改 Studio 导出物（除非用户明确说"这个文件以后不再从 Studio 导出"）
- 绝不跳过重新 Read 直接改实现层
- 命名变更不双向同步 = 埋雷
