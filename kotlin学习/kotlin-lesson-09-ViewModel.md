# Kotlin 第 9 课：ViewModel

> 适用读者：已完成第 1～7 课（尤其第 2 课类、第 4 课 Lambda、第 6 课继承）；第 8 课协程看过开头即可，本课不依赖协程。
> 核心收获：搞懂旋转屏幕时数据为什么会丢，用 `ViewModel` + `LiveData` 保存 UI 状态，`by viewModels()` 一行拿到实例，知道 ViewModel **不能持有什么**，以及 `SavedStateHandle` 应对进程被杀。

---

## 一、为什么需要 ViewModel？⭐

**Android 真实痛点**：旋转屏幕、切换深色模式、改系统语言，都属于**配置变更（configuration change）**。默认行为是：**Activity 被销毁再重建**，`onCreate` 重新跑一遍。

```kotlin
class CounterActivity : AppCompatActivity() {
    private var count = 0          // ❌ 字段跟着 Activity 走

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 点了 5 次，一旋转 → 新的 Activity 对象 → count 又是 0
    }
}
```

**ViewModel 的答案**：把 UI 状态放进一个**比 Activity 活得久**的对象里。

```
Activity 实例 #1 ──旋转销毁──▶ Activity 实例 #2
        │                              │
        └──────▶ 同一个 ViewModel ◀─────┘
                 （count = 5 还在）
```

- 配置变更时，Activity 重建，**ViewModel 不重建**，新 Activity 拿到的是同一个实例。
- 用户真正退出页面（按返回键 / `finish()`）时，ViewModel 才被清理。
- 职责划分：**ViewModel 管"数据和状态"，Activity/Fragment 管"把状态画出来"**。ViewModel 里不放任何 View。

口诀：**Activity 会死会生，ViewModel 只认"真退出"。**

## 二、依赖

```kotlin
// app/build.gradle.kts（2026-10 最新稳定版）
dependencies {
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")    // ViewModel + viewModelScope
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.11.0")     // LiveData
    implementation("androidx.activity:activity-ktx:1.13.0")                // by viewModels()
    // implementation("androidx.lifecycle:lifecycle-viewmodel-savedstate:2.11.0")  // SavedStateHandle（第六节）
    // implementation("androidx.fragment:fragment-ktx:1.9.1")                // Fragment 里的 by viewModels()/activityViewModels()
}
```

- `lifecycle-viewmodel-ktx`：`ViewModel` + `viewModelScope`。
- `activity-ktx`：`by viewModels()`。
- `lifecycle-viewmodel-savedstate`：`SavedStateHandle`（`activity-ktx` 常已间接带上，需要时显式写也行）。
- 用到哪个就**显式声明**哪个，别只靠 appcompat 间接依赖。

## 三、写一个 ViewModel：`CounterViewModel`

本课选 **`LiveData`** 来存状态（不需要协程知识）。协程时代的替代方案是 **`StateFlow`**，学完第 8 课后再换，思路完全一样。

```kotlin
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel

class CounterViewModel : ViewModel() {

    private val _count = 

(0)       // 内部可改
    val count: LiveData<Int> = _count             // 对外只读

    fun increment() {
        _count.value = (_count.value ?: 0) + 1    // 主线程用 value；后台线程用 postValue
    }

    override fun onCleared() {
        super.onCleared()
        // 页面真正结束时调用一次：释放监听、关闭资源
    }
}
```

要点：

- 继承 `ViewModel()`——冒号后带括号是调父类构造（第 6 课）。
- **`_count` 私有可变 + `count` 公开只读**：外界只能观察，改状态必须走 `increment()` 这类方法。这是 Android 官方推荐的"单向数据流"写法，下划线前缀是约定俗成。
- `MutableLiveData` 是 `LiveData` 的子类；对外声明成父类型 `LiveData<Int>`，调用方就拿不到 `setValue`——和第 7 课"只读 List / MutableList"是同一个思路。
- `value` 的类型是 `Int?`（LiveData 初始可能没值），所以用 `?: 0` 兜底（第 1 课 Elvis）。

## 四、在 Activity 里拿到并观察

```kotlin
import androidx.activity.viewModels

class CounterActivity : AppCompatActivity() {

    private val vm: CounterViewModel by viewModels()   // ⭐ 一行拿到

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_counter)

        val countText = findViewById<TextView>(R.id.countText)
        val addButton = findViewById<Button>(R.id.addButton)

        vm.count.observe(this) { count ->              // 状态变 → 自动刷新 UI
            countText.text = count.toString()
        }

        addButton.setOnClickListener { vm.increment() } // 事件 → 交给 ViewModel
    }
}
```

拆解：

- **`by viewModels()`** 是属性委托（和第 2 课 `by lazy` 同类）：重建后的 Activity 拿到的是**同一个**实例。**别自己 `CounterViewModel()` new**——每次重建都是新对象，等于没用。
- **`observe(this) { }`**：`this` 是 `LifecycleOwner`。LiveData 只在界面活跃（STARTED/RESUMED）时推送，Activity 销毁时**自动解除观察**，不会泄漏。
- 旋转后新 Activity 重新 `observe`，LiveData 立即推一次**当前值**（比如 5），界面马上恢复。
- 数据流向：**点击 → `vm.increment()` → `_count` 改变 → observe 回调 → 改 TextView**。Activity 自己不存 count。

Fragment 同理（需 `fragment-ktx`）：`by viewModels()` 拿自己的、`by activityViewModels()` 和宿主共享；观察时用 `viewLifecycleOwner`，不要 `observe(this)`。

## 五、生命周期与"不能持有什么" ⭐

### 1. `onCleared()` 何时调用

| 场景 | Activity | ViewModel |
|---|---|---|
| 旋转屏幕 / 切换深色模式 | 销毁 + 重建 | **保留**，不调 `onCleared` |
| 按返回键 / `finish()` | 销毁 | 调用 `onCleared()`，然后被回收 |
| 进程被系统杀掉 | 没了 | **也没了**（见第六节） |

### 2. 绝不持有 Activity / View / Context

```kotlin
class BadViewModel(private val activity: Activity) : ViewModel()    // ❌
class BadViewModel2 : ViewModel() { var textView: TextView? = null } // ❌
```

原因：ViewModel 比 Activity 活得久。旋转后旧 Activity 应该被回收，但 ViewModel 还抓着它的引用 → **内存泄漏**，还可能去操作一个已经销毁的界面。View 内部都持有 Context，同理不行。

真需要 Context（读资源、访问数据库）时用 **`AndroidViewModel`**，它只持有 **Application Context**（跟进程同寿命，不泄漏）：

```kotlin
class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("settings", Context.MODE_PRIVATE)
}
```

能不用就不用：依赖 Context 的活更适合放进 Repository 注入进来，ViewModel 保持纯 Kotlin、好测试。

口诀：**ViewModel 只装数据，不装界面；要 Context 只拿 Application。**

## 六、`SavedStateHandle`：旋转 vs 进程被杀

ViewModel 扛得住旋转，但扛不住**进程死亡**：App 在后台时内存紧张，系统可能直接杀掉进程；用户切回来时，系统会恢复页面栈，但 ViewModel 是**全新的**，count 又变 0。

`SavedStateHandle` 把少量关键状态存进系统的保存机制（底层就是 `Bundle`），进程重建后还能取回：

```kotlin
class CounterViewModel(private val state: SavedStateHandle) : ViewModel() {

    val count: LiveData<Int> = state.getLiveData("count", 0)   // key + 默认值

    fun increment() {
        state["count"] = (state.get<Int>("count") ?: 0) + 1
    }
}
```

- 构造函数里只要声明 `SavedStateHandle` 参数，`by viewModels()` 的默认工厂会**自动传进来**，Activity 侧代码一行不用改。
- 只存**小而关键**的东西（输入框文字、选中 Tab、搜索词）；大列表存 id，回来重新加载。

| 情况 | 普通字段 | ViewModel | SavedStateHandle |
|---|---|---|---|
| 旋转 / 配置变更 | ❌ 丢 | ✅ 保留 | ✅ 保留 |
| 后台进程被杀后恢复 | ❌ 丢 | ❌ 丢 | ✅ 保留 |
| 用户主动退出页面 | ❌ | ❌（本来就该丢） | ❌（本来就该丢） |

## 七、`viewModelScope`：与第 8 课的桥

ViewModel 里发网络请求，最常见的写法是：

```kotlin
class UserViewModel : ViewModel() {
    fun load() {
        viewModelScope.launch {          // ViewModel 自带的协程作用域
            // 请求数据、更新 LiveData
        }
    }
}
```

现在只需记住一句：**`viewModelScope` 里的协程，会在 ViewModel `onCleared()` 时自动取消**——页面关掉，请求跟着停，不会泄漏。具体的 `launch`/`withContext` 写法，等回到第 8 课再接上。

## 八、易错点

1. **自己 `new` ViewModel**：`val vm = CounterViewModel()` 每次重建都是新对象。必须 `by viewModels()`（或 `ViewModelProvider`）。
2. **ViewModel 里持有 Activity / View / Fragment / Context**：泄漏。要 Context 用 `AndroidViewModel` 的 Application。
3. **把 `MutableLiveData` 公开出去**：外部随便改状态，数据流就乱了。保持 `_xxx` 私有 + `xxx: LiveData` 只读。
4. **后台线程用 `value =`**：会抛异常。后台线程用 `postValue()`，主线程用 `value`。
5. **Fragment 里 `observe(this)`**：Fragment 的 View 会多次销毁重建，应该用 `viewLifecycleOwner`，否则重复回调。
6. **以为 ViewModel 能扛进程死亡**：不能，要扛用 `SavedStateHandle`。
7. **把 ViewModel 当全局单例**：寿命跟页面（ViewModelStoreOwner）绑定；跨页用 `activityViewModels()` / Repository，真全局才用 `object`。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 定义 ViewModel | `class XxxViewModel : ViewModel()` |
| Activity 里拿实例 | `private val vm: XxxViewModel by viewModels()` |
| Fragment 共享 Activity 的 | `by activityViewModels()` |
| 可变状态（内部） | `private val _x = MutableLiveData(0)` |
| 只读状态（对外） | `val x: LiveData<Int> = _x` |
| 观察 | `vm.x.observe(this) { ... }`（Fragment 用 `viewLifecycleOwner`） |
| 主线程 / 后台线程更新 | `value = ...` / `postValue(...)` |
| 扛进程死亡 | 构造参数 `SavedStateHandle` + `getLiveData(key, 默认值)` |
| 发异步请求 | `viewModelScope.launch { }`（自动取消） |

---

**下一课预告**：两条路任选——
- **回到第 8 课协程**，接上 `viewModelScope` + `withContext(Dispatchers.IO)`，在 ViewModel 里真正发网络请求；
- 或者 **LiveData / StateFlow 深入**：`map`/`switchMap`、一次性事件怎么处理、`StateFlow` 替换 LiveData 的标准写法。

---

## 答疑补充：ViewModel 比 Activity 活得久，那它归谁？

它归 **`ViewModelStore`** 管，属于「这个页面」，而不是某一个 Activity 对象。

1. `ComponentActivity`（`AppCompatActivity` 的父类）实现了 `ViewModelStoreOwner`，自带一个 `ViewModelStore`，可以理解成 `Map<String, ViewModel>`。`by viewModels()` 就是去这个 Map 里取，取不到才新建。
2. 转屏时旧 Activity 被销毁，系统通过 `onRetainNonConfigurationInstance()` 把整个 `ViewModelStore` 暂存起来，新 Activity 创建时接过来，所以取到的还是原来那个 ViewModel。
3. 只有页面真正结束（返回键 / `finish()`，此时 `isChangingConfigurations == false`），才会 `ViewModelStore.clear()`，逐个调用 `onCleared()`。

口诀：**Activity 只是 ViewModel 的「临时房东」，真正的主人是页面的生命周期。** Fragment 同理，它的 `ViewModelStore` 由 `FragmentManager` 托管。

### 示例项目

完整示例在 `C:\Users\Linsan\AndroidStudioProjects\coroutineStudy` 的 `app/src/main/java/com/fqf/coroutinestudy/viewmodel/`：普通字段、ViewModel、ViewModel + SavedStateHandle 三种计数并排对比，`onDestroy` 会打印 `isChangingConfigurations`。
