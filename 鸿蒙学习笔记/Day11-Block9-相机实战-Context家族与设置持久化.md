---
tags:
  - 鸿蒙
  - ArkTS
  - 相机实战
课次: Day11-Block9（第 9 课）
日期: 2026-10-11
主题: Stage 模型深化——Context 家族 + preferences 设置持久化
---

# Day11-Block9：Context 家族与设置持久化

> [!info] 复习题
> 欠账制已取消（2026-10-11 用户决策），本课起开场不再安排必答复习题。

## 痛点引入（为什么）

现在的相机每次重启都「失忆」：明明选了强制闪光，冷启动回到 AUTO；上次在录像模式，打开又是拍照。
系统相机为什么能记住？因为它把设置**写到了磁盘**。而写磁盘的第一步，是拿到一张「房卡」——Context。

## 知识点 1：Context 是什么（房卡类比）

**Context = 应用身份 + 沙箱地址的凭证。** 系统服务都要求出示它：既知道「你是谁」（权限判定、数据归属），也知道「你的私人储物柜在哪」（沙箱路径）。

我们其实一直在用 Context，只是没点破：

| 课次 | 用法 | 问 Context 借了什么 |
|---|---|---|
| 第 1 课 | `camera.getCameraManager(context)` | 相机能力 |
| 第 3 课 | `requestPermissionsFromUser(context, ...)` | 权限弹窗 |
| 第 8 课 | `context.startAbility(want)` | 拉起图库 |
| 第 9 课 | `preferences.getPreferences(context, name)` | **沙箱里的存储位置** |

**家族两个常用成员**：
- `ApplicationContext`——应用级（整栋楼的物业）；
- `UIAbilityContext`——能力级（你这一户的户主卡）。

`getPreferences` 传哪个 Context，数据就落在谁的目录下。本应用只有一条 UIAbility，
传 UIAbilityContext 即可；若将来多 Ability 共享设置，用 `context.getApplicationContext()` 再开。

## 知识点 2：preferences——轻量 KV 持久化（便利贴类比）

**为什么不用文件 / 数据库？** 设置项就几个字符串（`flashMode=ON`）：

- 动用 RelationalStore（SQLite）是高射炮打蚊子——要建表、管版本；
- 自己管文件要处理格式、并发、损坏；
- preferences = 平台帮你管好的「键值便利贴」：**内存缓存读超快，put 后 flush 异步落盘**。

**API 三步**：`getPreferences(context, name)` 拿实例 → `put(key, value)` 写内存 → `flush()` 落盘；读 `get(key, default)`。

**边界**：适合「少量、小体积、读写频」（设置、开关、上次状态）；别塞大 JSON（几百 KB 以上考虑文件/数据库）。

## 实现：OCP 四步接线

1. **领域端口 `domain/service/ISettingsStore.ets`**：`getString/putString`。
   契约亮点：**永不 reject**——持久化失败不该打断拍照，实现内部记日志、读失败回退默认值。
   接口契约不只写「做什么」，还要写「失败怎么办」。
2. **基础设施 `infrastructure/settings/PreferencesStore.ets`**：构造时即开始 `getPreferences`，
   所有读写 `await` 同一个 Promise（天然不重复打开）；put 后 flush。
3. **组装根 `ServiceLocator`**：`getSettingsStore()` 第三个 lazy 单例——和 cameraService、
   mediaSaver 完全同一个三行模板，组装根的价值就在这。
4. **ViewModel 接线**：
   - `init()` 顶部 `restoreSettings()`——读沙箱不需要权限，放在权限申请之前；
   - **闪光**：`flashMode = 恢复值; cameraService.setFlash(...)`——会话没启动时实现层只记
     「期望值」，openSession 后 `replaySessionParams` 重放。**第 5 课的机制一行没改，直接复用**；
   - **模式**：恢复成录像必须重建会话，但此刻还没有 surface → 记 `pendingMode`，
     等 `onSurfaceReady` 预览起来后走既有 `switchMode` 全量重建；
   - **保存时机**：`cycleFlash`/`switchMode` **成功后**才写（决策见下）。

> [!important] 关键决策：只记录「平台真正达成的状态」
> 保存放在 switchMode/cycleFlash 成功之后。模拟器录像必败（KI-006）→ currentMode 永远
> 停在 PHOTO → 保存的永远是 PHOTO → 恢复路径**天然不会踩 KI-006**。真机上录像成功 →
> 保存 VIDEO → 下次启动恢复 VIDEO → 真机能开录像会话 → 行为一致。持久层不需要写一行
> 「设备判断」，自洽来自「保存时机」这一个设计。

> [!note] 逐行讲解：`restoreSettings` 的两个分支为什么不一样
> 闪光是**会话参数**——长在 Session 上，但期望值由实现层持有，恢复只是「补记意图」，无需会话。
> 模式是**会话类型**——`createSession(sceneMode)` 一锤定音（第 4 课结论），改模式 = 全量重建，
> 而重建需要 surfaceId。所以闪光立即接，模式挂起等预览。恢复策略的差异，本质是两者
> 在会话里的生命周期不同。

## 踩坑实录（编译期撞出来的两颗雷）

1. **`getPreferencesAsync` 不存在**：API 24 d.ts 仅有 since9 `getPreferences`（Promise 版）
   和 since10 `getPreferencesSync`。教训：**写代码前先 grep d.ts**（`@ohos.data.preferences.d.ts`）。
2. **ArkTS 类字段空值收窄不可靠**：`if (this.store !== null) { return this.store; }` 仍报
   `Type 'Preferences | null' is not assignable to type 'Preferences'`。
   解法：可空字段 + 惰性打开 → **构造时打开 + readonly 共享 Promise**——无空值则无收窄问题。

## 遗留验证

- [ ] 模拟器可测：切闪光 ON → 杀进程重开 → 顶栏仍 ON（注意：模拟器无闪光硬件，
      UI 状态与硬件下发是两回事——`applyFlash` 会查 `hasFlash()` 跳过下发）
- [ ] 真机：切录像 → 重启 → 直接进录像模式；hilog 应看到 `设置已保存 key=captureMode value=VIDEO`

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [026] | feat(settings): 相机设置持久化——Context 家族 + preferences（第 9 课） | Linsan | 2026-10-11 12:41:36 |
| [027] | docs(context): 第 9 课收尾——[026] 登记、路线 7/8/9 行补齐、preferences/收窄坑实测、启动 prompt 指向第 10 课 | Linsan | 2026-10-11 12:44:02 |
