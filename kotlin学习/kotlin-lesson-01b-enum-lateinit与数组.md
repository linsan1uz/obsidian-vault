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

|     | `lateinit var` | `by lazy`（第 18 课）                           |
| --- | -------------- | ------------------------------------------- |
| 可变性 | `var`，可多次赋值    | 本质是 `val`，只初始化一次                            |
| 谁赋值 | **你自己**在某处赋值   | **第一次访问时**自动执行 lambda                       |
| 线程  | 无内置同步          | 默认线程安全（`LazyThreadSafetyMode.SYNCHRONIZED`） |
| 适用  | 框架回调里注入、测试里后赋值 | 昂贵对象、真正的延迟创建                                |

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

---

## 答疑补充：lateinit 用法详解

> Jerry 追问：lateinit 的用法可以再详细一点吗？

### 1. 解决什么问题？

有些属性在**构造时还拿不到**（要等 `onCreate`、依赖注入、测试里后赋值），又不想写成可空 `Type?` 到处 `?.`：

```kotlin
class ProfileActivity : AppCompatActivity() {
    private lateinit var binding: ActivityProfileBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityProfileBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.title.text = "资料"   // 之后像非空属性一样用
    }
}
```

口诀：**保证生命周期里一定会先赋值，再用；用 `lateinit` 换掉烦人的可空。**

### 2. 语法与限制（必须记住）

```kotlin
lateinit var binding: ActivityProfileBinding   // ✅
```

| 规则 | 说明 |
|---|---|
| 只能是 **`var`** | 不能 `lateinit val` |
| 类型**非空引用类型** | `String`、自定义类、接口都行 |
| **不能**是可空类型 | `lateinit var s: String?` ❌ |
| **不能**是基本类型 | `Int` / `Boolean` / `Long` 等 ❌（用普通 `var x = 0` 或可空） |
| 不能在主构造参数里写 | 只能是类体里的属性 |
| 不能自带自定义 getter/setter | `lateinit` 自己管底层存储 |

### 3. 未初始化就用 → 直接崩

```kotlin
lateinit var token: String

fun needToken() {
    println(token)   // 若还没赋值 → UninitializedPropertyAccessException
}
```

同模块内可先检查：

```kotlin
fun maybeUse() {
    if (::token.isInitialized) {
        println(token)
    } else {
        println("还没登录")
    }
}
```

注意：

- `::token.isInitialized` 一般在**属性所在类内部**用（或能访问到该属性的地方）。
- 这是防崩手段，**不是**鼓励到处判；正常流程应保证「用之前一定赋过值」。

### 4. 可以多次赋值

`lateinit var` 本质是可变属性，赋值不限一次：

```kotlin
lateinit var repo: UserRepository

fun useFake() { repo = FakeUserRepository() }
fun useReal() { repo = RealUserRepository() }
```

若「只应创建一次、且第一次访问时再创建」→ 更适合 `by lazy`（见下表）。

### 5. `lateinit` vs `lazy`

| | `lateinit var` | `by lazy { }` |
|---|---|---|
| 可变性 | `var`，可多次赋值 | 实质 `val`，只初始化一次 |
| 谁赋值 | **你自己**在某处写 `x = ...` | **第一次读**时自动跑 lambda |
| 线程 | 无内置同步 | 默认线程安全 |
| 典型场景 | ViewBinding、`onCreate` 注入、测试后赋值、Hilt 字段注入 | 昂贵对象、真正的延迟创建 |
| 未就绪 | 读则抛 `UninitializedPropertyAccessException` | 读就会触发初始化 |

```kotlin
// lazy：首次访问才建
val db by lazy { Room.databaseBuilder(context, AppDatabase::class.java, "app.db").build() }
```

### 6. 和 Hilt / 测试

字段注入常见写法（第 14 课会再系统讲）：

```kotlin
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @Inject lateinit var userRepo: UserRepository
    // Hilt 在合适时机注入；你在 onCreate 之后当非空用
}
```

单元测试里也常用：先 `new` 出对象，再给 `lateinit` 属性塞 Fake。

### 7. 什么时候别用？

1. 值在构造时就有 → 构造参数 / 普通 `val`。
2. 可能长期为「没有」→ 用可空 `Type?`，语义更清楚。
3. 基本类型计数、开关 → `var count = 0`，不要硬上 `lateinit`。
4. 「第一次用才创建、且只需一次」→ `by lazy`。
5. 跨异步回调、说不清何时赋值 → 容易忘初始化而崩；改用可空或显式状态。

### 8. 易错点再强调

1. `lateinit var flag: Boolean` → 编译不过。
2. `lateinit var name: String?` → 编译不过（可空请直接用 `var name: String? = null`）。
3. 访问未初始化属性 → 运行时崩，不是编译期错误。
4. 和扩展属性无关：扩展属性没有背后字段，更谈不上 `lateinit`。
5. 能构造注入就优先构造注入；`lateinit` + 字段注入是框架妥协，不是首选设计。

### 9. 和 01b 正文的关系

正文第三节已给规则表与 ViewBinding 例子；本节把**限制、崩溃、`isInitialized`、多次赋值、lazy 对比、Hilt/测试、禁用场景**展开，方便单独回查。
---

## 答疑补充：`::binding.isInitialized` demo

> 配合上一节：什么时候查「赋过值没有」。

### 要点（先记住）

1. **只对 `lateinit var` 有意义**（普通属性 / `lazy` 不用这套）。
2. 写法是属性引用：`::binding.isInitialized`（前面两个冒号）。
3. **通常在声明该属性的类内部**调用。
4. 赋过值 → `true`；还没赋 → `false`。再赋值仍是 `true`。
5. 它是**防崩检查**，不是业务状态机——别用它表达「已登录 / 未登录」这类领域状态（那种用显式 `sealed` / 可空 / StateFlow）。

### Demo 1：Activity + ViewBinding

```kotlin
class DemoActivity : AppCompatActivity() {
    private lateinit var binding: ActivityDemoBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // inflate 前：false，此时千万别碰 binding.xxx
        Log.d("lateinit", "before inflate: ${::binding.isInitialized}")  // false

        binding = ActivityDemoBinding.inflate(layoutInflater)
        setContentView(binding.root)

        Log.d("lateinit", "after inflate: ${::binding.isInitialized}")   // true
        binding.title.text = "Hello"
    }

    override fun onDestroy() {
        // Activity 销毁时属性往往仍是已初始化（对象还在）
        // 若你另有「可空 binding + onDestroyView 置 null」的 Fragment 写法，那是另一套模式
        Log.d("lateinit", "onDestroy: ${::binding.isInitialized}")
        super.onDestroy()
    }

    fun safeRefreshTitle(text: String) {
        if (::binding.isInitialized) {
            binding.title.text = text
        }
    }
}
```

Fragment + ViewBinding 更常见的是 `_binding` 可空、在 `onDestroyView` 置 `null`（第 28 课），不一定用 `lateinit`；Activity 全页 binding 用 `lateinit` + `isInitialized` 更常见。

### Demo 2：纯 Kotlin（不依赖 Android）

```kotlin
class Holder {
    private lateinit var value: String

    fun ready(): Boolean = ::value.isInitialized

    fun set(v: String) {
        value = v
    }

    fun getOrNull(): String? =
        if (::value.isInitialized) value else null
}

fun main() {
    val h = Holder()
    println(h.ready())        // false
    println(h.getOrNull())    // null
    h.set("Jerry")
    println(h.ready())        // true
    println(h.getOrNull())    // Jerry
}
```

可在 [Kotlin Playground](https://play.kotlinlang.org) 直接跑 Demo 2。

### 和上一节的衔接

- 未初始化就读属性 → `UninitializedPropertyAccessException`。
- 关键路径不确定时先 `isInitialized`；正常生命周期里更推荐**保证先赋值再使用**，少写分支。

---

## 答疑补充：KProperty 怎么理解？

> Jerry 提问：KProperty 怎么理解？

### 一句话

**`KProperty` 是「某个属性」在反射里的句柄**——不是属性里存的值，而是指向这个属性本身的元信息对象。通过它你可以问：叫什么名字、有没有初始化、取值/赋值（在可见的前提下）。

日常写业务几乎碰不到；你已经用过的 `::binding.isInitialized`，左边的 `::binding` 就是在拿这个句柄。

### 和「值」的区别

```kotlin
lateinit var binding: ActivityDemoBinding

binding          // 属性的【值】：那个 Binding 实例
::binding        // 属性的【引用/句柄】：KProperty / KMutableProperty
```

口诀：**不带 `::` 拿内容；带 `::` 拿属性本身。**

### 纯 Kotlin 小例子（Playground 可跑）

```kotlin
class Holder {
    lateinit var name: String

    fun demo() {
        val prop = ::name                    // KMutableProperty0<String>
        println(prop.name)                   // "name"
        println(prop.isInitialized)          // false（仅 lateinit 有）

        prop.set("Jerry")                    // 等价于 name = "Jerry"
        println(prop.isInitialized)          // true
        println(prop.get())                  // "Jerry"
    }
}

fun main() = Holder().demo()
```

- `get()` / `set()`：通过句柄读写（可变属性才是 `KMutableProperty`，才有 `set`）。
- `isInitialized`：挂在 lateinit 对应的句柄上（上一节 demo）。

### 常见 `::` 形态（了解即可）

| 写法 | 大致得到 | 含义 |
|---|---|---|
| `::name`（类内） | `KProperty0` / `KMutableProperty0` | 当前实例上的这个属性 |
| `Holder::name` | `KProperty1<Holder, …>` | 「Holder 的 name 属性」，用时要带接收者 |
| `::foo`（顶层函数） | `KFunction` | 函数引用（不是属性） |
| `instance::name` | 绑定到某实例的属性引用 | 少见，测试/框架里可能出现 |

应用层记住两格就够：`::binding` + `isInitialized`；以及「这是反射句柄」。

### 和委托的关系（第 18 课预告）

属性委托的约定签名里会看到 `KProperty<*>`：

```kotlin
operator fun getValue(thisRef: Any?, property: KProperty<*>): String {
    // property.name 是被委托的属性名
    return "..."
}
```

那是标准库/委托约定要用元信息；**不是**让你在 Activity 里手写反射业务。

### 什么时候需要关心？

| 需要 | 不需要 |
|---|---|
| 理解 `::x.isInitialized` | 普通读写 `x` / `x = ...` |
| 写属性委托、部分框架/序列化 | ViewModel、Repository、Compose UI |
| 调试、学习反射 | 用 KProperty 当业务状态 |

### 收束

**`KProperty` = 属性的反射身份证；`::binding` 把它拿到手；`isInitialized` / `get` / `set` 是身份证上能盖的几个戳。业务代码优先直接用属性值，把反射留给框架和少数工具场景。**
