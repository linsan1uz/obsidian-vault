# Day 1 · ArkUI 与声明式 UI：写出你的第一个页面

> **今日目标**：理解"声明式 UI"到底是什么，认识工程结构，独立写出第一个包含文本/图片/按钮的页面。
> **时长**：约 2 小时（30 分钟读 + 90 分钟写）
> **配套代码**：同目录 `Index.ets`（综合示例完整版）

---

## 1. 什么是 ArkUI（15 分钟）

ArkUI 是鸿蒙的**应用界面开发框架**，以后你写的所有界面代码都通过它完成。它采用**声明式 UI** 范式。

### 命令式 vs 声明式：一句话看懂

传统开发（如 Android 早期 View 体系）是**命令式**的——先创建控件，再手动找到它、手动改它：

```java
// 命令式：状态变了，你要自己一步步操作界面
TextView tv = findViewById(R.id.name);
tv.setText("新名字");
```

ArkUI 是**声明式**的——你只描述"界面在这个状态下长什么样"，状态一变，**框架自动刷新界面**：

```arkts
// 声明式：你只描述"样子"，更新交给框架
Text(this.name)   // this.name 变了 → Text 自动显示新值，你不用管
```

**核心心智模型：`UI = f(state)`，界面是状态的函数。** 这一句是整个 ArkUI 的灵魂，今天先记住，Day 5 会彻底讲透。

### ArkUI 代码三要素

| 要素  | 是什么               | 例子                                       |
| --- | ----------------- | ---------------------------------------- |
| 组件  | 界面积木（内置几十种，也可自定义） | `Text()` `Image()` `Button()` `Column()` |
| 属性  | 链式调用配置外观/行为       | `.fontSize(30).width('100%')`            |
| 状态  | 驱动界面变化的数据（带装饰器）   | `@State count: number = 0`（Day 5 讲）      |

---

## 2. 认识工程结构（15 分钟）

用 DevEco Studio 新建 Empty Ability 工程后，重点认识这些目录：

```
MyApplication
├── AppScope                        # 应用级配置（应用图标、应用名称）
│   └── app.json5
├── entry                           # 主模块（一个应用可含多个模块，先只管 entry）
│   └── src/main
│       ├── ets                     # ★ 你的全部源码
│       │   ├── entryability
│       │   │   └── EntryAbility.ets  # 应用入口，管理应用生命周期
│       │   └── pages
│       │       └── Index.ets         # ★ 首页（今天的主战场）
│       ├── resources               # ★ 资源目录（Day 13 细讲）
│       │   └── base/media          #   图片放这里
│       └── module.json5            # ★ 模块配置（页面注册、权限声明）
└── build-profile.json5             # 构建配置
```

启动关系一句话：**EntryAbility 启动后，加载 module.json5 中配置的首页（pages/Index）**。

---

## 3. 页面最小骨架（20 分钟）

打开 `pages/Index.ets`，删掉示例代码，敲这个最小骨架：

```arkts
@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('Hello ArkUI')
    }
  }
}
```

逐行拆解，**每一行都必须理解**：

| 代码              | 含义                                              |
| --------------- | ----------------------------------------------- |
| `@Entry`        | 装饰器：标记这是一个**独立页面**（可作为路由跳转目标）。一个文件最多一个          |
| `@Component`    | 装饰器：标记这是一个**自定义组件**。页面 = 被 @Entry 的组件；组件不一定都是页面 |
| `struct Index`  | 组件用 `struct` 声明（不是 class），名字首字母大写               |
| `build()`       | **UI 描述函数**：组件必须有且只有一个 build()，界面长什么样全在这里描述     |
| `Column(){...}` | 内置容器组件，垂直排列子组件；子组件写在大括号里                        |
| `Text('...')`   | 文本组件                                            |

写完点编辑器右侧的 **Previewer** 打开预览器，应该能看到文字。试着改改文字内容，观察热刷新。

### 三条新手必守规则

1. **build() 里只能有一个根组件**。不能并排写两个 Text，必须包在 Column / Row / Stack 等容器里。
2. **build() 里只能描述 UI**：只能出现组件、属性链、if/else、ForEach，不能写 `let x = 1` 这种语句。
3. 属性写在组件**圆括号后面**用点号链式连接：`Text('hi').fontSize(30)`，别写进花括号里。

---

## 4. 链式属性：给组件做配置（20 分钟）

所有组件都支持链式配置，下面这些是**通用属性**（全组件通吃）：

```arkts
Text('你好，鸿蒙')
  .fontSize(30)                          // 字号（fp）
  .fontWeight(FontWeight.Bold)           // 字重，也可写数字 400/500/600
  .fontColor('#182431')                  // 颜色支持 '#RRGGBB' / '#AARRGGBB' / Color.White
  .textAlign(TextAlign.Center)           // 文字对齐
  .width('100%')                         // '100%' 相对父容器；number 时单位 vp
  .height(50)
  .padding(12)                           // 内边距，也可 { left: 10, top: 8 }
  .margin({ top: 8 })                    // 外边距
  .backgroundColor('#F1F3F5')            // 背景色
  .borderRadius(12)                      // 圆角
  .border({ width: 1, color: '#EEEEEE' })// 边框
  .opacity(0.9)                          // 透明度
```

> **单位说明**：尺寸数字默认单位是 **vp**（虚拟像素，自动适配屏幕密度），字号是 **fp**（随系统字体大小缩放）。你只管写数字，鸿蒙帮你适配，不用像 Android 那样纠结 px/dp 转换。

---

## 5. 三个入门组件（30 分钟）

### Text 文本

常用属性见上。补充一个超长文本截断的组合技：

```arkts
Text('一段很长很长的简介文字，超出两行就省略...')
  .maxLines(2)                                        // 最多显示 2 行
  .textOverflow({ overflow: TextOverflow.Ellipsis })  // 超出部分显示省略号
```

### Image 图片

```arkts
// 1) 本地资源：把图片放进 resources/base/media/ 后用 $r 引用（注意：不写扩展名）
Image($r('app.media.avatar'))
  .width(96)
  .height(96)
  .borderRadius(48)               // 圆形头像技巧：圆角 = 宽高的一半
  .objectFit(ImageFit.Cover)      // 裁剪填充不变形，类似 CSS 的 object-fit

// 2) 网络图片：直接传 URL（需在 module.json5 声明 INTERNET 权限，Day 14 讲）
Image('https://example.com/photo.png')
```

`objectFit` 常用值：`Cover` 等比裁剪填满（最常用）/ `Contain` 等比完整显示留白 / `Fill` 拉伸变形（一般别用）。

### Button 按钮

```arkts
Button('登录')
  .type(ButtonType.Capsule)       // 形状：Capsule 胶囊(默认) / Circle 圆形 / Normal 矩形
  .width(200)
  .height(44)
  .backgroundColor('#007DFF')
  .onClick(() => {                // 点击事件——一切交互的起点
    console.log('按钮被点了')
  })

// 富内容按钮：花括号里放子组件
Button() {
  Text('同意并继续').fontSize(16)
}
```

查看日志：DevEco 底部 **Log 窗口**，`console.log` 在预览器和真机上都能看到。

---

## 6. 综合示例：个人名片卡片

把手敲下面这段完整代码进 Index.ets（**别复制粘贴，手敲才长记性**）：

```arkts
@Entry
@Component
struct ProfileCard {
  build() {
    Column({ space: 12 }) {              // space: 子组件之间的间距
      Image($r('app.media.avatar'))
        .width(96)
        .height(96)
        .borderRadius(48)
        .objectFit(ImageFit.Cover)

      Text('张三')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#182431')

      Text('鸿蒙开发 · 第 1 天')
        .fontSize(14)
        .fontColor('#999999')

      Row({ space: 8 }) {                // Row：水平排列
        Text('ArkTS')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
        Text('ArkUI')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
        Text('HarmonyOS')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
      }

      Button('点个赞')
        .width(140)
        .height(36)
        .onClick(() => {
          console.log('点赞!')
        })
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)  // Column 的交叉轴（水平方向）居中
  }
}
```

注意 `Column({ space: 12 })` 这个写法：**圆括号 = 配置参数，花括号 = 子组件**。这个模式贯穿 ArkUI 所有容器组件，记住它。

> 运行前准备：随便找一张图改名为 `avatar.png` 放进 `resources/base/media/`。

---

## 7. 今日作业（30 分钟）

**作业 1（必做）**：不参考示例，独立做一张"你的个人名片"页面：
- 头像（media 目录随便放一张图）+ 姓名 + 一句话签名
- 3 个技能标签（用 Row + Text 实现）
- 一个按钮，点击后在日志输出一句话

**作业 2（选做 · 挑战）**：做一枚"徽章"：外层 Column 居中，里面一个 120×120 的 Stack，Stack 里放一个圆形色块 + 居中文字"HO"，下方放你的名字和日期。（Stack 还没正式学，先靠感觉试试，明天讲布局就通了）

**思考题（交作业时口头答我）**：
1. build() 里能不能直接写两个 Text（不套容器）？为什么？
2. `.fontSize(30)` 写在 `Text('hi')` 的花括号里行不行？
3. Column 的 `alignItems` 用 `HorizontalAlign`，Row 的却用 `VerticalAlign`，猜猜为什么？（提示：交叉轴方向）

完成后把 Index.ets 代码贴给我 → 我来 review。明天 Day 2：更多基础组件 + 通用属性体系，作业里的写法都会被用到。

---

## 常见报错速查

| 现象 | 原因 |
|------|------|
| `Cannot find name 'xxx'` | 组件名拼错；内置组件无需导包，自定义的要 import |
| 预览器空白 | 页面必须有 @Entry 才能预览；确认改的是 module.json5 里注册的那个页面 |
| build 里写逻辑报错 | build() 只能描述 UI，逻辑放事件回调和组件方法里 |
| 图片不显示 | media 目录文件名只能小写字母/数字/下划线；$r 里不写扩展名 |
