# Kotlin 第 5 课：`when` 表达式、密封类与作用域函数

> 适用读者：已完成第 1～4 课。
> 核心收获：用 `when` 替代 switch，用密封类优雅建模 UI 状态，看懂 `let/apply/run/also/with` 五兄弟。

---

## 一、`when`：switch 的全面强化版

Java 的 switch 有三大槽点：忘写 `break` 就穿透、只能判基本类型、case 里放不了复杂条件。Kotlin 的 `when` 全解决：

```kotlin
fun httpMessage(code: Int): String = when (code) {
    200, 304 -> "正常"           // 多个值用逗号，不需要 break，不会穿透
    in 400..499 -> "客户端错误"   // 支持 in 范围！
    404 -> "页面不存在"
    else -> "未知"               // 相当于 default
}
```

要点：

- **不需要 `break`**，命中即走完，没有"穿透"坑。
- **`when` 是表达式**，有返回值，能直接 `return when(...)`、`val msg = when(x) {...}`。**`when` + 表达式函数体 `=` 是天然一对**。
- 分支条件可以是：具体值、多个值、`in 范围`、`is 类型`、任意布尔表达式。
- 无判断对象时就是 if-else 链的优雅版：

```kotlin
when {
    score >= 90 -> "优秀"
    score >= 60 -> "及格"
    else -> "不及格"
}
```

- `is` 类型判断 + 自动智能转换（smart cast）：

```kotlin
fun describe(obj: Any) = when (obj) {
    is Int -> "整数 ${obj + 1}"      // is 判断后 obj 自动当 Int 用，不用强转
    is String -> "字符串，长度 ${obj.length}"
    else -> "其他"
}
```

**易错点（本课练习实测踩过）：`is` 只用于类型，判断值直接写。**

```kotlin
when (code) {
    401 -> ...        // ✅ 值比较，直接写
    is 401 -> ...     // ❌ 编译报错：401 不是类型
}
```

风格习惯：**越精确的分支越靠前**（具体值写在 `in` 范围之前）。

## 二、密封类（sealed class）：`when` 的最佳拍档 ⭐

**Android 真实痛点**：加载页有三种状态——加载中、成功、失败。用 int 常量或枚举都放不下各自的数据。Kotlin 的答案：**密封类 + data class**：

```kotlin
sealed interface UiState {
    data class Loading(val message: String = "加载中...") : UiState
    data class Success(val data: List<String>) : UiState
    data class Error(val exception: Throwable) : UiState
}
```

三个关键点：

1. 密封类**限定子类只能生在同一个文件里**——外界无法偷偷加第四种状态，编译器因此**掌握所有可能的情况**。
2. 每个子类是 `data class`，**各自携带自己的数据**（Loading 有提示语、Success 有数据、Error 有异常）。
3. 配合 `when` 时**可以不写 `else`**：

```kotlin
fun render(state: UiState) = when (state) {
    is UiState.Loading -> showLoading(state.message)
    is UiState.Success -> showData(state.data)      // is 后直接取 state.data
    is UiState.Error -> showError(state.exception)
    // 没有 else！编译器保证三种情况全覆盖
}
```

**红利**：将来加第四种状态 `Empty` 时，所有漏处理的 `when` **当场编译报错**，编译器帮你查漏，而不是运行时才发现界面没刷新。Jetpack Compose、MVVM 的 `UiState`、`ViewModel` 事件全是这个套路，**现代 Android 必备模式**。

对照：普通继承体系（如 `Animal`）谁都能继承，`when` 永远需要 `else` 兜底——编译器不知道还有多少子类。"封闭"（sealed）的意义就在这。

## 三、作用域函数：`let / apply / run / also / with`

五个函数干的是同一类事：**把对象临时圈进一个作用域，方便做一串操作**。区别只有两个维度——Lambda 里用 `it` 还是 `this`、返回"处理结果"还是"对象本身"：

| 函数      | 引用对象   | 返回值       | 一句话记忆                |
| ------- | ------ | --------- | -------------------- |
| `let`   | `it`   | Lambda 结果 | 判空后操作，返回处理结果         |
| `run`   | `this` | Lambda 结果 | 对象配置 + 算个结果          |
| `with`  | `this` | Lambda 结果 | 对已有对象"带着它"干活（不是扩展函数） |
| `apply` | `this` | **对象自己**  | **配置对象**，配完返回它       |
| `also`  | `it`   | **对象自己**  | 顺手做副作用（日志、校验），不影响主线  |

### ① `let`：判空神器（最常用）

```kotlin
val name: String? = getName()

name?.let { println(it.length) }
// 非 null → Lambda 执行，it 就是那个非空值
// 为 null → Lambda 整个跳过，不崩也不执行
```

对比 `if (name != null)` 判空：效果一样，但 `?.let` 能串在链式调用后面，多步判空时优势明显：

```kotlin
intent.getStringExtra("user_id")?.let { loadUser(it) }
```

**关键理解（易错）：`let` 不会改变外面的变量。** Lambda 外的 `user` 仍是 `User?` 可空类型，`user.name` 编译不过；非空值是**作为参数传进 Lambda 的**，就是 `it`：

```kotlin
user?.let { println(it.name) }    // ✅ it 是保下来的非空值
user?.let { println(user.name) }  // ❌ 编译报错：user 在外面仍是可空类型
```

### ② `apply`：对象初始化/配置（Android 高频第一）

固定搭配：**`类名().apply { }`** —— 先 `()` 构造，再 `.apply` 配置：

```kotlin
val options = BitmapFactory.Options().apply {
    inSampleSize = 2            // Lambda 里 this 可省略，直接写属性名
    inJustDecodeBounds = false
}
// apply 返回对象本身，val 拿到的就是配置好的那个

startActivity(Intent(this, DetailActivity::class.java).apply {
    putExtra("id", 1)
    putExtra("title", "详情")
})
```

Java 要 `paint.setColor(...); paint.setAntiAlias(...)` 一行一个对象名；`apply` 省掉对象名，创建+配置一步到位。

### ③ `also`：顺手做副作用

```kotlin
val user = fetchUser()
    .also { log.d("TAG", "fetched $it") }   // it 用于日志/调试
    .also { require(it.age >= 0) }          // 或校验
// 返回的还是原对象，主线不受影响
```

### ④ `run` / `with`：配置 + 算个结果

```kotlin
val info = person.run { "$name, $age 岁" }   // this 作用域，返回 Lambda 结果

val info2 = with(person) { "$name, $age 岁" } // with 不是扩展函数，对象写进括号
```

### 选用口诀

> **判空用 let，配置用 apply，顺带做事用 also，算结果用 run/with。**
>
> 忘了就问两个问题：Lambda 里想用 `it` 还是省略成 `this`？想要"处理结果"还是"对象本身"？

初学优先掌握 **`let`（判空）和 `apply`（配置）**，占实际使用 90%；其余见到能看懂即可。

## 四、本课练习及参考答案（Playground）

```kotlin
// 1. when 表达式：月份 → 季节
fun season(month: Int): String = when (month) {
    in 3..5 -> "春"
    in 6..8 -> "夏"
    in 9..11 -> "秋"
    12, 1, 2 -> "冬"
    else -> "非法月份"
}

// 2. 密封类 + when（不写 else，编译器保证全覆盖）
sealed interface LoginResult {
    data class Success(val token: String) : LoginResult
    data class Failure(val code: Int, val msg: String) : LoginResult
}
fun render(result: LoginResult) = when (result) {
    is LoginResult.Success -> println("登录成功 token=${result.token}")
    is LoginResult.Failure ->
        if (result.code == 401) println("请重新登录")   // 值比较不用 is！
        else println(result.msg)
}
// 为什么能不写 else？密封类限定子类同文件，编译器掌握全部情况，
// is 分支覆盖完所有子类即视为穷尽；新增子类时漏处理的 when 直接编译报错。

// 3. apply 改写
val options = BitmapFactory.Options().apply {
    inSampleSize = 2
    inJustDecodeBounds = false
}

// 4. let + it 一行判空
data class User(val name: String)
val user: User? = null
user?.let { println(it.name) }
```

---

**下一课预告（第 6 课）：泛型与型变入门** —— `List<out T>` 的 out/in 是什么、为什么 `List<String>` 能当 `List<Any>` 用，看懂 Android 源码里的型变声明。

---

## 答疑补充：可运行的作用域函数 demo

> Jerry 提问：能给我写一段可以运行的作用域函数吗？
> 复制到 [Kotlin Playground](https://play.kotlinlang.org) 即可跑。

```kotlin
data class User(var name: String, var age: Int)

fun main() {
    val raw: String? = "  Jerry  "

    // let：it = 接收者，返回【块的最后一行】；常用于可空 + 转换
    val name = raw
        ?.let { it.trim() }
        ?.let { it.replaceFirstChar { c -> c.uppercase() } }
    println("let -> $name")                    // Jerry

    // also：it = 接收者，返回【接收者自己】；适合顺手打日志
    val user = User("Tom", 20)
        .also { println("also 创建前看看: $it") }

    // apply：this = 接收者，返回【接收者自己】；适合初始化
    user.apply {
        name = "Jerry"
        age = 25
    }
    println("apply -> $user")                  // User(name=Jerry, age=25)

    // run：this = 接收者，返回【块的最后一行】；配置完再算个结果
    val label = user.run {
        "$name ($age)"
    }
    println("run -> $label")                   // Jerry (25)

    // with：不是扩展函数，with(obj) { this = obj }，返回块结果
    val summary = with(user) {
        "摘要: $name / $age 岁"
    }
    println("with -> $summary")                // 摘要: Jerry / 25 岁
}
```

### 怎么记

| 函数 | 对象在块里 | 返回值 | 一句话 |
|---|---|---|---|
| `let` | `it` | 块结果 | 可空链式、转换 |
| `also` | `it` | **自己** | 顺带副作用（日志） |
| `apply` | `this` | **自己** | 初始化 / 改属性 |
| `run` | `this` | 块结果 | 配置并算出一个值 |
| `with(x)` | `this` | 块结果 | 对已有对象写多句 |

口诀：**要对象继续往下传 → apply / also；要算出新值 → let / run / with。块里想省略名字用 this → apply/run/with；想明确叫 it → let/also。**

### 预期输出

```
let -> Jerry
also 创建前看看: User(name=Tom, age=20)
apply -> User(name=Jerry, age=25)
run -> Jerry (25)
with -> 摘要: Jerry / 25 岁
```


> 工程可跑：coroutineStudy 里打开主页按钮「作用域函数 demo（第5课）」→ ScopeFunctionsDemoActivity（Logcat：ScopeFunctionsDemo）；单测 ScopeFunctionsDemoTest 断言链式结果 Bob -> 19。

---

## 答疑补充：demo 里几个作用域函数逐个讲解

> Jerry 提问：讲一下你写的几个作用域吧  
> 对照工程：`coroutineStudy` → 主页「作用域函数 demo（第5课）」→ `runScopeFunctionsDemo()`（Logcat：`ScopeFunctionsDemo`）。

### 1. `let`：可空检查 + 转换（`it`，返回最后一行）

```kotlin
val raw: String? = "  bob  "
val name = raw
    ?.let { it.trim() }
    ?.let { it.replaceFirstChar { c -> c.uppercase() } }
// → "Bob"；若 raw == null，整段跳过，name 为 null
```

- `?.let`：左边 null 就不进块。
- 块里默认叫 **`it`**。
- **返回值 = 块的最后一行**（新字符串）。

### 2. `also`：顺手副作用（`it`，返回自己）

```kotlin
val user = DemoUser("Tom", 20)
    .also { lines += "also 创建前看看: $it" }
// 返回的还是原来的 user
```

适合打日志、检查——**不改返回类型**。

### 3. `apply`：配置对象（`this`，返回自己）

```kotlin
user.apply {
    name = nameFromLet   // 可省略 this.
    age = 18
}
```

块里是 **`this`**，适合一口气改多个属性；返回自己，便于继续链式。

### 4. `run`：在对象上算结果（`this`，返回最后一行）

```kotlin
val label = user.run { "$name ($age)" }
// → "Bob (18)"，类型变成 String
```

和 `apply` 一样用 `this`，但**返回最后一行**（会变类型）。

### 5. `with`：不是扩展函数（`this`，返回最后一行）

```kotlin
val summary = with(user) { "摘要: $name / $age 岁" }
```

- 写法是 `with(obj) { }`，**不是** `obj.with { }`。
- **没有** `nullable?.with`；可空请用 `?.run` / `?.let`。
- 语义接近 `run`。

### 6. 链式那段为什么是 `"Bob -> 19"`

```kotlin
val chained = DemoUser("bob", 18)   // 或工程里等价的小写起步再大写
    .also { /* 看一眼，返回自己 */ }
    .apply {
        name = name.replaceFirstChar { it.uppercase() }  // bob → Bob
        age += 1                                         // 18 → 19
    }
    .run { "$name -> $age" }   // "Bob -> 19"
```

顺序：**also 旁观 → apply 改字段 → run 拼出新字符串**。单测 `ScopeFunctionsDemoTest` 断言的就是这个 `chained`。

### 7. 对照表

| 函数 | 块里叫 | 返回值 | 典型用途 |
|---|---|---|---|
| `let` | `it` | 最后一行 | 可空、转换 |
| `also` | `it` | **自己** | 日志等副作用 |
| `apply` | `this` | **自己** | 初始化 / 改属性 |
| `run` | `this` | 最后一行 | 算结果 |
| `with(x)` | `this` | 最后一行 | 对已有对象写多句 |

### 8. 口诀

- **要变返回类型** → `let` / `run` / `with`
- **还是原对象** → `apply` / `also`
- 可空用 `?.let` / `?.run` / `?.also` / `?.apply`；别写 `?.with`

---

## 答疑补充：let / apply / also 到底怎么选（语音答疑）

> Jerry 语音追问整理：`let` 到底干什么？`apply` 既然是初始化，为什么不直接 setter？`also` 和 `apply` 差在哪？

### 1. `let`：不只是判空

三件事常一起出现：

1. **判空**：`?.let { }` —— null 就不进块。  
2. **转换成新值**：块的**最后一行**当返回值（类型可以变）。  
3. **限定作用域**：临时名字只活在块里，外面干净。

```kotlin
val raw: String? = "  bob  "
val name = raw?.let { s ->
    s.trim().replaceFirstChar { it.uppercase() }   // 返回新 String
}
// name: String? = "Bob"
```

口诀：**有值才干；干完往往得到另一个东西。**

### 2. `apply`：为什么不「直接 setter」？

在 Kotlin 里写 `user.name = "Bob"`，**本来就会调用属性的 setter**（和 Java 的 `setName` 是一类事）。  
所以 `apply` **不是**为了「多一种赋值方式」，而是为了：

| 价值 | 说明 |
|---|---|
| **集中配置** | 多次赋值放进一个块，读起来是「在初始化这个对象」 |
| **少写变量名** | 块里是 `this`，不用反复 `paint.xxx` |
| **返回自己** | 整个 `apply { }` 是表达式，能直接赋给 `val` 或继续链式 |

```kotlin
// Kotlin：一块搞定 + 当表达式用
val paint = Paint().apply {
    color = Color.RED
    strokeWidth = 2f
    isAntiAlias = true
}

// 对照 Java 常见写法：先 new，再一行行 set
// Paint paint = new Paint();
// paint.setColor(Color.RED);
// paint.setStrokeWidth(2f);
// paint.setAntiAlias(true);
```

没有 `apply` 也能赋值；有了它，**初始化这段话更短、更能当一行表达式**。

### 3. `also`：顺便做一件事

- 块里叫 **`it`**（强调「顺手拿这个对象做点别的」）。  
- **返回自身**（和 `apply` 一样不换类型）。  
- 典型：打日志、加进列表、断言——**副作用**，不是改配置的主战场。

```kotlin
val user = DemoUser("Tom", 20)
    .also { Log.d("Demo", "创建了: $it") }
    .also { cache.add(it) }
```

### 4. `also` vs `apply`（就记这一点）

| | `apply` | `also` |
|---|---|---|
| 块里 | **`this`**（可直接写 `name = ...`） | **`it`**（写 `it.name`） |
| 返回 | 自己 | 自己 |
| 语感 | **配置 / 初始化我自己** | **顺便用我做件事** |

```kotlin
user.apply { age = 18 }                 // this.age
user.also { println(it.age) }           // 旁观 it
```

两者都能链式；**改属性优先 apply，旁观/日志优先 also**。

### 5. 超短选用

- 可空 → 转换新值 → **`let`**
- 一堆属性初始化、要当表达式 → **`apply`**
- 不改类型、只顺便干一票 → **`also`**
