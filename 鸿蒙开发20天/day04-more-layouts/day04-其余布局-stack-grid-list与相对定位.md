# Day 4 · 其余布局：Stack、Grid、List 与相对定位

> **今日目标**：补齐剩余的常用布局——叠在一起的 Stack、摆成网格的 Grid、能滚动的 List、按参照物定位的 RelativeContainer 和 position。学完这课，常见界面就没有你搭不出来的了。
> **时长**：约 2.5 小时
> **配套代码**：`LayoutShowcase.ets`（综合示例：头像角标 + 九宫格 + 消息列表）

---

## 1. 今天的四个布局各回答一个问题（5 分钟）

| 布局 | 回答的问题 | 典型场景 |
|------|-----------|---------|
| Stack | 怎么把东西**叠**在一起？ | 头像角标、图片上叠文字、悬浮按钮 |
| Grid | 怎么摆成**网格**？ | 九宫格功能入口、相册、仪表盘 |
| List | 怎么做**可滚动的列表**？ | 消息列表、设置列表、商品列表 |
| RelativeContainer / position | 怎么**按参照物**定位？ | 复杂锚定关系、个别元素的绝对位置 |

原则不变：**能线性嵌套解决的，优先线性嵌套**。今天这些是补充，不是替代。

---

## 2. Stack 层叠布局（25 分钟）

子组件按书写顺序入栈，**后写的在上层**：

```arkts
Stack() {
  Text('底层')
  Text('上层')     // 盖在"底层"上面
}
```

`alignContent` 控制整摞内容在容器里的对齐位置：

```arkts
Stack({ alignContent: Alignment.TopEnd }) { ... }
// Alignment：TopStart / Top / TopEnd / Start / Center / End / BottomStart / Bottom / BottomEnd
```

### 经典案例：头像未读角标

```arkts
Stack({ alignContent: Alignment.TopEnd }) {
  Image($r('app.media.avatar'))
    .width(52)
    .height(52)
    .borderRadius(26)

  Text('5')
    .fontSize(11)
    .fontColor(Color.White)
    .width(18)
    .height(18)
    .borderRadius(9)
    .backgroundColor('#F44336')
    .textAlign(TextAlign.Center)
    .offset({ x: 4, y: -4 })      // 往右上一挪，露出"挂在角上"的感觉
}
```

两个要点：
- `.offset({ x, y })` 是**视觉位移**，不改变布局占位——微调角标位置就靠它（Day 2 见过 translate，类似但 translate 属于图形变换，offset 更常用于这种微调）；
- 层级不服气时用通用属性 `.zIndex(数字)` 强行调整，数字越大越靠上。

---

## 3. Grid 网格布局（25 分钟）

Grid 里每个格子必须是 `GridItem`：

```arkts
Grid() {
  GridItem() { Text('1') }
  GridItem() { Text('2') }
  GridItem() { Text('3') }
  GridItem() { Text('4') }
}
.columnsTemplate('1fr 1fr')   // 2 列等分
.columnsGap(8)                // 列间距
.rowsGap(8)                   // 行间距
```

`'1fr 1fr'` 里的 **fr 是"份数"**：`'1fr 2fr'` 就是第一列占 1/3、第二列占 2/3。

### 关键规则：rowsTemplate 决定能不能滚

| 配置 | 行为 | 场景 |
|------|------|------|
| 只设 `columnsTemplate`，不设 rowsTemplate | **可以竖向滚动**，行高由内容决定 | 相册、商品瀑布流 |
| `columnsTemplate` + `rowsTemplate` 都设 | **固定不可滚动**，格子按行列硬分配 | 九宫格入口、计算器按键 |

记住这句：**设了行模板就钉死，只设列模板就能滚**。

完整九宫格示例见 `LayoutShowcase.ets` 中段（2 行 4 列 + 高度 180）。

---

## 4. List 列表（30 分钟）

List 是"专业列表"：自带滚动、分割线、分组能力。子项必须是 `ListItem`：

```arkts
List({ space: 12 }) {              // 子项之间的间距
  ListItem() {
    // 一个列表项的内容，里面随便套 Row/Column
  }
  ListItem() { ... }
}
.width('100%')
.layoutWeight(1)                   // 在页面 Column 里吃掉剩余高度 → 内部滚动
.scrollBar(BarState.Off)           // 隐藏滚动条（On/Auto/Off）
```

内置分割线，不用自己画：

```arkts
List() { ... }
  .divider({
    strokeWidth: 1,
    color: '#F0F0F0',
    startMargin: 68,               // 分割线左侧留空（避开头像）
    endMargin: 16
  })
```

横向列表也是它：`.listDirection(Axis.Horizontal)`。

**为什么不用 Column 塞一堆卡片？** Column 塞几十条会一次全部创建、超出屏幕还得自己套 Scroll；List 自带滚动 + 按需创建（性能细节 Day 8 的 LazyForEach 再深入），还有分组 `ListItemGroup` 能力。**能预见的"多行重复内容"，直接上 List。**

---

## 5. RelativeContainer 与 position（25 分钟）

### RelativeContainer：按参照物定位

子组件先起 `.id()`，再用 `.alignRules()` 声明"我相对谁、怎么对齐"。参照物可以是容器自身（特殊 id `__container__`），也可以是任何兄弟组件：

```arkts
RelativeContainer() {
  Button('返回')
    .id('back')
    .alignRules({
      left: { anchor: '__container__', align: HorizontalAlign.Start },
      top:  { anchor: '__container__', align: VerticalAlign.Top }
    })

  Text('消息中心')
    .id('title')
    .fontSize(18)
    .alignRules({
      center: { anchor: '__container__', align: HorizontalAlign.Center },  // 水平居中
      top:    { anchor: 'back', align: VerticalAlign.Top }                  // 和返回按钮顶对齐
    })

  Text('更多')
    .id('more')
    .alignRules({
      right:  { anchor: '__container__', align: HorizontalAlign.End },
      middle: { anchor: 'back', align: VerticalAlign.Center }               // 和返回按钮垂直居中
    })
}
.width('100%')
.height(56)
```

规则键名：`left / center / right` 管水平锚（配 HorizontalAlign），`top / middle / bottom` 管竖直锚（配 VerticalAlign）。

**克制使用**： RelativeContainer 类似 Android 的 ConstraintLayout，适合"多个元素互为参照"的复杂锚定；普通界面用线性布局嵌套更直观、更好维护。还有个隐藏好处：`.alignRules` 的 `middle` / `center` 规则，比线性布局里反复嵌套居中省事——标题栏这种"左右贴边、中间绝对居中"的结构就很适合。

### position：绝对定位（最后的手段）

```arkts
Button('+')
  .width(52)
  .height(52)
  .type(ButtonType.Circle)
  .position({ x: '78%', y: '80%' })    // 相对父容器左上角
```

相对父容器左上角摆放，支持数字（vp）和百分比。**能不用就不用**——写死的坐标不响应内容变化和多端适配，只有悬浮按钮这类"就是钉在这里"的元素才值得用。配套还有 `.markAnchor({ x, y })` 可以改定位基准点（比如以按钮中心为锚），用到再查。

---

## 6. 综合示例：布局全家福（20 分钟）

`LayoutShowcase.ets` 用一个"首页"把今天三个主角串起来：

- **顶部**：Stack 做头像 + 未读角标
- **中部**：Grid 做固定 2 行 4 列的九宫格入口（rowsTemplate 钉死，不滚动）
- **下部**：List 做消息列表（`layoutWeight(1)` 吃掉剩余高度，内部滚动；每条消息里又嵌了一个 Stack 角标）

注意看它的**拆解过程**：从上到下先切三大块（Column），每块内部再选合适的布局——布局选择是"逐层决策"，不是整页一次性决定的。替换进 Index.ets 跑起来，改改参数感受每个属性的作用。

---

## 7. 常见坑速查

| 现象 | 原因 |
|------|------|
| Stack 里的东西被盖住了 | 层级 = 书写顺序（后写在上）；需要时用 `.zIndex()` |
| Grid 想滚动却滚不动 | 设置了 rowsTemplate 就固定不可滚，去掉它（保留 columnsTemplate） |
| 九宫格自己滚了 | 不想滚却没设 rowsTemplate，补上 |
| List 不显示 / 不滚动 | 高度不确定：给它固定 height，或在外层 Column 里挂 `layoutWeight(1)` |
| position 写死后换设备就歪 | 绝对定位不参与自适应，改用容器布局；真要钉死用百分比 |
| RelativeContainer 子组件全挤在左上角 | 忘了写 `.id()` 或 `.alignRules()`——没有规则就停在默认位置 |

---

## 8. 今日作业（40 分钟）

**作业 1（必做）：消息列表页**
- 顶部标题栏：RelativeContainer 实现（左侧返回、标题绝对居中、右侧"更多"）
- List 消息列表 ≥ 8 条：每条 = 头像（Stack + 未读角标，没未读的不显示角标）+ 昵称/最后一条消息 + 右侧时间
- 用 List 自带 divider 做分割线
- 滚动到底也不出界（想想怎么让 List 只占剩余高度）

**作业 2（选做）：九宫格"我的服务"**
- 2 行 4 列，每个格子 = 色块圆形图标（emoji）+ 名称
- 要求格子完全不可滚动、间距均匀

**思考题**：
1. Stack 里先写的 A 和后写的 B，谁在上面？怎么让 A 反过来盖住 B？
2. 九宫格"固定不可滚"和"可滚动"，分别怎么配置 Grid？
3. 举一个"用线性布局嵌套会很别扭、用 RelativeContainer 一条规则就解决"的场景，并写出那条 alignRules。

完成后贴代码给我 review。

---

## 明日预告

Day 5 是全部课程的分水岭——**状态管理**：@State 到底怎么驱动界面刷新？什么时候刷新什么时候不刷新？加上 if/else 条件渲染和 ForEach 循环渲染，前面所有"复制粘贴重复代码"的地方都会被干掉。
