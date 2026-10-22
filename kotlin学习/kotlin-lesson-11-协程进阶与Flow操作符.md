# Kotlin 第 11 课：协程进阶与 Flow 操作符

> 适用读者：已完成第 9、10 课（ViewModel、StateFlow、`viewModelScope`）；第 8 课协程只看到一半也没关系，第一节会快速补齐。
> 核心收获：协程异常怎么接住（`try/catch`、`CoroutineExceptionHandler`、`SupervisorJob`），分清冷 Flow 与 StateFlow，会用 `map/filter/debounce/flatMapLatest/combine` 等操作符，最后用 `stateIn` 写出一个带防抖的搜索框。

---

## 一、第 8 课快速回顾（30 秒版）

```kotlin
viewModelScope.launch {                      // 启动协程，不要结果
    val user = withContext(Dispatchers.IO) { // 切到 IO，块结束自动切回
        api.getUser(1)
    }
    _name.value = user.name
}

val a = async { loadA() }                    // 要结果：async + await
val b = async { loadB() }
show(a.await(), b.await())                   // 并行
```

- `suspend` = 可挂起，**不等于**已经在后台。
- 协程活在 Scope 里：`viewModelScope` 随 ViewModel、`lifecycleScope` 随界面。
- **结构化并发**：父取消 → 子全取消；子出错 → 默认把父和兄弟一起拖垮（第二节重点）。

## 二、异常处理 ⭐

### 1. 最直接：`try/catch` 包住挂起调用

```kotlin
viewModelScope.launch {
    try {
        val users = api.getUsers()
        _state.value = UiState.Success(users)
    } catch (e: CancellationException) {
        throw e                               // ⚠️ 取消信号必须放行
    } catch (e: Exception) {
        _state.value = UiState.Error(e.message ?: "未知错误")
    }
}
```

`CancellationException` 是协程"被取消"的正常信号，吞掉它会让协程停不下来。`catch (e: Exception)` 会顺手抓住它，所以要么单独放行，要么只抓具体类型（`IOException`、`HttpException`）。

### 2. 兜底：`CoroutineExceptionHandler`

```kotlin
private val handler = CoroutineExceptionHandler { _, e ->
    _state.value = UiState.Error(e.message ?: "出错了")
}

fun load() = viewModelScope.launch(handler) {
    _state.value = UiState.Success(api.getUsers())
}
```

- 只对**根协程的 `launch`** 生效，相当于"未捕获异常的最后一道网"。
- 对 `async` 无效：`async` 的异常在 `await()` 时抛出，要在 `await` 处 `try/catch`。
- 它只能记录/报错，不能让协程"继续往下跑"。业务上要恢复，用 `try/catch`。

### 3. `SupervisorJob` / `supervisorScope`：一个失败不连坐

默认 `Job`：子协程 A 抛异常 → 父取消 → 兄弟 B 也被取消。
`SupervisorJob`：子失败**只影响自己**。

```kotlin
// viewModelScope 内部就是 SupervisorJob() + Dispatchers.Main.immediate
// 所以 viewModelScope.launch {A} 和 launch {B} 互不影响

suspend fun loadDashboard() = supervisorScope {
    val news = async { api.news() }          // 失败了
    val weather = async { api.weather() }    // 不受影响
    val n = runCatching { news.await() }.getOrNull()
    val w = runCatching { weather.await() }.getOrNull()
    Dashboard(n, w)
}
```

对比：`coroutineScope { }` 一个子失败全体取消（"要么全成要么全败"）；`supervisorScope { }` 各管各的（"能拿多少拿多少"）。

口诀：**能恢复用 try/catch，兜底用 Handler；不想连坐用 Supervisor；`CancellationException` 永远放行。**

## 三、冷 Flow vs StateFlow ⭐

第 10 课的 `StateFlow` 是**热流**：不管有没有人收集，它都存着一个当前值。
`flow { }` 造出来的是**冷流**：**没人 collect 就什么都不做，每个收集者各跑一遍**。

```kotlin
fun ticker(): Flow<Int> = flow {
    for (i in 1..3) {
        delay(1000)
        emit(i)                               // 发射一个值
    }
}

viewModelScope.launch { ticker().collect { println("A 收到 $it") } }
viewModelScope.launch { ticker().collect { println("B 收到 $it") } }
// A、B 各自从 1 开始收，代码块执行了两次
```

| | 冷 Flow（`flow { }`） | StateFlow |
|---|---|---|
| 何时执行 | 每次 `collect` 才执行 | 一直存在 |
| 多个收集者 | 各跑一遍 | 共享同一个值 |
| 当前值 | 没有 | 必须有 `.value` |
| 典型来源 | Room 查询、网络分页、计时器 | ViewModel 暴露给 UI 的状态 |

ViewModel 的常见套路：**内部用冷 Flow 加工数据 → `stateIn` 转成 StateFlow 交给 UI**（第五节）。

## 四、常用操作符

操作符和第 4 课集合的 `map/filter` 同名同义，区别是**作用在"随时间到来的值"上**：

```kotlin
repository.observeUsers()                     // Flow<List<User>>
    .map { list -> list.filter { it.active } } // 变换
    .filter { it.isNotEmpty() }                // 过滤整次发射
    .onEach { Log.d("TAG", "size=${it.size}") }// 顺手做副作用（像第 5 课 also）
    .distinctUntilChanged()                    // 和上一次一样就不往下发
    .flowOn(Dispatchers.Default)               // ⭐ 上游跑在 Default
    .catch { e -> emit(emptyList()) }          // 接住上游异常，发兜底值
```

| 操作符 | 作用 | 一句话 |
|---|---|---|
| `map` / `filter` | 变换 / 过滤 | 同集合 |
| `onEach` | 每个值经过时做点事 | 日志、埋点 |
| `distinctUntilChanged` | 连续重复值去掉 | 防止重复刷新 |
| `debounce(ms)` | 停顿 ms 后才发最后一个 | 搜索框防抖 |
| `flowOn(dispatcher)` | 改变**上游**运行线程 | 下游（collect）线程不变 |
| `catch { }` | 捕获**上游**异常 | 写在哪，就只管它上面的 |
| `combine(a, b) { }` | 任一方变化就用双方最新值合成 | 关键词 + 排序方式 |
| `flatMapLatest { }` | 新值来了就**取消旧的内层 Flow** | 搜索只要最新一次的结果 |

两个方向性规则（高频易错）：

- **`flowOn` 管上游，`catch` 管上游**——它们都只影响写在自己**上面**的部分。
- **`collect` 下游里抛的异常 `catch` 接不住**，要么在 collect 里 try，要么把逻辑挪到 `onEach` 再接 `catch`。

`combine` 示例：

```kotlin
val sortAsc = MutableStateFlow(true)
val sorted: Flow<List<User>> = combine(usersFlow, sortAsc) { users, asc ->
    if (asc) users.sortedBy { it.name } else users.sortedByDescending { it.name }
}
```

## 五、`stateIn`：冷流变成 UI 用的 StateFlow ⭐

```kotlin
val users: StateFlow<List<User>> = repository.observeUsers()
    .stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = emptyList()
    )
```

三个参数：

1. **`scope`**：上游在哪个作用域里跑 → `viewModelScope`，ViewModel 清掉就停。
2. **`started = WhileSubscribed(5000)`**：有人收集时启动上游；最后一个收集者离开 **5 秒后**才停。为什么是 5 秒？**转屏重建通常在 5 秒内完成**，上游不用重启；真退到后台超过 5 秒，就停掉省电省流量。
3. **`initialValue`**：StateFlow 必须有值，上游还没发之前 UI 先看到它。

和第 10 课的 `repeatOnLifecycle(STARTED)` 是一对：界面不可见 → 停止收集 → 5 秒后上游也停。

## 六、实战：搜索框防抖

需求：用户输入关键词，**停止输入 300ms 后**才搜索；新输入到来时，丢弃上一次还没回来的搜索。

```kotlin
@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class SearchViewModel(private val repo: UserRepository) : ViewModel() {

    private val query = MutableStateFlow("")

    val results: StateFlow<SearchUiState> = query
        .debounce(300)                                 // 停 300ms 才往下走
        .map { it.trim() }
        .distinctUntilChanged()                        // "kot" → "kot " trim 后相同，不重复搜
        .flatMapLatest { q ->                          // 新关键词来了，旧搜索取消
            if (q.isEmpty()) flowOf(SearchUiState.Idle)
            else repo.search(q)                        // Flow<List<User>>
                .map<List<User>, SearchUiState> { SearchUiState.Success(it) }
                .onStart { emit(SearchUiState.Loading) }
                .catch { emit(SearchUiState.Error(it.message ?: "搜索失败")) }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SearchUiState.Idle)

    fun onQueryChange(text: String) {
        query.value = text
    }
}

sealed interface SearchUiState {                       // 第 5 课密封类
    data object Idle : SearchUiState
    data object Loading : SearchUiState
    data class Success(val users: List<User>) : SearchUiState
    data class Error(val msg: String) : SearchUiState
}
```

- `debounce` 是 `FlowPreview`、`flatMapLatest` 是 `ExperimentalCoroutinesApi`，所以类上加 `@OptIn`。API 稳定可放心用，只是还挂着实验标记。
- `catch` 放在 `flatMapLatest` **内部**：一次搜索失败只影响这一次；放在外层的话，上游流会直接结束，后面再输入也不会搜了。
- Activity 侧：`editText.doAfterTextChanged { vm.onQueryChange(it.toString()) }`，`results` 照第 10 课用 `repeatOnLifecycle` 收集，`when (state)` 渲染。

## 七、易错点

1. **`catch (e: Exception)` 吞掉 `CancellationException`**：协程取消不了。单独 rethrow，或只抓具体异常。
2. **以为 `CoroutineExceptionHandler` 能管 `async`**：不能，`async` 的异常在 `await()` 处理。
3. **`catch` / `flowOn` 写错位置**：它们只管上游。写在 `collect` 前面的最后一个也接不住 collect 里的异常。
4. **在 `flow { }` 里 `withContext` 切线程再 `emit`**：违反 Flow 上下文规则，运行时报错。切线程用 `flowOn`。
5. **把 `catch` 放在搜索流最外层**：一次失败整条流终止，之后输入失效。放进 `flatMapLatest` 里。
6. **`stateIn` 用 `SharingStarted.Eagerly` 当默认**：ViewModel 一创建就跑上游，界面不可见也不停。UI 状态优先 `WhileSubscribed(5000)`。
7. **每次调用函数都 `stateIn` 一遍**：每次都新建一个 StateFlow。应声明为 `val` 属性，只建一次。
8. **用 `map` 发起搜索**：得到 `Flow<Flow<…>>`。搜索要"只认最新"，用 `flatMapLatest`。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 可恢复的异常 | `try/catch`，`CancellationException` 要 rethrow |
| 根协程兜底 | `launch(CoroutineExceptionHandler { _, e -> })` |
| 子任务失败互不影响 | `SupervisorJob()` / `supervisorScope { }` |
| 造冷流 | `flow { emit(x) }` / `flowOf(a, b)` |
| 变换 / 过滤 / 副作用 | `map` / `filter` / `onEach` |
| 去重 / 防抖 | `distinctUntilChanged()` / `debounce(300)` |
| 上游换线程 | `flowOn(Dispatchers.Default)` |
| 上游异常兜底 | `catch { emit(默认值) }` |
| 合并两个流 | `combine(a, b) { x, y -> }` |
| 只要最新一次 | `flatMapLatest { }` |
| 冷流转 UI 状态 | `stateIn(viewModelScope, WhileSubscribed(5000), 初始值)` |

依赖（项目 Kotlin 2.3.21）：

```kotlin
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
```

---

**下一课预告（第 12 课）：Room 本地数据库** —— 本课 `repo.observeUsers()` 返回的 `Flow<List<User>>` 从哪来？答案是 Room：DAO 直接返回 Flow，数据库一变，界面自动刷新。
