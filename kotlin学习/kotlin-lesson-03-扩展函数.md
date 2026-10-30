---
lark_doc_url: https://longcheer.feishu.cn/docx/CUf0dRIjGod2IRxL5Pucxhuunrh
---
# Kotlin 第 3 课：扩展函数（Extension Functions）

> 适用读者：已完成第 1、2 课（null 安全、data class）。
> 核心收获：给任何类（包括系统类）直接"添加"方法，告别 `XxxUtils` 工具类。

---

## 一、解决什么问题？

Java 里想给系统类加方法，只能写工具类：

```java
// Java：Utils 之路
public class ViewUtils {
    public static void hide(View view) {
        view.setVisibility(View.GONE);
    }
}
// 调用时要带上类名，可读性差
ViewUtils.hide(myView);
```

Kotlin 扩展函数允许**直接给任何类"添加"方法**，包括没有源码、不能继承的系统类：

```kotlin
fun View.hide() {
    visibility = View.GONE
}

myView.hide()   // 像 View 原生就有这个方法
```

## 二、语法拆解

```kotlin
fun View.hide() { ... }
//  ↑
// 类型名.方法名：给 View 这个类加一个 hide 方法
```

- `View.` 叫**接收者（receiver）**，函数体内 `this` 指代调用者，可省略：

```kotlin
fun View.hide() {
    this.visibility = View.GONE   // this 可省略，直接写 visibility = View.GONE
}
```

- 扩展函数定义在**文件顶层**（不在 class 里），import 后全局可用。
- 底层原理：编译后就是普通静态函数 `ViewKt.hide(myView)`，**不是真的把方法塞进类里**。所以只能访问目标类的公开成员，不破坏封装。

## 三、带参数和返回值

和普通函数完全一样：

```kotlin
fun View.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

button.translationY = button.dp(8)   // "8dp" 转像素
```

## 四、可空接收者

接收者类型可以带 `?`，表示"连 null 都能调用"，函数体里用 `this?.` 处理：

```kotlin
fun String?.safeLength(): Int = this?.length ?: 0

"abc".safeLength()    // 3
null.safeLength()     // 0，合法且不崩溃
```

知识点自洽：接收者写成 `String?` 后，函数体内 `this` 就是 `String?` 类型，编译器强制用 `?.` 访问。标准库的 `orEmpty()`（`fun String?.orEmpty(): String = this ?: ""`）就是同款写法。

## 五、Android 日常实战

```kotlin
// View 显隐：Android 最高频操作，语义化极强
fun View.visible() { visibility = View.VISIBLE }
fun View.gone() { visibility = View.GONE }
fun View.isVisible(): Boolean = visibility == View.VISIBLE

loadingView.gone()
contentView.visible()

// Context 弹 Toast，告别 makeText(...).show()
fun Context.toast(msg: String, duration: Int = Toast.LENGTH_SHORT) {
    Toast.makeText(this, msg, duration).show()
}
// activity 里直接：toast("保存成功")

// String / 数值工具，甚至能写出接近自然语言的效果
fun String.toDate(): Date = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).parse(this)!!
fun Int.times(action: () -> Unit) { repeat(this) { action() } }
3.times { println("hi") }
```

标准库的 `let`、`apply`、`also` 本质上都是扩展函数（第 5 课作用域函数的基础）。

## 六、两条重要规则（高频考点）

**① 扩展按"声明类型"静态解析，没有多态。**

```kotlin
open class Animal
class Dog : Animal()

fun Animal.name() = "动物"
fun Dog.name() = "狗"

val d: Dog = Dog()
d.name()                  // "狗"，Dog 的扩展更具体，优先

val a: Animal = Dog()     // 变量声明类型是 Animal
a.name()                  // "动物"！编译期按声明类型解析，不看实际对象
```

原因：扩展函数编译后是静态方法调用，编译期就定死，运行时不多态分派。**对比成员函数：成员是动态分派（看实际对象），扩展是静态解析（看声明类型）。**

同款推论：扩展函数不能 `open`、不能被重写——它根本不参与多态体系。

**② 成员函数永远优先。** 类自身有 `foo()` 时，同名扩展 `foo()` 不会被调用——扩展只是"外面的备胎"。

## 七、扩展属性（顺带）

没有 backing field，只能靠 getter 计算：

```kotlin
val Context.appVersion: String
    get() = packageManager.getPackageInfo(packageName, 0).versionName

context.appVersion   // 用起来像属性
```

## 八、对照速查表

| Java | Kotlin |
|---|---|
| `ViewUtils.hide(view)` | `view.hide()` |
| `StringUtils.isEmpty(s)` | `s.isNullOrEmpty()` |
| Utils 类 + static 方法 | 顶层扩展函数 |
| 手写单位转换工具 | `fun View.dp(v: Int): Int` |

## 九、函数体两种写法（易错点）

合法写法二选一，**不能混搭**：

```kotlin
// 写法一：表达式函数体，用 =，右边是不带 return 的表达式
fun String.shout(): String = uppercase() + "!"

// 写法二：块函数体，用 {}，返回靠 return
fun String.shout(): String {
    return uppercase() + "!"
}

// ❌ 错误混搭：= 后面跟了带 return 的块，会被解析成 Lambda，
//    类型是 () -> String 而不是 String，编译报类型不匹配
// fun String.shout(): String = { return uppercase() + "!" }
```

补充：**表达式函数体（`=`）可省略返回类型**（编译器从右边推）；**块函数体带 return 时必须显式写返回类型**（返回 `Unit` 的除外）。

另外注意：扩展的"对象"写在类型位置，**不能写进参数括号**——`fun String.shout(s: String)` 不是扩展 String，而是"String 上带一个额外参数的方法"。

## 十、本课练习及参考答案

```kotlin
// 1. 给 String 加 shout()，返回全大写加感叹号
fun String.shout(): String = uppercase() + "!"
// "hello".shout() → "HELLO!"

// 2. 给 Int 加 isEven() 判断偶数
fun Int.isEven(): Boolean = this % 2 == 0

// 3. 可空接收者，null 返回 0
fun String?.safeLength(): Int = this?.length ?: 0

// 4. 思考题：
fun Any.describe() = "任意对象"
fun String.describe() = "字符串"
val x: Any = "hi"
x.describe()   // 输出 "任意对象"！
// 规则①：按声明类型 Any 静态解析，运行时不多态。
// 若是成员函数则会输出 "字符串"（动态分派）——这就是扩展与成员的本质区别。
```

## 十一、字符串创建与模板补充（第 1 课延伸）

```kotlin
val s = "hello"                       // 首选：字面量 + 类型推断
val greeting = "你好, $name"           // 模板取值：$变量名
val info = "明年 ${age + 1} 岁"        // 表达式 / 成员链 / 函数调用必须 ${}
val line = listOf("a","b","c").joinToString()   // "a, b, c"，替代循环拼接
val regex = """\d{3}-\d{4}"""         // 三引号原始字符串，写正则不用转义
```

- 模板是**创建字符串那一刻取值**，之后变量再改，老字符串不变。
- 只写 `$变量名` 可以省大括号；变量后跟着 `.`、`[`、运算符就必须 `${}` 包起来。
- 输出 `$` 本身：`${'$'}`
- Kotlin 里 `"a" == "b"` 比较内容（相当于 Java 的 `equals`）；比引用用 `===`。

---


---

## 答疑补充：扩展函数写在哪里？

一般写在**顶层**，也就是直接写在 `.kt` 文件里、不放进任何类，常见做法是单独建一个文件，比如 `ViewExt.kt`：

```kotlin
// 文件：ViewExt.kt
package com.example.util

import android.view.View

fun View.gone() {
    this.visibility = View.GONE   // this 就是调用它的那个 View
}

fun String.isPhone(): Boolean = length == 11 && all { it.isDigit() }
```

使用时像调用自带方法一样：

```kotlin
import com.example.util.gone
import com.example.util.isPhone

button.gone()
"13800138000".isPhone()   // true
```

- 在别的包里用要 `import` 这个函数，同一个包里不用。
- 扩展函数也能写在类里面，但那样只能在这个类内部用，所以平时基本都写在顶层。

---

## 答疑补充：扩展函数怎么用？

一句话：**给已有类型“外挂”一个方法**，调用时看起来像成员函数，但编译后其实是静态工具函数。

### 1. 怎么写、怎么调

```kotlin
// 语法：fun 接收者类型.函数名(...)
fun View.show() {
    visibility = View.VISIBLE   // 函数体内 this = 调用它的那个 View，可省略
}

fun Context.toast(msg: String, duration: Int = Toast.LENGTH_SHORT) {
    Toast.makeText(this, msg, duration).show()
}

// 调用点：像自带方法一样
button.show()
context.toast("保存成功")
```

- 接收者写在 **类型位置**（`View.`），不要写进参数括号。
- 函数体里的 `this` 就是左边那个对象。

### 2. 可空接收者

```kotlin
fun String?.safeLength(): Int = this?.length ?: 0

"hi".safeLength()   // 2
null.safeLength()   // 0，不崩
```

接收者写成 `String?` 后，连 `null` 也能点出来调用。

### 3. 扩展属性（也能“加字段感”，但没有背后存储）

```kotlin
val View.isVisible: Boolean
    get() = visibility == View.VISIBLE

if (button.isVisible) { /* ... */ }
```

只有 getter/setter 逻辑，**不会真的在类里多出一块内存字段**。

### 4. 三条铁律

1. **盖不过真成员**：类里已有同名成员方法时，永远走成员，扩展被晾在一边。
2. **按静态类型解析**：不多态。`val x: Any = "hi"` 时，`x` 上的扩展按 `Any` 找，不会按运行时 `String` 找。
3. **跨包要 import**：扩展写在顶层文件（如 `ViewExt.kt`），别的包用前 `import com.xxx.show`。

### 5. Android 常见例子

| 写法 | 用途 |
|---|---|
| `fun View.show()/gone()/invisible()` | 控制可见性 |
| `fun Context.toast(msg)` | 快速 Toast |
| `fun Int.dp(context): Int` | dp → px |
| `fun String?.orEmpty()`（标准库） | null 当空串 |

口诀：**像成员一样用，像工具函数一样定义；能调用公开 API，改不了类的内部实现。**
