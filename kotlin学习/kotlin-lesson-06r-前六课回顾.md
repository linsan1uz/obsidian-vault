# Kotlin 前六课回顾（第 1～6 课 + 补充课）

> 用途：进入第 7 课前的复盘笔记，只做回顾、不含练习。
> 读法：每课「核心 → 代码 → 易错点」，最后一屏速查表。

---

## 第 1 课：变量、函数与 Null 安全

**核心**

- `val` 不可变（≈ `final`），`var` 可变；**默认写 `val`**。
- 默认参数 + 命名参数替代 Java 重载；字符串模板 `$x` / `${表达式}`。
- `String` 永不为 null，`String?` 才可空，编译器强制处理。

```kotlin
fun toast(msg: String, duration: Int = 1000) = println("$msg, $duration")
val len = subtitle?.length ?: 0      // 安全调用 + Elvis 兜底
```

**易错点**

- `!!` 等于亲手拆掉保护，是 null 就当场崩。优先级：`?.`/`?:` → `if` 判空（smart cast）→ `!!`。
- 模板里跟了 `.`、运算符必须写 `${}`：`"${age + 1}"`。

## 第 2 课：类、data class 与 object

**核心**

- 主构造写在类名上，`val`/`var` 参数自动成为属性；没有 `new`。
- `data class` 自动生成 `equals/hashCode/toString/copy`，支持解构。
- `object` = 单例；`companion object` + `const val` = static 的替身。

```kotlin
data class User(val id: Long, val name: String)
val u2 = u1.copy(name = "老樊")      // 原对象不变
object Counter { var count = 0 }
```

**易错点**

- data class 的 `==` 比**内容**（Java 默认比引用）；比引用用 `===`。
- `const val` 只能是基本类型和 String；Java 调 object 要写 `Xxx.INSTANCE`。

## 第 3 课：扩展函数

**核心**

- `fun 类型.方法()` 给任何类"加"方法，替代 `XxxUtils`；体内 `this` 是接收者。
- 本质是编译成静态函数，只能访问公开成员。
- 可空接收者 `String?.xxx()` 连 null 都能调；还有扩展属性（只能靠 getter）。

```kotlin
fun View.gone() { visibility = View.GONE }
fun String?.safeLength(): Int = this?.length ?: 0
```

**易错点**

- **扩展按声明类型静态解析，没有多态**：`val x: Any = "hi"; x.describe()` 走 `Any` 的版本。
- 成员函数永远优先于同名扩展。
- 函数体二选一：`= 表达式` 或 `{ return ... }`，**`= { return ... }` 会变成 Lambda**。

## 第 4 课：Lambda、高阶函数与集合操作

**核心**

- 函数是值，有类型 `(Int) -> Int`；单参数 Lambda 用隐式 `it`。
- 高阶函数接收函数参数；最后一个参数是 Lambda 可移出括号（尾随 Lambda）。
- 集合直接 `filter/map/find/any/groupBy/sumOf`，不用 `.stream()`/`collect`。

```kotlin
val titles = articles.filter { !it.draft }.map { it.title }.take(10)
button.setOnClickListener { doSomething() }   // SAM 转换 + 尾随 Lambda
```

**易错点**

- 嵌套 Lambda 内外 `it` 撞车，外层要显式命名：`users.map { user -> ... }`。
- 回调 Lambda 是"收下、等时机再调"，不是立即执行。
- 上万条且多步链式才考虑 `asSequence()`，日常列表直接用。

## 第 5 课：when、密封类与作用域函数

**核心**

- `when` 是表达式，无 `break`、不穿透，分支可写值、`in` 范围、`is` 类型（自动 smart cast）。
- `sealed interface` + `data class` 建模 UI 状态，`when` 覆盖全部子类可**不写 else**；新增子类时漏处理处编译报错。
- 作用域函数按「`it`/`this`」×「返回结果/对象本身」区分。

```kotlin
sealed interface UiState {
    data class Loading(val message: String = "加载中...") : UiState
    data class Success(val data: List<String>) : UiState
}
fun render(s: UiState) = when (s) {
    is UiState.Loading -> showLoading(s.message)
    is UiState.Success -> showData(s.data)
}
```

| 函数 | 引用 | 返回 | 用途 |
|---|---|---|---|
| `let` | `it` | 结果 | 判空 |
| `apply` | `this` | 对象 | 配置 |
| `also` | `it` | 对象 | 副作用 |
| `run`/`with` | `this` | 结果 | 算结果 |

> 口诀：**判空用 let，配置用 apply，顺带做事用 also，算结果用 run/with。**

**易错点**

- `is` 只用于类型，值直接写：`401 ->`，不是 `is 401 ->`。
- `user?.let { user.name }` 编译不过——外面的 `user` 仍可空，要用 `it`。
- 精确分支放前面。

## 补充课：条件与循环

**核心**

- `if` 是表达式，替代三目运算符：`val lv = if (s >= 90) "优秀" else "一般"`。
- `for` 只有 `for (x in ...)`：`0..9`、`0 until 10`、`10 downTo 1`、`step 2`；带下标用 `withIndex()`。
- `while`/`do-while` 同 Java；`break@outer` 可跳出外层。

```kotlin
for ((i, item) in list.withIndex()) println("$i: $item")
when {                                   // 无对象形态：分支写条件
    i % 15 == 0 -> "FizzBuzz"
    i % 3 == 0 -> "Fizz"
    else -> "$i"
}
```

**易错点**

- `..` 含尾，`until` 不含尾；`3..100 step 3` 最后是 99。
- `when` 口诀：**有对象，分支写值；没对象，分支写条件**，两种不能混。
- 字符串用双引号，`'a'` 是 `Char`。
- 能用 `find/filter/sum` 就别手写循环；手写"找第一个"别忘了 `break`。

## 第 6 课：面向对象进阶

**核心**

- **默认 final，双层 open**：类要 `open` 才能继承，方法要 `open` 才能重写，重写强制 `override`。
- `abstract` 成员天生可重写；接口方法可直接带默认实现、可有抽象属性；单继承类 + 多实现接口。
- 主构造 + `init`（按顺序执行）+ 从构造 `constructor(...) : this(...)`；自定义 View 用 `@JvmOverloads`。
- 可见性默认 `public`，`internal` = 同模块可见，没有 package-private。

```kotlin
abstract class Vehicle(val wheels: Int) { abstract fun drive(): String }
interface Refuelable { val fuelType: String; fun refuel() = "加 $fuelType" }
class Car : Vehicle(4), Refuelable {      // 类带括号，接口不带
    override val fuelType = "汽油"
    override fun drive() = "开车"
}
```

**易错点**

- 继承报错分两种："type is final"（类没 open）vs "is final and cannot be overridden"（方法没 open）。
- `init` ≠ Java `static {}`：`init` 每个对象跑一次，类级只跑一次的放 `companion object`。
- 开放度阶梯：`final < sealed < abstract < open`；sealed 允许继承，只是锁在同文件。

---

## 速查表（一屏总览）

| 课 | 主题 | 一句话记住 | Java → Kotlin |
|---|---|---|---|
| 1 | 变量 / 函数 / null | 默认 `val`，`?.` + `?:`，少用 `!!` | 重载 → 默认参数 |
| 2 | 类 / data / object | 数据模型一律 `data class`，改值用 `copy` | POJO → 一行；单例 → `object`；static → `companion` |
| 3 | 扩展函数 | 静态解析、无多态，成员优先 | `Utils.hide(v)` → `v.hide()` |
| 4 | Lambda / 集合 | `it` 一层用，尾随 Lambda | 匿名内部类 → `{ }`；Stream → `filter/map` |
| 5 | when / sealed / 作用域 | sealed + when 免 else；let 判空 apply 配置 | switch → `when` |
| 5b | 条件与循环 | `if` 是表达式；`until` 最常用 | `i < 10` → `0 until 10`；三目 → `if` |
| 6 | OOP 进阶 | 双层 open，`final < sealed < abstract < open` | `extends/implements` → `: X(), Y`；package-private → `internal` |

---

**下一课：第 7 课 泛型与型变入门** —— `<T>`、上界约束、`out`/`in`、`reified`。
