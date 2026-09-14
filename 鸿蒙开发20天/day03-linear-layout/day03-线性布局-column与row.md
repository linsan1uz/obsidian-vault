# Day 3 · 线性布局：Column 与 Row

> **今日目标**：吃透"主轴 / 交叉轴"这一个概念，掌握 justifyContent、alignItems、space、layoutWeight 四件武器，能纯靠线性布局嵌套搭出真实页面。
> **时长**：约 2.5 小时（布局是手感活，多花的时间都值）
> **配套代码**：`AlignPlayground.ets`（对齐实验场）、`SettingsDemo.ets`（综合示例：设置页）

---

## 1. 布局的心智模型（10 分钟）

ArkUI 的布局 = **容器树**。没有"自由摆放"，每个界面都是这样问出来的：

```
这个区域：横排还是竖排？  → 选 Row 或 Column
里面的东西：横着怎么对齐？竖着怎么对齐？ → justifyContent / alignItems
不够宽/高怎么办？ → 权重 layoutWeight 或比例尺寸
```

整个界面就是 Column/Row 一层套一层。真实项目里 **90% 的界面靠线性布局嵌套完成**，所以今天的内容会用到 Day 20。

---

## 2. 主轴与交叉轴（今天最重要的概念）

每个线性容器都有两根看不见的轴：

| 容器 | 排列方向 = **主轴** | 垂直于排列方向 = **交叉轴** |
|------|--------------------|------------------------------|
| Column（竖排） | 竖直 ↑↓ | 水平 ←→ |
| Row（横排） | 水平 ←→ | 竖直 ↑↓ |

然后记住这组对应关系，**终身受用**：

```
justifyContent → 管主轴对齐（FlexAlign 枚举）
alignItems     → 管交叉轴对齐（Column 用 HorizontalAlign，Row 用 VerticalAlign）
```

记忆法：**justify = 主轴，align = 交叉轴**，跟容器是横是竖无关。两个属性名字永远不变，变的是它们管的实际方向。

Day 1 思考题第 3 题的答案现在正式揭晓：Column 的交叉轴是水平方向，所以对齐枚举叫 `HorizontalAlign`；Row 的交叉轴是竖直方向，所以叫 `VerticalAlign`——**枚举名描述的是轴的实际方向，不是容器类型**。

---

## 3. justifyContent：主轴对齐的 6 个值

```arkts
Column() { ... }
  .justifyContent(FlexAlign.Center)
```

以 Row（从左到右）为例，6 个值的区别：

```
Start        |ABC.........|   全部靠起点
Center       |...ABC......|   居中
End          |.........ABC|   全部靠终点
SpaceBetween |A....B....C.|   两端顶满，中间均分（首尾无空隙）
SpaceAround  |.A...B...C..|   每项两侧空隙相等（首尾空隙 = 中间的一半）
SpaceEvenly  |..A..B..C...|   所有空隙完全相等（含首尾）
```

Column 里同理，方向变成从上到下。SpaceBetween / SpaceAround / SpaceEvenly 三兄弟最容易混：**Between 首尾贴边，Around 首尾有半个空隙，Evenly 首尾有完整空隙**。

**别背，动手**：打开 `AlignPlayground.ets`，把内容替换进 Index.ets，反复改 `.justifyContent()` 的枚举值，看色块怎么动。两分钟建立的手感胜过背十分钟表格。

---

## 4. alignItems：交叉轴对齐

```arkts
Column() { ... }
  .alignItems(HorizontalAlign.Center)   // 子组件水平居中：Start / Center / End

Row() { ... }
  .alignItems(VerticalAlign.Center)     // 子组件垂直居中：Top / Center / Bottom
```

注意**枚举名不一样**，这是新手最高频的编译错误来源。写错时看编译器提示就行，不用背。

最常用的一句话：**"让 Row 里高低不齐的东西垂直居中"** → `.alignItems(VerticalAlign.Center)`，设置项、列表行、工具栏全都靠它。

---

## 5. 间距：space 参数

```arkts
Column({ space: 12 }) {    // 子组件之间统一留 12vp 间距
  Text('第一行')
  Text('第二行')
  Text('第三行')
}
```

- `space` 是构造参数，效果 = 子组件之间均匀插空。比逐个写 margin 更整洁、间距节奏一致，**优先用它**；
- 注意：space 是"子组件**之间**"的间距，3 个子组件只有 2 个间隙。想让首尾也留白，给容器加 `.padding()`；
- 某一处需要特殊间距时，再单独给那个子组件加 margin 微调。

---

## 6. layoutWeight：权重分配剩余空间

```arkts
Row({ space: 12 }) {
  Text('标签')
    .width(60)                       // 固定宽度
  TextInput({ placeholder: '请输入' })
    .layoutWeight(1)                 // ← 吃掉中间所有剩余宽度
  Button('搜索')
    .width(80)                       // 固定宽度
}
.width('100%')
```

`layoutWeight(1)` = "父容器主轴上扣除固定尺寸后，剩下的空间全给我"。多个组件都设权重就按比例分（权重 1:2 就是分 1/3 和 2/3）。

**规则**：设了 layoutWeight 的那个轴上不用再写尺寸（写了也没意义），另一轴的尺寸照常设置。

和 Day 2 的 `Blank()` 对比着记：
- **Blank()** 是个组件，作用 = 占位符，撑开剩余空间 → 适合"左右两端对齐"；
- **layoutWeight** 是属性，谁都能挂 → 适合"这个控件吃掉剩余空间 / 几个控件按份分"。
两者在"占满剩余"这件事上经常互换，但 layoutWeight 能挂在实际控件上（让输入框、文字占满），Blank 只能当垫片。

---

## 7. 嵌套实战：拆解一个设置页（30 分钟）

拿到任何设计稿，先**从外到内画框**：

```
整个页面            → Column（竖排：用户卡、列表、按钮）
 └ 用户卡片          → Row（横排：头像、名字列、VIP徽章）
     └ 名字列        → Column（竖排：名字、签名）
 └ 设置项 × N        → Row（横排：图标、文字列、右侧控件）
     └ 文字列        → Column（竖排：标题、副标题）
 └ 退出按钮
```

完整代码在 `SettingsDemo.ets`，替换进 Index.ets 跑起来。三个值得盯着的细节：

1. **用户卡片**：中间的名字列挂 `.layoutWeight(1)`，右边的 VIP 徽章自动贴到行尾——不需要 Blank，不需要对齐枚举；
2. **每一行设置项**都挂 `.alignItems(VerticalAlign.Center)`，图标/两行文字/开关立刻垂直居中；
3. 页面 Column 里放了一个 `Blank()` 在退出按钮之前——**用空隙把按钮推到底部**，这是"底部固定按钮"最朴素的写法。

另外注意 demo 里"消息通知 / 深色模式"两个设置项是复制粘贴的重复代码——先忍着，Day 5 的 ForEach 会把这种重复干掉，到时候你会更有体感。

---

## 8. 常见坑速查

| 现象 | 原因 |
|------|------|
| 想水平居中却写 justifyContent(FlexAlign.Center) 的 Column 不生效 | Column 的水平方向是**交叉轴**，该用 alignItems(HorizontalAlign.Center) |
| 容器里的对齐完全没反应 | 容器没撑满：补 `.width('100%')`（不撑满就没有可分配的剩余空间） |
| layoutWeight 不生效 | 同上，父容器主轴上没有确定尺寸；或该组件自己又写死了那根轴的尺寸 |
| space 看起来没生效 | 子组件已经占满容器，没有剩余空间可分 |
| alignItems 编译报错 | Column 配 HorizontalAlign，Row 配 VerticalAlign，别配反 |

---

## 9. 今日作业（40 分钟）

**作业 1（必做）：登录页**
- 整体竖排居中：顶部头像图当 logo（80×80 圆角）+ App 名称
- 账号、密码两个 TextInput（密码用 Password 类型）
- 登录按钮：占满页面宽度
- 一行"忘记密码"和"新用户注册"：**分居两端**（想想用 justifyContent 哪个值）
- 底部一行三个圆形色块模拟第三方登录（微信绿 / QQ 蓝 / 微博橙）：**完全均分**（哪个值？）
- 要求：整页只允许 Column / Row / space / justifyContent / alignItems / layoutWeight / padding，不允许 position

**作业 2（选做）：音乐播放条**
- 横排：封面图（60×60 圆角）+ 中间列（歌名 + 歌手两行文字）+ 右侧两个按钮（喜欢 ♥ / 播放 ▶）
- 中间列吃掉所有剩余宽度，播放条固定在页面底部

**思考题**：
1. Column 里让子组件水平居中用哪个属性？Row 里让子组件垂直居中呢？（答出属性 + 枚举才算对）
2. Row 里三个子组件：文字固定宽、输入框吃掉剩余、按钮固定宽，怎么写？
3. `Column({ space: 10 })` 装了 3 个子组件，一共产生几个间隙？想要首尾也各留 10vp 怎么补？

完成后贴代码给我 review，重点看你"主轴/交叉轴"有没有用反。

---

## 明日预告

Day 4 把剩下的布局一次补齐：Stack 层叠（做角标、悬浮按钮）、Grid 网格、List 列表、RelativeContainer 相对布局——之后你就能搭任何常见界面了。
