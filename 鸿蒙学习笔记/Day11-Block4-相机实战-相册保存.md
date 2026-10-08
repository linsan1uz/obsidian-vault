---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 架构设计
lesson: 相机实战 第 4 课
date: 2026-10-04
project: C:\Users\Linsan\camera
---

# Day11-Block4 相机实战：相册保存

> [!abstract] 本课目标
> 把沙箱里的照片/视频正式送进系统相册（photoAccessHelper + SaveButton 安全控件），
> 修复 KI-004，并保持落盘职责在分层架构中的正确位置。

## 开课复习题（第 1~3 课）

### 第 1 题（分层）✅ 讲评

**Q**：domain 禁止 import 任何 `@kit`/`@ohos`，为什么？ViewModel 依赖 domain 接口、
实现在 infrastructure、ServiceLocator 组装——这个方向叫什么？

**A**：
- domain 是「标准菜谱」，`@kit` 是「华为厨房的厨具」。菜谱绑死厨具就只能在一家厨房用；
  实际教训：SDK 升级导致 `camera.ConnectionType`、`Photo.main` 等 API 改名——**API 变动
  只该炸 infrastructure 一个地方**，domain 必须稳如泰山。
- 换来三点：domain 纯 TypeScript 永远稳定 / 可内存假实现做单测 / 可整体替换实现。
- 这个方向叫**依赖倒置原则（DIP，SOLID 的 D）**：高层（ViewModel）和低层
  （CameraServiceImpl）都向中间的抽象（ICameraService）看齐，SDK 细节压到最外圈；
  ServiceLocator 是唯一组装点（组装根）。

### 第 2 题（V1 状态管理）✅ 90 分

**Q**：ModeSwitcher 订阅 @Observed 的 ViewModel，为什么必须 @ObjectLink 而不能 @Prop？

**A（用户答对核心，纠一处表述）**：
- @Prop 是**复印**：子组件拿到副本，子改不回传父 → 子组件显示录像、ViewModel 还是拍照，
  **UI 和内核分家**（快门拍的还是照片）。
- @ObjectLink 是**给钥匙**：全项目只有同一份实例，谁改属性所有观察者都收到通知。
  严格说不是「双向传递」——**根本没有第二份存在，无传递可言**。
- @Observed 是前提：让类的**属性**变化进通知系统，裸 class 连 @ObjectLink 都接不住。
- 记忆：**@Prop 给复印件会撒谎，@ObjectLink 给的是同一本人，谁改都是真的。**

### 第 3 题（会话）✅ 讲评

**Q**：拍照切录像为什么不往现有会话加流，而是整个关掉重建？

**A**：
- **PhotoSession ≠ VideoSession，种类在铸造时定死**：`createSession(sceneMode)` 一锤定音，
  会话没有「变身」API——轿车不能敲成面包车，只能换车。
- **两种会话认的输出流不同**：PhotoSession 只认 PhotoOutput，VideoSession 才认 VideoOutput
  （往 AVRecorder surface 泵帧），`addOutput` 按会话类型门禁放行。
- 录像要的三样（VideoSession / VideoOutput / AVRecorder）有两样现会话里不存在 → 只能
  closeSession 逆序释放 → 换 sceneMode 重新 createSession → 重新组装。
- **前后摄切换同理走全量重建**：换 CameraInput = 换原材料，部分更新易漏状态，
  全量重建 > 精细补丁。
- 陷阱澄清：**SurfaceId 不换**——它是 XComponent 预览面的门牌号，窗口还在；
  换的是「会话这辆车」，不是「收货地址」。

### 第 4 题（异步）✅ 前半 60 分

**用户答案**：await 是等后面语句返回执行的结果。（方向对，精确化见下）
后半「桥接模式解决什么」答不知道 → 讲评补上。

**A（精确化）**：await 等的是**右边表达式产出的 Promise 兑现**（pending →
fulfilled/rejected），不是笼统的「后面的语句」——后面的语句本来就排在 await 解冻之后。

**A（兑现桥解决什么）**：
- 世界有两种约定：**回调世界**（「有事叫我」photoAvailable）和 **await 世界**（「拿号等」）。
- ViewModel 要 `await vm.capture()`，capture() 必须立刻返回一张**取餐号（Promise）**，
  否则没东西可等；但照片何时洗出来是硬件说了算，return 那一刻给不出结果。
- 解法：new Promise 把 `resolve/reject` 挂成员变量 → 先还号；硬件回调到达时调
  `resolve(path)` 取餐号变 fulfilled → await 处解冻拿到路径。
- 拍照失败走 `reject` → await 处抛异常 → **被外层 try/catch 接住** → errorMessage。
- 一句话：**把「有事叫我」翻译成「我等结果」，顺带让错误进入 await 的 try/catch 通道，
  而不是丢在回调里没人管。**

## 第 4 课预习题（课后回收，届时自己作答）

1. 为什么写系统相册不能直接用文件路径，而要走 `photoAccessHelper`？沙箱路径和媒体库 URI 的区别是什么？
2. `SaveButton` 安全控件为什么能"免权限"保存？它的授权时机和普通权限弹窗有什么不同？
3. 拍照/录像落盘现在在 infrastructure 里直接写 `filesDir`，要接入相册时这个职责应该挪到哪一层？新增什么接口？

## 课程正文

### 知识点 1：photoAccessHelper 入库流程

- **沙箱 vs 媒体库**：沙箱是「自家保险柜」，媒体库是「图书馆书架」——相册只扫媒体库
  索引；HarmonyOS NEXT 起不再允许裸文件路径写公共目录，跨 App 认的是 URI 不是路径
- **入库三步**：`helper.createAsset(PhotoType, 'jpg')` 申请入库位返回可写 URI
  → `fileIo.openSync(uri)` → 写字节 → 相册即刻可见（createAsset 已登记索引，无需扫描）
- d.ts 关键确认：**「没有 WRITE_IMAGEVIDEO 权限时，可以通过安全控件创建媒体资产」**
  → 走 SaveButton 路线，module.json5 一行不用改

### 知识点 2：SaveButton 安全控件（免权限）

- `SaveButton({ icon, text })` 是**系统级安全控件**（全局声明，无需 import），
  不是普通按钮，样式受安全组件规范强约束
- **授权模型**：首次点击弹系统确认框，同意后拿临时授权，之后不弹；
  **倒计时窗口 API ≤19 为 10 秒、API ≥20 为 1 分钟**——
  `createAsset` 必须在窗口内调用（「拿号」限时），拿到 URI 后的字节拷贝不受限
- `onClick(event, result)`：`result === SUCCESS` 才能调 media library API
- **布局坑**：安全控件支持 padding/width/height **但不支持 margin** → 外层套 Row 布局

### 架构（预习题 3 的答案）

- **落盘职责拆两半**：PhotoMode 写沙箱保留（相机流水线终点，缩略图数据源）；
  **入库是独立领域动作**（授权时机在拍照之后、录像也要入库、PhotoMode 是相机策略不该掺媒体库）
- **新增 domain 接口 `IMediaSaver.saveToGallery(sandboxPath)`**（纯类型，无 @kit）
  + **infrastructure 实现 `GallerySaver`**（photoAccessHelper + fileIo 分块拷贝）
  + ServiceLocator 注册 `getMediaSaver()`——依赖方向与 ICameraService 同构
- **触发链**：SaveToGalleryButton(UI 安全控件) → `vm.saveToGallery()` → IMediaSaver → GallerySaver
- 防重复入库：`savedGalleryPath === lastPhotoPath` 时隐藏按钮

### 时序图

```
用户点 SaveButton → 系统确认框（仅首次）→ result=SUCCESS，倒计时开始
   → createAsset(IMAGE,'jpg') 拿 URI（限时）→ openSync/readSync/writeSync 分块拷贝（不限时）
   → 相册可见；savedGalleryPath=lastPhotoPath → 按钮消失 + toast
```

> [!tip] 「拿号」与「取餐」的限时差异
> 授权窗口只限制 **createAsset 这一步**；d.ts 明确「有效期内取得的文件句柄
> 过期后仍可读写」——所以慢速大文件拷贝放窗口外也安全。

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [014] | feat(gallery): SaveButton 安全控件 + photoAccessHelper 相册入库 | Linsan | 2026-10-08 23:05:49 |

## 真机验证清单（待用户执行）

1. 拍一张照 → 控制区出现「保存到相册」胶囊按钮
2. 首次点击 → 系统确认弹窗 → 同意 → toast「已保存到相册」→ 按钮消失
3. 打开系统相册 → 照片在
4. 再拍一张 → 按钮重新出现（新照片未入库）
