# Kotlin 补充课：条件与循环

> 适用读者：已完成第 1～5 课，但 if/for/while 还没系统练过。
> 核心收获：if 表达式替代三目运算、`for + in` 的四种范围写法、`when` 两种形态不混淆、能用集合操作符就不写循环。

---

## 一、if / else：和 Java 几乎一样，但可以是表达式

```kotlin
val score = 85

// 语句用法：和 Java 一模一样
if (score >= 60) {
    println("及格")
} else {
    println("不及格")
}

// 表达式用法：if 有返回值
// （Kotlin 没有三目运算符 ?:，if 表达式就是它的替代品）
val level = if (score >= 90) "优秀" else "一般"

// 多分支：每个分支最后一个表达式的值就是返回值
val desc = if (score >= 90) {
    "优秀"
} else if (score >= 60) {
    "及格"
} else {
    "不及格"
}
```

Java 对照：`int level = score >= 90 ? "优秀" : "一般";` → `val level = if (...) "优秀" else "一般"`。

## 二、for 循环：只有一种形态，配合范围（Range）

Kotlin **没有** `for (int i = 0; i < 10; i++)` 三段式，全部用 `for + in`：

```kotlin
for (i in 0..9) { }            // 0 到 9，含头含尾
for (i in 0 until 10) { }      // 0 到 9，不含 10（最常用，相当于 i < 10）
for (i in 10 downTo 1) { }     // 倒序 10, 9, ... 1
for (i in 0..20 step 2) { }    // 步长 2：0, 2, 4 ... 20
```

遍历集合与带下标：

```kotlin
val list = listOf("a", "b", "c")

for (item in list) { println(item) }   // 依次取出每个元素，相当于 Java 的 for (T x : list)

for (i in list.indices) { println("$i: ${list[i]}") }
for ((index, item) in list.withIndex()) { println("$index: $item") }   // 解构，下标和元素一起拿
```

范围速查表：

| 写法 | 含义 | Java 等价 |
|---|---|---|
| `0..9` | 0 到 9（含 9） | `i <= 9` |
| `0 until 10` | 0 到 9（不含 10） | `i < 10` ✅ 最常用 |
| `10 downTo 1` | 倒序 | `i--` |
| `0..20 step 2` | 步长 2 | `i += 2` |

细节验证：`3..100 step 3` 最后一个打印 **99**（下一个 102 超出 100），含头含尾的边界要自己心里过一遍。

## 三、while / do-while：和 Java 完全一样

```kotlin
var i = 0
while (i < 5) {
    println(i)
    i++
}

do {
    println("至少执行一次")
} while (i < 0)
```

## 四、break / continue：一样，但可以打标签

```kotlin
for (i in 1..3) {
    if (i == 2) continue   // 跳过本次，立刻进下一轮
    if (i == 4) break      // 跳出整个循环
    println(i)
}

// 嵌套循环想直接跳出外层？打标签（知道即可，很少用）
outer@ for (i in 1..3) {
    for (j in 1..3) {
        if (j == 2) break@outer
    }
}
```

## 五、能不写循环就不写：集合操作符优先 ⭐

学了第 4 课后，大部分循环都有现成的一行版：

| 循环在干的事 | 替代写法 |
|---|---|
| 累加求和 | `numbers.sum()` |
| 找第一个满足条件的 | `nums.find { it > 50 }`（找不到返回 null） |
| 筛选 | `nums.filter { ... }` |
| 逐个变换 | `nums.map { ... }` |
| 拼接字符串 | `nums.joinToString()` |

判断标准：**"对每个元素做转换/筛选/统计"用集合操作符；只关心"执行 N 次"或需要中途 break 才写 for。**

`for + if + break` 手写"找第一个大于 50 的数"，就是 `find { }` 内部的实现原理：

```kotlin
val nums = listOf(3, 88, 20, 90)

var found = 0
for (n in nums) {
    if (n > 50) {
        found = n
        break          // 找到就停，不浪费后续遍历
    }
}
println(found)          // 88

nums.find { it > 50 }   // 88，一行等价
```

**常见错误**：循环体里直接 `found = n` 不加条件也不 break——循环跑完后 `found` 是**最后一个元素**，不是"第一个满足条件的"。

## 六、`when` 两种形态（本课练习实测混淆点）⭐

```kotlin
when (i) {                  // 形态一：带判断对象 → 分支写"候选值"，和 i 比较
    1 -> println("一")
    in 2..5 -> println("二到五")
    else -> println("其他")
}

when {                      // 形态二：不带对象 → 分支写任意布尔表达式，谁先 true 走谁
    i % 3 == 0 && i % 5 == 0 -> println("FizzBuzz")
    i % 3 == 0 -> println("Fizz")
    else -> println(i)
}
```

口诀：**有对象，分支写值；没对象，分支写条件。** 两种不能混——带对象时分支里写 `if(...)` 或条件表达式都是编译错误。

分支顺序原则：**越特殊的条件越靠前**（如 FizzBuzz 的"同时被 3 和 5 整除"必须放最前，否则 15 会先被 `i % 3 == 0` 抢走）。

其他易错点：

- **字符串必须双引号**。单引号是字符 `Char`，只能装一个字符（`'a'` ✅，`'Buzz'` ❌）。

## 七、本课练习及参考答案（Playground）

```kotlin
// 1. 打印 1~100 中所有 3 的倍数（两种写法）
for (i in 3..100 step 3) { println(i) }        // step 版
for (i in 1..100) {                            // continue 版
    if (i % 3 != 0) continue
    println(i)
}

// 2. FizzBuzz：when 无对象形态 + 特殊条件在前
fun fizzBuzz(n: Int) {
    for (i in 1..n) {
        when {
            i % 3 == 0 && i % 5 == 0 -> println("FizzBuzz")
            i % 3 == 0 -> println("Fizz")
            i % 5 == 0 -> println("Buzz")
            else -> println(i)
        }
    }
}

// 3. while 算 5!（先自增再乘，避开多乘/少乘的坑）
var i = 1
var result = 1
while (i < 5) {
    i++
    result = i * result
}
println(result)   // 120
// for 版更短：var result = 1; for (i in 2..5) { result *= i }

// 4. 找第一个大于 50 的数（见第五节：for+if+break 与 find 等价）
```

---

**下一课预告（第 6 课）：泛型与型变入门** —— `List<out T>` 的 out/in、为什么 `List<String>` 能当 `List<Any>` 用，看懂 Android 源码里的型变声明。
