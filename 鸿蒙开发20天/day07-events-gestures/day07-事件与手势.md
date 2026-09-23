# Day 7 · 事件与手势：让界面响应触摸

> **今日目标**：补齐通用事件体系（onClick 之外的世界）；掌握 Tap / LongPress / Pan / Pinch 四种手势与手势竞争规则；然后完成**第一个里程碑项目：计算器**——Day 1~6 的布局、状态、组件拆分全部用上。
> **时长**：约 3 小时（2 小时课 + 1 小时精读计算器）
> **配套代码**：`GestureLab.ets`（手势实验场）、`Calculator.ets`（里程碑：计算器完整实现）

---

## 1. 事件地图：三类入口（10 分钟）

用户和界面交互，代码的"接线口"分三层，从简单到复杂：

| 层 | 入口 | 适合 |
|----|------|------|
| **通用事件** | `onClick` / `onChange` / `onSubmit` / `onScroll` / `onAppear`… | 离散动作：点一下、输入完、滚一下 |
| **原始触摸** | `onTouch`（Down/Move/Up 流） | 极少数底层需求（画板类），日常不用 |
| **手势** | `.gesture(TapGesture(...))` / Pan / LongPress / Pinch… | 需要**识别动作类型**或**多指**、或手势之间要竞争协作 |

选择口诀：**能用 onClick 解决就别上手势；要"长按/拖拽/捏合"或多指，才进手势体系。**

一句话概念备用：ArkUI 的事件沿组件树**冒泡**（从内层组件向外传），需要截断时用 `stopPropagation()`——今天知道有这回事即可，遇到具体需求再查。

---

## 2. 通用事件速查（20 分钟）

Day 2 学了 onClick / onChange，这里补齐剩下的高消费事件：

```arkts
TextInput({ placeholder: '搜索' })
  .onChange((value: string) => { ... })            // 输入框内容每次变化（Day 2）
  .onSubmit((key: EnterKeyType) => { ... })        // 点键盘回车/搜索键触发

Scroll() { ... }
  .onScroll((offset: number, state: ScrollState) => {
    console.log(`滚动到 ${offset}px，状态：${state}`)   // state: Idle/Scrolling/Forward/Backward
  })

Text('懒加载的卡片')
  .onAppear(() => { ... })      // 组件首次出现在界面上（图片懒加载的经典搭档）
  .onDisappear(() => { ... })   // 组件从界面移除
```

通用事件三条规律：

1. **回调参数就是事件数据**：TextInput 给 string，Toggle 给 boolean，Scroll 给 offset——各组件各给各的，点 Ctrl+跳声明看签名；
2. `onAppear` / `onDisappear` 是**组件级生命周期**（对象挂载/卸载），页面级的 `onPageAppear` 等放 Day 14；
3. 事件回调里做三件事：**收数据、改 @State、调方法**——逻辑放成员方法里，别堆在回调里（build 里的事件回调要短小）。

### 点击体验两个小技巧

```arkts
Button('点赞')
  .clickEffect({ scale: 0.9, level: ClickEffectLevel.LIGHT })   // 点击缩放反馈（涟漪样式见 API 12+ ClickEffectType.Ripple）
  .onClick(() => {
    const now = Date.now()
    if (now - this.lastClick < 300) { return }   // 防抖：300ms 内的重复点击直接忽略
    this.lastClick = now
    this.like()
  })
```

防抖三行套路在点赞、提交、跳转按钮上**到处能用**——重复点击引发重复提交是新手高频 bug。`lastClick` 是纯逻辑字段，用普通成员即可，不用 @State。

---

## 3. 手势：写法与四种主力手势（35 分钟）

手势写在组件上，结构和事件一样是链式回调：

```arkts
SomeComponent()
  .gesture(
    TapGesture({ count: 1 })                 // 手势对象（配置）
      .onAction(() => { ... })               // 手势触发
  )
```

手势回调三兄弟：`onActionStart`（识别成功瞬间）→ `onActionUpdate`（过程中，持续触发）→ `onActionEnd`（结束）。连续手势（拖、捏）靠 Update 拿实时数据。

### 四种主力手势

| 手势                                       | 事件数据                                   | 典型场景      |
| ---------------------------------------- | -------------------------------------- | --------- |
| `TapGesture({ count: 1/2 })`             | 无（count=连击次数）                          | 单击/双击     |
| `LongPressGesture({ repeat, duration })` | 无                                      | 长按菜单、长按删除 |
| `PanGesture({ direction, distance })`    | `translationX/Y`（位移）、`velocityX/Y`（速度） | 拖拽、滑动删除   |
| `PinchGesture({ fingers: 2 })`           | `scale`（缩放倍数）                          | 双指缩放图片    |
| `RotationGesture`                        | `angle`（旋转角）                           | 旋转视图      |

### Pan 拖拽（用法最广，重点吃透）

```arkts
@State ballX: number = 0
@State ballY: number = 0
private startX: number = 0                    // 拖拽起点，不驱动 UI → 普通成员
private startY: number = 0

Circle()
  .translate({ x: this.ballX, y: this.ballY })
  .gesture(
    PanGesture({ direction: Direction.All })
      .onActionStart(() => {
        this.startX = this.ballX              // 记录按下那一刻的位置
        this.startY = this.ballY
      })
      .onActionUpdate((e: PanGestureEvent) => {
        this.ballX = this.startX + e.translationX   // 起点 + 本次位移（不是累计值！）
        this.ballY = this.startY + e.translationY
      })
  )
```

**关键模式**：`目标位置 = 按下时的位置 + 本次手势的位移`。`translationX` 是**从 onActionStart 到当前**的总位移，所以必须配一个"按下瞬间的快照"，否则位置会跳。边界钳制就是在这个赋值外包一层 `Math.min/max`——完整写法见 `GestureLab.ets`。

### Pinch 缩放（同一个快照模式）

```arkts
@State scale: number = 1
private baseScale: number = 1

Box()
  .scale({ x: this.scale, y: this.scale })
  .gesture(
    PinchGesture({ fingers: 2 })
      .onActionStart(() => { this.baseScale = this.scale })
      .onActionUpdate((e: PinchGestureEvent) => {
        this.scale = Math.min(3, Math.max(0.5, this.baseScale * e.scale))
      })
  )
```

缩放 = **按下时的基准值 × 当前手势倍数**，还是快照模式。两种手势共用一个套路，记住它。

---

## 4. 手势竞争与组合（20 分钟）

多个手势识别同一次触摸时，需要 `GestureGroup` 指定共存规则：

```arkts
.gesture(
  GestureGroup(GestureMode.Exclusive,        // 互斥：同一时刻只有一个能成功
    TapGesture({ count: 1 })
      .onAction(() => promptAction.showToast({ message: '单击' })),
    LongPressGesture({ duration: 400 })
      .onAction(() => promptAction.showToast({ message: '长按' }))
  )
)
```

三种模式的口诀：

| 模式             | 口诀                     | 场景                 |
| -------------- | ---------------------- | ------------------ |
| `Exclusive` 互斥 | **抢椅子**：同时竞争，先识别成功者独占  | 单击 **或** 长按（最常用）   |
| `Priority` 优先级 | **排队**：按声明顺序依次尝试，靠前的优先 | 需要精确控制谁先谁后         |
| `Parallel` 并行  | **各玩各的**：可同时触发         | 两个手势本质不冲突（如一边拖一边转） |

没有 `promptAction`？开头一行：

```arkts
import { promptAction } from '@kit.ArkTS'     // Toast 轻提示，Day 11 还会深讲
```

**实用建议**：同一组件不要同时写 `onClick` 和 `TapGesture`——两个点击入口的识别顺序容易让人迷惑，建议一个组件只留一种。需要长按共存时，统一用 `GestureGroup(Exclusive, Tap, LongPress)` 这个标准写法。

---

## 5. 综合示例：GestureLab 手势实验场（20 分钟）

`GestureLab.ets` 四个实验台，替换进 Index.ets 按剧本玩：

1. **拖拽小球**：Pan 快照模式 + 边界钳制（拖不出棋盘）；
2. **长按高亮**：LongPress 按住变色、松手恢复；
3. **双指缩放**：Pinch 快照模式，0.5~3 倍夹紧；
4. **单击/长按共存**：Exclusive 互斥组，验证"长按后松手不会误触单击"。

---

## 6. 🏁 里程碑：计算器（45 分钟，精读）

完整代码在 `Calculator.ets`。这是阶段一的收官项目，先读设计，再读代码，最后合上文件自己复述一遍状态机。

### 设计拆解

```
Calculator（页面）
├── 顶部显示区：右对齐 Text（自适应字号）—— @State display
└── Grid 4列×5行：20 个按键
     └── CalcKeyButton（Day 6 的组件复用：label + kind + 回调）
```

- **布局**：Grid `columnsTemplate('1fr 1fr 1fr 1fr')` + `rowsTemplate('1fr 1fr 1fr 1fr 1fr')`——固定不滚动（Day 4 规则的实战）；
- **按键数据**：20 个 label 拍平成数组，`ForEach` 循环生成，键用 label（唯一）——Day 5 的实战；
- **分工**：`CalcKeyButton` 只会喊"我被按了，label 是 X"，怎么算全在页面——Day 6 单向数据流。

### 状态机（本项目的心脏，重点理解）

四个 @State 就是一台完整的四则运算机器：

| 状态                | 职责                 |
| ----------------- | ------------------ |
| `display: string` | 屏幕上显示什么            |
| `acc: number`     | 前一个操作数（按运算符前存下的值）  |
| `op: string`      | 待执行的运算符（'' 表示没有）   |
| `fresh: boolean`  | **下一个数字是否要重新开始输入** |

`fresh` 是新手最难想通的一位：按完运算符或等号后它为 true，此时再按数字键，`display` 被整个替换成新数字而不是接在后面。它就是"该开新数字了"的旗子。

按键处理的完整规则表（读代码前先看这个）：

| 按键 | fresh=true 时 | fresh=false 时 | 其他 |
|------|--------------|----------------|------|
| 数字 | 替换 display，置 fresh=false | 追加（防前导 0） | 以'错误'开头 → 先清 |
| `.` | 显示 '0.' | 已有 `.` 则忽略 | — |
| 运算符 | 存 display 进 acc、记 op、置 fresh=true | 同左（连续按换运算符） | — |
| `=` | — | 算出结果、格式化、清 op、置 fresh=true | 除零 → '错误' |
| `AC` | 全部复位 | 同左 | — |
| `⌫` | 显示 '0' | 删末位 | — |
| `±` / `%` | 不动 / 除以 100 | 取反 / 除以 100 | — |

**格式化函数 `fmt()` 别忽略**：`0.1+0.2` 直接显示是 `0.30000000000000004`（所有浮点语言的祖传问题），用 `parseFloat(n.toPrecision(12)).toString()` 压掉尾巴。

### 验收清单（跑起来逐条核对）

1. `7 + 8 =` → 15；接着 `× 3 =` → 45（**连续运算**，fresh 旗的功劳）；
2. `5 ÷ 0 =` → 显示"错误"，按任意数字可继续用；
3. `3.14`：连按 `.` 只进一个；`±` 切换正负；`%` 变 0.0314；
4. `123 ⌫` → 12，再删到 0 不再变负；
5. 按 `=` 手速再快也只算一次（防抖）。

---

## 7. 常见坑速查

| 现象 | 原因 |
|------|------|
| 拖拽物越拖越飞 | 用了累计位移没记起点：`当前位置 = 起点 + translation` |
| 长按松手也触发了单击 | 没用 Exclusive 互斥组隔离 |
| 同组件 onClick 和 TapGesture 行为怪异 | 两个点击入口打架，留一种 |
| 计算器 `7 +` 后输的数字接在 7 后面 | 忘了 fresh 旗，按运算符没置 true |
| 显示 `0.30000000000000004` | 浮点误差，过一遍 fmt() |
| 防抖没生效 | 比较的时间戳本身没更新（忘了 `this.lastClick = now`） |
| onAppear 执行了两次 | 预览器与真机刷新机制差异，以真机/模拟器行为为准 |

---

## 8. 今日作业（40 分钟）

**作业 1（必做）：计算器扩展**
- 连续小数防护（已实现，读懂它）；自己加 `⌫` 之外的 `AC` 区分（清空 vs 清零当前输入，任选方案说明理由）
- 按键按下的**高亮反馈**（给 CalcKeyButton 加 pressed 态，想想用哪个事件）
- 长按显示区 → 清空全部（长按手势 + 互斥组实战）

**作业 2（选做）：双击点赞**
- Text 上 TapGesture({ count: 2 }) 双击爱心 +1，和单击共存；图标用 emoji 即可

**思考题**：
1. Pan 手势的 `translationX` 从哪里开始算？为什么必须记录"按下瞬间的起点"？
2. 长按删除列表项和单击进入详情如何共存？写出 GestureGroup 那一行的结构。
3. 计算器里 `fresh` 为 true 时按 `+`，状态机里发生什么？（对照规则表回答）
4. （选做）什么时候用 `onAppear` 而不是"在 build 里直接执行"？

完成后贴代码/复述状态机给我 review。

---

## 明日预告

阶段一收官后进入阶段二：Day 8 列表与滚动——Scroll / Swiper / Refresh 下拉刷新、**LazyForEach 与 IDataSource**（列表性能的秘密），从此告别卡顿列表。

> 学完 Day 7 = 阶段一（ArkUI 基础）完成 ✅ ——布局、状态、事件三件套齐了，Day 8 起全是进阶内容。
