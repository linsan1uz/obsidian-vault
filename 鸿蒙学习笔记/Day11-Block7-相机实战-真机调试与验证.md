---
tags:
  - 鸿蒙
  - ArkTS
  - 调试
  - hdc
lesson: 相机实战 第 7 课
date: 2026-10-10
project: C:\Users\Linsan\camera
---

# Day11-Block7 相机实战：真机调试与验证

> [!abstract] 本课目标
> 把攒了两课的「真机验证清单」真正跑掉：学会 hdc 装包、hilog 过滤日志、
> 对照清单逐项验证；验证不过就修，修完才提交（AGENTS 铁律「验证未通过不提交」的落地课）。

## 复习题存档（欠账制已取消——用户裁决「没啥用」，仅留题干自查）

### 第 1 题（欠账 Q5：会话参数生命周期）（已取消）

**Q**：闪光/曝光与变焦在「会话重建」后的处理策略为什么**不一样**？
一边是「保留-重放」，一边是「读回真值」，各自的理由是什么？

（代码坐标提示：重建 = CameraServiceImpl `closeSession()` + `openSession()`，
铸造点 `createSession()`，重放点 `replaySessionParams()`；字段 `desiredFlash/desiredExposure`）

### 第 2 题（第 6 课：transition vs animation）（已取消）

**Q**：toast 浮层为什么必须用 `.transition()` 而不是 `.animation()`？
两者各自的触发时机是什么？（提示：想想 `if (toastMessage !== '')` 成立/不成立时组件处于什么状态）

### 第 3 题（第 6 课：性能账）（已取消）

**Q**：为什么 toast 的出场动画选 `OPACITY + move` 而不是让 `height` 从 0 撑到 60？
「布局（reflow）」和「绘制（repaint）」的成本差异是什么？

### 第 4 题（第 6 课：反馈分层）（已取消）

**Q**：KI-005 修复把错误反馈拆成了两条通道。什么错误走 `errorMessage` + ERROR 态（常驻），
什么错误走 `toastMessage`（2.5s 自动清除）？为什么"入库成功"也走 toast？

## 课程正文

### 知识点 1：hdc 装包——鸿蒙世界的 adb

**Why**：`hvigorw assembleHap` 只是把 hap 印好放硬盘（印刷厂），要手机跑起来得有人
"搬"进去安装（物流）——这个搬运工就是 **hdc**（HarmonyOS Device Connector）。

| 命令 | 作用 |
|---|---|
| `hdc list targets` | 列出连接设备（本课：`127.0.0.1:5555` 模拟器） |
| `hdc install <path>.hap` | 装包（产物 `entry-default-unsigned.hap`，未签名可装模拟器） |
| `hdc shell aa start -b <bundle> -a EntryAbility` | 启动 App |
| `hdc shell aa force-stop <bundle>` | 杀进程 |

### 知识点 2：hilog 过滤——让日志说话

**Why**：项目里所有 `Logger.x()` 打进系统日志管道，但全系统进程同时刷屏——
收音机全频道同播，得先**调台**。项目台标：Domain `0x0188` + TAG `EasyCam`（第 1 课埋的统一门面）。

```bash
hdc shell "hilog -x | grep -i EasyCam"     # 应用层日志
hdc shell "hilog -x | grep C02b01"         # native 相机服务层（取证 commit 失败细节）
```

> [!tip] Git Bash 实操坑
> - `hdc shell` 内路径被 MSYS 吃掉单斜杠 → 写 `//data/local/tmp/...` 或 `MSYS_NO_PATHCONV=1`
> - UI 自动化：`uitest dumpLayout -p //data/...json` 拿控件坐标 + `uinput -T -c x y` 点击
>   （本课用它找到「录像」(750,1736)、「快门」(660,1932)）

### 实战：日志抓出 5 处编译期不可见的缺陷（全部已修，[022]）

| # | 日志证据 | 根因 | 修复 |
|---|---|---|---|
| ① | `videoFrameRate is invalid` | `AVRecorderProfile.videoFrameRate` 类型可选但真机强制校验 | 补 `pickFrameRate()`（能力内取 30，无效兜底 30） |
| ② | 40ms 内两条并发 `switchMode 失败` | async 窗口期 guard 读旧值，双击穿透 → 两个 openSession 抢同一单例 | `rebuilding` 防重入标记（try/finally） |
| ③ | 每次切模式 `7400201 Invalid Session Configuration` | 对 stopped 会话做 beginConfig/remove/**commit** 舞步；且单 try 结构——commit 一炸，后续 input.close/mode.release 全被吞（fd/recorder 泄漏） | 拆解改 `stop() → release()`，每步独立 try 不互吞 |
| ④ | `Cannot read property length of undefined` | 模拟器 `getZoomRatioRange()` 返回 undefined（d.ts 未标注） | `toRange(values \| undefined)` 设防，抛干净的 CAMERA_BAD_RANGE |
| ⑤ | 每次开会话 `setFlash 7400102` 刷屏 | 无闪光硬件仍硬下发 | 先 `hasFlash()/isFlashModeSupported()` 再下发，不支持则 info 跳过 |

**验证方法论（本课核心）**：改 → 编译 → 装 → 跑 → **再看日志** → 对比修前修后。
①~⑤ 修后日志全清；`CAMERA_BAD_RANGE` 成为**干净的捕获错误**（模拟器不上报变焦能力，
预期差异，非故障）。

### KI-006/007：模拟器 HAL 限制（待真机裁决，不恋战）

**KI-006 切录像必败** `7400201 Mismatch resolution configuration`（native `CommitStreams rc:33`）：
JS 侧三组对照实验**全部证伪**——

1. 同宽高比配对（预览=视频=1280x720）❌ 仍 Mismatch
2. 预览对齐视频帧率 30-60/30-30 ❌ 模拟器拒设（`getSupportedFrameRates()` 上报 `{0,0}`，NAPI 7400101）
3. 视频清零帧率 {0,0} 与预览完全对等 ❌ 仍 Mismatch

伴随 native `GetCameraAllVendorTags failed` 等元数据缺失 → **疑似模拟器虚拟相机
不支持 NORMAL_VIDEO 流组合**。JS 侧可对等的字段（尺寸/格式/帧率）已穷尽。

**KI-007 拍照出图悬死**：`Capture rc:0` 且 JPEG 编码侧有日志，但 `photoAvailable`
回调永不返回（App 侧无保存日志无报错）——同样疑似模拟器出图管线不完整。

> [!important] 教训：失败实验要撤干净
> 帧率对齐的三组实验代码已从主干移除，**只留 SPI 接口**（`previewFrameRate()` 恒返回
> null）并把实验过程写进注释——真机若复现 Mismatch，它是第一个实验点。
> 没证实的东西不上主干，证伪过程写进提交说明（[022]）。

### 真机接入后的复验顺序（第 8 课优先）

1. KI-006 切录像 → 若真机也败，试 `previewFrameRate()` 帧率对齐
2. KI-007 拍照出图 → 连带 KI-004/005（自动入库 + toast）
3. 第 5~7 课累计清单：捏合 Nx / 拖动 EV / 闪光三态 / 录像无闪光按钮 / toast 2.5s / 201 引导

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [022] | fix(camera): 真机调试首轮修复——日志取证的 5 处缺陷（第 7 课） | Linsan | 2026-10-11 11:50:54 |
| [023] | docs(context): 第 7 课收尾——KI-006/007 登记、路线/清单登记、启动 prompt 指向第 8 课 | Linsan | 2026-10-11 11:51:36 |
