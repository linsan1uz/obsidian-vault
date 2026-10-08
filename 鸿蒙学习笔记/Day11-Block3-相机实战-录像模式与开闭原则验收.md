---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 架构设计
lesson: 相机实战 第 3 课
date: 2026-10-03
project: C:\Users\Linsan\camera
---

# Day11-Block3 相机实战：录像模式与开闭原则验收

> [!abstract] 本课目标
> 把"拍照应用"扩展成"照片 + 录像双模式"，并当堂验收第 1 课的分层架构：
> 新增能力应该表现为**加文件**，而不是改旧文件。

## OCP 验收报告（git diff 实证）

- **新增 6 文件**：ICaptureMode（SPI）、ModeRegistry（注册表）、ProfilePicker（共享策略）、
  PhotoMode（拍照流迁移）、VideoMode（录像链）、ModeSwitcher（UI 组件）
- **修改 8 文件**：全部是声明级接线（枚举值、接口方法签名、注册一行、组件引用）
- **零 if-else 模式分叉**：模式差异全部封装在策略对象里

## 核心设计：策略模式 + 注册表

```
ICameraService.capture()/startRecording()/stopRecording()
        │ execute(ModeCommand) 转发
        ▼
currentMode: ICaptureMode ◀── ModeRegistry（PhotoMode / VideoMode / …）
```

- **SPI 放在 infrastructure 而非 domain**：它必须操纵 camera.Session 等平台类型；
  domain 只暴露 `CameraMode` 枚举——务实取舍，不为纯度硬造包装层
- **命令用枚举路由**：模式自己校验支持的命令，不支持抛 `MODE_COMMAND_UNSUPPORTED:`
- **服务瘦身为会话骨架**：createSession(currentMode.sceneType) 铸造对应会话，
  输出流的创建/释放/拆卸清单全部委托给模式

## 录像链路（VideoMode）

```
AVRecorder.prepare(fd://xxx) → getInputSurface() → createVideoOutput(profile, 该surface)
会话组装（NORMAL_VIDEO + VideoSession） → recorder.start() → stop() → 封装 mp4
```

- **一段录像一个 recorder**：stop 后 release，下次 START 重建 recorder 并把
  新 VideoOutput **热插拔**进会话（beginConfig → removeOutput 旧 → addOutput 新）
- fd 自己开自己关；release 兜底（录制中退后台也安全）

> [!warning] 2026 SDK 录像 API 实测（旧教程编译不过）
> - `VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_ES`（非 SURFACE）
> - `CodecMimeType.VIDEO_AVC`（非 VIDEO_H264）
> - `AVRecorderProfile.videoFrameWidth/Height`（非 videoWidth/Height）
> - **相机侧没有 AudioInput**：录音由 AVRecorder 的 audioSourceType 直采

## UI：第一个 @ObjectLink 子组件

`ModeSwitcher` 用 `@ObjectLink vm` 订阅（@Prop 会拷贝快照断链），
快门路由进 ViewModel 的 `onShutterClick()`：拍照→capture；录像→start/stop。
页面保持"无脑转发"，录制中内圈变红。

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [011] | refactor(camera): 模式抽象落地（SPI + 注册表 + 策略对象 + 录像 + 麦克风权限） | Linsan | 2026-10-03 00:24:37 |
| [012] | feat(ui): 模式切换条 + 快门行为随模式 | Linsan | 2026-10-03 00:24:38 |

## 第 4 课复习题（相册保存：photoAccessHelper + SaveButton）

1. 为什么写系统相册不能直接用文件路径，而要走 `photoAccessHelper`？沙箱路径和媒体库 URI 的区别是什么？
2. `SaveButton` 安全控件为什么能"免权限"保存？它的授权时机和普通权限弹窗有什么不同？
3. 拍照/录像落盘现在在 infrastructure 里直接写 `filesDir`，要接入相册时这个职责应该挪到哪一层？新增什么接口？
