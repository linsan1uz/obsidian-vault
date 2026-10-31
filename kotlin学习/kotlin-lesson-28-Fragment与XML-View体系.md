# Kotlin 第 28 课：Fragment 与 XML View 体系

> 适用读者：已完成第 9～10、15～17 课（ViewModel、LiveData/StateFlow、Compose、Navigation）。本课面向**读旧代码 / 混编**，不是鼓励新项目全上 Fragment。
> 核心收获：知道何时还需要 View/Fragment；会用 ViewBinding；分清 Fragment 与 Compose 生命周期；会用 `activityViewModels` 共享状态；用 Fragment Result API 替代乱传接口 / 部分 EventBus 场景。

---

## 一、什么时候还需要 View / Fragment？

| 场景 | 建议 |
|---|---|
| 全新 App | **Compose + Navigation Compose**（第 15～17 课） |
| 维护老项目、大量 XML | 继续 Fragment + ViewBinding，新屏幕可逐步 Compose |
| 必须嵌入的第三方 UI（部分地图 / 支付 SDK） | Fragment / View 容器里塞，外层仍可用 Compose `AndroidView` |
| 单 Activity 多页面且已是 NavHost Fragment | 先别整体重写，按特征迁移 |

口诀：**新写优先 Compose；懂 Fragment 是为了读历史与混编。**

## 二、依赖

```kotlin
dependencies {
    implementation("androidx.fragment:fragment-ktx:1.9.1")
    implementation("androidx.activity:activity-ktx:1.13.0")
    // ViewBinding：不靠额外依赖，开开关即可
}
android {
    buildFeatures {
        viewBinding = true
    }
}
```

## 三、ViewBinding：告别 `findViewById`

```xml
<!-- res/layout/fragment_user_list.xml -->
<LinearLayout ...>
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/recycler"
        ... />
    <TextView android:id="@+id/empty" ... />
</LinearLayout>
```

```kotlin
class UserListFragment : Fragment() {
    private var _binding: FragmentUserListBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        _binding = FragmentUserListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.empty.text = "暂无用户"
        // 收集 ViewModel……
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null          // ⭐ 防止泄漏：视图毁了，binding 必须放下
    }
}
```

- 类名：`fragment_user_list.xml` → `FragmentUserListBinding`。
- **只在 `onCreateView`～`onDestroyView` 之间用 binding**。

## 四、Fragment 生命周期 vs Compose ⭐

```
Fragment: onAttach → onCreate → onCreateView → onViewCreated
        → onStart → onResume ⇄ onPause → onStop
        → onDestroyView → onDestroy → onDetach
```

对照：

| 关注点 | Fragment / View | Compose |
|---|---|---|
| "界面还在" | `viewLifecycleOwner` | `LifecycleOwner` + `collectAsStateWithLifecycle` |
| 销毁视图 | `onDestroyView`（可重建） | 离开 Composition；记得取消收集 |
| 配置变更 | Fragment 实例可能保留，**View 会重建** | Activity 重建；VM 仍在 |
| 状态存放 | `ViewModel` + 必要时 `savedInstanceState` | 同左；UI 局部用 `rememberSaveable` |

收集 Flow 时**务必**用 `viewLifecycleOwner`，不要用 Fragment 自身当 lifecycle：

```kotlin
viewLifecycleOwner.lifecycleScope.launch {
    viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
        vm.uiState.collect { state -> render(state) }
    }
}
```

原因：Fragment 可能比自己的 View 活得长（进返回栈）。用错 owner 会在 View 销毁后仍更新 UI → 崩或泄漏。

## 五、`viewModels` / `activityViewModels`

```kotlin
// 仅本 Fragment 用
private val vm: UserListViewModel by viewModels()

// 同一 Activity 内多个 Fragment 共享（类似"页面簇"共享状态）
private val shared: CheckoutViewModel by activityViewModels()
```

| 委托 | ViewModel 作用域 |
|---|---|
| `by viewModels()` | 该 Fragment |
| `by activityViewModels()` | 宿主 Activity |
| `by navGraphViewModels(R.id.checkout_graph)` | 某个 Navigation Graph |

和 Compose 的 `hiltViewModel()` / 父入口 VM 思路一致：想共享就放到共同的 owner。

有 Hilt：

```kotlin
@AndroidEntryPoint
class UserListFragment : Fragment() {
    private val vm: UserListViewModel by viewModels()
}
```

## 六、Fragment Result API：替代乱回调 / 部分 EventBus ⭐

老写法：接口回调、`setTargetFragment`、EventBus 乱飞（和你笔记里 LiveData 事件、EventBus 对比同一类问题）。

官方替代——**Fragment Result**：

```kotlin
// 父 Fragment / Activity：监听结果
override fun onViewCreated(...) {
    childFragmentManager.setFragmentResultListener("pick_user", viewLifecycleOwner) { _, bundle ->
        val id = bundle.getLong("userId")
        vm.onUserPicked(id)
    }
}

// 子 Fragment：返回结果后关闭自己
binding.ok.setOnClickListener {
    setFragmentResult(
        "pick_user",
        bundleOf("userId" to selectedId)
    )
    findNavController().popBackStack()
}
```

跨同级也可用 `parentFragmentManager`，key 约定好即可。

对比：

| 方案 | 适用 |
|---|---|
| Fragment Result | 页面间一次性回传（选图、选人） |
| 共享 ViewModel | 同流程多步持续状态 |
| 一次性事件 SharedFlow / Channel | 跨层"吐司/导航"事件（第 10、20 课） |
| EventBus | 遗留代码；新代码不推荐 |

## 七、XML Navigation 与 Compose 混搭（简）

- 旧：`NavHostFragment` + XML `nav_graph.xml` + `findNavController().navigate(R.id.xxx)`。
- 新：全 Compose `NavHost`。
- 混搭：某个 destination 用 `ComposeView` 包 `@Composable`；或 Compose 里 `AndroidViewBinding`。

迁移策略：按特征一屏一屏换，不必 Big Bang。

## 八、易错点

1. **`onDestroyView` 不置空 binding**：泄漏整个视图树。
2. **用 `lifecycleScope` 而不是 `viewLifecycleOwner.lifecycleScope` 更新 UI**：返回栈场景崩溃。
3. **在 `onCreate` 里碰 `binding`**：此时 View 可能还没有。
4. **滥用 `activityViewModels`**：整个 Activity 作用域过大，内存与误共享。
5. **Fragment 之间互相强持有引用**：用 Result API 或共享 VM。
6. **新功能继续铺 XML**：维护成本叠加；能 Compose 就 Compose。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 开 ViewBinding | `buildFeatures { viewBinding = true }` |
| inflate | `XxxBinding.inflate(inflater, container, false)` |
| 清 binding | `onDestroyView` 里 `_binding = null` |
| 收集 Flow | `viewLifecycleOwner.repeatOnLifecycle(STARTED)` |
| 本页 VM | `by viewModels()` |
| 共享 VM | `by activityViewModels()` |
| 回传结果 | `setFragmentResult` / `setFragmentResultListener` |
| 依赖 | `fragment-ktx:1.9.1` |

## 十、本课练习

1. 把一个简单 XML 列表页改成 ViewBinding，并在 `onDestroyView` 置空。
2. 两个 Fragment 用 `activityViewModels` 共享一个计数器，验证切换后数字还在。
3. 用 Fragment Result 实现"列表 → 选择页 → 回传 userId"。

---

**下一课预告（第 29 课）：Compose UI 测试** —— 和第 21 课的 VM 单测互补：对屏幕上的节点做点击与断言。

---

## 答疑补充：为什么 onDraw 里创建对象是内存抖动而不是 OOM

> Jerry 提问：为什么在 `onDraw` 方法中创建对象会导致**内存抖动**，而不是**内存溢出**？

### 一句话

`onDraw` 调用极频繁（一帧可多次）。里面 `new` 的都是**短命小对象** → 堆里进进出出，触发频繁 GC → **卡顿 / 抖动（jank）**。  
它们很快就能被回收，堆占用往往**不会持续涨上去**，所以通常**不是**一直涨到 OOM 那种溢出。

### 内存抖动 vs 内存溢出

| | 内存抖动（GC thrashing） | 内存溢出（OOM） |
|---|---|---|
| 典型原因 | 高频路径（如 `onDraw`）反复分配短命对象 | 泄漏、超大分配、缓存无限涨 |
| 堆走势 | 锯齿：涨一点 → GC 砍掉 → 再涨 | 整体**持续上升**，最后撑爆 |
| 用户感受 | 掉帧、滑动卡 | 进程被杀 / 崩溃 |
| `onDraw` 里乱 new | ✅ 很常见 | 单靠短命小对象一般 ❌ |

口诀：**抖 = 造得快也收得快，GC 忙到抖；溢 = 造了没收干净或一次造太大。**

### 什么时候会变成 OOM？

`onDraw` 本身很少单独搞出 OOM，但若叠加这些就会：

1. **泄漏**：静态集合 / 单例一直持有 View、Bitmap、大数组，GC 收不掉。  
2. **超大分配**：每帧解码大图、复制巨大 `ByteArray` / `Bitmap`。  
3. **缓存无上限**：`onDraw` 外层缓存只加不删。

那时堆**真的涨着不回落**，才是溢出路线。

### 正确写法：对象提到成员，反复复用

```kotlin
class DemoView(context: Context, attrs: AttributeSet?) : View(context, attrs) {

    // ✅ 提到字段：只创建一次，onDraw 里复用
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.RED
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private val rect = RectF()
    private val path = Path()

    override fun onDraw(canvas: Canvas) {
        // ❌ 不要：Paint() / RectF() / Path() 写在这里
        rect.set(0f, 0f, width.toFloat(), height.toFloat())
        path.reset()
        path.addRoundRect(rect, 16f, 16f, Path.Direction.CW)
        canvas.drawPath(path, paint)
    }
}
```

| 做法 | 结果 |
|---|---|
| `onDraw` 里每次 `Paint()` / `RectF()` | 高频分配 → GC 抖动 |
| 字段持有，`onDraw` 只 `set` / `reset` / 改属性 | 分配次数≈0 → 更稳帧 |

### 和本课的关系

第 28 课讲 View / Fragment 体系；自定义 View 的 `onDraw` 属于同一条「别在热点路径乱分配」的工程纪律。Compose 里也少在每次重组里无意义地 `new` 大对象，道理类似。
