# Day 8 · 列表与滚动：Scroll / Swiper / Refresh / LazyForEach

> **今日目标**：让界面"动起来、刷得动、不卡顿"——掌握滚动容器与轮播、下拉刷新+上拉加载的完整闭环、LazyForEach 懒加载列表与 IDataSource 数据源。学完即拥有"资讯浏览页"里程碑（Day 13）的全部列表零件。
> **阶段**：阶段二 · ArkUI 进阶（Day 8–13）开篇
> **配套代码**：`NewsListDemo.ets`（三课时最终形态：轮播 + 刷新加载 + 懒加载列表）
> **授课节奏**：3 个课时——①Scroll+Swiper ②Refresh+分页加载 ③LazyForEach+IDataSource

---

## 第 1 课时 · Scroll 与 Swiper

### 1.1 为什么内容会"被裁掉"——Scroll

ArkUI 的 Column 像**固定大小的画框**：画比框大，多出的部分直接裁掉，且默认没有"挪画"能力（不像网页有无限长的纸）。**想滚动，必须显式套一个"传送带"——Scroll 组件**。设计动机：不是所有内容都该滚（计算器的 20 个键就不该），滚不滚由开发者显式声明。

```arkts
Scroll() {                          // 传送带：包住要滚动的内容
  Column() { /* 20 条新闻 */ }      // 货物：Column 自己不会滚，是 Scroll 在挪它
}
.scrollBar(BarState.Auto)          // 滚动条：滑动时才出现（On 常驻 / Off 隐藏）
.edgeEffect(EdgeEffect.Spring)     // 到头橡皮筋回弹
.onReachEnd(() => { ... })         // 滚到底回调：分页加载的挂钩子（第 2 课时用）
```

> **嵌套铁律**：竖向 Scroll 里不要再套竖向滚动组件（双传送带打架）；内层需要滑就换横向（`.scrollable(ScrollDirection.Horizontal)`）或 Swiper。

### 1.2 轮播图 —— Swiper

App 顶部"三张图自动轮滑 + 小圆点"的横幅是行业标配，Swiper 是配好的成品：滑动翻页 + 指示器 + 循环 + 自动播放。

> 类比：Scroll 是随便滑的传送带，Swiper 是**一页一页翻的幻灯机**——一次只展示一屏。

```arkts
Swiper() { ForEach(banners, ...) }   // 花括号里每个直接子组件 = 一页
.width('100%').height(160)
.autoPlay(true)                      // 自动播放（用户手指一碰自动暂停）
.interval(2000)                      // 2 秒翻页
.loop(true)                          // 循环（只有 1 页别开）
.indicator(new DotIndicator()        // API 10+ 新写法（旧对象写法已废弃！见错题）
  .color('#80FFFFFF')                // 未选中：半透明白（#AARRGGBB 透明度在前！）
  .selectedColor(Color.White))       // 选中：纯白
.onChange((index: number) => { ... })  // 翻页回调（index 从 0 数）
```

偷懒写法：`.indicator(true)` 默认小圆点 / `.indicator(false)` 隐藏。加分项眼熟即可：`.displayCount(1.2)` 露半张暗示可滑、`.maxDisplayCount(5)` 圆点收起。

---

## 第 2 课时 · Refresh 下拉刷新 + 上拉加载

### 2.1 下拉刷新 —— Refresh

**Why**：移动端数据会过期（10 分钟前的新闻列表已有突发），且没有 F5——"下拉→转圈→松手→新内容到顶"是行业标准手势（2009 年 Twitter 发明）。类比：饮水机按钮，列表是水杯，松手那一刻出水。

```arkts
Refresh({ refreshing: $$this.isRefreshing }) {   // 皮：双向管道 $$ = 我改它圈转 / 它替我置 true
  Scroll() { ... }                               // 骨：内部结构原样不变
}
.onRefreshing(() => {                            // 心：用户下拉到阈值松手时触发
  // 拉数据……拉完必须手动 this.isRefreshing = false 收圈
})
```

- **`$$` 双向绑定**：`@Prop` 单行道、`@Link` 双行道，`$$` 就是双行道语法——下拉松手后圈自动转（它把 isRefreshing 置 true），你负责拉完数据改回 false。
- **头号新手坑**：忘了 `isRefreshing = false` → 圈转到天荒地老。

### 2.2 上拉加载 —— 分页三道防线

**Why**：服务器每次只给一页（如 10 条），滚到底自动要下一页接在后面（= 分页加载）。裸挂 `onReachEnd` 会疯狂重复触发 → 几十个并发请求 → 数据错乱，所以要设防：

| 防线 | 作用 | 实现 |
|------|------|------|
| 1. 加载锁 | 上页没回来不许再要 | `isLoadingMore` 布尔，进门卫 `if (锁) return` |
| 2. 页码推进 | 每次要第 page+1 页 | `page++` |
| 3. 没有更多 | 最后一页到了永久停 | `hasMore` 旗子 |

- `setTimeout(() => {...}, 1000)` = 闹钟：1 秒后执行——**假装网络请求返回**（真请求 Day 15 学），先把异步骨架搭对。
- 尾部"⏳ 加载中 / —已经到底啦—"用 Day 5 的 `if` 条件渲染，挂 ForEach **外面**。
- `counter` 全局编号保证 key 唯一；刷新时 `counter/page` 要随数据一起重置。

---

## 第 3 课时 · LazyForEach 与 IDataSource

### 3.1 为什么 ForEach 是"隐形胖子"

**ForEach 渲染时把数组全部变成真实组件**：1 万条 = 1 万个 Text 全建好，屏幕只看得见 10 条，9990 个看不见的组件白占内存，首屏卡、滚动掉帧。

> 笨厨师接 1000 桌的单一次性全炒 vs **来了哪桌炒哪桌**（LazyForEach）。

数据一条不少（存在数据源里），变的只是**组件生成策略**：滚出视野的组件可回收，滚入的现场创建。

```arkts
List() {                                          // 铁律：懒循环只认 List
  LazyForEach(this.source, (item, index) => {
    ListItem() { ... }                            // 法定外壳，不可少
  }, (item, index) => `${index}-${item}`)         // 第三参数 key 与 ForEach 相同
}
```

- **为什么不能 Scroll**：Scroll 眼里只有整块布料，不知道谁在屏幕外；List 天生认识 ListItem。
- **List 里 `if` 的孩子也要包 ListItem**（"加载中"提示搬过来要穿外套）。

### 3.2 IDataSource —— 按需供货的仓库合同

普通数组是"一次性全给"，LazyForEach 要"要哪件给哪件"——只收 `implements IDataSource` 的对象。**接口 = 加盟合同**，4 项义务不可少：

```arkts
class NewsSource implements IDataSource {
  private news: string[] = []
  private listeners: DataChangeListener[] = []     // 登记在册的"订货员"

  totalCount(): number { return this.news.length }            // 义务1：总共几件
  getData(index: number): string { return this.news[index] }  // 义务2：第 index 件
  registerDataChangeListener(l) { ... push ... }              // 义务3：登记
  unregisterDataChangeListener(l) { ... splice ... }          // 义务4：退订

  reloadAll(data: string[]): void {                // 进货：整批换
    this.news = data
    for (const l of this.listeners) { l.onDataReloaded() }    // 必须广播！
  }
  addMore(data: string[]): void {                  // 进货：追加
    const start = this.news.length
    this.news = this.news.concat(data)
    for (const l of this.listeners) { l.onDataAdded(start, data.length) }
  }
}
```

- **改完数据必须广播**（`onDataReloaded()` 全换 / `onDataAdded(起始, 个数)` 增量），否则 UI 纹丝不动——**头号坑**。
- `private source = new NewsSource()` **不需要 @State**：驱动界面的是广播，不是装饰器——和过去所有写法最大的观念转变。
- 页面侧改造只有三处：Scroll+Column→List、ForEach→LazyForEach(source)、`newsList=.../push`→`source.reloadAll/addMore`。轮播、圈、三道防线原样不动。

### 3.3 选型速查

| 场景 | 用哪个 |
|------|--------|
| < 100 条、固定不变（设置页、计算器键盘） | **ForEach**，别过度设计 |
| 上百条、持续追加、无限流 | **LazyForEach + List** |
| 中间地带 | 先 ForEach，卡了再换 |

---

## 错题记录

### 1. `.indicator({ indicatorStyle: {...} })` 报错（Day 8 实错）

- **报错原因**：网上的教程代码是 API 8 旧语法；本机 SDK（API 10+）签名已是 `indicator(value: DotIndicator | DigitIndicator | boolean)`，旧对象形式 `@deprecated since 10`，编译器直接拒收（*"not assignable to parameter of type..."*）。
- **修正**：新版是链式类写法 —— `new DotIndicator().color('#80FFFFFF').selectedColor(Color.White)`，或偷懒 `.indicator(true)`。
- **连带错误**：`#FFFFFF80` 是 CSS 的 RRGGBBAA；**ArkUI 是 `#AARRGGBB` 透明度在最前**，半透明白 = `#80FFFFFF`（写错不报编译错，但颜色悄悄不对）。
- **方法论**：教程/网上的代码 ≠ 你 SDK 的现行 API。报错先查本机权威声明：`{DevEco安装目录}/sdk/default/openharmony/ets/component/*.d.ts`（本次为 `swiper.d.ts`，grep 接口名即可）。

---

## 常见坑速查

| 现象 | 原因 |
|------|------|
| 下拉刷新圈永远在转 | 拉完忘了 `isRefreshing = false` |
| 快速滑到底重复加载 | onReachEnd 没设加载锁 |
| 改了数据界面不动 | 忘了广播 `onDataReloaded()/onDataAdded()` |
| LazyForEach 一片红/不显示 | 没放 List 里，或条目没包 ListItem |
| List 里 if 的提示不显示 | List 的孩子必须是 ListItem，if 里也要包 |
| getData 越界崩溃 | totalCount 与数组长度不同步 |
| indicator 报错 | 用了 API 8 旧对象写法（见错题） |
| 轮播第一个点颜色怪异 | 颜色 alpha 写反了（#AARRGGBB） |
| 竖向 Scroll 里内层划不动 | 双竖向滚动嵌套打架 |
| ForEach 大列表首屏卡 | 换 LazyForEach + List |

## 今日作业（Day 8）

1. **必做**：跑通 `NewsListDemo.ets`，按验收清单过一遍——下拉 1 秒后新数据顶掉旧的且收圈；快速连滑到底只出现一条"加载中"；刷满 3 页变"已经到底啦"；轮播 2 秒翻页且控制台打印页码。
2. **进阶**：不看课件，把第 2 课时的 ForEach 版自己改成 LazyForEach 版，重点默写 `NewsSource` 的 4 义务 + 2 广播。
3. **思考题**：
   - 为什么 LazyForEach 必须在 List 里、Scroll 不行？
   - `reloadAll` 后忘了调 `onDataReloaded()` 会怎样？
   - 什么场景下 ForEach 反而是更好的选择？（用选型表回答）

完成后贴代码给我 review。

---

## 明日预告

**Day 9 · 自定义组件进阶**：@Builder / @BuilderParam · @Styles / @Extend · @Require · @Reusable · 泛型组件——把重复 UI 抽成"零件工厂"的全套手艺。
