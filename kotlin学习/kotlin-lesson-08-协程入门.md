# Kotlin 第 8 课：协程入门（Coroutines Basics）

> 适用读者：已完成第 1～7 课（尤其是第 4 课 Lambda / 高阶函数）。
> 核心收获：理解协程为什么能告别回调地狱，会写 `suspend`、在作用域里 `launch`/`async`、用 `Dispatchers` + `withContext` 切线程，掌握结构化并发的取消常识。

---

## 一、为什么需要协程？⭐

Android 里几乎所有"耗时活"都不能堵在主线程：网络请求、读数据库、写文件。Java / 早期 Android 常见写法是回调嵌套：

```java
// Java 风格：回调地狱
api.getUser(userId, new Callback<User>() {
    @Override public void onSuccess(User user) {
        api.getOrders(user.id, new Callback<List<Order>>() {
            @Override public void onSuccess(List<Order> orders) {
                runOnUiThread(() -> show(orders));  // 还要记得切回主线程
            }
            @Override public void onFailure(Throwable t) { ... }
        });
    }
    @Override public void onFailure(Throwable t) { ... }
});
```

问题：层次一深就难读、难取消、难统一处理错误；`Thread` / `AsyncTask` 又容易泄漏、不好组合。

Kotlin 协程让**异步代码写出同步的样子**：

```kotlin
// 协程：顺序写，底层挂起不堵线程
lifecycleScope.launch {
    val user = api.getUser(userId)       // suspend，等结果但不卡死线程
    val orders = api.getOrders(user.id)
    show(orders)                         // 默认还在主线程，直接刷 UI
}
```

口诀：**协程 = 可挂起的轻量任务**；挂起时把线程让出去干别的，恢复时从断点继续——看起来像阻塞，实际不堵线程。

依赖（Android 常见）：

```kotlin
// build.gradle.kts
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")
```

Playground / 纯 JVM 用 `kotlinx-coroutines-core` 即可；下面示例用 `runBlocking` 方便在 main 里演示。

## 二、`suspend`：可挂起函数

```kotlin
suspend fun fetchUser(id: Long): User {
    delay(1000)                 // 挂起 1 秒（不阻塞线程），标准库提供
    return api.getUser(id)
}
```

要点：

- **`suspend` 只能从协程或其他 `suspend` 函数里调用**——普通函数直接调会编译报错。这是编译器帮你守的门：提醒"这里可能耗时/异步"。
- `suspend` **本身不切换线程**，只表示"这里可以挂起"。真正跑在哪条线程，由下面的 Dispatcher 决定。
- `delay(ms)` ≠ `Thread.sleep`：`sleep` 卡住整条线程；`delay` 只挂起当前协程，线程可以去跑别的协程。

```kotlin
// ❌ 普通函数里不能直接调 suspend
fun bad() {
    delay(100)                  // 编译报错
}

// ✅ 在协程里调
fun good() {
    runBlocking { delay(100) }  // runBlocking：阻塞当前线程直到里面的协程跑完（演示/测试用）
}
```

## 三、作用域与启动：`CoroutineScope` / `launch` / `async`

协程必须活在**作用域（Scope）**里——规定"这批协程的生命周期跟谁走"。Android 里常用：

| 作用域               | 跟谁绑定                | 典型用途                 |
| ----------------- | ------------------- | -------------------- |
| `lifecycleScope`  | Activity / Fragment | UI 相关，界面销毁自动取消       |
| `viewModelScope`  | ViewModel           | 业务请求，ViewModel 清掉时取消 |
| `GlobalScope`     | 进程级                 | ⚠️ 几乎别用，难取消、易泄漏      |
| `runBlocking { }` | 当前线程                | 演示、测试；**App 正式代码别用** |

### 1. `launch`：开火不管（返回 `Job`）

```kotlin
lifecycleScope.launch {
    val user = fetchUser(1)
    binding.name.text = user.name
}
// launch 立刻返回，不等结果；适合"做完就刷 UI / 写日志"这种无返回值任务
```

### 2. `async` / `await`：要结果（返回 `Deferred<T>`）

```kotlin
lifecycleScope.launch {
    val user = async { fetchUser(1) }      // 先启动
    val config = async { fetchConfig() }            // 并行启动
    show(user.await(), config.await())              // 都完成再继续
}
```

对比：

|     | `launch`     | `async`                |
| --- | ------------ | ---------------------- |
| 返回值 | `Job`（只表示任务） | `Deferred<T>`（能取出 `T`） |
| 取结果 | 无            | `await()`              |
| 适用  | 副作用、刷 UI     | 需要返回值、并行拼结果            |

口诀：**不要结果用 launch，要结果用 async + await。**

### 3. 最小可运行示例（Playground）

```kotlin
import kotlinx.coroutines.*

fun main() = runBlocking {
    println("start on ${Thread.currentThread().name}")

    launch {
        delay(500)
        println("launch done")
    }

    val deferred = async {
        delay(300)
        "hello"
    }
    println(deferred.await())   // hello
    println("end")
}
// 输出大致：start → hello → launch done → end
```

## 四、线程调度：`Dispatchers` 与 `withContext` ⭐

协程挂起不堵线程，但**默认不会自动帮你切到 IO 线程**——要显式指定：

| Dispatcher | 干什么 | Android 用法 |
|---|---|---|
| `Dispatchers.Main` | 主线程 / UI | 更新界面、碰 View |
| `Dispatchers.IO` | 阻塞式 IO 优化过的线程池 | 网络、数据库、文件 |
| `Dispatchers.Default` | CPU 密集 | 解析 JSON、排序、图片压缩 |
| `Dispatchers.Unconfined` | 不限定 | 知道即可，日常别用 |

**`withContext`：切过去干活，干完自动回到原来的上下文**——Android 最常用写法：

```kotlin
lifecycleScope.launch {                          // 默认 Main（lifecycleScope）
    binding.progress.visible()

    val user = withContext(Dispatchers.IO) {     // 切到 IO
        api.getUser(1)                           // 网络请求
    }                                            // 块结束 → 自动回到 Main

    binding.name.text = user.name                // 安全更新 UI
    binding.progress.gone()
}
```

也可以在启动时指定：

```kotlin
lifecycleScope.launch(Dispatchers.IO) {
    val data = heavyRead()
    withContext(Dispatchers.Main) {
        show(data)
    }
}
```

易错点：

- **`suspend` ≠ 已在后台**。只写 `suspend fun` 仍可能跑在 Main 上；卡 UI 的活必须 `withContext(IO/Default)`。
- 在 `Dispatchers.IO` 里直接改 View → 崩溃。改 UI 必须回 Main。
- 不要在循环里反复 `withContext` 切来切去；一大段 IO 包一次即可。

## 五、结构化并发：`Job` 与取消

协程不是"发射后不管"——父子关系绑在 Scope / Job 上：

```kotlin
val job = lifecycleScope.launch {
    launch { workA() }          // 子协程
    launch { workB() }
}
// Activity 销毁 → lifecycleScope 取消 → 子协程一并取消
job.cancel()                    // 也可手动取消整个树
```

要点：

1. **父取消 → 子全部取消**；父要等所有子完成后自己才结束（除非自己被取消）。
2. 取消是**协作式**的：协程要在挂起点（`delay`、`withContext`、`await` 等）或主动检查才能停下。
3. 自己写死循环要响应取消：

```kotlin
lifecycleScope.launch {
    while (isActive) {          // 或 ensureActive()
        doChunk()
        delay(100)
    }
}
```

4. `try/finally` 仍可做清理；需要挂起清理时用 `NonCancellable`（进阶，知道即可）。

口诀：**协程跟 Scope 走，界面没了任务停；取消靠挂起点，死循环记得看 `isActive`。**

这就是"结构化并发"：任务有父子边界，不会像随手 `new Thread` 那样失控乱飞。

## 六、对照速查表

| Java / 旧 Android     | Kotlin 协程                              |
| -------------------- | -------------------------------------- |
| 回调嵌套 / `AsyncTask`   | `launch { }` 顺序写                       |
| `Thread.sleep`       | `delay`（挂起不堵线程）                        |
| `Executor` + 回调切回主线程 | `withContext(Dispatchers.IO)` 自动回到原上下文 |
| 难取消的后台任务             | `Job.cancel()` / Scope 生命周期自动取消        |
| `Future.get()`       | `async { }.await()`                    |
| 忘记切线程改 UI 崩          | Main 上 launch，IO 用 withContext         |

## 七、本课练习及参考答案

```kotlin
import kotlinx.coroutines.*

// 1. suspend + delay：模拟耗时
suspend fun loadName(): String {
    delay(200)
    return "Jerry"
}

// 2. launch vs async
fun main() = runBlocking {
    launch {
        println("launch: ${loadName()}")
    }
    val name = async { loadName() }
    println("async: ${name.await()}")
}

// 3. withContext 切线程（看线程名）
fun main() = runBlocking {
    println("outer: ${Thread.currentThread().name}")
    val result = withContext(Dispatchers.Default) {
        println("inner: ${Thread.currentThread().name}")
        42
    }
    println("back: ${Thread.currentThread().name}, result=$result")
}

// 4. 取消：启动后 delay 一下再 cancel，观察 isActive
fun main() = runBlocking {
    val job = launch {
        repeat(5) { i ->
            if (!isActive) return@launch
            println("tick $i")
            delay(100)
        }
    }
    delay(250)
    job.cancel()
    job.join()          // 等它真正停掉
    println("cancelled")
}
```

---

**下一课预告（第 9 课）：协程进阶与 Flow 入门** —— 异常处理（`CoroutineExceptionHandler` / `supervisorScope`）、`Flow` 冷流基础，以及 Android 里 `viewModelScope` + UI 状态的常见写法。
