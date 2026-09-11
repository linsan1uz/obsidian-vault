---
lark_doc_url: https://longcheer.feishu.cn/docx/HA26dwRtro28YAxR56CcKjCQnrb
---
# Kotlin 第 1 课：变量、函数与 Null 安全

> 适用读者：有 Java 基础、目标 Android 开发。
> 在线练习工具：[Kotlin Playground](https://play.kotlinlang.org)（浏览器直接跑 Kotlin，零安装）

---

## 一、变量：`val` / `var`，类型自动推断

```kotlin
val name = "Android"       // 不可变，相当于 final String
var age = 25               // 可变
val list: List<Int> = listOf(1, 2, 3)   // 需要时可以显式标注类型
```

- **`val`** = 不可变（只能赋值一次），对应 Java 的 `final`。
- **`var`** = 可变（可以重新赋值）。
- 规则：**默认写 `val`**，只有确实需要重新赋值时才用 `var`。
- Kotlin 没有 Java "基本类型 vs 包装类型" 的分裂（`int` vs `Integer`），`Int` 永远不会出现自动装箱的坑。

## 二、函数：默认参数 + 命名参数

```kotlin
// Java 里要写一堆重载，Kotlin 一个函数搞定
fun toast(msg: String, duration: Int = 1000) {
    println("显示 $msg，时长 $duration")
}

toast("Hello")                    // 用默认值
toast("Hello", duration = 1000)   // 命名参数，可读性极好
```

- 函数声明：`fun 函数名(参数): 返回类型 { ... }`
- **默认参数**替代 Java 的大量重载方法。
- **字符串模板**：`$变量`，复杂表达式用 `"${表达式}"`，替代 `+` 拼接：

```kotlin
println("hello, $name, $age")
println("明年 ${age + 1} 岁")
```

- 语句末尾**不需要分号**（写了也不报错）。唯一需要分号的场景：两条语句写在同一行，如 `val a = 1; val b = 2`。

## 三、Null 安全：Kotlin 最核心的设计

Kotlin 把 null 检查从"运行时崩溃"提前到了"编译期错误"，直接消灭 Android 崩溃榜第一的 `NullPointerException`。

### 1. 类型分可空与不可空

```kotlin
var title: String = "abc"
title = null              // ❌ 编译不过，String 不可能为 null

var subtitle: String? = null   // 加 ? 才是可空类型
subtitle.length           // ❌ 编译不过，必须处理 null
```

- `String` = 永远不为 null
- `String?` = 可能为 null
- 声明为可空后，编译器**强制你处理 null** 才能使用。

### 2. 处理 null 的三板斧

```kotlin
val len1 = subtitle?.length          // 安全调用：null 就返回 null，不抛 NPE
val len2 = subtitle?.length ?: 0     // Elvis：为 null 时给默认值 0
val len3 = subtitle!!.length         // 非空断言：赌它非空，是 null 就当场崩溃
```

**两行对比（重点理解）：**

```kotlin
val len2 = subtitle?.length ?: 0
// subtitle = "hello" → 5
// subtitle = null    → 0（兜底，永不崩溃）
// 等价于 Java：int len2 = (subtitle != null) ? subtitle.length() : 0;

val len3 = subtitle!!.length
// subtitle = "hello" → 5，正常运行
// subtitle = null    → 💥 运行时抛 NullPointerException
// 等价于 Java 直接写 subtitle.length()，把 Kotlin 的保护亲手拆掉
```

### 3. 实战优先级

```kotlin
// 1️⃣ 最优先：?. 和 ?:，一行搞定
view?.visibility = View.GONE
val len = name?.length ?: 0

// 2️⃣ 多步操作：if 判空 + 编译器智能推断（smart cast）
if (name != null) {
    println(name.length)   // 刚判过非空，这里直接用
}

// 3️⃣ 最后手段：!!（能不写就不写，通常意味着在埋崩溃）
val len = name!!.length
```



---

## 四、和 Java 的心智对照（后续课程展开）

| Java 痛点 | Kotlin 方案 | 所属课程 |
|---|---|---|
| POJO 写一堆 getter/setter | `data class` 一行 | 第 2 课 |
| static 方法 / 单例 | `object` / `companion object` | 第 2 课 |
| 工具类 Utils | 扩展函数 | 第 3 课 |
| 匿名内部类回调 | Lambda + 高阶函数 | 第 4 课 |
| Stream API 繁琐 | `filter/map` 直接建在集合上 | 第 4 课 |
| switch 不强大 | `when` 表达式 + 密封类 | 第 5 课 |
| 回调地狱 | 协程 | 第 8 课 |

## 五、本课练习

1. 写一个 `greet(name: String, greeting: String = "你好")` 函数，分别用默认值和命名参数调用它。
2. 声明一个可空变量，分别用 `?.`、`?:`、`!!` 三种方式访问，观察编译器和运行结果的区别。

## 六、完整示例代码

```kotlin
fun main() {
    val name = "fanqifu"      // val：不可变
    var age = 25              // var：可变
    age = 28                  // ✅ var 可以重新赋值

    println("hello, $name, $age")   // 字符串模板
    toast("fanqifu", 100)
}

fun toast(msg: String, duration: Int = 1000) {
    println("显示 $msg，时长 $duration")
}
```
