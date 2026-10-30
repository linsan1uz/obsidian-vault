# Kotlin 第 1b 课补遗：enum、lateinit、数组与嵌套类

> 适用读者：已学完第 1～7 课（变量、类、`when`、密封类、面向对象）。本课是**语法薄点补遗**，不替代前面内容。
> 核心收获：会写 `enum class` 并知道它和 `sealed` 的分工；掌握 `lateinit` 的规则与和 `lazy` 的区别；分清 `Array` / `IntArray`；会用 `typealias`；分清 nested class 与 `inner` class。

---

## 一、本课在路线图里的位置

第 1～7 课已经覆盖了日常 90% 的 Kotlin 语法。下面几块在早期课里只一带而过，或完全没展开——补完后，读 Android / 开源代码时就不会再卡壳。

| 主题 | 已在哪学过相关内容 | 本课补什么 |
|---|---|---|
| 条件分支 / 密封类 | 第 5 课 `when`、`sealed class` | `enum class` 与 sealed 怎么选 |
| 属性延迟初始化 | 第 2 课 `by lazy`、第 9 课 ViewModel | `lateinit` 规则与适用场景 |
| 集合 | 第 4 课 `List`/`Map` | `Array` / 基本类型数组 |
| 类型别名 | — | `typealias` |
| 嵌套类型 | 第 2、6 课 class / object | nested vs `inner` |

## 二、`enum class`：固定、有限的一组常量 ⭐

```kotlin
enum class NetworkState {
    Idle, Loading, Success, Error
}

fun label(s: NetworkState): String = when (s) {
    NetworkState.Idle -> "空闲"
    NetworkState.Loading -> "加载中"
    NetworkState.Success -> "成功"
    NetworkState.Error -> "失败"
    // enum 的 when 写全分支后，不必写 else
}
```

枚举也可以带属性、方法：

```kotlin
enum class HttpMethod(val code: String) {
    GET("GET"), POST("POST"), PUT("PUT"), DELETE("DELETE");

    fun isIdempotent(): Boolean = this == GET || this == PUT || this == DELETE
}
```

### 和 `sealed` 怎么选？

| | `enum class` | `sealed class` / `sealed interface`（第 5 课） |
|---|---|---|
| 成员形态 | 只能是**同一类型**的常量实例 | 子类可以是 `object`、`data class`，**可携带不同数据** |
| 典型例子 | 方向、HTTP 方法、主题模式 | `Result`、`UiState`（Success 带 data，Error 带 message） |
| 扩展性 | 加常量要改枚举本身 | 同文件内可加新子类型 |

口诀：**只有几种固定取值、不需要各自带不同字段 → enum；每种结果要带不同数据 → sealed。**

Android 里常见：`enum class ThemeMode { System, Light, Dark }`；网络结果继续用第 13 课的 `sealed interface UiState`。

## 三、`lateinit`：非空属性晚一点再赋值 ⭐

有时属性在构造时还拿不到（例如 Activity 的 `onCreate` 里才 `findViewById`，或测试里先 new 再注入），又不想写成可空 `Type?`：

```kotlin
class ProfileActivity : AppCompatActivity() {
    private lateinit var binding: ActivityProfileBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProfileBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.title.text = "资料"   // 像非空属性一样用
    }
}
```

### 规则（记牢）

1. 只能用于 **`var`**，不能用于 `val`。
2. 不能是可空类型（`String?` 不行），也不能是基本类型（`Int`/`Boolean` 等不行）。
3. 使用前必须先赋值，否则抛 `UninitializedPropertyAccessException`。
4. 可用 `::binding.isInitialized` 检查是否已赋值。

### `lateinit` vs `lazy`

| | `lateinit var` | `by lazy`（第 2 课） |
|---|---|---|
| 可变性 | `var`，可多次赋值 | 本质是 `val`，只初始化一次 |
| 谁赋值 | **你自己**在某处赋值 | **第一次访问时**自动执行 lambda |
| 线程 | 无内置同步 | 默认线程安全（`LazyThreadSafetyMode.SYNCHRONIZED`） |
| 适用 | 框架回调里注入、测试里后赋值 | 昂贵对象、真正的延迟创建 |

Compose / 现代写法里，ViewBinding 场景变少；`lateinit` 仍常见于测试、部分 DI、遗留 View 代码。能用构造注入或 `lazy` 就优先它们。

## 四、基本类型概览 + `Array` / `IntArray`

Kotlin 没有 Java 那种"基本类型 / 包装类型"分裂：`Int`、`Long`、`Boolean`、`Char`、`Float`、`Double`、`Byte`、`Short` 在语法上都是类，编译器在能优化时会落成 JVM 基本类型。

集合优先用第 4 课的 `List` / `MutableList`。需要**定长、可按下标改、或与 Java API / NDK 交互**时才用数组：

```kotlin
val names: Array<String> = arrayOf("A", "B", "C")
names[0] = "Alpha"

val scores: IntArray = intArrayOf(90, 85, 100)   // 无装箱，更省
val flags = BooleanArray(3) { false }

println(scores.size)        // 3
scores.forEachIndexed { i, v -> println("$i -> $v") }
```

| 类型 | 说明 |
|---|---|
| `Array<T>` | 引用类型数组，元素可以是任意对象 |
| `IntArray` / `LongArray` / `BooleanArray` … | **基本类型专用数组**，避免装箱 |
| `List<T>` | 日常首选：不可变默认、API 丰富 |

`Array` **不变型**（invariant）：`Array<String>` 不能当成 `Array<Any>` 用——否则 `arr[0] = 1` 会破坏类型安全（和第 7 课泛型同一道理）。

## 五、`typealias`：给类型起别名

不产生新类型，只是换个好读的名字：

```kotlin
typealias UserId = Long
typealias ClickHandler = (UserId) -> Unit

fun onUserClick(handler: ClickHandler) { /* ... */ }

typealias StringMap = Map<String, String>
```

适合：长函数类型、反复出现的泛型组合。需要"新类型 + 类型检查"时用 `value class`（进阶，本课不展开），别名**不能**防止把普通 `Long` 当成 `UserId` 传入。

## 六、嵌套类 vs `inner` 类

```kotlin
class Outer(val name: String) {
    private val secret = 42

    class Nested {                      // 嵌套类：默认不持有 Outer
        fun hi() = "nested"             // 不能访问 secret / name
    }

    inner class Inner {                 // inner：持有外部类引用
        fun hi() = "inner of $name, secret=$secret"
    }
}

val n = Outer.Nested()                  // 不需要 Outer 实例
val i = Outer("Jerry").Inner()          // 必须先有 Outer
```

| | nested（默认） | `inner` |
|---|---|---|
| 外部引用 | 无 | 有（隐含 `Outer.this`） |
| 创建 | `Outer.Nested()` | `Outer(...).Inner()` |
| 风险 | 更干净 | 易泄漏外部实例（RecyclerView Adapter 里乱写 inner 要小心） |

`object` 伴生（第 2 课）也是嵌套在类里的单例，和 nested class 一样不持有外部实例。

## 七、易错点

1. **用 enum 建模带数据的 UI 状态**：`Success` 需要列表、`Error` 需要文案时，改用 `sealed`。
2. **`lateinit` 用于 `Int`/`Boolean`**：编译不过；基本类型用普通 `var` + 默认值，或可空。
3. **访问未初始化的 `lateinit`**：直接崩。关键路径先 `isInitialized`，或保证生命周期内一定先赋值。
4. **把 `Array` 当 `List` 用**：`arrayOf` 得到的是数组，很多 API 要 `listOf` / `toList()`。
5. **不必要地用 `inner`**：多占一个外部引用，可能泄漏 Activity / Fragment。
6. **以为 `typealias` 能防呆**：它只是别名，编译器仍按底层类型检查。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 固定常量集 | `enum class State { A, B, C }` |
| 带不同数据的状态 | `sealed interface UiState`（第 5、13 课） |
| 晚赋值非空 var | `lateinit var binding: XxxBinding` |
| 检查是否已赋值 | `::binding.isInitialized` |
| 首次访问才创建 | `val db by lazy { ... }` |
| 对象数组 | `arrayOf(...)` / `Array(n) { ... }` |
| 基本类型数组 | `intArrayOf(...)` / `IntArray(n)` |
| 类型别名 | `typealias Handler = (Int) -> Unit` |
| 不要外部引用 | `class Outer { class Nested }` |
| 要外部引用 | `class Outer { inner class Inner }` |

## 九、本课练习

1. 定义 `enum class Priority { Low, Medium, High }`，写一个 `fun label(p: Priority): String` 用穷尽 `when`。
2. 说明：为什么 `UiState.Success(data: List<User>)` 不适合做成 enum。
3. 写一个类，用 `lateinit` 声明 `lateinit var token: String`，在 `initAuth()` 里赋值，并用 `isInitialized` 决定是否跳过登录。
4. 对比：`val nums = intArrayOf(1,2,3)` 与 `val nums = listOf(1,2,3)` 各适合什么场景。

---

**下一课**：若你按主线走，语法部分到第 7 课已齐；Android 主线从第 8 课协程开始。本补遗可随时回查。第 23 课起补 Paging、WorkManager 等工程专题。
