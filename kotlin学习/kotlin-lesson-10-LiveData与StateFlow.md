# Kotlin 第 10 课：LiveData 与 StateFlow

> 适用读者：已完成第 9 课（ViewModel + LiveData）；第 8 课协程看过 `launch` / `delay` 即可。
> 核心收获：知道为什么要从 LiveData 迁到 StateFlow，会在 ViewModel 里用 `MutableStateFlow` + `asStateFlow()`，用 `repeatOnLifecycle` 安全收集，分清 StateFlow（状态）和 SharedFlow（事件），接上 `viewModelScope`。

---

## 一、为什么要从 LiveData 往前走？⭐

第 9 课的 `MutableLiveData` 够用，但现代 Android（尤其 Compose）更推荐 **Kotlin Flow 家族**：

|      | LiveData                      | StateFlow                                    |
| ---- | ----------------------------- | -------------------------------------------- |
| 属于   | AndroidX Lifecycle            | Kotlin 协程库（跨平台）                              |
| 当前值  | 可能还没设过（`value` 可 null）        | **永远有**一个当前值                                 |
| 观察方式 | `observe(LifecycleOwner)`     | `collect`（协程） / Compose 里 `collectAsState()` |
| 线程   | `value` 必须主线程，后台用 `postValue` | 任意线程都能 `_count.value =`                      |
| 测试   | 要 InstantTaskExecutorRule 等   | 普通协程测试即可                                     |

三个常见动机：

1. **Compose 原生吃 Flow**：`collectAsState()` / `collectAsStateWithLifecycle()` 一等公民；LiveData 是兼容层。
2. **状态 vs 连续流**：LiveData 偏"页面观察状态"；Flow 还能做管道（`map`/`filter`/`flatMapLatest`），网络、数据库、传感器一条链。
3. **可测试、少 Android 依赖**：StateFlow 是纯 Kotlin，单测不用抬 Lifecycle。

口诀：**LiveData 还能用；新代码优先 StateFlow 管状态。**

## 二、LiveData 的几个坑（简要）

```kotlin
_count.value = 1          // 必须主线程，否则 IllegalStateException
_count.postValue(1)       // 后台线程才用这个
liveData.observe(owner) { }  // 必须有 LifecycleOwner；纯 Kotlin 模块里不好用
```

- 没有背压（backpressure）概念：生产太快时只能"最新值盖住"，细粒度流控弱。
- 粘性：新观察者一上来会立刻收到**最后一次值**——状态场景好用，但拿它发"只弹一次的 Toast"容易重复弹（事件场景见第七节）。

这些不是"不能用"，而是迁到 StateFlow 后，同一套坑用协程惯用法解决更干净。

## 三、StateFlow：永远有当前值的状态流

```kotlin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

private val _count = MutableStateFlow(0)     // 创建时就必须给初始值
val count: StateFlow<Int> = _count.asStateFlow()
```

要点：

- **`MutableStateFlow` 内部可写，`StateFlow` 对外只读**——和第 9 课 `_count` / `count` 配对一模一样，只是类型换了。
- **始终有值**：`count.value` 永远是 `Int`，不是 `Int?`，不用 `?: 0`。
- **合并（conflation）**：若短时间连续写 `1, 2, 3`，收集端可能只看到最新的 `3`——状态只关心"现在是多少"，中间值可丢。这是特性，不是 bug。
- 改值两种写法：

```kotlin
_count.value = (_count.value) + 1
_count.update { it + 1 }          // 推荐：原子读改写，并发更安全
```

Compose 一行（知道即可）：`val count by vm.count.collectAsStateWithLifecycle()`。本课 Activity 用下面第五节的 `collect`，不依赖 Compose。

## 四、改写 CounterViewModel

```kotlin
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

class CounterViewModel : ViewModel() {

    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    fun increment() {
        _count.update { it + 1 }
    }

    /** 假加载：演示 viewModelScope，不依赖真实网络 */
    fun refresh() {
        viewModelScope.launch {
            _loading.value = true
            delay(500)                    // 假装 IO（第 8 课 delay）
            _count.value = 0
            _loading.value = false
        }
    }
}
```

对照第 9 课：

| 第 9 课 LiveData | 第 10 课 StateFlow |
|---|---|
| `MutableLiveData(0)` | `MutableStateFlow(0)` |
| `val count: LiveData<Int> = _count` | `val count: StateFlow<Int> = _count.asStateFlow()` |
| `_count.value = (… ?: 0) + 1` | `_count.update { it + 1 }` |
| `observe(this) { }` | `collect { }`（见下） |

依赖补充（版本号按你工程 BOM / 官网为准）：

```kotlin
// app/build.gradle.kts
implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")   // repeatOnLifecycle
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0") // viewModelScope
implementation("androidx.activity:activity-ktx:1.13.0")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")
```

## 五、Activity 里安全收集：`repeatOnLifecycle` ⭐

LiveData 的 `observe` 自带生命周期感知；StateFlow 的 `collect` **默认会一直挂着**——若不加约束，后台界面仍在收值，可能浪费甚至碰已销毁的 View。

标准写法（不依赖 Compose）：

```kotlin
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch

class CounterActivity : AppCompatActivity() {

    private val vm: CounterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_counter)

        val countText = findViewById<TextView>(R.id.countText)
        val addButton = findViewById<Button>(R.id.addButton)

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                vm.count.collect { count ->
                    countText.text = count.toString()
                }
            }
        }

        addButton.setOnClickListener { vm.increment() }
    }
}
```

为什么必须 `repeatOnLifecycle(STARTED)`：

1. **进入 STARTED**（界面可见）→ 开始 `collect`。
2. **离开 STARTED**（进后台 / 被遮挡）→ **取消**内部协程，停止收集。
3. **再次 STARTED** → 自动重新 collect；StateFlow 会立刻给出**当前值**，界面同步。

只写 `lifecycleScope.launch { vm.count.collect { } }` 没有这层开关：Activity 停了收集还在跑。Fragment 同理，把 `lifecycleScope` / `LifecycleOwner` 换成 `viewLifecycleOwner`。

口诀：**StateFlow 用 collect，外面套 repeatOnLifecycle；别裸奔。**

## 六、`viewModelScope`：和 ViewModel 同生共死

- 定义在 `lifecycle-viewmodel-ktx`：`ViewModel` 自带的 `CoroutineScope`。
- 默认调度器偏 Main（可在块里再 `withContext(Dispatchers.IO)`，第 8 课）。
- **`onCleared()` 时整个 scope 取消**——页面真退出，未完成的 `launch` 一起停，不会泄漏。

```kotlin
viewModelScope.launch {
    _loading.value = true
    delay(500)
    _count.value = 0
    _loading.value = false
}
```

和 Activity 的 `lifecycleScope` 对比：一个跟 **ViewModel** 走，一个跟 **界面** 走。请求数据放 `viewModelScope`；只为刷新 UI 的收集放 `lifecycleScope` + `repeatOnLifecycle`。

## 七、SharedFlow：事件，不是状态（短对比）

| | StateFlow | SharedFlow（常用 MutableSharedFlow） |
|---|---|---|
| 模型 | **状态**：现在是多少 | **事件**：发生了一件事 |
| 当前值 | 必须有 | 可以没有 |
| 新收集者 | 立刻拿到最新状态 | 默认**不重放**已过去的事件 |
| 典型用途 | count、UiState、loading | Snackbar、导航、一次性 Toast |

```kotlin
private val _events = MutableSharedFlow<String>()   // 例如提示文案
val events = _events.asSharedFlow()

fun onSave() {
    viewModelScope.launch {
        _events.emit("保存成功")     // 转屏后新界面不会再弹一次旧提示
    }
}
```

口诀：**屏幕上一直能看见的 → StateFlow；弹一下就没的 → SharedFlow。**  
（用 LiveData 发事件容易因粘性重复消费，这是迁走的另一大理由。）

## 八、易错点

1. **裸 `collect` 不套 `repeatOnLifecycle`**：后台仍收集，浪费甚至碰销毁的 View。
2. **把 `MutableStateFlow` 直接公开**：外部乱改状态。必须 `asStateFlow()` 只读暴露。
3. **用 StateFlow 发一次性事件**：新观察者（旋转后）会再吃到旧状态当"事件"。事件用 SharedFlow（或 Channel）。
4. **以为 `update` 和 `value =` 完全一样**：单线程下差不多；并发读改写优先 `update { }`。
5. **在 `viewModelScope` 里直接改 View**：Scope 不保证你在 Main 且不该持有 View（第 9 课红线仍在）。只改 Flow，让 Activity collect 去画。
6. **Fragment 用 Activity 的 `lifecycleScope` 收集**：View 销毁后 Activity 可能还在，改用 `viewLifecycleOwner.lifecycleScope` + `repeatOnLifecycle`。
7. **忘记 StateFlow 要初始值**：`MutableStateFlow()` 少参数编不过，和 `MutableLiveData()` 可不设值不同。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 内部状态 | `private val _x = MutableStateFlow(初始值)` |
| 对外只读 | `val x: StateFlow<T> = _x.asStateFlow()` |
| 更新 | `_x.value = …` 或 `_x.update { … }` |
| Activity 收集 | `lifecycleScope.launch { repeatOnLifecycle(STARTED) { vm.x.collect { } } }` |
| Compose 收集 | `collectAsStateWithLifecycle()` |
| 发请求 | `viewModelScope.launch { … }`（随 ViewModel 取消） |
| 一次性事件 | `MutableSharedFlow` + `emit` |
| 旧 LiveData 观察 | `observe(owner) { }`（仍可用，新代码优先 Flow） |

---

**下一课预告**：两条路任选——
- **回到第 8 课协程加深**：`withContext`、异常处理，再学 Flow 操作符（`map` / `filter` / `flatMapLatest`）；
- 或者 **Room + Flow**：数据库查询直接暴露 `Flow<List<Entity>>`，和本课 StateFlow 接到同一套 UI 收集写法。


---

## 💬 课后问答：LiveData 是用来干嘛的？

LiveData 是一个**能被观察、并且知道生命周期的数据盒子**。它主要用来把 ViewModel 里的数据交给 Activity 或 Fragment 显示，数据一变，界面就自动刷新。

```kotlin
// ViewModel 里
private val _count = MutableLiveData(0)
val count: LiveData<Int> = _count        // 对外只读
fun add() { _count.value = (_count.value ?: 0) + 1 }

// Activity 里
vm.count.observe(this) { n -> countText.text = "点了 $n 次" }
```

它解决了三件事：

1. **数据变了自动通知**：不用每次手动改 TextView。
2. **懂生命周期** ⭐：页面在后台时不推送；页面销毁时自动取消观察，不会内存泄漏，也不会更新已经不存在的 View。
3. **配合 ViewModel 扛住屏幕旋转**：Activity 重建后重新 `observe`，马上拿到最新的值。

新项目更推荐 StateFlow（见本课正文）：它属于 Kotlin 协程体系，能用 `map`、`combine` 等 Flow 操作符，在 Compose 里也更顺手。LiveData 主要在老项目和 XML 界面里常见。

> 口诀：**LiveData 是"懂生命周期的可观察数据"，新代码用 StateFlow + `repeatOnLifecycle` 替代它。**


---

## 💬 课后问答：LiveData 怎么用？

三步走：**ViewModel 里放数据 → 对外只读 → 界面 observe**。

### ① 依赖（lifecycle 2.11.0）

```kotlin
implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.11.0")
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
implementation("androidx.activity:activity-ktx:1.13.0")   // by viewModels()
```

### ② ViewModel：内部可写，外部只读

```kotlin
class CounterViewModel : ViewModel() {
    private val _count = MutableLiveData(0)
    val count: LiveData<Int> = _count

    fun add() { _count.value = (_count.value ?: 0) + 1 }   // 主线程用 value

    fun loadFromNet() = viewModelScope.launch(Dispatchers.IO) {
        val n = 100                       // 假装网络结果
        _count.postValue(n)               // 子线程用 postValue
    }
}
```

### ③ Activity / Fragment 观察

```kotlin
class CounterActivity : AppCompatActivity() {
    private val vm: CounterViewModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_counter)
        vm.count.observe(this) { n -> findViewById<TextView>(R.id.tv).text = "点了 $n 次" }
        findViewById<Button>(R.id.btn).setOnClickListener { vm.add() }
    }
}
// Fragment 里一定用 viewLifecycleOwner ⭐
vm.count.observe(viewLifecycleOwner) { ... }
```

### ④ 进阶写法

```kotlin
val label: LiveData<String> = count.map { "当前 $it" }                     // 转换
val user: LiveData<User> = userId.switchMap { id -> repo.getUser(id) }   // 切换数据源
val users: LiveData<List<User>> = liveData { emit(repo.fetchUsers()) }   // 构造器里写挂起代码
val fromFlow: LiveData<Int> = someFlow.asLiveData()                       // Flow → LiveData
```

### ⚠️ 易错点

- 子线程写 `value =` 会崩溃，子线程用 `postValue`。
- **粘性**：新观察者注册后会立刻收到最后一个值。Toast、跳转这种一次性事件不要用 LiveData，改用 SharedFlow 或 Channel（见第 10、20 课）。
- Fragment 里写 `observe(this)` 会重复观察，要用 `viewLifecycleOwner`。

> 示例：`coroutineStudy` 项目的 `viewmodel/CounterActivity.kt`（第 9 课，Logcat tag `ViewModelDemo`）。
>
> 口诀：**私有 Mutable，公开 LiveData；主线程 value，子线程 post；Fragment 用 viewLifecycleOwner。**
