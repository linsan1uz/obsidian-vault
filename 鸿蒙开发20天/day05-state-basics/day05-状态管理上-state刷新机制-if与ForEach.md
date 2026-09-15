# Day 5 · 状态管理（上）：@State 深入、刷新机制、if 与 ForEach

> **今日目标**：彻底搞懂 @State 的刷新机制（什么变化能触发界面刷新、什么不能）；掌握条件渲染 if/else 和循环渲染 ForEach，把前面所有复制粘贴的重复代码干掉。
> **时长**：约 2.5~3 小时（分水岭课程，慢就是快）
> **配套代码**：`StateLab.ets`（刷新机制实验场，今天的核心）

---

## 1. @State 到底做了什么（20 分钟）

Day 2 学了最小用法，今天补全心智模型：

```
@State 变量 = 被框架"装了监听器"的数据
      │
      ├─ 你对它做了"能被观察到"的修改
      ↓
框架重新执行这个组件的 build()
      ↓
框架对比新旧界面描述，只把真正变化的部分更新到屏幕（最小化更新）
```

三条使用规则，今天补上细节：

1. **必须本地初始化**：`@State count: number = 0`，不初始化直接编译报错；
2. **只有"被观察到"的修改才触发刷新**（下一节详讲，今天最重要的知识点）；
3. **@State 是组件私有的**：只在当前组件内生效，想传给子组件要 @Prop/@Link——Day 6 的内容。

另外记住：状态一变，**build() 会重新执行**。框架的 diff 保证了性能，但 build 里依然别放昂贵计算（比如在 build 里排序一个大数组）——要算就在事件回调里算好存进状态。

---

## 2. 什么变化能触发刷新？（今天最重要的表格）

```arkts
@State count: number = 0
@State user: UserProfile = new UserProfile('张三', 18)   // 类对象
@State list: TodoItem[] = [...]                          // 对象数组
```

| 操作 | 刷新？ | 原因 |
|------|--------|------|
| `this.count = 1` / `this.count++` | ✅ | 整体赋值 |
| `this.user.age = 19` | ✅ | 对象**第一层**属性赋值 |
| `this.user = new UserProfile(...)` | ✅ | 整体替换，永远有效 |
| `this.list.push(x)` / `pop` / `splice` / `this.list[0] = x` | ✅ | 数组项的增删改（第一层） |
| `this.user.address.city = 'x'` | ❌ | 对象**第二层**，观察不到 |
| `this.list[0].done = true` | ❌ | 数组元素的属性 = 第二层，观察不到 |
| `let c = this.count; c++` | ❌ | 没碰状态本身 |

**观察规则一句话：@State 只看第一层——整体赋值、对象第一层属性、数组项增删改。再深就看不见了。**

`this.list[0].done = true` 这种是真实项目里最高频的 bug：数据明明变了，界面纹丝不动。两种解法：

1. **整体替换 / 整项替换**（推荐，今天就用）：
   ```arkts
   // 替换单项：splice 是数组层操作，能被观察到
   this.list.splice(0, 1, new TodoItem(item.id, item.title, !item.done))
   // 全量映射出新数组再赋值（不可变风格）
   this.list = this.list.map(...)
   ```
2. **@Observed + @ObjectLink**：让对象自己具备观察能力——Day 17 全局状态课细讲。

**动手验证**：把 `StateLab.ets` 替换进 Index.ets，按钮都点一遍，每个按钮都标注了 ✅；然后再试着加一个"直接改 `todo.done`"的按钮，亲眼看它失效——这个坑你自己踩过一次才防得住。

---

## 3. if / else 条件渲染（20 分钟）

build() 里可以直接写 if/else/else if：

```arkts
if (this.todos.length === 0) {
  Text('没有待办，躺平吧')
    .fontColor('#999999')
} else {
  Text(`还有 ${this.todos.length} 件事没做`)
    .fontColor('#E53935')
}
```

关键语义：**切换分支 = 销毁旧分支的组件、创建新分支的组件**。由此推出和 `visibility` 的本质区别（Day 1 思考题第 3 题的答案）：

| | if/else | Visibility.None |
|---|---------|-----------------|
| 组件是否在组件树里 | 不满足就不在（销毁） | 一直在（只是不显示不占位） |
| 组件内部状态 | **切换即丢失** | 保留 |
| 适合 | 分支内容完全不同 | 同一个东西频繁显隐（如密码可见切换） |

---

## 4. ForEach 循环渲染（40 分钟，重头戏）

三个参数，一个都不少：

```arkts
ForEach(
  this.messages,                  // ① 数据源：@State 数组
  (msg: ChatMsg) => {             // ② 组件生成函数：每项长什么样
    ListItem() { Text(msg.name) }
  },
  (msg: ChatMsg) => msg.id.toString()   // ③ 键值生成函数：每项的唯一身份证
)
```

### 键值生成函数为什么必须有、为什么不能糊弄？

框架靠 key 识别每一项的身份：数据变化时，**key 相同的项做就地更新，key 新出现的项创建，key 消失的项销毁**——这就是最小化更新的基础。

两条铁律：
- **要稳定且唯一**：用数据里的业务唯一标识（id），不要用 `JSON.stringify(item)`（性能差）；
- **不要用 index**：一旦数组发生"删除中间项 / 重排"，后面的项 index 全部前移，框架会张冠李戴地把旧组件更新到错误的数据上（界面错乱的经典来源）。Day 8 讲性能时你会再见到这条。

### 实战：干掉 Day 4 的复制粘贴

Day 4 的消息列表每条 ListItem 都是复制粘贴的。现在换成数据驱动：

```arkts
class ChatMsg {
  id: number
  name: string
  preview: string
  time: string
  color: string
  unread: number

  constructor(id: number, name: string, preview: string,
              time: string, color: string, unread: number) {
    this.id = id
    this.name = name
    this.preview = preview
    this.time = time
    this.color = color
    this.unread = unread
  }
}

@State messages: ChatMsg[] = [
  new ChatMsg(1, '张三', 'Day 5 的课程更新了', '09:12', '#4A90D9', 2),
  new ChatMsg(2, '李四', '作业记得交', '昨天', '#50B87A', 0),
]

List({ space: 12 }) {
  ForEach(this.messages, (msg: ChatMsg) => {
    ListItem() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Text(msg.name[0])                          // 头像：取名字首字
            .fontSize(18).fontColor(Color.White)
            .width(44).height(44).borderRadius(22)
            .backgroundColor(msg.color)
            .textAlign(TextAlign.Center)
          if (msg.unread > 0) {                      // if 和 ForEach 随便混用
            Text(`${msg.unread}`)
              .fontSize(10).fontColor(Color.White)
              .width(16).height(16).borderRadius(8)
              .backgroundColor('#F44336')
              .textAlign(TextAlign.Center)
              .offset({ x: 3, y: -3 })
          }
        }
        Column({ space: 4 }) {
          Text(msg.name).fontSize(16)
          Text(msg.preview).fontSize(13).fontColor('#999999').maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(msg.time).fontSize(12).fontColor('#CCCCCC')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(Color.White)
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
    }
  }, (msg: ChatMsg) => msg.id.toString())
}
.layoutWeight(1)
```

以后加消息 = 往数组里 push 一条数据，界面自动多一行；改 UI = 只改 ForEach 里的模板一处。**这就是"数据驱动界面"的日常形态。**

---

## 5. 渲染控制总结

build() 里允许出现的"逻辑"只有四种：

```
组件与嵌套    Text() / Column() { ... }
属性链        .fontSize(16).onClick(...)
条件渲染      if / else if / else
循环渲染      ForEach（以及 Day 8 的 LazyForEach、Day 9 的 Repeat）
```

再复杂的逻辑（计算、排序、判断走哪个分支更划算）都放到**成员方法**或**事件回调**里去。

---

## 6. 常见坑速查

| 现象 | 原因 |
|------|------|
| 数据明明变了，界面不刷新 | 改的是第二层属性（如 `list[0].done = true`），用 splice 整项替换或整体赋值 |
| push 之后界面没反应（少数场景） | 保险起见换成整体赋值 `this.list = [...this.list, x]` |
| ForEach 列表删中间一项后，后面几行显示错乱 | 键用了 index，换成稳定唯一的业务 id |
| if 切换分支后输入框内容丢了 | 分支切换 = 销毁重建；要保状态用 visibility |
| build 越来越卡 | build 里放了昂贵计算，挪到事件回调里，结果存状态 |

---

## 7. 今日作业（45 分钟）

**作业 1（必做）：待办清单 ToDo v1**
- 顶部：TextInput + "添加"按钮（回车也行，`onSubmit` 试一试）→ push 进 @State 数组
- List + ForEach 渲染待办项：每项有"完成"和"删除"两个按钮
- 点"完成"切换状态：已完成加删除线（查一下 Text 的 `.decoration()` 属性）+ 文字变灰——注意这个操作正好踩在"第二层"的坑上，用今天的解法解决
- 底部一行统计："共 X 项，未完成 Y 项"；列表为空时显示占位文案（用 if）
- 键值生成函数用 id，不许用 index

**作业 2（选做）**：把 Day 4 的 LayoutShowcase 消息列表改成 ForEach 数据驱动，再加一个"全部已读"按钮（把所有 unread 置 0，观察角标怎么消失——注意用会触发刷新的写法）。

**思考题**：
1. `this.list.push(item)` 能触发刷新吗？`this.list[0].done = true` 呢？为什么后者不行，怎么改？
2. ForEach 的键为什么不能用 index？构造一个"删除中间项导致显示错乱"的具体场景。
3. "密码框后面的眼睛图标切换明文/密文"这个需求，用 if 还是 visibility 实现？为什么？

完成后贴代码给我 review，重点检查你有没有踩"第二层"的坑。

---

## 明日预告

Day 6 状态管理（下）：组件拆分与父子通信——@Prop / @Link / @Watch，把"一个巨大 build"拆成干净的自定义组件树。
