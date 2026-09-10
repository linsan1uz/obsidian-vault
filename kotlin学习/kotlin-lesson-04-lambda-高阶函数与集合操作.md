# Kotlin 第 4 课：Lambda、高阶函数与集合操作

> 适用读者：已完成第 1～3 课。
> 核心收获：看懂 `setOnClickListener { }` 的原理，用 `filter/map` 替代 Java Stream 样板，理解一切回调的本质。

---

## 一、Lambda 本质：一个"函数类型的值"

Kotlin 里函数可以像普通值一样存进变量、传来传去。函数也有类型：

```kotlin
// 声明一个"函数类型"的变量：接收一个 Int，返回一个 Int
val double: (Int) -> Int = { x -> x * 2 }

double(5)        // 10，像调用函数一样调用这个变量
```

- `{ x -> x * 2 }` 就是 **Lambda**：一段匿名的、可传递的函数代码。`->` 左边是参数，右边是函数体。
- **`it` 是唯一参数的隐式名字**：Lambda 只有一个参数时，可以不写参数声明，编译器自动命名为 `it`：

```kotlin
val double: (Int) -> Int = { it * 2 }    // it 就是那个唯一的参数
```

`it` 不是关键字，就是约定俗成的自动参数名；想自己起名随时可以写 `参数名 ->`：

```kotlin
students.filter { student -> student.score >= 60 }
```

## 二、高阶函数：接收函数作为参数的函数

```kotlin
// 第二个参数 operation 是函数类型
fun calculate(a: Int, b: Int, operation: (Int, Int) -> Int): Int {
    return operation(a, b)
}

calculate(3, 4, { x, y -> x + y })   // 7
calculate(3, 4) { x, y -> x * y }    // 12
```

**Trailing lambda（尾随 Lambda）**：如果 Lambda 是函数的**最后一个参数**，可以把它移出括号。这是 Kotlin 最重要的语法糖之一，以下代码全是同一个原理：

```kotlin
button.setOnClickListener { v -> doSomething() }
lifecycleScope.launch { fetchData() }
Thread { backgroundWork() }.start()
```

Java 对照：同样的 `setOnClickListener` 在 Java 里要写整个匿名内部类。`OnClickListener` 是单方法 Java 接口（SAM 接口），Kotlin 自动把 Lambda 转换成它：

```java
button.setOnClickListener(new View.OnClickListener() {
    @Override
    public void onClick(View v) { doSomething(); }
});
```

## 三、集合操作：Stream 的活儿，集合直接干

```kotlin
val numbers = listOf(1, 2, 3, 4, 5)              // 不可变 List
val map = mapOf("name" to "fz", "age" to 25)     // Map，用 to 创建键值对

numbers.filter { it % 2 == 0 }                   // [2, 4]
numbers.map { it * 10 }                          // [10, 20, 30, 40, 50]
numbers.filter { it % 2 == 0 }.map { it * 10 }   // [20, 40]，链式组合
```

对比 Java Stream：不需要 `.stream()` 开头、`.collect(Collectors.toList())` 结尾。

### 常用操作符速查（按使用频率）

| 操作 | 作用 | 示例 |
|---|---|---|
| `filter { }` | 按条件筛选 | `users.filter { it.age > 18 }` |
| `map { }` | 逐个变换 | `users.map { it.name }` |
| `find { }` / `firstOrNull { }` | 找第一个满足的，没有返回 null | `users.find { it.id == 1 }` |
| `any { }` / `all { }` | 存在/全部满足？返回 Boolean | `users.any { it.isVip }` |
| `count { }` | 满足条件的个数 | `users.count { it.age > 18 }` |
| `sortedBy { }` | 排序 | `users.sortedBy { it.age }` |
| `groupBy { }` | 按条件分组，返回 Map | `users.groupBy { it.city }` |
| `sumOf { }` / `maxOfOrNull { }` | 求和/最大 | `users.sumOf { it.score }` |
| `forEach { }` | 遍历 | `users.forEach { println(it) }` |

Android 典型用法——接口实体转列表模型：

```kotlin
val titles = response.articles
    .filter { !it.draft }
    .map { it.title }
    .take(10)
```

### `it` 详解（以 filter 为例）

`filter { it % 2 == 0 }` 中，`filter` 对列表**每个元素**执行一次 Lambda，元素作为参数传入；返回 `true` 的留下，`false` 的丢弃：

| 元素（it 的值） | it % 2 == 0 | 结果 |
|---|---|---|
| 1 | false | 丢弃 |
| 2 | true | 保留 |
| 3 | false | 丢弃 |
| 4 | true | 保留 |
| 5 | false | 丢弃 |

**it 的使用时机**：一层时用 `it` 清爽；嵌套 Lambda 时内外 `it` 撞车，外层必须显式命名：

```kotlin
users.filter { it.age > 18 }                                   // ✅ 一层用 it
users.map { user -> user.orders.filter { it.isPaid } }         // ✅ 嵌套时外层命名
users.map { it.orders.filter { o -> it.age > 18 } }            // ❌ 两个 it 混乱
```

## 四、性能注意：asSequence()

`map`/`filter` 每次都创建新集合。数据量大（上万条）且多次链式操作时，用 `asSequence()` 换成惰性序列（相当于 Java Stream）：

```kotlin
numbers.asSequence().filter { ... }.map { ... }.toList()
```

日常 Android 列表数据量（几十几百条）直接用普通集合操作即可。

## 五、自己写一个高阶函数：理解 repeat 和回调

```kotlin
fun repeatN(n: Int, action: (Int) -> Unit) {
    for (i in 0 until n) {
        action(i)          // 把 0, 1, 2 ... n-1 依次传给传入的 Lambda
    }
}

fun main() {
    repeatN(3) { i ->
        println("第 $i 次执行")
    }
}
// 输出：第 0 次执行 / 第 1 次执行 / 第 2 次执行
```

理解要点：

- `repeatN` **不决定打印什么**，它只负责"调用 n 次别人传进来的函数"，把序号当参数喂进去。打印内容由调用时的 Lambda 说了算。
- `action` 只是一个"待调用的函数"，`repeatN` 不知道也不关心里面写了什么——这就是"高阶函数"的含义：**把另一个函数当参数收进来，在合适的时机调用它**。
- Kotlin 标准库的 `repeat(3) { println("hi") }` 内部几乎就是这样的实现。
- **回调的本质也一样**：`button.setOnClickListener { }` 收下你的 Lambda 但当下不执行，等用户真点了按钮，系统才调用它。与 `repeatN` 的区别只是调用时机：一个立刻循环调用，一个事件发生时调用。

### 高阶函数 + 默认参数 + 扩展函数合体

```kotlin
fun String?.showOrDefault(transform: (String) -> String = { it }): String {
    return transform(this ?: "默认值")
}

null.showOrDefault()                        // "默认值"
"hello".showOrDefault { it.uppercase() }    // "HELLO"
```

这个三件套就是 Kotlin 代码简洁的核心配方。

## 六、对照速查表

| Java | Kotlin |
|---|---|
| 匿名内部类回调（几十行） | `view.setOnClickListener { }` |
| `.stream().filter().collect()` | `list.filter { }.map { }` |
| `Collectors.groupingBy` | `list.groupBy { }` |
| `Function<T,R>` / `Predicate<T>` | `(T) -> R` / `(T) -> Boolean` |
| 手写 for 循环拼接字符串 | `joinToString()` |

## 七、本课练习及参考答案

```kotlin
data class Student(val name: String, val score: Int)

fun main() {
    val students = listOf(
        Student("小明", 85), Student("小红", 55), Student("小刚", 92),
        Student("小丽", 60), Student("小强", 40)
    )

    // 2. 筛出 60 分以上的名字
    val passed = students.filter { it.score >= 60 }.map { it.name }
    println(passed)   // [小明, 小刚, 小丽]

    // 3. 平均分
    println(students.sumOf { it.score } / students.size.toDouble())   // 66.4
    // 或 students.map { it.score }.average()

    // 4. 按及格与否分组
    println(students.groupBy { if (it.score >= 60) "及格" else "不及格" })
    // {及格=[小明, 小刚, 小丽], 不及格=[小红, 小强]}

    // 5. 高阶函数 repeatN（见第五节实现）
    repeatN(3) { i -> println("序号=$i") }
}

fun repeatN(n: Int, action: (Int) -> Unit) {
    for (i in 0 until n) action(i)
}
```

---

**下一课预告（第 5 课）：when 表达式、密封类与作用域函数** —— 替代 switch 的 `when`、状态建模神器密封类，以及 `let / apply / run / also / with` 三兄弟的选用口诀。
