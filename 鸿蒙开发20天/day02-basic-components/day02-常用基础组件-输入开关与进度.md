# Day 2 · 常用基础组件：输入、开关与进度

> **今日目标**：掌握表单类组件（TextInput / Toggle / Checkbox / Radio / Slider / Progress），学会"三段式"自学新组件的方法，并第一次让界面"动起来"。
> **时长**：约 2 小时
> **配套代码**：同目录 `RegisterForm.ets`（注册表单完整示例）

---

## 1. 先学"怎么学组件"：三段式套路（10 分钟）

ArkUI 内置组件有几十个，你不可能背完，也不用背完。**每个组件都遵循同一个套路**：

```
组件名({ 构造参数 })      ← 圆括号：创建时传什么（初始值、配置对象）
  .专有属性(xxx)          ← 这个组件独有的能力
  .通用属性(xxx)          ← Day 1 学的 width/height/padding，全组件通吃
  .onXxx((参数) => {})    ← 事件回调：用户操作了它，你做什么
```

遇到新组件就按这三段查文档：**构造参数 → 专有属性 → 事件**。

两个自查技巧：
- DevEco 里 **Ctrl + 点击组件名**，直接跳到它的类型声明文件，所有可用属性一览无余；
- 官方文档（developer.huawei.com/consumer/cn/doc/）搜索组件名，每个组件都有示例代码可以直接抄。

---

## 2. TextInput 文本输入框（20 分钟）

```arkts
TextInput({ placeholder: '请输入昵称' })
  .type(InputType.Normal)            // Normal 普通 / Password 密码 / Number 数字 / Email 邮箱
  .maxLength(12)                     // 最大输入长度
  .height(44)
  .backgroundColor('#FFFFFF')
  .borderRadius(8)
  .caretColor('#007DFF')             // 光标颜色
  .onChange((value: string) => {     // 每敲一个字都会回调，value 是当前完整文本
    console.log('输入了：' + value)
  })
```

要点：
- `placeholder` 是占位提示文字；`text` 参数可以传入初始内容；
- `.type(InputType.Password)` 只是**显示**成圆点掩码，onChange 拿到的仍是原文——掩码是壳，数据没变；
- `.enterKeyType(EnterKeyType.Search)` 可以改软键盘回车键的样式（Done / Search / Send 等）；
- TextInput 自带浅灰底和圆角，想自定义外观就覆盖 `.backgroundColor()` 和 `.borderRadius()`。

---

## 3. 表单三件套：Toggle / Checkbox / Radio（25 分钟）

### Toggle 开关

```arkts
Toggle({ type: ToggleType.Switch, isOn: false })
  .selectedColor('#007DFF')          // 打开时的颜色
  .onChange((isOn: boolean) => {
    console.log('开关状态：' + isOn)
  })
```

`type` 可选：`Switch` 开关 / `Checkbox` 勾选样式 / `Button` 按钮样式（按钮式开关要配子组件文字）。
注意 `isOn` 只是**初始值**，用户点击后组件自己变外观，新值要通过 onChange 拿。

### Checkbox 复选框

```arkts
Checkbox({ name: 'agree' })
  .select(true)                      // 默认是否选中
  .selectColor('#007DFF')            // 选中颜色
  .onChange((value: boolean) => {
    console.log('是否勾选：' + value)
  })
```

### Radio 单选框

```arkts
Row({ space: 12 }) {
  Radio({ value: 'male', group: 'gender' })    // group 相同的 Radio 自动互斥
    .onChange((isChecked: boolean) => {
      if (isChecked) { console.log('选了男') }
    })
  Text('男').fontSize(15)

  Radio({ value: 'female', group: 'gender' })
    .onChange((isChecked: boolean) => {
      if (isChecked) { console.log('选了女') }
    })
  Text('女').fontSize(15)
}
```

**互斥是免费的**：`group` 名相同的 Radio 自动"选一个清其他"，不用你写取消逻辑——这是组件化思维的典型体现：通用行为下沉到组件里，你只管用。

---

## 4. Slider 滑块 与 Progress 进度条（20 分钟）

### Slider：让用户在一个区间里选值

```arkts
Slider({ value: 18, min: 1, max: 100, step: 1 })   // 初始值 / 最小 / 最大 / 步长
  .blockColor('#007DFF')             // 滑块圆点颜色
  .selectedColor('#007DFF')          // 已滑过轨道的颜色
  .onChange((value: number, mode: SliderChangeMode) => {
    // mode: Begin 开始拖 / Moving 拖动中 / End 结束
    console.log('当前值：' + value)
  })
```

### Progress：向用户展示进度（只能看，不能操作）

```arkts
Progress({ value: 60, total: 100, type: ProgressType.Linear })
  .color('#007DFF')
  .width('80%')
```

`type` 可选：`Linear` 线性 / `Ring` 环形 / `Capsule` 胶囊 / `ScaleRing` 刻度环 / `Eclipse` 月食。
环形进度条粗细用 `.style({ strokeWidth: 10 })` 调。

**分清方向**：Slider 是**输入**组件（用户 → 数据），Progress 是**展示**组件（数据 → 用户）。Progress 的 value 不会自己涨，你更新数据它才动。

---

## 5. 补几个高消费率的通用属性（15 分钟）

```arkts
Button('提交')
  .enabled(false)                    // 禁用：变灰、不可点击（表单校验必备）
  .visibility(Visibility.None)       // None 不显示也不占位 / Hidden 不显示但占位 / Visible 显示
```

```arkts
Column() { ... }
  .aspectRatio(1)                    // 宽高比：给了宽，高自动算（做正方形头像框神器）
```

图形变换三兄弟——今天混个脸熟，Day 12 动画课它们是主角：

```arkts
Text('我')
  .translate({ x: 20, y: 0 })        // 平移（vp）
  .rotate({ z: 45 })                 // 绕 z 轴旋转（度）
  .scale({ x: 1.2, y: 1.2 })         // 缩放
```

再认识一个**布局小工具组件** `Blank()`：放在 Row/Column 里自动占满剩余空间，做"左标题右开关"这种两端对齐布局神器：

```arkts
Row({ space: 8 }) {
  Text('接收推送')
  Blank()                            // 中间被它撑开
  Toggle({ type: ToggleType.Switch, isOn: false })
}
.width('100%')
```

---

## 6. 先尝一口状态：让界面动起来（20 分钟）

Day 1 的按钮只会打日志，界面纹丝不动。今天提前引入 Day 5 的主角 `@State`，先学**最小可用版**：

```arkts
@Entry
@Component
struct LikeDemo {
  @State count: number = 0           // ① 用 @State 标记的数据 = 状态

  build() {
    Column({ space: 12 }) {
      Text(`点赞数：${this.count}`)   // ② 界面引用状态（模板字符串）
        .fontSize(20)

      Button('点个赞')
        .onClick(() => {
          this.count++               // ③ 事件里重新赋值 → 界面自动刷新
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

跑起来点几下——文字实时变化，这就是声明式 UI 的威力：**你没写任何"更新界面"的代码，只改了数据**。

今天先记住三条使用规则，原理 Day 5 讲透：
1. `@State` 变量声明时**必须给初始值**；
2. 事件回调里**重新赋值**（`this.count = xxx`）；
3. 赋值后，build() 里**引用了这个变量的部分自动更新**。

---

## 7. 综合示例：注册表单

完整代码在 `RegisterForm.ets`，把内容替换进 Index.ets 跑起来。它把今天所有组件串成一个真实场景：

- 昵称 `TextInput`（限长）+ 密码 `TextInput`（Password 类型）
- 密码强度 `Progress`：随输入实时变化，颜色随强度从红→橙→绿
- 年龄 `Slider` + 实时数值文字
- 性别 `Radio`（同 group 互斥）、推送通知 `Toggle`（Blank 两端对齐）
- 协议 `Checkbox`：不勾选时注册按钮 `enabled(false)`
- 所有值存在 `@State` 里，点注册一次性输出

重点观察一个模式：**每个组件的 onChange 都在做同一件事——把界面上的新值存进状态变量**。界面（输入框）和数据（变量）始终保持同步，这是以后所有表单页的标准写法。

---

## 8. 今日作业（30 分钟）

**作业 1（必做）：个人资料编辑页**
- 头像（Image）+ 昵称 TextInput（maxLength 12）+ 个性签名 TextInput
- 性别 Radio 单选
- Slider 选择"每日学习目标（小时）"，旁边实时显示 `X 小时`
- Toggle："仅自己可见"
- Progress 显示"资料完成度"：昵称、签名、性别各占 1/3，填好一项加一点（用 @State 存各项值，算出 0~100）
- 保存按钮：资料完成度 100% 才 enabled，点击后 console.log 输出全部信息

**作业 2（选做）：升级 Day 1 名片**
- 给"点个赞"加 @State 计数，按钮显示"点赞 (n)"
- 加一个"取消赞"按钮，计数为 0 时禁用

**思考题**：
1. `.type(InputType.Password)` 之后，onChange 里拿到的 value 是圆点掩码还是原文？
2. `Toggle({ isOn: true })` 的 isOn 是"初始值"还是"永远保持的值"？如果点击开关后你不写 onChange 存值，下次界面刷新会发生什么？由此说说：为什么"界面状态"和"数据状态"必须分开管？
3. `visibility(Visibility.None)` 和"用 if 把组件从代码里去掉"，都能让界面看不见，猜猜本质区别是什么？

完成后把代码贴给我 review。

---

## 常见坑速查

| 现象 | 原因 |
|------|------|
| Toggle 点击后外观变了，逻辑里却读不到新值 | isOn 只是初始值，必须在 onChange 里自己存 |
| Slider 拖动后想用代码把它拨回去，没反应 | value 参数只在初始时生效；"程序控制滑块位置"要等状态管理课之后的受控用法 |
| TextInput 想改背景发现有默认灰底 | 覆盖 `.backgroundColor()` + `.borderRadius()` 即可 |
| Progress 数值变了但条不动 | 检查 value 是否接了 @State 变量；传常量它永远不动 |
| Radio 没有互斥 | 检查 group 名是否完全一致（大小写敏感） |
| 模板字符串报错 | 反引号 `` ` `` 不是单引号；ArkTS 里 `` `文本${变量}` `` 的写法和 TS 一致 |
