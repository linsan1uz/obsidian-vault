---
lark_doc_url: https://longcheer.feishu.cn/docx/OikOdt7h1oUrAix0pw2cdANenUv
---
# Kotlin 第 2 课：类、data class 与 object

> 适用读者：已完成第 1 课（变量、函数、null 安全）。
> 核心收获：用 1 行 Kotlin 替代几十行 Java 样板代码。

---

## 一、类的基本写法：主构造函数直接写在类名上

```java
// Java：一个"人"类
public class Person {
    private final String name;
    private int age;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
    }
    public String getName() { return name; }
    public int getAge() { return age; }
    public void setAge(int age) { this.age = age; }
}
```

```kotlin
// Kotlin：同样的事，一行
class Person(val name: String, var age: Int)

val p = Person("fanqifu", 25)   // 没有 new 关键字
p.age = 28                      // 看起来像直接访问字段
```

要点：

- 括号里的就是**主构造函数**参数；加 `val`/`var` 的参数自动成为属性（字段 + getter/setter 一并生成）。
- **不需要手写 getter/setter**。`p.age = 28` 实际调用自动生成的 setter；Java 代码调 Kotlin 时看到的才是 `getAge()` / `setAge()`。
- **没有 `new`**，创建对象直接 `Person(...)`。

## 二、data class：一行干掉整个 POJO

Android 里大量类是纯数据载体：接口返回的 JSON 实体、列表条目模型。`data` 关键字自动生成 getter/setter、`equals()`、`hashCode()`、`toString()`、`copy()` 等：

```kotlin
data class User(
    val id: Long,
    val name: String,
    val avatarUrl: String?
)
```

免费获得的能力：

```kotlin
val u1 = User(1, "fanqifu", null)
val u2 = User(1, "fanqifu", null)

u1 == u2            // true！按"内容"比较（Java 默认比较引用，结果是 false）
println(u1)         // User(id=1, name=fanqifu, avatarUrl=null)，toString 自动生成

// copy：改任意字段生成新对象，其余照抄
val adult = u1.copy(name = "老樊")
// User(id=1, name=老樊, avatarUrl=null)
```

### Android 常用点

**① `copy` + 不可变对象**：Compose 和 UI 状态管理中不直接改字段，而是 `copy` 出新对象交给界面刷新。所有属性是 `val`，对象创建后不可变，天然线程安全。

**② 解构声明**：按位置把属性拆出来。

```kotlin
val (id, name, avatar) = u1
println(name)   // fanqifu
```

**规则：纯数据模型一律用 `data class`。** Android 里的 `User`、`Article`、`UiState` 等实体类几乎全是 data class。

## 三、object：单例也是一个关键字

Java 单例要手写 `getInstance()` 双重检查锁或用枚举；Kotlin 一个 `object` 搞定：

```kotlin
object RetrofitClient {
    val api: ApiService by lazy {
        createApiService()   // 初始化代码，只会执行一次
    }
}

// 直接用，不需要 getInstance()
RetrofitClient.api.getUser(1)
```

- 全局**只有一个实例**，第一次被访问时才初始化，线程安全由 JVM 保证。
- 适合放：网络客户端、数据库、日志工具、SharedPreferences 封装等全局唯一的东西。
- Java 互调时写作 `RetrofitClient.INSTANCE.api`。

## 四、companion object：替代 static

Java 的 `static` 方法/常量，Kotlin 用"伴生对象"承接（写在类内部的 object）：

```kotlin
class Article private constructor(val title: String) {
    companion object {
        const val MAX_TITLE = 50          // 相当于 static final 常量

        fun create(title: String): Article {   // 相当于 static 工厂方法
            require(title.length <= MAX_TITLE) { "标题太长" }
            return Article(title)
        }
    }
}

// 调用方式看起来和 Java static 一模一样
Article.MAX_TITLE
Article.create("Kotlin 入门")
```

- `const val` = 编译期常量（对应 `static final`，只能是基本类型和 String）。
- 初始化逻辑复杂的常量，用普通 `val` 放在 companion object 里。

## 五、对照速查表

| Java | Kotlin |
|---|---|
| POJO + getter/setter/equals/hashCode/toString | `data class User(val id: Long)` |
| `new Person("a", 1)` | `Person("a", 1)` |
| 单例 + getInstance() 双重检查锁 | `object Xxx { ... }` |
| `static` 方法 / 常量 | `companion object` + `const val` |
| 不可变实体手动防御 | 所有属性 `val` + `copy()` |

## 六、本课练习（Playground）

```kotlin
// 1. data class：内容相等比较 + toString
data class Student(val name: String, var score: Int)

fun main() {
    val s1 = Student("小明", 90)
    val s2 = Student("小明", 90)
    println(s1 == s2)   // true
    println(s1)         // Student(name=小明, score=90)

    // 2. copy：原对象不变，生成新对象
    val s3 = s1.copy(score = 100)
    println(s1)   // score 还是 90
    println(s3)   // score 变成 100

    // 3. object 单例验证
    Counter.increment()
    Counter.increment()
    Counter.increment()
    println(Counter.count)   // 3，证明全局只有一份
}

object Counter {
    var count = 0
    fun increment() { count++ }
}
```

---


---

## 答疑补充：有主构造 vs 无主构造

- **有主构造**：参数前加 `val`/`var` 就直接成为属性，构造方法也一并生成，不用自己写字段和构造方法。
  ```kotlin
  class User(val name: String, var age: Int)
  ```
- 不加 `val`/`var` 的参数（`class User(name: String)`）只是构造参数，只能在 `init` 或属性初始化里用，不会变成属性。
- **无主构造**：类名后不带括号，属性要自己在类体里声明，再用 `constructor` 写次构造（像 Java）：
  ```kotlin
  class User {
      val name: String
      var age: Int
      constructor(name: String, age: Int) {
          this.name = name
          this.age = age
      }
  }
  ```
- 一般只在需要多种构造方式时才这样写，比如继承 Android 的 `View`。平时优先用主构造。

### `@JvmOverloads`

Kotlin 的默认参数在 Java 里不会自动生成重载。加上 `@JvmOverloads` 后，编译器会按默认参数从右往左生成一串 Java 能用的重载方法：

```kotlin
@JvmOverloads
fun toast(msg: String, duration: Int = Toast.LENGTH_SHORT) { ... }
```

Java 里就能写 `toast("hi")` 和 `toast("hi", Toast.LENGTH_LONG)`。纯 Kotlin 项目一般用不到，混编、写库或自定义 View（构造函数）时才需要。

---

## 答疑补充：private constructor 是什么意思？

> Jerry 提问：下面这种写法里的 `private constructor` 是什么意思？

```kotlin
class Article private constructor(val title: String) {
    companion object {
        const val MAX_TITLE = 50          // 相当于 static final 常量

        fun create(title: String): Article {   // 相当于 static 工厂方法
            require(title.length <= MAX_TITLE) { "标题太长" }
            return Article(title)
        }
    }
}
```

### 一句话

**`private constructor` = 主构造函数是私有的**：类外面**不能**直接写 `Article("xxx")` 来 new；只有类自己内部（含 **companion object**）能调用这个构造。

### 拆开看语法

```kotlin
class Article private constructor(val title: String)
//           ↑        ↑
//        可见性    主构造函数
```

- 默认不写时，主构造是 public，外面随便 `Article("hi")`。
- 写成 `private constructor` 后，外部编译会报：构造函数不可见。
- **`private` 修饰的是构造，不是整个类。** 类本身仍是 public，外面可以声明 `Article` 类型、接收 `create` 的返回值，只是不能自己 new。

对比：

| 写法 | 含义 |
|---|---|
| `class Article(...)` | 类公开，构造也公开 |
| `class Article private constructor(...)` | 类公开，**只能内部/伴生构造** |
| `private class Article(...)` | **类本身**对外不可见（另一回事） |

### 为什么要和 companion 一起用？

伴生对象（第 2 课的 `object` / `companion object`）活在类内部，**可以调用私有构造**：

```kotlin
Article.create("Kotlin")     // ✅ 走工厂，先校验再构造
// Article("Kotlin")         // ❌ 外部禁止，逼你走 create
```

这就是常见的**工厂模式**：

1. 创建前统一校验（`require`、默认值、规范化字符串…）。
2. 以后若改成缓存、单例、子类型，调用方仍只认 `Article.create(...)`，构造细节可藏起来。

`MAX_TITLE` 放 companion 里，相当于 Java 的 `static final`；`create` 相当于 static 工厂方法。

### 小练习理解

```kotlin
fun main() {
    val a = Article.create("短标题")     // OK
    // val b = Article("短标题")         // 编译错误
    println(Article.MAX_TITLE)           // 50，常量仍可从外面读
}
```

### 收束

**`private constructor`：外面别直接 new，请走我提供的入口（这里是 `Article.create`）。类还能用，构造被收口了。**
