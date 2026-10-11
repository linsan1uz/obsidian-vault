---
tags:
  - 鸿蒙
  - ArkTS
  - Stage模型
  - Want
lesson: 相机实战 第 8 课
date: 2026-10-11
project: C:\Users\Linsan\camera
---

# Day11-Block8 相机实战：拍完进系统相册

> [!abstract] 本课目标
> 拍完自动入库 [016] 已有，补上"看得到"的入口：点击缩略图用**隐式 Want 拉起系统图库**
> 查看刚拍的照片。第一次让 App 走出自己的进程——Stage 模型的跨应用协作。

## 复习题存档（欠账制已取消——用户裁决「没啥用」，仅留题干自查，不再批改不阻塞）

### 第 1 题（欠账 Q5：会话参数生命周期）（已取消）

**Q**：闪光/曝光与变焦在「会话重建」后的处理策略为什么**不一样**？
一边是「保留-重放」，一边是「读回真值」，各自的理由是什么？
（提示：字段 `desiredFlash/desiredExposure`、`replaySessionParams()`；"UI 显示的必须是什么"）

### 第 2 题（第 6 课：transition vs animation）（已取消）

**Q**：toast 浮层为什么必须用 `.transition()` 而不是 `.animation()`？
两者各自的触发时机是什么？

### 第 3 题（第 6 课：性能账）（已取消）

**Q**：为什么 toast 的出场动画选 `OPACITY + move` 而不是让 `height` 从 0 撑到 60？
「布局（reflow）」和「绘制（repaint）」的成本差异是什么？

### 第 4 题（第 6 课：反馈分层）（已取消）

**Q**：KI-005 把错误反馈拆成两条通道：什么错误走 `errorMessage` + ERROR 态（常驻），
什么走 `toastMessage`（2.5s 自动清除）？为什么"入库成功"也走 toast？

## 课程正文

### 知识点 1：UIAbility 上下文——App 的「身份证 + 遥控器」

**Why**：前 7 课所有能力都在自己进程内（相机拍、photoAccessHelper 存）——App 是孤岛。
但"看照片"系统图库干得更好（滚动/缩放/分享/编辑都是现成的）。**重复造相册浏览页，
不如递条子请图库帮忙开**。跨应用协作的入口 = `startAbility`，挂在 `UIAbilityContext` 上。

```
ApplicationContext   → 应用级（全局目录、订阅）
UIAbilityContext     → 页面级（拉起其他 Ability、startAbility）← 本课用的
```

第 1 课组装根里存的 `UIAbilityContext`（`ServiceLocator.init(context)`），
当初只用来申请权限——现在第二份用途来了。

**类比**：Context 是住户卡。自己家的事刷这张卡；去邻居图库家串门，
用它开「跨楼栋通行证」= startAbility。

### 知识点 2：隐式 Want——不指定「谁来做」，只说「要什么」

| | 显式 Want | 隐式 Want |
|---|---|---|
| 写法 | 指名 bundleName + abilityName | 只给 action + uri + type |
| 类比 | 点名老王来修 | 发公告「谁会修水管谁来」 |
| 适用 | 拉自己的页面 | 借系统/第三方能力 |

看照片 = 典型隐式：不关心设备上谁是默认图库。三样东西定意图：

```typescript
const want: Want = {
  action: 'ohos.want.action.viewData',  // 意图：查看数据
  uri: 'file://media/Photo/xx/IMG.jpg', // 看什么：媒体库 URI（第 4 课「号牌」在这里兑现）
  type: 'image/jpeg'                    // 类型：帮系统缩小候选
};
await context.startAbility(want);
```

系统拿 want 和各 App 在 `module.json5` 声明的 skills **对暗号**（action/uri/type），
命中的候选打开默认项。

> [!note] 权限口径
> 媒体库 URI 受保护，但带 viewData 意图**转交系统图库时不需要额外授权**
> （图库是系统应用，有自己的权限）；传 `file://` 沙箱路径给第三方才要临时授权。
> 我们走 URI 路线最干净——「号牌」是媒体库发的，图库凭号自己取图。

### 实现（[024]）

- VM 加 `lastPhotoUri`：`saveToGallery` 成功后记录返回的 URI（**视频不覆盖**——
  缩略图只展示照片，video uri 与 image/jpeg 类型不匹配）
- `openLastPhoto()`：无 URI → 引导 toast；有 URI → 组装 Want → `startAbility`；
  失败 toast 报错（错误也有反馈通道，KI-005 的原则一致）
- 缩略图/占位图 `.onClick` → `vm.openLastPhoto()`（没拍过也有引导，不是死按钮）

### 遗留验证（设备断开，下次顺手）

- 有照片资产后点缩略图 → 拉起图库显示该照片
- 无照片点缩略图 → 「还没有照片」引导 toast

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [024] | feat(gallery): 点缩略图拉起系统图库查看最近照片（隐式 Want） | Linsan | 2026-10-11 12:23:05 |
| [025] | docs(context): 第 8 课收尾——[024] 登记、路线指向第 9 课、取消复习题欠账制 | Linsan | 2026-10-11 12:23:30 |
