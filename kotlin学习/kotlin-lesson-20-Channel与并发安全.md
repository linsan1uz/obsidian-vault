# Kotlin 第 20 课：Channel 与并发安全

> 适用读者：已完成第 8、11 课（协程、异常、Flow）和第 10 课（SharedFlow 事件）。
> 核心收获：会用 `Channel` 在协程之间传数据，区分各种容量（缓冲 / 合并），知道一次性事件用 Channel 还是 SharedFlow，理解竞态条件，用 `Mutex`、原子类、`limitedParallelism` 保证并发安全。

---

## 一、Channel：协程之间的管道

Flow 是"一个数据源发给收集者"；**Channel 是两个（或多个）协程之间的管道**：一端 `send`，另一端 `receive`。

```kotlin
val channel = Channel<Int>()

launch {                         // 生产者
    for (i in 1..3) {
        channel.send(i)          // suspend：对方没收，就挂起等
        println("发送 $i")
    }
    channel.close()              // 发完关闭，接收端的 for 循环会结束
}

launch {                         // 消费者
    for (x in channel) {         // 一直 receive，直到 close
        println("收到 $x")
    }
}
```

- `send` / `receive` 都是 **suspend** 函数：管道满了发送方挂起，空了接收方挂起，**不阻塞线程**（第 8 课）。
- **每个元素只会被一个接收者拿到**（多个消费者时是"抢"，不是"广播"）。这是和 SharedFlow 最大的区别。
- 不再发送要 `close()`，否则消费者的 `for` 永远等下去。

`produce`：创建"一个协程 + 一个 Channel"的快捷写法，协程结束时自动关闭：

```kotlin
@OptIn(ExperimentalCoroutinesApi::class)
fun CoroutineScope.numbers(): ReceiveChannel<Int> = produce {
    for (i in 1..5) send(i)
}                                // 不用手动 close

val ch = numbers()
ch.consumeEach { println(it) }
```

## 二、容量：缓冲与合并

```kotlin
Channel<Int>()                          // RENDEZVOUS（默认）：容量 0，send 要等到有人 receive
Channel<Int>(capacity = 10)             // 固定缓冲：最多存 10 个，满了 send 挂起
Channel<Int>(Channel.BUFFERED)          // 默认缓冲大小（64）
Channel<Int>(Channel.UNLIMITED)         // 无限缓冲：send 永不挂起（小心内存）
Channel<Int>(Channel.CONFLATED)         // 合并：只保留最新一个，旧的被覆盖
```

| 容量 | send 会挂起吗 | 丢数据吗 | 适合 |
|---|---|---|---|
| RENDEZVOUS | 没人收就挂起 | 不丢 | 严格一手交一手 |
| 固定 / BUFFERED | 满了挂起 | 不丢 | 生产消费速度不一致 |
| UNLIMITED | 不挂起 | 不丢，但可能爆内存 | 数量确定很少 |
| CONFLATED | 不挂起 | 丢旧值，只留最新 | 只关心最新进度 |

也可以用 `onBufferOverflow = BufferOverflow.DROP_OLDEST` 自定义满了以后的策略。

## 三、一次性事件：Channel vs SharedFlow ⭐

第 10 课说过：Snackbar、导航这类"发生一次就完"的事件不能用 StateFlow。用 SharedFlow 和 Channel 都可以，但行为不同：

```kotlin
// 方案 A：SharedFlow
private val _events = MutableSharedFlow<String>()
val events = _events.asSharedFlow()

// 方案 B：Channel
private val _events = Channel<String>(Channel.BUFFERED)
val events = _events.receiveAsFlow()          // 转成 Flow 给 UI 收集

fun onSave() = viewModelScope.launch { _events.send("保存成功") }
```

| | `MutableSharedFlow()`（默认 replay = 0） | `Channel(BUFFERED)` + `receiveAsFlow()` |
|---|---|---|
| 没人收集时发事件 | **直接丢掉** | **存进缓冲**，等有人收集再送 |
| 多个收集者 | 每个都收到（广播） | 只有一个收到 |
| 转屏重建的空档期 | 事件可能丢 | 等新界面收集后补发 |

结论：**界面只有一个收集者、事件不能丢 → Channel 更合适；多处都要听同一事件 → SharedFlow。**

再进一步：Google 架构指南更推荐把"事件"也**做成状态**（例如 `UiState` 里放 `userMessage: String?`，界面显示完回调 `onMessageShown()` 清空），这样连 Channel 的边界情况都不会有。小项目用 Channel 足够。

口诀：**广播用 SharedFlow，一对一不丢用 Channel，最稳是把事件当状态。**

## 四、竞态条件：多个协程同时改一个变量 ⭐

```kotlin
var counter = 0

suspend fun main() = coroutineScope {
    repeat(1000) {
        launch(Dispatchers.Default) {         // 多个线程并行
            repeat(100) { counter++ }
        }
    }
}
// 期望 100000，实际经常是 9xxxx
```

原因：`counter++` 不是一步，而是"**读 → 加 1 → 写回**"三步。两个线程同时读到 500，各自加 1 写回 501，丢了一次。

- 协程跑在 `Dispatchers.Main` 上时只有一个线程，不会出现这个问题。
- **只要用了 `Dispatchers.Default` / `IO`，共享的可变状态就要保护。**

## 五、三种解决办法

### 1. `Mutex`：协程版的锁

```kotlin
val mutex = Mutex()
var counter = 0

launch(Dispatchers.Default) {
    repeat(100) {
        mutex.withLock { counter++ }          // 同一时间只有一个协程进来
    }
}
```

- `withLock` 是 **suspend**：抢不到锁时**挂起**而不是阻塞线程。
- 不要用 Java 的 `synchronized` 包 suspend 调用：在锁里挂起，恢复时可能换了线程，编译器也会报错。
- `Mutex` **不可重入**：同一个协程在 `withLock` 里再 `withLock` 同一个锁会死锁。

### 2. 原子类：单个变量最简单

```kotlin
val counter = AtomicInteger(0)               // java.util.concurrent.atomic
counter.incrementAndGet()                    // 读改写一步完成，线程安全
```

还有第 10 课的 `MutableStateFlow.update { it + 1 }`——它内部就是原子的"比较并替换"，所以 ViewModel 里并发更新状态用 `update` 就是安全的。

### 3. 线程限制：只让一个线程碰它

```kotlin
private val counterDispatcher = Dispatchers.Default.limitedParallelism(1)

launch(counterDispatcher) { counter++ }      // 同时最多 1 个协程在跑
```

- `limitedParallelism(n)`：从现有线程池里切出一个"最多同时 n 个"的视图，不新建线程。
- `limitedParallelism(1)` 相当于一个串行队列。
- 也常用于限流：`Dispatchers.IO.limitedParallelism(4)`，同时最多 4 个下载。

| 方案 | 适合 | 注意 |
|---|---|---|
| `Mutex.withLock` | 保护一段多步逻辑 | 不可重入 |
| `AtomicInteger` / `update { }` | 单个值 | 多个变量要一起改时不够 |
| `limitedParallelism(1)` | 整个对象都限定在串行上下文 | 所有访问都要走这个 dispatcher |

最省心的办法其实是**不共享可变状态**：用不可变数据 + `StateFlow.update` 整体替换（第 2 课 `copy`、第 10 课）。

## 六、例子：限流下载

```kotlin
class AvatarDownloader @Inject constructor(private val api: AvatarApi) {
    private val io = Dispatchers.IO.limitedParallelism(3)   // 同时最多 3 个请求
    private val mutex = Mutex()
    private val cache = mutableMapOf<Long, ByteArray>()

    suspend fun load(userId: Long): ByteArray {
        mutex.withLock { cache[userId] }?.let { return it }      // 先查缓存
        val bytes = withContext(io) { api.download(userId) }      // 下载不占锁
        mutex.withLock { cache[userId] = bytes }
        return bytes
    }
}
```

要点：**锁只包住访问共享状态的那一小段**，网络请求放在锁外面，否则所有下载被串行化。

## 七、易错点

1. **生产者发完不 `close()`**：消费者 `for (x in channel)` 永远挂起。或者用 `produce` 自动关。
2. **以为 Channel 是广播**：多个消费者是抢着拿，每个元素只给一个。广播用 SharedFlow。
3. **用 `UNLIMITED` 接高频数据**：消费跟不上时内存一直涨。
4. **用 `MutableSharedFlow()` 发事件，界面转屏空档期事件丢失**：改用 Channel，或把事件做成状态。
5. **在 `Dispatchers.Default` 上 `count++`**：竞态，结果不对。用原子类 / Mutex / `update`。
6. **用 `synchronized` 包 suspend 调用**：编译报错或行为错误。用 `Mutex`。
7. **`Mutex` 里嵌套再锁同一个 Mutex**：死锁，Mutex 不可重入。
8. **锁住整个网络请求**：并发退化成串行。锁只包共享状态的读写。
9. **以为 Main 上的代码也要加锁**：Main 只有一个线程，协程之间不会真并行，一般不需要。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 创建管道 | `val ch = Channel<T>(capacity)` |
| 发送 / 接收 | `ch.send(x)` / `ch.receive()` / `for (x in ch)` |
| 发完关闭 | `ch.close()` |
| 协程 + 管道 | `produce { send(x) }`（需 `@OptIn(ExperimentalCoroutinesApi::class)`） |
| 只要最新 | `Channel(Channel.CONFLATED)` |
| 一次性事件给 UI | `Channel<E>(Channel.BUFFERED)` + `receiveAsFlow()` |
| 协程锁 | `mutex.withLock { }` |
| 单值原子操作 | `AtomicInteger.incrementAndGet()` / `stateFlow.update { }` |
| 串行执行 | `Dispatchers.Default.limitedParallelism(1)` |
| 限并发数 | `Dispatchers.IO.limitedParallelism(n)` |

---

**下一课预告（第 21 课）：测试协程与 Flow** —— 本系列写了这么多 ViewModel、Repository、Flow，怎么验证它们对不对？`runTest` 跳过 `delay`、`MainDispatcherRule` 替换主线程、Turbine 测 StateFlow，给第 13～14 课的 `UserListViewModel` 写测试。
