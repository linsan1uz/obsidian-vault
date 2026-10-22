# Kotlin 第 18 课：委托

> 适用读者：已完成第 6 课（接口、继承），用过 `by lazy`（第 2 课）、`by viewModels()`（第 9 课）、`by remember`（第 16 课）。
> 核心收获：理解 `by` 的两种用法——**类委托**（把接口实现交给另一个对象）和**属性委托**（把 get/set 交给另一个对象），会用 `lazy`、`observable`、`vetoable`、Map 委托，能自己写一个 `ReadWriteProperty`。

---

## 一、委托是什么

"委托" = **把活儿交给别人干**。Kotlin 用一个关键字 `by` 支持两种委托：

| | 写在哪 | 交出去的是什么 |
|---|---|---|
| 类委托 | `class A : 接口 by 对象` | 接口里所有方法的实现 |
| 属性委托 | `val x by 对象` | 这个属性的 `get` / `set` |

你已经用了很多次属性委托，只是没拆开看：

```kotlin
val api: ApiService by lazy { createApiService() }        // 第 2 课
private val vm: CounterViewModel by viewModels()          // 第 9 课
var query by remember { mutableStateOf("") }              // 第 16 课
```

## 二、类委托：组合优于继承 ⭐

需求：要一个"每次 add 都打日志"的列表。继承 `ArrayList` 可以，但第 6 课说过 Kotlin 默认 final、继承耦合高；实现 `MutableList` 接口的话，要手写二十多个方法。

**类委托**：实现接口，但把所有方法**自动转发**给内部对象，只重写你关心的：

```kotlin
class LoggingList<T>(
    private val inner: MutableList<T> = mutableListOf()
) : MutableList<T> by inner {                      // ⭐ 没写的方法全部转发给 inner

    override fun add(element: T): Boolean {        // 只改这一个
        println("添加: $element")
        return inner.add(element)
    }
}

val list = LoggingList<String>()
list.add("Jerry")        // 添加: Jerry
list.size                // 1，自动转发给 inner.size
```

- 编译器帮你生成所有转发代码，等价于 Java 里手写装饰器模式。
- 只能委托**接口**，不能委托类。
- 典型用途：装饰器（加日志、加缓存）、把大接口拆给多个对象实现。

Android 例子——第 14 课的 Repository 加内存缓存而不改原实现：

```kotlin
class CachedUserRepository(
    private val origin: UserRepository
) : UserRepository by origin {
    private var cache: List<User>? = null
    // 只重写需要缓存的方法，其他全转发
}
```

口诀：**类委托 = 实现接口，活儿全交给别人，只改自己关心的那几个方法。**

## 三、`by lazy`：首次访问才初始化

```kotlin
val database: AppDatabase by lazy {
    Room.databaseBuilder(context, AppDatabase::class.java, "app.db").build()
}
```

- 只能用于 `val`。第一次读取时执行 Lambda，结果缓存，之后直接返回。
- 默认**线程安全**（`LazyThreadSafetyMode.SYNCHRONIZED`，加锁保证只初始化一次）。
- 确定只在主线程访问时可以 `lazy(LazyThreadSafetyMode.NONE) { }`，省掉锁的开销。

`lazy` vs `lateinit var`：

| | `by lazy` | `lateinit var` |
|---|---|---|
| 可变性 | `val` | `var` |
| 何时赋值 | 第一次访问时自动算 | 你在某处手动赋值 |
| 没初始化就访问 | 不存在这种情况 | 抛 `UninitializedPropertyAccessException` |
| 类型限制 | 任意 | 不能是基本类型（Int 等）、不能可空 |

## 四、`Delegates.observable` / `vetoable`

```kotlin
import kotlin.properties.Delegates

class Settings {
    var theme: String by Delegates.observable("light") { property, old, new ->
        println("${property.name}: $old → $new")     // 每次赋值后回调
    }

    var fontSize: Int by Delegates.vetoable(14) { _, _, new ->
        new in 10..30                                // 返回 false 则拒绝这次赋值
    }
}

val s = Settings()
s.theme = "dark"      // theme: light → dark
s.fontSize = 100      // 被拒绝，仍是 14
```

- `observable`：赋值**之后**通知，适合"值变了刷新 UI / 写日志"。
- `vetoable`：赋值**之前**拦截，返回 `true` 才生效，适合校验。

## 五、Map 委托：用 Map 当属性

```kotlin
class UserConfig(map: Map<String, Any?>) {
    val name: String by map        // 读 map["name"]
    val age: Int by map            // 读 map["age"]
}

val c = UserConfig(mapOf("name" to "Jerry", "age" to 25))
c.name    // Jerry
```

- 属性名就是 key。可变属性用 `MutableMap`：`var age: Int by mutableMap`。
- 适合动态配置、解析松散的 JSON 片段。key 不存在时访问会抛 `NoSuchElementException`。

## 六、属性之间委托

```kotlin
class User {
    var displayName: String = ""

    @Deprecated("用 displayName")
    var nickname: String by this::displayName    // 读写都转给 displayName
}
```

重构时改名、保留旧 API 兼容很好用。

## 七、自己写一个委托 ⭐

属性委托的本质：`by` 后面的对象只要提供 `getValue`（`var` 还要 `setValue`）运算符函数就行。标准库给了接口 `ReadWriteProperty` 方便实现：

```kotlin
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

class PrefInt(
    private val prefs: SharedPreferences,
    private val default: Int
) : ReadWriteProperty<Any?, Int> {

    override fun getValue(thisRef: Any?, property: KProperty<*>): Int =
        prefs.getInt(property.name, default)              // 属性名当 key

    override fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) {
        prefs.edit().putInt(property.name, value).apply()
    }
}

fun SharedPreferences.int(default: Int = 0) = PrefInt(this, default)   // 第 3 课扩展

class AppSettings(prefs: SharedPreferences) {
    var launchCount by prefs.int()       // 读写自动走 SharedPreferences
    var fontSize by prefs.int(14)
}

settings.launchCount++                   // 读 → +1 → 写，一行搞定
```

编译器做的事：

```kotlin
// 你写：var launchCount by prefs.int()
// 编译后大致是：
private val launchCount$delegate = prefs.int()
var launchCount: Int
    get() = launchCount$delegate.getValue(this, ::launchCount)
    set(v) = launchCount$delegate.setValue(this, ::launchCount, v)
```

`thisRef` 是属性所在的对象，`property` 是属性的反射信息（最常用 `property.name`）。

## 八、回头看：`by viewModels()` 和 `by remember`

```kotlin
private val vm: CounterViewModel by viewModels()
```

- `viewModels()` 返回的是 `Lazy<CounterViewModel>`。
- 标准库给 `Lazy<T>` 定义了 `operator fun getValue`，所以能用 `by`。
- 第一次访问 `vm` 时才去 `ViewModelProvider` 取——这就是为什么在 `onCreate` 之前访问 `vm` 会崩（Activity 还没准备好）。

```kotlin
var query by remember { mutableStateOf("") }
```

- `mutableStateOf` 返回 `MutableState<String>`。
- Compose 为 `State` / `MutableState` 定义了 `getValue` / `setValue` 扩展运算符，所以要 `import androidx.compose.runtime.getValue / setValue`——第 16 课那个 import 的原因就在这。

口诀：**`by` 后面只要有 `getValue`（和 `setValue`），什么都能当委托。**

## 九、易错点

1. **类委托想委托一个类**：只能委托接口。`class A : ArrayList<T>() by x` 不合法。
2. **类委托里重写了方法，以为 inner 内部调用也会走重写版**：不会。inner 内部互相调用的仍是 inner 自己的方法，委托不是继承。
3. **`by lazy` 用在 `var` 上**：编译错误，`lazy` 只提供 `getValue`。
4. **在 `onCreate` 之前（如构造函数、字段初始化）访问 `by viewModels()` 的属性**：崩溃。
5. **Map 委托 key 写错或缺失**：运行时 `NoSuchElementException`，编译期查不出来。
6. **`by remember { mutableStateOf() }` 缺 import**：`getValue` 报红，补 Compose runtime 的两个 import。
7. **自定义委托在 `getValue` 里做耗时操作**：每次读属性都执行，主线程读 SharedPreferences 大量数据会卡。
8. **`lazy` 里引用 Activity 等短命对象，并把 lazy 属性放进长命对象**：泄漏。

## 十、对照速查表

| 需求 | 写法 |
|---|---|
| 接口实现转发 | `class A(inner: I) : I by inner` |
| 首次访问初始化 | `val x by lazy { ... }` |
| 单线程 lazy | `lazy(LazyThreadSafetyMode.NONE) { }` |
| 赋值后回调 | `var x by Delegates.observable(初值) { _, old, new -> }` |
| 赋值前校验 | `var x by Delegates.vetoable(初值) { _, _, new -> 条件 }` |
| Map 当属性 | `val name: String by map` |
| 属性转属性 | `var old by this::newProp` |
| 自定义委托 | `class D : ReadWriteProperty<Any?, T> { getValue / setValue }` |
| ViewModel | `by viewModels()`（`Lazy<T>` 的 `getValue`） |
| Compose 状态 | `by remember { mutableStateOf() }`（`State` 的 `getValue/setValue`） |

---

**下一课预告（第 19 课）：运算符重载、inline 与 DSL** —— `getValue` 前面那个 `operator` 是什么？`+`、`[]`、`in` 也能自己定义；再学 `inline` 和"带接收者的 Lambda"，看懂 Gradle kts 和 Compose 的 `Column { }` 为什么能那样写。
