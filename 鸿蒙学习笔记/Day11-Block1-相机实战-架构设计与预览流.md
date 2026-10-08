---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 架构设计
lesson: 相机实战 第 1 课
date: 2026-09-30
project: C:\Users\Linsan\camera
---

# Day11-Block1 相机实战：架构设计与预览流

> [!abstract] 本课目标
> 从零搭一个**符合开闭原则（OCP）**的鸿蒙相机应用骨架，跑通「权限申请 → XComponent surface → Camera Kit 会话 → 全屏预览 → 前后摄切换」完整链路。

> [!important] 架构一句话
> **UI 层 → ViewModel → 领域接口（ICameraService）← 基础设施实现（Camera Kit）**，
> 上层只认识接口；唯一知道具体实现的地方是组装根 `di/ServiceLocator`（依赖倒置 DIP）。

## 分层与目录

| 层 | 目录 | 关键文件 |
|---|---|---|
| UI | `pages/` `ui/tokens/` | CameraPage.ets、CameraTokens.ets（设计令牌） |
| 展示 | `viewmodel/` | CameraViewModel（@ObservedV2 + @Trace） |
| 领域 | `domain/` | CameraTypes、ICameraService —— **禁止 import @kit/@ohos** |
| 基础设施 | `infrastructure/camera/` | CameraServiceImpl（唯一 import @kit.CameraKit 处）、PermissionManager |
| 组装根 | `di/` | ServiceLocator —— 替换实现/Mock 只改这里 |

## Camera Kit 会话组装四步（必背）

```typescript
// 1. 输入流：物理设备
cameraInput = cameraManager.createCameraInput(device);
await cameraInput.open();
// 2. 预览输出流：帧写入 XComponent 的 surface
previewOutput = cameraManager.createPreviewOutput(profile, surfaceId);
// 3. 会话：输入 + 输出 组装
session = cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
session.beginConfig();
session.addInput(cameraInput);   session.addOutput(previewOutput);
// 4. 提交并启动
await session.commitConfig();
await session.start();
```

## 本课新踩的 API 坑（2026 SDK 实测）

> [!warning] 新 SDK 写法变化
> 1. 设备类型枚举是 `camera.ConnectionType.CAMERA_CONNECTION_BUILT_IN`（不是老教程的 `CameraConnection`）
> 2. XComponent 挂载控制器不能再 `.controller()` 链式调用，要用 **XComponentOptions**：
>    `XComponent({ type: XComponentType.SURFACE, controller: this.xComponentController })`
> 3. `Circle.fill/stroke` 是 SDK 26 API，兼容 6.1.1(24) 有风险 → 圆形用 `borderRadius` + `border` 画
> 4. surfaceId 获取：`xComponentController.getXComponentSurfaceId()`，在 `onLoad` 回调里取

## 沉浸式全屏模板（对齐 arkui-immersive-statusbar skill）

- `EntryAbility.onWindowStageCreate`：`setWindowLayoutFullScreen(true)` + 透明系统栏
- 页面 `aboutToAppear`：`getWindowAvoidArea(TYPE_SYSTEM / TYPE_NAVIGATION_INDICATOR)` → `px2vp` 测量
- 背景层 `expandSafeArea([SYSTEM],[TOP,BOTTOM])`；控制层用测得高度做 padding 避让

## ArkTS 严格模式用到的红线

- catch 里 `const err = e as BusinessError` 取 code/message；向上抛必须 `new Error('PREFIX: ...')`
- `build()` 内禁止前置语句（计算放私有方法/字段）
- 颜色 `#AARRGGBB`（alpha 在前）；对象字面量返回值要写显式类型上下文
- 状态管理用 **V1**（2026-09-30 定）：`@Component` + `@State`（页面）+ `@Observed`（ViewModel）；子组件用 `@ObjectLink`，禁 `@Prop` 断链

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [001] | 导入 DevEco 模板 + 架构文档 + 运营脚手架 | Linsan | 2026-09-30 20:44:30 |
| [002] | feat(domain): 领域层抽象 | Linsan | 2026-09-30 20:44:52 |
| [003] | feat(infrastructure): Camera Kit 适配 + 权限 + 组装根 | Linsan | 2026-09-30 20:49:18 |
| [004] | feat(ui): 预览页（V2 状态 + 沉浸式 + 切换） | Linsan | 2026-09-30 20:49:26 |
| [005] | docs(context): 课收尾 + KI-003 | Linsan | 2026-09-30 20:50:28 |
| [006] | refactor(ui): 状态管理 V2 → V1（@State/@Observed） | Linsan | 2026-09-30 21:09:11 |

## 下节课复习题（先做再看新内容）

1. 为什么 `domain/` 里一行 `@kit` import 都不能有？`viewmodel` 想拿到相机能力，依赖的是谁？
2. `startPreview` 之前必须先发生哪两件事？（提示：一个在 EntryAbility，一个在页面回调）
3. `switchCamera` 为什么要先 `closeSession` 再 `openSession`？直接 addInput 换设备行不行？

## 遗留问题

- 预览比例未按 profile 适配（可能拉伸）→ 第 2 课
- 切后台不释放相机 → 第 2 课
- API 可用性警告（targetSdk 26 vs compatible 24）→ 第 2 课评估

## 补记：状态管理统一切到 V1（2026-09-30 晚，提交 [006]）

用户决策：项目与技能库规则都改为**默认 V1**，对齐 15 天计划 Day 4 的装饰器体系。

| 维度 | V1（本项目采用） | V2（仅用户点名才用） |
|---|---|---|
| 页面装饰器 | `@Component` | `@ComponentV2` |
| 页面内状态 | `@State` | `@Local` |
| 对象深度订阅 | `@Observed` 类 + 子组件 `@ObjectLink` | `@ObservedV2` 类 + `@Trace` 属性 |
| 观察粒度 | @State 只看**第一层**属性；嵌套对象要靠子组件 @ObjectLink | @Trace 精确到单个属性 |
| 高频坑 | `@Prop` 传 @Observed 对象会断链 | 无此坑，但资料少 |
| 混用 | V1/V2 装饰器不可混用 | 同左 |

规则落点：项目 `AGENTS.md` 编码规范 + 技能库 `arkui-state-refresh` 开头的「状态管理选型规则」。
