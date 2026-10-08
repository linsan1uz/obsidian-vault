---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 异步编程
lesson: 相机实战 第 2 课
date: 2026-09-30
project: C:\Users\Linsan\camera
---

# Day11-Block2 相机实战：拍照流与生命周期

> [!abstract] 本课目标
> 上半场：按快门 → 照片落盘沙箱 → 缩略图 + 快门反馈，修 KI-001（预览拉伸）。
> 下半场：切后台释放相机、回前台恢复，修 KI-002——顺便学 V1 跨层通信。

## 上半场：拍照流三个概念

1. **PhotoOutput 与 PreviewOutput 是兄弟**：一条会话可并列多条输出流（直播 + 出片）。
2. **照片的一生（异步链）**：
   `capture()` 挂起 Promise → 硬件出图 → `photoAvailable` 回调 → `getComponent(0)` 取 JPEG 字节 → fileIo 写沙箱 → resolver(path) 兑现 → VM 更新 `lastPhotoPath` → 缩略图自动出现。
3. **双层 finally 资源纪律**：文件句柄必关（内层）、Image 的 native 内存必放（外层）。

> [!warning] 2026 新 SDK 实测变化（旧教程会编译不过）
> - `Photo.mainImage` 已更名为 **`Photo.main`**
> - `on('photoAvailable')` 回调首参是 **BusinessError**（不是 CameraErrorCode）
> - 桥接模式：把 Promise 的 resolve 存成员变量，回调送达时兑现（回调世界 → await 世界的翻译器）

## UI 三件套

- 闪白：常驻白幕 + `opacity 0↔0.8` + `.animation({duration:100})` + setTimeout 收场
- 快门按压：`.onTouch` 判 `Down/Up/Cancel` → `@State shutterPressed` → `.scale()` 缩放
- 缩略图：`Image('file://' + 沙箱路径)`；KI-001 用 `.aspectRatio(预览宽/高)` 修复

## 下半场：生命周期与 V1 跨层通信（KI-002）

```
EntryAbility.onBackground ──AppStorage.setOrCreate('app_foreground', false)
                                     │ 广播
CameraPage @StorageProp('app_foreground') @Watch('onAppForegroundChange')
                                     │ 单向订阅
                     false → vm.pause()（closeSession 保留 surfaceId）
                     true  → vm.resume()（openSession 重建会话接回同一 surface）
```

- `@StorageProp` 单向读 vs `@StorageLink` 双向写：页面只读广播就用 Prop
- `@Watch('方法名')` 收变化通知，回调签名 `(propName: string): void`
- 服务层保留 `surfaceId / activePosition / lastPreviewSize` 字段，pause 不清空——恢复就是"重新开机"而不是"重新插线"

## 异步复习战果（本课前置复习）

> [!important] await 三步公式
> 遇到 await：① 立刻启动它身后的任务 ② 当前函数原地冻结（只冻自己，线程照常渲染响应）③ 任务出结果 → 从下一行复活。
> 调用 async 函数 = 执行到第一个 await + 返回小票；不 await = 发射后不管，错误由函数内部 try/catch 兜住转状态。

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [007] | feat(camera): 拍照能力接入 | Linsan | 2026-09-30 23:52:32 |
| [008] | feat(ui): 快门交互 + KI-001 修复 | Linsan | 2026-09-30 23:52:33 |
| [009] | feat(camera): 生命周期 pause/resume 能力 | Linsan | 2026-09-30 |
| [010] | feat(app): 前后台桥修复 KI-002 | Linsan | 2026-09-30 |

## 第 3 课复习题（录像模式：用 ICaptureMode 验证开闭原则）

1. 为什么加"录像模式"时，理想的 diff 是**只加文件不改旧文件**？哪一层最容易被迫改？怎么用接口避免？
2. 录像需要新增哪些输出流和哪些权限？`AudioRecorder`/`AVRecorder` 负责什么？
3. 模式切换时（拍照→录像），会话为什么要整个重建？和前后摄切换是同一个理由吗？

## 遗留问题

- KI-003：SDK 基线差异警告（开放）
- KI-004：沙箱照片未入系统相册 → 第 4 课 photoAccessHelper + SaveButton
