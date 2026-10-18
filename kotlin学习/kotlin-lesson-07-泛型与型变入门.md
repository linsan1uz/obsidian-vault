# Kotlin 第 7 课：泛型与型变入门

> 适用读者：已完成第 4、6 课（集合、继承）。
> 核心收获：会写带泛型的类/函数，搞懂 `out`/`in` 为什么存在，理解为什么 `List<String>` 能当 `List<Any>` 用，以及 `reified` 如何绕过类型擦除。

---

## 一、为什么需要泛型？

没有泛型时，"装东西的盒子"只能写成 `Any`，取出来再强转——容易写错类型、运行时才崩：

```kotlin
// 没有泛型：什么都能塞，取出要赌类型
class Box(var value: Any?)

val box = Box("hello")
val n: Int = box.value as Int   // 💥 ClassCastException，编译过得了，运行崩
```

泛型把"这个盒子装什么"写进类型系统，**编译期就拦住错误**：

```kotlin
class Box<T>(var value: T)

val box = Box("hello")          // T 被推断为 String
val s: String = box.value       // ✅ 不用强转
// val n: Int = box.value       // ❌ 编译报错，根本塞不进来
```

- `<T>` 叫**类型参数**，`T` 只是占位符名字（常见还有 `E`/`K`/`V`/`R`）。
- 创建时传入真实类型（或靠推断），之后这个实例里 `T` 就定死了。
- Android 里到处是：`List<User>`、`LiveData<UiState>`、`Result<T>`、`Flow<T>`。

## 二、泛型函数与泛型约束

类可以带泛型，**函数也能**：

```kotlin
fun <T> singletonList(item: T): List<T> = listOf(item)

singletonList(42)          // List<Int>
singletonList("hi")        // List<String>
```

有时你希望 `T` 不能是任意类型，必须满足某个条件——这叫**上界约束**：

```kotlin
fun <T : Comparable<T>> maxOf(a: T, b: T): T =
    if (a > b) a else b     // 因为 T : Comparable，才能用 >

maxOf(3, 5)                 // 5
maxOf("a", "z")             // "z"
// maxOf(Any(), Any())      // ❌ Any 没实现 Comparable
```

多个约束用 `where`（少见，知道即可）：

```kotlin
fun <T> copyWhenGreater(list: List<T>, threshold: T): List<T>
    where T : CharSequence, T : Comparable<T> { ... }
```

口诀：**`<T>` = 随便什么；`<T : Xxx>` = 必须是 Xxx 的子类型。**

## 三、型变：`out` 与 `in` ⭐

这是本课最核心、也最容易晕的一块。先从一个直觉问题切入：

```kotlin
val strings: List<String> = listOf("a", "b")
val anyList: List<Any> = strings    // ✅ 合法！为什么？
```

`String` 是 `Any` 的子类型，那 `List<String>` 是不是 `List<Any>` 的子类型？**Java 里不是**（数组才是，还埋了坑）；Kotlin 的只读 `List` **故意做成是**——靠关键字 `out`。

### 1. `out T`：生产者（协变）——只能往外"产"

```kotlin
interface Producer<out T> {
    fun produce(): T          // ✅ T 只出现在"输出"位置（返回值）
    // fun consume(item: T)   // ❌ 编译报错：out 不能当参数
}

// 因为 out，Producer<String> 可以当成 Producer<Any> 用
val p: Producer<Any> = object : Producer<String> {
    override fun produce() = "hello"
}
```

标准库的 `List` 就是这样声明的：`interface List<out E>`。只读列表只会"拿出"元素，绝不会"塞进"元素，所以 `List<String>` → `List<Any>` 安全。

**对比可变列表**：`MutableList` **没有** `out`，因为既能 get 也能 add：

```kotlin
val strings: MutableList<String> = mutableListOf("a")
// val anyList: MutableList<Any> = strings   // ❌ 编译报错
// 假如允许，anyList.add(1) 就会把 Int 塞进 String 列表——灾难
```

### 2. `in T`：消费者（逆变）——只能往里"吃"

```kotlin
interface Consumer<in T> {
    fun consume(item: T)      // ✅ T 只出现在"输入"位置（参数）
    // fun produce(): T       // ❌ in 不能当返回值
}

// 因为 in，Consumer<Any> 可以当成 Consumer<String> 用
// （能吃 Any 的，当然能吃 String）
val c: Consumer<String> = object : Consumer<Any> {
    override fun consume(item: Any) { println(item) }
}
```

Android 实战例子：`Comparator` 是 `in` 的——`Comparator<Number>` 可以比较 `Int`。

### 3. 不变（invariant）：什么都不写

```kotlin
class Box<T>(var value: T)    // 又读又写 → 不变
// Box<String> 和 Box<Any> 互不兼容
```

### 型变口诀（务必背）

> **`out` = 输出 = 生产者 = 协变 = "子类盒子能当父类盒子"**  
> **`in` = 输入 = 消费者 = 逆变 = "父类消费者能当子类消费者"**  
> **又读又写 = 不变 = 什么都不写**

记不住就问：这个类型参数是"拿出来用"还是"传进去用"？只出 → `out`；只进 → `in`；又进又出 → 不加。

## 四、星号投影与类型擦除

### 1. 星号投影 `*`

不知道具体类型参数时写 `*`（"某种东西，但我不管是什么"）：

```kotlin
fun printSize(list: List<*>) {
    println(list.size)          // ✅ 和类型无关的操作可以
    // val item: String = list[0]  // ❌ 取出来只能当 Any?
}

val boxes: List<Box<*>> = listOf(Box(1), Box("a"))
```

大致相当于 Java 的 `List<?>`。

### 2. 类型擦除：运行时没有 `T`

和 Java 一样，泛型信息在编译后被擦掉——运行时 `List<String>` 和 `List<Int>` 都是 `List`：

```kotlin
fun <T> isStringList(list: List<T>): Boolean {
    // return list is List<String>   // ❌ 编译报错：Cannot check for instance of erased type
    return true
}
```

所以 `is`/`as` 检查具体泛型参数通常做不到。

## 五、`reified`：让泛型在运行时"看得见" ⭐

配合 `inline`，可以把类型参数标成 `reified`（具体化），编译器会把真实类型**内联进调用处**，从而绕过擦除：

```kotlin
inline fun <reified T> Any.isOfType(): Boolean = this is T

"hello".isOfType<String>()    // true
"hello".isOfType<Int>()       // false
```

Android 高频用法——启动 Activity 不用再写 `XXX::class.java`：

```kotlin
inline fun <reified T : Activity> Context.startActivity() {
    startActivity(Intent(this, T::class.java))
}

// 调用：
startActivity<DetailActivity>()
```

要点：

- **必须是 `inline fun`**——内联后才知道调用处的真实 `T`。
- `reified` 只能用在内联函数的类型参数上，不能标在类上。
- 这是 Kotlin 相对 Java 的巨大优势：Java 做不到等价的事。

## 六、对照速查表

| Java | Kotlin |
|---|---|
| `class Box<T>` | `class Box<T>`（写法几乎一样） |
| `<? extends T>` 上界通配 | `out T`（声明处型变） |
| `<? super T>` 下界通配 | `in T` |
| `List<?>` | `List<*>` |
| 无法在运行时拿 `T.class` | `inline fun <reified T>` + `T::class` |
| `T extends Comparable` | `<T : Comparable<T>>` |
| PECS（Producer Extends, Consumer Super） | `out` 生产者 / `in` 消费者 |

Java 的通配符写在**使用处**（`List<? extends Number>`）；Kotlin 的 `out`/`in` 写在**声明处**（`interface List<out E>`），用的时候干净很多——这叫**声明处型变**。

## 七、本课练习及参考答案（Playground）

```kotlin
// 1. 泛型类：写一个不可变的 Holder
class Holder<T>(val value: T)
val h = Holder("Kotlin")
println(h.value)   // Kotlin

// 2. 带约束的泛型函数
fun <T : Number> doubleOf(x: T): Double = x.toDouble() * 2
println(doubleOf(3))      // 6.0
println(doubleOf(2.5))    // 5.0

// 3. out：只读生产者
interface Source<out T> {
    fun next(): T
}
class StringSource : Source<String> {
    override fun next() = "hi"
}
val src: Source<Any> = StringSource()   // ✅ 协变，String → Any
println(src.next())                     // hi

// 4. 思考：为什么下面这行编译不过？
// val ms: MutableList<Any> = mutableListOf<String>("a")
// 答：MutableList 不变（又能 add 又能 get）。若允许，ms.add(1) 会破坏 String 列表。
//     只读 List 有 out，所以 List<String> 能赋给 List<Any>。

// 5. reified：类型判断
inline fun <reified T> List<*>.firstIs(): T? =
    firstOrNull()?.let { if (it is T) it else null }

val mixed: List<Any> = listOf(1, "a", 2.0)
println(mixed.firstIs<String>())   // a
println(mixed.firstIs<Int>())      // 1
```

---

**下一课预告（第 8 课）：协程入门** —— `suspend`、`launch`/`async`、结构化并发，彻底告别回调地狱（第 1 课路线图里预告过的那一块）。
