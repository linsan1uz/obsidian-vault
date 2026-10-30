# Kotlin 语法糖速查

> **答疑：kotlin一些简化的语法糖**（Jerry 提问整理）
> 用途：把日常会省掉的写法收成一张表，方便回查。深入讲解仍以各课正文为准。
> 对应课次：第 1、2、3、4、5、5b、18、19 课等。

---

## 一、类型推断（第 1 课）

右边能看出来类型，左边就不用写：

```kotlin
val name = "Jerry"          // String
var count = 0               // Int
val list = listOf(1, 2, 3)  // List<Int>
```

需要写的时候：函数参数、返回类型（块函数体）、接口实现、想强调类型时。

## 二、单表达式函数（第 1、3 课）

函数体只有一个表达式时，用 `=`，可省略返回类型：

```kotlin
fun double(x: Int) = x * 2
fun String.shout() = uppercase() + "!"
```

块函数体 `{ return ... }` 则**必须**显式写返回类型（返回 `Unit` 除外）。

## 三、默认参数 + 命名参数（第 1 课）

少写重载：

```kotlin
fun toast(msg: String, duration: Int = 1000) { /* ... */ }

toast("你好")
toast("你好", duration = 2000)   // 命名参数，可读性好，顺序可乱
```

## 四、字符串模板（第 1 课）

```kotlin
val age = 25
println("明年 ${age + 1} 岁")   // 表达式用 ${}
println("名字 $name")            // 简单变量可省大括号
println("价格 ${'$'}9.9")        // 输出字面 $
```

## 五、Null 安全（第 1 课）

```kotlin
val s: String? = null
val len = s?.length          // 安全调用，null 则整段为 null
val len2 = s?.length ?: 0    // Elvis：左边 null 就用右边
val must = s!!               // 非空断言（真信它非空才用，崩了自负）

s?.let { println(it.length) }  // 非空才进块
```

提前返回常用：

```kotlin
fun parse(id: String?): Int {
    val v = id?.toIntOrNull() ?: return -1
    return v
}
```

## 六、`if` / `when` 是表达式（第 5、5b 课）

能赋值、能当返回值：

```kotlin
val max = if (a > b) a else b

val label = when (code) {
    200 -> "OK"
    404 -> "Not Found"
    else -> "Other"
}
```

`when` 还可不带参数，当加强版 if-else 链；配合 **密封类 / enum** 可穷尽分支、少写 `else`（第 5 课、01b）。

## 七、尾随 Lambda、`it`、`_`（第 4 课）

最后一个参数是函数类型时，Lambda 可挪到括号外：

```kotlin
list.filter { it > 0 }              // 单参默认叫 it
list.forEach { item -> println(item) }
list.mapIndexed { _, value -> value * 2 }  // 不用的参数用 _
button.setOnClickListener { toast("点了") }
```

## 八、作用域函数速查（第 5 课）

| 函数 | 对象在块里叫 | 返回值 | 典型用途 |
|---|---|---|---|
| `let` | `it` | 块结果 | 可空链式、转换 |
| `run` | `this` | 块结果 | 配置并算一个结果 |
| `with(x)` | `this` | 块结果 | 对已有对象写多句 |
| `apply` | `this` | **对象本身** | 初始化 / 链式配置 |
| `also` | `it` | **对象本身** | 顺手做副作用（打日志） |

`also` vs `apply` 一行对比：

```kotlin
val p = Person().apply { name = "Jerry" }     // 块里 this，返回 Person
val q = Person().also { println(it.name) }    // 块里 it，返回 Person
```

口诀：**要改对象自身并继续用它 → apply；要顺带看看/记下它 → also。**

## 九、`data class` / `object` / 扩展 / 委托（第 2、3、18 课）

```kotlin
data class User(val id: Long, val name: String)  // equals/hashCode/toString/copy/组件

object AppConfig { val baseUrl = "https://api.example.com" }  // 单例

fun View.gone() { visibility = View.GONE }   // 扩展函数（第 3 课）

val name by lazy { loadName() }              // 委托属性（第 18 课）
class Repo : UserApi by apiImpl              // 类委托：接口实现转交
```

## 十、区间、`infix`、解构（第 5b、19、2 课）

```kotlin
for (i in 1..5) { }          // 1 到 5
for (i in 1 until 5) { }     // 1 到 4
for (i in 5 downTo 1) { }
if (x in 1..10) { }

infix fun Int.times(s: String) = s.repeat(this)
3 times "哈"                  // 中缀：看起来像自然语言（第 19 课）

val (id, name) = User(1, "Jerry")     // 解构：data class 组件函数
val (a, b) = listOf(1, 2)             // List/Map.Entry 等也支持
for ((k, v) in map) { }
```

## 十一、`==` vs `===`

| | 含义 |
|---|---|
| `==` | 结构相等（会走 `equals`）；对基本类型比的是值 |
| `===` | 引用同一实例（身份） |

```kotlin
val a = "hi"
val b = "hi"
a == b    // true（内容）
a === b   // 多数情况 true（字符串池），别依赖这个细节
data class P(val x: Int)
P(1) == P(1)    // true
P(1) === P(1)   // false（两个对象）
```

## 十二、智能转换注意点（第 1、5 课）

```kotlin
fun printLen(x: Any) {
    if (x is String) {
        println(x.length)   // 智能转成 String ✅
    }
}
```

**坑：可变属性（`var`）或自定义 getter 不一定能智能转换**——检查后可能已被别的线程/代码改掉：

```kotlin
var prop: Any = "hi"
if (prop is String) {
    // println(prop.length)  // 可能编译不过
    val s = prop as String   // 或先 val local = prop
    println(s.length)
}
```

局部 `val` 最稳。

## 十三、其它高频短写法

```kotlin
list.filterNotNull()
list.firstOrNull { it > 10 }
map.getOrElse("k") { "默认" }
require(x > 0) { "x 必须为正" }   // 不满足抛 IllegalArgumentException
checkNotNull(user)
"a,b,c".split(",").map { it.trim() }
```

Elvis 提前返回（再强调一次）：

```kotlin
val user = repo.find(id) ?: return
val user2 = repo.find(id) ?: error("找不到")
```

## 十四、和课次对照

| 语法糖 | 深入课次 |
|---|---|
| `val`/`var`、类型推断、null、`==` | 第 1 课 |
| `data class`、`object`、解构 | 第 2 课 |
| 扩展函数 / 扩展属性 | 第 3 课 |
| Lambda、`it`、集合操作 | 第 4 课 |
| `when`、密封类、作用域函数 | 第 5 课 |
| `if`/循环/区间 | 第 5b 课 |
| 委托 `by` | 第 18 课 |
| 运算符、`infix`、DSL | 第 19 课 |
| enum / `lateinit` 等薄点 | 第 01b 课 |

---

**怎么用这张表**：写代码卡壳时先搜关键字；要系统学仍按主线课往下走。有新的「这也能省？」随时再加一节答疑。
