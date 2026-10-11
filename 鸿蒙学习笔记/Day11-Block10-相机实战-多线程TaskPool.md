---
tags:
  - 鸿蒙
  - ArkTS
  - 相机实战
课次: Day11-Block10（第 10 课）
日期: 2026-10-11
主题: 多线程——TaskPool 下放主线程重 I/O
---

# Day11-Block10：多线程 TaskPool

> [!info] 复习题
> 欠账制已取消（2026-10-11 用户决策），开场不再安排必答复习题。

## 痛点引入（为什么）

> [!question] 拍完照到「已保存到相册」弹出的那一瞬间，画面卡不卡？
> 答案藏在代码里：**入库的分块拷贝循环是同步 I/O，跑在主线程上**。一张十几 MB 的照片 =
> 主线程上几十次「读 512KB + 写 512KB」的同步循环；照片落盘更是整张 buffer 一次 `writeSync`。
> **做多少毫秒，画面就卡多少毫秒**——模拟器上没感觉是因为拍照链路断着（KI-007），真机上就是拍照后瞬间的掉帧。

## 知识点 1：主线程模型与「毒药」

鸿蒙 ArkUI 应用默认**一个主线程**跑 UI + JS 逻辑（单线程事件循环）。类比：前台只有一位厨师长，
又要点单（响应用户手势）、又要颠勺（渲染）、还要自己杀鱼（同步 I/O）——杀鱼的时候没人接待。

**主线程毒药清单**：一切 `*Sync` 文件 I/O、大 JSON.parse、图像处理、加密计算。
病征：动画掉帧、手势跟手性变差、点击响应迟钝。

## 知识点 2：TaskPool vs Worker（选型）+ @Concurrent 规矩

| | TaskPool | Worker |
|---|---|---|
| 类比 | 外包零工平台 | 常驻员工 |
| 生命周期 | 系统调度、干完即走、自动扩缩 | 自己创建、自己 release 养到老 |
| 适合 | **短平快任务**（拷贝、解码、落盘） | 长驻轮询、高频消息往来 |
| 我们的选择 | ✅ 入库拷贝、照片落盘 | （暂无用武之地） |

**@Concurrent 三条硬规矩**（编译器会查）：
1. **顶层函数**——不能是类方法；
2. **参数只发「复印件」**——可序列化类型（string / number / boolean / ArrayBuffer / 普通对象），
   不能传 `this`、不能传函数。类比：给外包发需求单只能发复印件，不能把公司印章寄过去；
3. **不捕获闭包**——要用什么就当参数传（chunkSize 因此移进函数体内定义，不能引类静态成员）。

**为什么 `createAsset` 留在主线程？** 两个理由：
- 它需要 **Context**——Context 不可序列化，「身份凭证」当然不能复印；
- 它本身是**异步系统调用**，await 期间主线程是自由的，不构成阻塞。

## 实现走读（[028]）

```typescript
@Concurrent
function copySandboxToGallery(srcPath: string, destUri: string): void {
  // 分块读写循环 + 耗时日志（Date.now 在 TaskPool 线程可用）
}

// 主线程只剩一句话：
await taskpool.execute(copySandboxToGallery, sandboxPath, uri);
```

- 同款套路第二处：`PhotoMode.savePhoto` 的整张照片写盘 → `@Concurrent writePhotoToSandbox(path, buffer)`，
  **ArrayBuffer 可以直接当参数传**（taskpool 支持转移大块内存）。
- 对上层的接口（IMediaSaver）、ViewModel、UI **零改动**——线程模型是基础设施的实现细节，
  这就是第 1 课埋的依赖倒置在这里的回报。

## 实测（编译期）

- `@Concurrent` 是语言内置装饰器，无须 import；`taskpool` 从 `@kit.ArkTS` 导入
- 任务函数内可用 import 的模块（fileIo / Logger）和 Date.now
- 一把编译通过（BUILD SUCCESSFUL），运行验证留给真机/模拟器

## 遗留验证

- [ ] 真机/模拟器：拍照 / 录像入库瞬间拖动画面不掉帧
- [ ] hilog 出现 `TaskPool 拷贝完成: Xms` 行

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [028] | feat(perf): 入库拷贝与照片落盘迁移 TaskPool——主线程重 I/O 清零（第 10 课） | Linsan | 2026-10-11 13:03:33 |
| [029] | docs(context): 第 10 课收尾——[028] 登记、路线 10 行、TaskPool 实测记录、启动 prompt 指向第 11 课（签名打包） | Linsan | 2026-10-11 13:04:22 |
