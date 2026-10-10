---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 手势交互
lesson: 相机实战 第 5 课
date: 2026-10-08
project: C:\Users\Linsan\camera
---

# Day11-Block5 相机实战：手势变焦 / 闪光灯 / 曝光

> [!abstract] 本课目标
> 在预览画面上加双指捏合变焦，控制栏加闪光灯模式切换与曝光补偿，
> 全部走「UI → ViewModel → domain 接口 → 会话能力」的既有链路，不动分层。

## 开课复习题（第 1~4 课）

### 第 1 题（依赖倒置 DIP）⏳ 待答

**Q**：domain 层禁 import `@kit`/`@ohos` 是为什么？「ViewModel → ICameraService ← CameraServiceImpl，
由 ServiceLocator 组装」这个方向里，谁依赖谁？「倒置」二字体现在哪？
（上节课这题你是听我讲的，这次试着自己输出）

### 第 2 题（V1 状态管理）⏳ 待答

**Q**：场景题——ModeSwitcher 把 `@ObjectLink vm` 改回 `@Prop vm`，用户点「录像」后会发生什么？
请分别描述 **UI 显示什么** 和 **内核实际执行了什么**，以及为什么会分家。

### 第 3 题（会话生命周期）⏳ 待答

**Q**：为什么切模式（拍照↔录像）和切前后摄都走「整个关掉会话再重建」，
而不是往现有会话里加/换一路流？（提示：会话种类在哪一步定死；「换车不改装」）

### 第 4 题（相册入库两条授权路线）⏳ 待答

**Q**：第 4 课先后落地了 SaveButton 安全控件 [014] 与 WRITE_IMAGEVIDEO 常规权限 [016] 两条路线。
各说一条核心区别（授权时长 / 触发方式 / 交互），以及我们最后为什么选了后者？

## 课程正文

### d.ts 考古：三个能力全部挂在会话上

```
PhotoSession extends Session, Flash, AutoExposure, WhiteBalance, Focus, Zoom, ...
VideoSession extends Session, Flash, AutoExposure, ..., Zoom, Stabilization, ...
```

- 变焦 `Zoom`：`getZoomRatioRange()/getZoomRatio()/setZoomRatio(r)`——数码变焦 = 中央裁切放大
- 闪光 `Flash`：`setFlashMode(FlashMode)`，枚举 `CLOSE=0/OPEN=1/AUTO=2/ALWAYS_OPEN=3`
- 曝光 `AutoExposure`：`getExposureBiasRange()`（EV 范围）+ `setExposureBias(ev)`
- 老 `CaptureSession` 自 API 11 整类废弃 → 教程抄老代码编译不过（教程会老，d.ts 是真相）

### 知识点 1：手势变焦（why → how）

- 捏合变焦是相机 App 肌肉记忆；手势 = UI 层只负责「手指动作 → 数字」
- 三段接力：`PinchGesture → VM.updatePinch(scale) → setZoom(ratio) → session.setZoomRatio`
- **`e.scale` 是相对起手的总比例，不是每帧增量** → 起手记 `baseZoom`，
  更新算 `target = base × scale` 夹紧下发；否则 3x 起手一捏会跳回 1.3x
- **显示不撒谎**：会话重建（切模式/切镜头/前后台）= 换车 → 硬件变焦归位，
  VM 必须读回 `getZoom()` 真值（呼应 @ObjectLink「复印件会撒谎」）

### 知识点 2：会话参数的生命周期（本课真正的架构题）

参数长在会话上，而会话会被整段重建——「状态存哪、何时重放」：

| 参数 | 策略 | 理由 |
|---|---|---|
| 闪光 / 曝光 | **impl 存期望值，`openSession` 尾部重放**（同 activePosition 保留-重放） | 用户设过一次不该被重建清掉；VM 显示的用户意图即真值 |
| 变焦 | **不保留，重建后读回真值** | 真机惯例切镜头归位；前后摄范围不同，强留必失真 |

- 闪光只在「拍照模式 + 后摄」应用（前摄无闪光硬件；录像会话闪光是补光语义）
- 单指上下拖 = 曝光补偿（`offsetY` 向下为正 → EV 取负，0.1 档步进，每 50vp≈1 档）
- 双指捏合时 `pinchActive` 标记让单指拖曝光让路（Parallel 手势组防打架）

### 2026 SDK 实测坑（旧教程会挂）

- GestureEvent 位移字段是 **`offsetX/offsetY`**（不是 translationX/Y）
- **`GestureGroup(mode, ...gestures)` 第二参是可变参数**，传数组报 10505001
- `createSession<T extends Session>(sceneMode)` 泛型直取能力宿主类型，
  会话字段类型必须是 `PhotoSession | VideoSession`（基类 Session 没有这些能力方法）

### 架构落点（OCP 验收）

- domain：`NumericRange`/`CameraFlashMode` 纯类型 + ICameraService 6 个**同步**方法
- infra：期望值存储 + 重放 + 能力方法（PhotoMode/VideoMode/GallerySaver **零改动**）
- VM：三态 + beginPinch/updatePinch/beginPan/updatePan/cycleFlash + 四处 syncSessionParams
- UI：`GestureGroup(Parallel)` 双手势、顶栏闪光按钮、变焦/EV 浮层（chip 令牌）

## 真机验证清单（待用户执行）

1. 双指捏合 → 画面放大，顶部浮层显示 `Nx`；松手保留；切前后摄 → 回到 `1x` 浮层消失
2. 单指上下拖 → 画面明暗变化，顶部显示 `EV ±x.x`；捏合时拖动不误调曝光
3. 后摄拍照模式 → 顶栏右侧「闪光自动 → 闪光开 → 闪光关」循环
4. 切到录像模式/前摄 → 闪光按钮消失；切回 → 之前设的闪光状态还在（重放生效）
5. 拍照 → 相册自动可见（[016] 回归）

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [018] | feat(camera): 手势变焦 + 单指曝光 + 闪光控制（会话参数保留-重放） | Linsan | 2026-10-10 20:33:44 |
