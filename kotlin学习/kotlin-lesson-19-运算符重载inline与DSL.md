# Kotlin 第 19 课：运算符重载、inline 与 DSL

> 适用读者：已完成第 4 课（Lambda、高阶函数）、第 7 课（`reified`）、第 18 课（委托里的 `operator fun getValue`）。
> 核心收获：会用 `operator fun` 重载 `+ [] in ()` 等运算符，会写 `infix` 函数，理解 `inline / noinline / crossinline` 和 `value class`，掌握"带接收者的 Lambda"，亲手写一个小 DSL，看懂 Gradle kts 和 Compose 的语法本质。

---

## 一、运算符重载：`operator fun`

Kotlin 的运算符其实是**固定名字的函数**。给函数加 `operator`，就能用符号调用：

```kotlin
data class Money(val cents: Long) {
    operator fun plus(other: Money) = Money(cents + other.cents)     // a + b
    operator fun times(n: Int) = Money(cents * n)                    // a * 3
    operator fun compareTo(other: Money) = cents.compareTo(other.cents) // a > b
    operator fun unaryMinus() = Money(-cents)                        // -a
}

val price = Money(1999)
val total = price * 3 + Money(500)      // Money(cents=6497)
if (total > Money(5000)) println("满减")
```

常用对照：

| 符号 | 函数名 | 例子 |
|---|---|---|
| `a + b` / `a - b` / `a * b` | `plus` / `minus` / `times` | 金额、向量 |
| `a += b` | `plusAssign`（或用 `plus` 再赋值） | 可变集合 |
| `a[i]` / `a[i] = v` | `get` / `set` | 自定义容器 |
| `x in a` | `contains` | 范围、集合 |
| `a()` | `invoke` | 把对象当函数调 |
| `a > b` 等 | `compareTo` | 排序比较 |
| `a..b` | `rangeTo` | 第 5b 课的范围 |
| `val (x, y) = a` | `component1()` / `component2()` | data class 自动生成（第 2 课） |

`invoke` 很常见——UseCase 写法：

```kotlin
class GetActiveUsersUseCase @Inject constructor(private val repo: UserRepository) {
    operator fun invoke(): Flow<List<User>> = repo.users.map { list -> list.filter { it.active } }
}

val users = getActiveUsers()        // 对象像函数一样调用
```

口诀：**运算符 = 约定名字的函数；只在语义一看就懂时重载，别让 `+` 去删数据库。**

## 二、`infix`：去掉点和括号

```kotlin
infix fun Int.percentOf(total: Int): Int = total * this / 100

val discount = 20 percentOf 300      // 60，等价于 20.percentOf(300)
```

- 要求：成员函数或扩展函数，**恰好一个参数**。
- 你早就用过：`"name" to "fz"`（第 4 课 `mapOf`）、`0 until 10`、`10 downTo 1`、`step 2`（第 5b 课）都是 infix。

## 三、`inline`：把 Lambda 原地展开 ⭐

第 4 课的高阶函数，每传一个 Lambda，运行时都要**创建一个函数对象**。`inline` 让编译器把函数体和 Lambda **直接复制到调用处**：

```kotlin
inline fun <T> measure(tag: String, block: () -> T): T {
    val start = System.nanoTime()
    val result = block()
    println("$tag 耗时 ${(System.nanoTime() - start) / 1_000_000}ms")
    return result
}

val users = measure("查询") { dao.getAllOnce() }
// 编译后相当于直接把计时代码写在这里，没有 Lambda 对象
```

`inline` 的三个效果：

1. **省掉 Lambda 对象分配**：`filter`、`map`、`let`、`apply` 等标准库函数都是 inline，所以第 4、5 课随便链式调用也不怕性能问题。
2. **非局部返回**：inline Lambda 里的 `return` 直接返回**外层函数**。

```kotlin
fun findJerry(users: List<User>): User? {
    users.forEach {                    // forEach 是 inline
        if (it.name == "Jerry") return it   // 直接从 findJerry 返回
    }
    return null
}
```

3. **支持 `reified`**（第 7 课）：类型在调用处已知，所以 `T::class` 能用。

### `noinline` 和 `crossinline`

```kotlin
inline fun runTask(
    onStart: () -> Unit,
    noinline onDone: () -> Unit,        // 这个 Lambda 要存起来/传给别人，不能展开
    crossinline onTick: () -> Unit      // 会展开，但禁止在里面写非局部 return
) {
    onStart()
    handler.post(onDone)                // 当对象传出去 → 必须 noinline
    executor.execute { onTick() }       // 在另一个 Lambda 里调用 → 必须 crossinline
}
```

| 修饰 | 意思 | 什么时候需要 |
|---|---|---|
| （默认） | 展开，允许非局部 return | 只在函数体里直接调用 |
| `noinline` | 不展开，就是普通函数对象 | 要把 Lambda 存进变量、传给非 inline 函数 |
| `crossinline` | 展开，但禁止非局部 return | 在另一个 Lambda / 对象里调用它 |

什么时候写 `inline`：**参数里有 Lambda 的小工具函数**。没有 Lambda 参数的普通函数加 inline 没好处，编译器还会警告。

## 四、`value class`：零开销的类型包装

```kotlin
fun loadUser(userId: Long, orgId: Long) { }
loadUser(orgId, userId)               // ❌ 参数传反了，编译器发现不了
```

```kotlin
@JvmInline
value class UserId(val value: Long)

@JvmInline
value class OrgId(val value: Long)

fun loadUser(userId: UserId, orgId: OrgId) { }
loadUser(OrgId(1), UserId(2))         // ✅ 编译报错，类型不同
```

- 只能有**一个属性**。运行时大多数情况下直接用底层的 `Long`，**不额外创建对象**。
- 适合：各种 id、金额、单位（`Dp` 就是 Compose 里的 value class，所以 `16.dp` 几乎没有开销）。
- 可以有方法、`init` 校验，不能有额外的状态。

## 五、带接收者的 Lambda ⭐

第 5 课的 `apply` 里能直接写属性名，因为它的参数类型是 **`T.() -> Unit`**——Lambda 里的 `this` 就是 `T`：

```kotlin
// 普通 Lambda：参数是 StringBuilder，要用 it
val a: (StringBuilder) -> Unit = { it.append("hi") }

// 带接收者的 Lambda：this 是 StringBuilder，直接调方法
val b: StringBuilder.() -> Unit = { append("hi") }
```

自己写一个：

```kotlin
fun buildGreeting(block: StringBuilder.() -> Unit): String {
    val sb = StringBuilder()
    sb.block()                       // 让 sb 当 this 执行 Lambda
    return sb.toString()
}

val s = buildGreeting {
    append("你好，")                  // this = StringBuilder
    append("Jerry")
}
```

标准库的 `buildString { }`、`buildList { }` 就是这样实现的。第 3 课扩展函数 + 第 4 课 Lambda 合体，就是 DSL 的全部地基。

## 六、写一个小 DSL ⭐

目标：用声明式写法构造假数据，给第 15 课的 Preview 和第 21 课的测试用。

```kotlin
@DslMarker
annotation class UserDsl                 // 防止内外层作用域串

@UserDsl
class UserBuilder {
    var id: Long = 0
    var name: String = ""
    var email: String = ""
    fun build() = User(id, name, email)
}

@UserDsl
class UserListBuilder {
    private val users = mutableListOf<User>()
    fun user(block: UserBuilder.() -> Unit) {
        users += UserBuilder().apply(block).build()
    }
    fun build(): List<User> = users
}

fun userList(block: UserListBuilder.() -> Unit): List<User> =
    UserListBuilder().apply(block).build()

// 使用
val fakeUsers = userList {
    user { id = 1; name = "Jerry"; email = "j@x.com" }
    user { id = 2; name = "Tom";   email = "t@x.com" }
}
```

**`@DslMarker` 的作用**：没有它时，在 `user { }` 里面还能隐式调用外层的 `user()`，写出 `user { user { } }` 这种奇怪嵌套也能编译。标了之后，内层只能访问最近的接收者，外层的要显式写 `this@userList`。

## 七、回头看：Gradle kts 和 Compose

```kotlin
// build.gradle.kts
dependencies {                             // dependencies(block: DependencyHandlerScope.() -> Unit)
    implementation("androidx.room:room-runtime:2.8.5")   // this 是 DependencyHandlerScope
}

android {
    buildFeatures { compose = true }       // 一层层带接收者的 Lambda
}
```

```kotlin
// Compose
Column {                                   // content: @Composable ColumnScope.() -> Unit
    Text("A", Modifier.weight(1f))         // weight 是 ColumnScope 的扩展，只能在 Column 里用
}
```

- 为什么 `Modifier.weight()` 只在 `Column` / `Row` 里能用？因为它定义在 `ColumnScope` / `RowScope` 上，只有带这个接收者时才可见——和本课 DSL 原理一样。
- `LazyColumn { items(...) { } }` 的 `items` 是 `LazyListScope` 的方法，同理。

口诀：**DSL = 扩展函数 + 带接收者的 Lambda + `@DslMarker`；Gradle 和 Compose 都是这么写出来的。**

## 八、易错点

1. **重载运算符语义不直观**：`user + group` 到底是加入还是合并？看不懂就别用运算符，写普通函数名。
2. **`operator` 函数名拼错**：比如写成 `add` 想重载 `+`，编译报错——名字是约定死的（`plus`）。
3. **给没有 Lambda 参数的函数加 `inline`**：没收益，代码体积变大，编译器警告。
4. **大函数加 `inline`**：每个调用处都复制一份，APK 变大。只给小工具函数加。
5. **在非 inline 的 Lambda 里写 `return`**：编译报错，要用 `return@标签`（第 5b 课标签）。
6. **把 inline 参数存进变量、传给别的函数**：要加 `noinline`。
7. **`value class` 想放两个属性**：不允许，多个属性用 data class。
8. **DSL 不加 `@DslMarker`**：内层可以误调外层方法，产生莫名其妙的嵌套。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 重载 `+` | `operator fun plus(o: T): T` |
| 重载 `[]` | `operator fun get(i: Int)` / `set(i: Int, v: T)` |
| 对象当函数调 | `operator fun invoke()` |
| 去掉点和括号 | `infix fun A.op(b: B)` → `a op b` |
| Lambda 原地展开 | `inline fun f(block: () -> Unit)` |
| 不展开某个 Lambda | `noinline` |
| 展开但禁止 return | `crossinline` |
| 零开销类型包装 | `@JvmInline value class UserId(val value: Long)` |
| 带接收者的 Lambda | `block: T.() -> Unit`，调用 `t.block()` |
| DSL 作用域隔离 | `@DslMarker annotation class XxxDsl` |

---

**下一课预告（第 20 课）：Channel 与并发安全** —— 协程之间怎么传数据？多个协程同时改一个变量会出什么事？`Channel`、`Mutex`、原子类，以及 Channel 和 SharedFlow 发一次性事件的区别。
