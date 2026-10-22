# Kotlin 第 21 课：测试协程与 Flow

> 适用读者：已完成第 11 课（Flow、`stateIn`）、第 13～14 课（`UserListViewModel`、`UserRepository` 接口）。
> 核心收获：会用 `runTest` 写协程测试，理解虚拟时间和 `StandardTestDispatcher`，用 `MainDispatcherRule` 替换主线程，用假 Repository 隔离网络和数据库，用 Turbine 测 StateFlow，给第 13 课的 `UserListViewModel` 写出真正能跑的单元测试。

---

## 一、为什么协程代码难测

普通 JUnit 测试里直接调 suspend 函数编译不过；就算用 `runBlocking`，还有三个问题：

1. **`delay(5000)` 真的等 5 秒**，测试慢得没法跑。
2. **`viewModelScope` 用的是 `Dispatchers.Main`**，JVM 单元测试里没有 Android 主线程，直接崩。
3. **ViewModel 依赖 Retrofit 和 Room**，单测里不可能真去联网、建库。

本课逐个解决：`runTest`（虚拟时间）→ `MainDispatcherRule`（替换 Main）→ 假 Repository（隔离依赖）→ Turbine（测 Flow）。

## 二、依赖

```kotlin
// app/build.gradle.kts
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")   // 和 coroutines 版本一致
    testImplementation("app.cash.turbine:turbine:1.2.1")
}
```

测试代码放在 `src/test/java/...`（JVM 单元测试，跑得快）；需要真机 / 模拟器的放 `src/androidTest/`。

## 三、`runTest` 与虚拟时间 ⭐

```kotlin
class DelayTest {
    @Test
    fun 延迟不会真的等() = runTest {          // ⭐ 测试体是协程，能直接调 suspend
        val start = currentTime              // 虚拟时钟，单位 ms
        delay(5_000)                         // 不真等，瞬间跳过
        assertEquals(5_000, currentTime - start)
    }
}
```

- `runTest` 内部用 **`StandardTestDispatcher`** + **虚拟时间调度器**：`delay` 不真等，而是把虚拟时钟往前拨。
- 测试名可以用中文（反引号写法 `` fun `xxx`() `` 也行），读起来像需求说明。

### 调度控制：`StandardTestDispatcher`

在 `StandardTestDispatcher` 上 `launch` 的协程**不会立刻执行**，而是进入队列，等你推进时间：

```kotlin
@Test
fun 手动推进() = runTest {
    var done = false
    launch {
        delay(1_000)
        done = true
    }
    assertFalse(done)            // 还没执行
    advanceTimeBy(999)
    runCurrent()
    assertFalse(done)            // 999ms，还差一点
    advanceUntilIdle()           // 跑完所有排队任务
    assertTrue(done)
}
```

| 函数 | 作用 |
|---|---|
| `runCurrent()` | 执行当前时刻已就绪的任务 |
| `advanceTimeBy(ms)` | 时钟前进 ms，执行这段时间内到期的任务 |
| `advanceUntilIdle()` | 一直推进，直到没有任务 |
| `currentTime` | 当前虚拟时间 |

另一个 `UnconfinedTestDispatcher`：协程**立刻**执行到第一个挂起点，写起来省事但顺序不好控制。**默认用 Standard，需要"立刻跑"的场景才用 Unconfined。**

## 四、`MainDispatcherRule`：替换主线程 ⭐

`viewModelScope` 固定用 `Dispatchers.Main`。测试里把它换成测试调度器：

```kotlin
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = StandardTestDispatcher()
) : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(testDispatcher)
    override fun finished(description: Description) = Dispatchers.resetMain()
}
```

```kotlin
class UserListViewModelTest {
    @get:Rule
    val mainRule = MainDispatcherRule()       // 每个测试前 setMain，测试后 resetMain
}
```

- JUnit4 的 Rule：每个测试前后自动执行，不会忘记还原。
- `runTest` 发现 Main 已被换成 `TestDispatcher`，会**共用同一个虚拟时钟**，所以 `advanceUntilIdle()` 也能推进 `viewModelScope` 里的协程。

## 五、假 Repository：隔离网络和数据库 ⭐

第 14 课把 `UserRepository` 抽成了接口，这时候派上用场：

```kotlin
class FakeUserRepository : UserRepository {

    private val _users = MutableStateFlow<List<User>>(emptyList())
    override val users: Flow<List<User>> = _users

    var remoteUsers: List<User> = emptyList()   // 模拟服务器返回
    var shouldFail = false                      // 模拟网络错误
    var refreshCount = 0
    var lastQuery: String? = null               // 记录最近一次搜索词

    override fun search(q: String): Flow<List<User>> {
        lastQuery = q
        return _users.map { list -> list.filter { q in it.name } }
    }

    override suspend fun refresh(): Result<Unit> {
        refreshCount++
        if (shouldFail) return Result.failure(IOException("no network"))
        _users.value = remoteUsers              // 像真 Repository 一样"写进数据库"
        return Result.success(Unit)
    }
}
```

为什么写 Fake 而不是用 Mock 框架？Fake 是一个真实可运行的简化实现，行为和真实 Repository 一致（刷新后 `users` 发新值），测试读起来像真实流程；接口一改，Fake 编译不过，立刻发现。

第 19 课的 DSL 可以用来造假数据：`remoteUsers = userList { user { id = 1; name = "Jerry" } }`。

## 六、Turbine：测 Flow 的利器

```kotlin
@Test
fun flow按顺序发值() = runTest {
    flowOf(1, 2, 3).test {                   // Turbine 提供的 test 扩展
        assertEquals(1, awaitItem())
        assertEquals(2, awaitItem())
        assertEquals(3, awaitItem())
        awaitComplete()                      // 断言流正常结束
    }
}
```

| 函数 | 作用 |
|---|---|
| `awaitItem()` | 挂起等下一个值，超时（默认 3 秒）就失败 |
| `awaitComplete()` / `awaitError()` | 断言流结束 / 出错 |
| `expectNoEvents()` | 断言目前没有新值 |
| `cancelAndIgnoreRemainingEvents()` | 不关心后面的值，结束测试 |

`test { }` 块结束时如果还有没消费的值，Turbine 会让测试失败——逼你把每次发射都想清楚。

## 七、测试 UserListViewModel ⭐

回顾第 13 课的 ViewModel：`state` 由 `combine(users, refreshing, error)` + `stateIn(WhileSubscribed(5000), UiState.Loading)` 得到，`init` 里调用 `refresh()`。

```kotlin
class UserListViewModelTest {

    @get:Rule
    val mainRule = MainDispatcherRule()

    private val jerry = User(1, "Jerry", "j@x.com")
    private val repo = FakeUserRepository()

    @Test
    fun 刷新成功显示用户列表() = runTest {
        repo.remoteUsers = listOf(jerry)
        val vm = UserListViewModel(repo)

        vm.state.test {
            assertEquals(UiState.Loading, awaitItem())                // stateIn 初始值
            assertEquals(UiState.Success(listOf(jerry)), awaitItem()) // 刷新完成
        }
        assertEquals(1, repo.refreshCount)
    }

    @Test
    fun 没缓存且网络失败显示错误() = runTest {
        repo.shouldFail = true
        val vm = UserListViewModel(repo)

        vm.state.test {
            assertEquals(UiState.Loading, awaitItem())
            assertEquals(UiState.Error("网络连接失败，请检查网络"), awaitItem())   // 第 13 课 toUserMessage
        }
    }
}
```

执行过程：

1. `UserListViewModel(repo)` 构造时 `init { refresh() }` 在 `viewModelScope`（测试 Main）里**排队**，还没执行。
2. `vm.state.test { }` 开始收集 → `WhileSubscribed` 启动上游；第一个 `awaitItem()` 拿到初始值 `Loading`。
3. 第二个 `awaitItem()` 挂起 → 测试调度器执行排队任务：`refresh()` 跑完，`combine` 算出 `Success` 或 `Error`。
4. StateFlow 会**去重**：中途算出的重复 `Loading` 不会再发一次，所以断言不用写它。

**关键坑**：`stateIn(WhileSubscribed)` 没人收集时**根本不启动**。如果不用 Turbine，只写 `advanceUntilIdle(); assertEquals(..., vm.state.value)`，`value` 会一直是 `Loading`。不用 Turbine 时要先开一个收集者：

```kotlin
backgroundScope.launch { vm.state.collect {} }   // runTest 结束时自动取消
advanceUntilIdle()
assertEquals(UiState.Success(listOf(jerry)), vm.state.value)
```

### 测试防抖（第 11 课搜索）

```kotlin
@Test
fun 停止输入300ms后才搜索() = runTest {
    val vm = SearchViewModel(repo)
    backgroundScope.launch { vm.results.collect {} }   // 开一个收集者，让 stateIn 启动上游

    vm.onQueryChange("je")
    advanceTimeBy(299); runCurrent()
    assertNull(repo.lastQuery)                         // 299ms：还没搜
    advanceTimeBy(1); runCurrent()
    assertEquals("je", repo.lastQuery)                 // 满 300ms：发起搜索
}
```

虚拟时间让 "300ms 防抖" 这种逻辑可以精确到毫秒验证，而且测试瞬间跑完。

## 八、其他层的测试（了解）

- **Room DAO**：放 `androidTest`，用 `Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).build()` 建内存库，每个测试一个新库。
- **Retrofit**：用 OkHttp 的 `MockWebServer` 返回固定 JSON，测解析和错误码映射。
- **Compose UI**：`createComposeRule()` + `onNodeWithText("重试").performClick()`。第 16 课把 `UserListContent` 写成无状态，正是为了这里能直接传假 `state` 测。
- **Hilt**：`@HiltAndroidTest` + `@TestInstallIn` 替换 Module（第 14 课）。

## 九、易错点

1. **用 `runBlocking` 测协程**：`delay` 真等，测试慢。用 `runTest`。
2. **忘了 `MainDispatcherRule`**：`viewModelScope` 报 `Module with the Main dispatcher is missing`。
3. **Rule 里自己 new 的调度器和 `runTest` 不共用时钟**：`advanceUntilIdle()` 推不动 ViewModel 里的协程。让 Main 用 `TestDispatcher`，`runTest` 会自动共用它的调度器。
4. **测 `stateIn(WhileSubscribed)` 只读 `.value`**：没人收集，上游不启动。用 Turbine 或 `backgroundScope` 收集。
5. **`StandardTestDispatcher` 下断言太早**：协程还在排队。先 `advanceUntilIdle()` / `runCurrent()`。
6. **Turbine `test { }` 里留着没消费的值**：测试失败。消费完，或 `cancelAndIgnoreRemainingEvents()`。
7. **单测里依赖真 Retrofit / Room**：慢、不稳定、要联网。用 Fake 实现接口。
8. **断言 StateFlow 每一次中间值**：StateFlow 会合并、去重，中间值可能看不到。断言关键状态即可。
9. **`kotlinx-coroutines-test` 版本和 coroutines 不一致**：奇怪的运行时错误。保持同一版本（1.11.0）。

## 十、对照速查表

| 需求 | 写法 |
|---|---|
| 协程测试 | `@Test fun x() = runTest { }` |
| 推进时间 | `advanceTimeBy(ms)` / `runCurrent()` / `advanceUntilIdle()` |
| 当前虚拟时间 | `currentTime` |
| 替换 Main | `MainDispatcherRule` + `Dispatchers.setMain(StandardTestDispatcher())` |
| 隔离依赖 | `class FakeUserRepository : UserRepository` |
| 测 Flow | `flow.test { awaitItem(); awaitComplete() }` |
| 不关心剩余值 | `cancelAndIgnoreRemainingEvents()` |
| 断言没新值 | `expectNoEvents()` |
| 后台收集 | `backgroundScope.launch { flow.collect {} }` |
| 依赖 | `kotlinx-coroutines-test:1.11.0`、`turbine:1.2.1`、`junit:4.13.2` |

---

**下一课预告（第 22 课）：总复习与综合项目** —— 最后一课：把 1～21 课串成一张地图，画出整体架构，并把 Compose + ViewModel + Room + Retrofit + Hilt + Navigation 组装成一个完整的"用户列表 App"。
