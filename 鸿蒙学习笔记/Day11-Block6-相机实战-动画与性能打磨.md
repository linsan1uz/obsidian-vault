---
tags:
  - 鸿蒙
  - ArkTS
  - CameraKit
  - 动画
lesson: 相机实战 第 6 课
date: 2026-10-10
project: C:\Users\Linsan\camera
---

# Day11-Block6 相机实战：动画与性能打磨

> [!abstract] 本课目标
> 收尾打磨：补齐拍摄反馈动画与错误提示通道（KI-005），
> 顺带过一遍预览链路的性能检查点。

## 开课复习题批改记录（第 1~5 课）

### 第 1 题（依赖倒置 DIP）✅ 90 分

**Q**：domain 层禁 import `@kit`/`@ohos` 是为什么？「ViewModel → ICameraService ← CameraServiceImpl，
由 ServiceLocator 组装」这个方向里，谁依赖谁？「倒置」二字体现在哪？

> **答**：domain 是接口层只定义契约，所以禁平台工具箱；引入中间层后 CameraServiceImpl 依赖
> ICameraService，由 ServiceLocator 组装，形成倒置。
>
> **精化**：方向说反了一处——ViewModel 依赖的也是**接口**，不是 CameraServiceImpl（它连实现类名都不知道）。
> 源码级依赖：ViewModel → 接口 ← CameraServiceImpl，**双方都指向抽象**；倒置体现在
> 「高层不再 import 低层，低层反而要实现高层认可的接口，new 谁的权力上交组装根」。
> 类比：点外卖只认订单不认骑手，平台撮合，换骑手订单不变。

### 第 2 题（V1 状态管理）✅ 85 分

**Q**：ModeSwitcher 把 `@ObjectLink vm` 改回 `@Prop vm`，用户点「录像」后会发生什么？

> **答**：@ObjectLink 父子都传；@Prop 父传子、子不回父。
>
> **精化**：@ObjectLink 的"双向"本质是**世界上只有一份数据**（引用传递），不存在同步；
> @Prop 的真正危害不在"子不回父"，而在**复印件会撒谎**——本课现场实测：模式条（复印件）显示录像、
> 父页面快门（真身）还是拍照，两个组件对同一事实给出不同答案。
> 另注意：@Prop 副本**自己**的第一层变化能刷子组件自己（表现为"高亮迟到"），
> 断的是**向父和兄弟组件**的链。
> **选型一句话**：共享事实（ViewModel/列表项）→ @ObjectLink；独立快照（子组件改了别人不用知道）→ @Prop。

### 第 3 题（会话生命周期）✅ 满分

**Q**：为什么切模式和切前后摄都走「整个关掉会话再重建」？

> **答**：createSession(sceneMode) 一锤定音，PhotoSession/VideoSession 类型创建后不可变（无变身 API）；
> 两种会话认的输出流不同，往拍照会话塞 VideoOutput 会被 addOutput 直接拒绝（门禁刷卡类比）；
> 录像三样（VideoSession/VideoOutput/AVRecorder）两样在现有会话不存在，唯一出路全量重建；
> 前后摄同构：换设备=换原材料，部分更新易漏状态，**全量重建 > 精细补丁**（简单、可预测、不漏）。
>
> **补充**：逆序释放的顺序=依赖方向——先拆被依赖的（Output/Input），后关会话本身，反了会拿句柄失效错误。

### 第 4 题（相册入库两条授权路线）✅ 90 分

**Q**：SaveButton 与 WRITE_IMAGEVIDEO 的核心区别？为什么选后者？

> **答**：SaveButton 每次要提示，WRITE_IMAGEVIDEO 首启一次后无提示。
>
> **精化（取舍要两头都看）**：SaveButton 每次保存弹安全控件、授权仅 1 分钟、不能自动入库，
> 但免声明权限 AGC 审核友好；WRITE_IMAGEVIDEO 首启一次长期有效、支持拍完自动入库，
> 代价是**审核风险**（非图库类 App 申请写媒体权限可能被质询，留第 15 课验证）。
> 决策逻辑：相机 App 自动入库是核心预期行为，**技术上 SaveButton 更安全，产品上 WRITE_IMAGEVIDEO 更正确**。

### 第 5 题（第 5 课：会话参数生命周期）⏳ 移交第 7 课回收

**Q**：闪光/曝光与变焦在「会话重建」后的处理策略为什么**不一样**？

> 课上因进度移交，第 7 课开课先答此题。
> （坐标提示已给：重建 = CameraServiceImpl `closeSession()`(:281) + `openSession()`(:236)，
> 铸造点 `:260 createSession()`，重放点 `:270 replaySessionParams()`）

## 课程正文

### 知识点 1：反馈分层——致命错误 vs 瞬时提示（KI-005 修复）

**事故现场**：`statusText()` 只在 `status=ERROR` 时读 `errorMessage`；而预览态下拍照失败只写
`errorMessage` 不改 status → 错误写进没人看的字段。类比：公司只有「全厂停产红屏」一种报警，
车间手割破了也往红屏递纸条，纸条永远没人看——**小伤需要创可贴，不是停产警报**。

**拆成两种命运**：

| | 致命错误 | 瞬时提示 |
|---|---|---|
| 例子 | 无相机权限、预览启动失败 | 拍照失败、201 引导、保存成功 |
| 还能继续用吗 | ❌ | ✅ |
| 形态 | errorMessage + ERROR 态，**常驻** | toastMessage，**2.5s 自动清除** |
| 通道 | statusText（保留） | 新增浮层 |

**实现要点**（[020]）：
- VM 加 `toastMessage` + `showToast()`：**重复提示重置计时**（连拍失败两次，第二条要完整展示）
- 7 处预览态错误改道：切模式/切镜头/拍照/入库/录制×2/麦克风权限
- 入库**成功**也走同通道（「已保存到相册」）——toast 不只报忧
- `destroy()` 清理计时器，防页面销毁后回调写死状态
- 定时器归 VM（业务状态归 ViewModel，页面只负责显示）

### 知识点 2：`.animation` vs `.transition` + 性能账

| 机制 | 触发时机 | 例子 |
|---|---|---|
| `.animation()` | 状态值**改变**，属性旧值→新值补间 | 闪白 opacity、快门 scale |
| `.transition()` | 组件**挂载/卸载**（`if` 生灭，无旧值可补间） | toast 浮层、变焦/EV chip |

类比：`.animation` 是**灯光渐变**（灯一直在），`.transition` 是**演员上下场**（人得先在/先走）。

**性能账——重绘比重排便宜**：

```
布局 reflow：算位置尺寸 —— 贵，牵一发动全身
绘制 repaint：上色 —— 便宜，只影响自己
```

- ❌ toast 用 height 0→60 动画：每帧触发布局，下面整条 Column 跟着挪，又贵又抖
- ✅ `OPACITY + move`：一开始就占位，只动透明度/位移——纯绘制层，GPU 合成
- **一句话**：动画只动 `opacity/translate/scale/rotate`（绘制层），少动 `width/height/margin`（布局层）

**toast 浮层写法**（条件渲染 + 进出场）：

```typescript
if (this.vm.toastMessage !== '') {
  Text(this.vm.toastMessage)
    ...
    .transition(TransitionEffect.OPACITY
      .animation({ duration: 200, curve: Curve.EaseOut })
      .combine(TransitionEffect.move(TransitionEdge.BOTTOM)
        .animation({ duration: 200, curve: Curve.EaseOut })))
}
```

> [!warning] 2026 SDK 实测
> `TransitionEffect.combine()` 是**实例方法**——静态写法 `TransitionEffect.combine(...)`
> 编译报 10505001。从 `TransitionEffect.OPACITY` 实例上链式调用。

### 现场小插曲：@Prop 翻车实测

课前把 ModeSwitcher 改成 `@Prop vm` 复现断链：第 1 次点「录像」不高亮、第 2 次才亮。
归因错位分析：`switchMode` 是 async，写 `currentMode` 排在会话重建（几百毫秒）之后，
高亮是**第 1 次点击迟到的结果**，第 2 次点击是空枪；且复印件真身分家——父页面快门还是拍照，
点快门执行的是拍照分支（Q2 答案的现场版）。已改回 `@ObjectLink`。

## 真机验证清单（第 5+6 课累计）

- [ ] 双指捏合放大且顶部显示 Nx，切镜头回 1x（浮层消失）
- [ ] 单指上下拖画面明暗变化且显示 EV
- [ ] 后摄拍照模式顶栏闪光三态循环；录像/前摄无闪光按钮
- [ ] 拍照自动入相册并弹「已保存到相册」toast（2.5s 自动消失）
- [ ] 关掉相册权限后拍照，弹 201 引导 toast（预览不中断）

## 提交记录（编号 | 描述 | 提交人 | 时间）

| # | 描述 | 提交人 | 时间 |
|---|---|---|---|
| [020] | fix(ui): 瞬时反馈通道修复 KI-005 + toast transition 进出场 | Linsan | 2026-10-10 22:50:27 |
| [021] | docs(context): 第 6 课收尾——KI-005 关闭、课程路线/提交清单登记、启动 prompt 指向第 7 课 | Linsan | 2026-10-10 22:51:28 |
