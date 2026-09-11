# Kotlin 第 6 课：面向对象进阶——继承、abstract/interface、构造与可见性

> 适用读者：已完成第 2、5 课（类、密封类）。
> 核心收获：理解 Kotlin"默认 final"的双层设计、接口默认方法、自定义 View 必备的构造函数知识、`internal` 修饰符，理清 `final < sealed < abstract < open` 继承开放度阶梯。

---

## 一、继承：Kotlin 默认"封死"，显式 `open` 才能继承 ⭐

Java 和 Kotlin 方向完全相反：

```java
// Java：默认可继承，想禁止才写 final
public class Animal { }
public class Dog extends Animal { }
```

```kotlin
// Kotlin：默认一切不可继承（相当于所有类偷偷带了 final）
class Animal { }
class Dog : Animal() { }        // ❌ 编译报错：This type is final

open class Animal               // 加 open 才允许被继承
class Dog : Animal() { }        // ✅ 继承写冒号 + 括号，没有 extends
```

**成员同理——"双层 final"**：类默认不能被继承，成员方法默认不能被重写，**两层要分别 open**：

```kotlin
open class Animal {
    open fun name() = "动物"     // open 方法才能被重写
    fun eat() = "吃饭"           // 没 open = final，子类不能重写
}

class Dog : Animal() {
    override fun name() = "狗"   // 重写必须写 override（Java 的 @Override 可选，这里强制）
}
```

自查口诀：**继承要过两道门——类的门和方法门，每道门单独递 `open` 门票**。编译器报错也分得清：

- `This type is final, so it cannot be inherited from` → 类没 open
- `'eat' in 'Animal' is final and cannot be overridden` → 方法没 open

为什么这么设计？防**脆弱基类**：库作者没打算被继承的类被强行继承重写，库一升级子类悄悄炸掉。Kotlin 把默认值定成"禁止"，要开必须明说。`override` 的成员**天生 open**，想封住写 `final override fun`。

小语法点：`class Dog : Animal()` 冒号后的**括号是调父类构造函数**；接口没有构造函数，实现接口不带括号。

## 二、abstract 与 interface

```kotlin
abstract class Vehicle(val wheels: Int) {      // 抽象类：不能实例化，可以有构造函数和状态
    abstract fun drive()                        // 抽象方法：没方法体，子类必须实现
    fun horn() = "按喇叭"                       // 普通方法照常
}

interface Refuelable {
    val fuelType: String                        // 抽象属性：只有声明，没值
    fun refuel() = "加 $fuelType"               // ⭐ 接口方法可带默认实现（不用 default 关键字）
}

class Car : Vehicle(4), Refuelable {            // 单继承类 + 多实现接口，逗号隔开
    override val fuelType = "汽油"
    override fun drive() = "开车"
    // refuel() 不写也行——白嫖接口默认实现
}
```

要点：

- **抽象成员不用 `open`**——abstract 天生含"等着被重写"之意。有抽象成员的类必须标 `abstract`。
- **抽象属性**和抽象方法同一套规则：`abstract val area: Double` 只有声明没值，子类 `override val area = ...` 提供。
- 接口方法能带方法体（Java 8 default 方法的对应物），是"免费的赠品"——子类不实现也能直接调。
- 一个类**只能继承一个类，可实现多个接口**。
- 选择标准照搬 Java：有状态/构造逻辑/部分实现 → 抽象类；纯能力契约 → 接口。

## 三、构造函数与初始化

**主构造函数 = 长在类名上的构造函数**，和 Java 构造函数是一回事，只是写法融进类声明：

```kotlin
class Person(val name: String) {           // 主构造函数
    init { println("创建了 $name") }        // 初始化块：主构造的"身体"

    var age: Int = 0

    constructor(name: String, age: Int) : this(name) {  // 从构造：必须委托给主构造
        this.age = age                                    // : this(name) ≈ Java 的 this(...)
    }
}
```

等价于 Java 的 `Person(String name)` 构造函数 + 字段 + getter 全套。细节：

- 括号里参数**加 `val`/`var` 才升级为属性**（生成字段+getter）；不加只是普通构造参数，构造完即失效。
- **属性初始化器和 init 块是主构造函数体的延伸**，按代码出现顺序从上到下执行；所以 init 里能用主构造参数 `name`。
- 从构造必须委托主构造（保证主构造逻辑先跑），Java 没这个强制。

**`init` ≠ Java 静态块**（高频混淆）：

| | 执行时机 | 执行次数 |
|---|---|---|
| Java `static { }` | 类加载时 | 整个类一辈子 1 次 |
| Kotlin `init { }` | 每次构造对象时 | 创建几个执行几次 |
| Java 不带 static 的 `{ }` | 每次构造对象时 | 才是 init 的对应物 |

类级别"只跑一次"的活儿归 `companion object`。口诀：**init = 每个对象一次（构造函数的身体）；companion object = 类一次（static 的替身）**。

**Android 实战——自定义 View**：

```kotlin
// 写法一：多个从构造函数（XML 布局需要三参版）
class MyView : View {
    constructor(context: Context) : super(context)
    constructor(context: Context, attrs: AttributeSet?) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet?, style: Int) : super(context, attrs, style)
}

// 写法二：@JvmOverloads 一个搞定（推荐）
class MyView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    style: Int = 0
) : View(context, attrs, style)
```

## 四、可见性修饰符

| Kotlin | 可见范围 | Java 对应 |
|---|---|---|
| `public`（**默认**） | 处处可见 | public |
| `private` | 本类内 | private |
| `protected` | 本类 + 子类 | protected（不能修饰顶层声明） |
| `internal` | **同一模块内** | ⭐ Java 没有 |
| （无此概念） | —— | package-private（Kotlin 没有） |

- 默认就是 public，所以 Kotlin 代码大量函数不写修饰符。
- **`internal` 是 Kotlin 特色**：模块级真隔离，业务 module 内部工具函数标它，其他模块调不到；Java 的 package-private 能被乱设包名绕过，internal 不能。

## 五、继承开放度完整阶梯（本课收官考点）⭐

```
final（默认，什么都不写） < sealed < abstract < open
```

| 关键字 | 谁能继承 | 能直接实例化 | 一句话定位 |
|---|---|---|---|
| 什么都不写 | 谁都不能 | ✅ | 默认 final，防脆弱基类 |
| `sealed` | **只有同文件的类** | ❌ | 锁死子类名单，换 `when` 穷尽验算（第 5 课） |
| `abstract` | 任何人 | ❌ 不能 new | 生来当爹：必须被继承，留抽象成员等子类实现 |
| `open` | 任何人 | ✅ | 最普通的"我允许被继承"，其他照旧 |

三档回答的是同一问题——"我的子类谁来做、做到什么程度"：sealed 控制**谁**，abstract 控制**必须做什么**，open 控制**可改什么**。

注意 sealed **不是**"不能继承"——它允许继承，只是把继承权锁在同一个文件里；"不能继承"的是不加关键字的普通类。

## 六、`by lazy` 预告

第 2 课的 `val api by lazy { createApiService() }` 属于**属性委托**（惰性初始化 + 线程安全自动加锁）。`by` 委托是下下课主题。

## 七、对照速查表

| Java | Kotlin |
|---|---|
| `class Animal` 默认可继承 | 必须 `open class Animal` |
| `@Override` 可选注解 | `override` 强制关键字 |
| `final` 方法防重写 | 默认就是 final，要重写先 `open` |
| `interface` + `default` 方法 | 接口方法直接写方法体 |
| `extends X implements Y` | `: X(), Y`（类带括号，接口不带） |
| 多个构造函数重载 | 主构造 + `constructor` 从构造（或 `@JvmOverloads`） |
| `static { }` 类加载执行一次 | `companion object`（`init` 是每个对象一次） |
| package-private | `internal`（模块级） |

## 八、本课练习及参考答案

```kotlin
// 1. 抽象类 + 抽象属性（radius 属于 Circle 不属于 Shape——基类只放公共交集）
abstract class Shape {
    abstract val area: Double
    fun describe() = "面积是$area"
}
class Circle(val radius: Double) : Shape() {
    override val area = 3.14 * radius * radius
}
class Square(val side: Double) : Shape() {
    override val area = side * side
}
// Circle(2.0).describe() → 面积是12.56；Square(3.0).describe() → 面积是9.0

// 2. 双层 final：错两处——Animal 类没 open，eat 方法也没 open
open class Animal {
    open fun eat() {}
}
class Dog : Animal() {
    override fun eat() {}
}

// 3. 接口默认实现：只实现 click()，show() 白嫖
interface Clickable {
    fun click()
    fun show() = "我被点击了"       // 函数声明必须有 ()！
}
class Square2(val side: Double) : Shape(), Clickable {
    override val area = side * side
    override fun click() {
        println(show())              // 调用要加 ()——show 是函数值，show() 才是调用
    }
}

// 4. 开放度排序：final < sealed < abstract < open（见第五节）
```

---

**下一课预告（第 7 课）：泛型与型变入门** —— `out/in`、为什么 `List<String>` 能当 `List<Any>` 用、`reified`，看懂 Android 源码里的型变声明。
