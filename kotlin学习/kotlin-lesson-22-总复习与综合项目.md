# Kotlin 第 22 课：总复习与综合项目

> 适用读者：已完成第 1～21 课。
> 核心收获：把 21 课串成一张地图，看清现代 Android 应用的分层架构，把 Compose + ViewModel + Room + Retrofit + Hilt + Navigation 组装成一个完整的"用户列表 App"，对照技能清单确认掌握情况，知道接下来往哪走。

---

## 一、21 课全景地图 ⭐

| 阶段 | 课 | 主题 | 一句话 |
|---|---|---|---|
| **语言基础** | 1 | 变量、函数、Null 安全 | 默认 `val`，`?.` + `?:`，少用 `!!` |
| | 2 | 类、data class、object | 数据模型用 `data class`，单例用 `object` |
| | 3 | 扩展函数 | 给任何类加方法；静态解析，无多态 |
| | 4 | Lambda、高阶函数、集合 | 尾随 Lambda，`filter/map` 链式 |
| | 5 / 5b | `when`、密封类、作用域函数、循环 | 密封类 + `when` 免 else；let 判空 apply 配置 |
| | 6 | 面向对象进阶 | 默认 final，双层 `open`；接口带默认实现 |
| | 7 | 泛型与型变 | `out` 生产 `in` 消费；`reified` 绕过擦除 |
| **协程** | 8 | 协程入门 | `suspend`、`launch/async`、`withContext` |
| | 11 | 协程进阶、Flow 操作符 | 异常、Supervisor、`debounce/flatMapLatest/stateIn` |
| | 20 | Channel 与并发安全 | 一对一用 Channel；共享状态用 Mutex / 原子 |
| **Android 架构** | 9 | ViewModel | 扛转屏，只装数据不装 View |
| | 10 | LiveData → StateFlow | `asStateFlow()` 只读暴露，`repeatOnLifecycle` 收集 |
| | 12 | Room | DAO 返回 Flow，数据变界面自动刷新 |
| | 13 | Retrofit + Repository | 网络只写库，界面只读库（单一数据源） |
| | 14 | Hilt | `@Inject constructor`，Module 提供第三方类 |
| **Compose UI** | 15 | Compose 入门 | 声明式 UI，Modifier 链，`LazyColumn` |
| | 16 | Compose 状态与 ViewModel | 状态往下传，事件往上抛；Effect 做副作用 |
| | 17 | Navigation | `@Serializable` 路由，传 id 不传对象 |
| **语言进阶** | 18 | 委托 | `by` 后面只要有 `getValue` |
| | 19 | 运算符、inline、DSL | 带接收者的 Lambda 是 DSL 的地基 |
| **质量** | 21 | 测试 | `runTest` 虚拟时间，Fake + Turbine |

另有第 0 课《前六课回顾》可随时翻语言基础。

## 二、整体架构

```mermaid
flowchart TD
    subgraph UI["UI 层（第 15～17 课）"]
        A[MainActivity<br/>@AndroidEntryPoint] --> N[AppNavHost<br/>Navigation Compose]
        N --> LS[UserListScreen]
        N --> DS[UserDetailScreen]
    end

    subgraph VM["状态层（第 9～11、16 课）"]
        LVM[UserListViewModel<br/>StateFlow&lt;UiState&gt;]
        DVM[UserDetailViewModel<br/>SavedStateHandle.toRoute]
    end

    subgraph DATA["数据层（第 12～14 课）"]
        R[UserRepository<br/>单一数据源]
        DAO[(Room<br/>UserDao)]
        API[Retrofit<br/>UserApi]
    end

    LS -- collectAsStateWithLifecycle --> LVM
    DS -- collectAsStateWithLifecycle --> DVM
    LS -- 事件 onRefresh / onUserClick --> LVM
    LVM --> R
    DVM --> R
    R -- Flow 读取 --> DAO
    R -- refresh 拉取 --> API
    API -- 写入 upsertAll --> DAO

    H[Hilt SingletonComponent<br/>第 14 课] -.注入.-> R
    H -.注入.-> DAO
    H -.注入.-> API
```

三条规则贯穿全系列：

1. **单向数据流**：状态从下往上流到界面（Room → Repository → ViewModel → Composable），事件从界面往下（点击 → ViewModel → Repository）。
2. **单一数据源**：界面只读 Room；网络结果先写库，再由 Flow 带回界面。
3. **依赖倒置**：上层依赖接口（`UserRepository`），具体实现由 Hilt 注入，测试时换 Fake（第 21 课）。

口诀：**数据往上流，事件往下走；界面只读库，网络只写库；依赖靠注入，测试换 Fake。**

## 三、项目结构

```
app/src/main/java/com/example/users/
├── App.kt                       // @HiltAndroidApp（第 14 课）
├── MainActivity.kt              // @AndroidEntryPoint + setContent（第 15 课）
├── data/
│   ├── local/                   // UserEntity、UserDao、AppDatabase（第 12 课）
│   ├── remote/                  // UserDto、UserApi（第 13 课）
│   ├── UserRepository.kt        // 接口 + DefaultUserRepository
│   └── Mappers.kt               // toEntity / toDomain（第 3 课扩展函数）
├── di/
│   ├── NetworkModule.kt         // @Provides Retrofit / OkHttp / Json
│   ├── DatabaseModule.kt        // @Provides AppDatabase / UserDao
│   └── RepositoryModule.kt      // @Binds
├── domain/
│   └── User.kt                  // 领域模型 data class
└── ui/
    ├── UiState.kt               // sealed interface（第 5、7、13 课）
    ├── navigation/AppNavHost.kt // @Serializable 路由（第 17 课）
    ├── list/UserListScreen.kt + UserListViewModel.kt
    └── detail/UserDetailScreen.kt + UserDetailViewModel.kt
app/src/test/.../UserListViewModelTest.kt + FakeUserRepository.kt   // 第 21 课
```

## 四、版本目录（本系列最终版本）

```toml
# gradle/libs.versions.toml
[versions]
agp = "9.4.1"
kotlin = "2.3.21"
ksp = "2.3.12"
composeBom = "2026.09.00"
activity = "1.13.0"
lifecycle = "2.11.0"
navigation = "2.10.2"
room = "2.8.5"
retrofit = "3.0.0"
okhttp = "5.5.1"
serialization = "1.12.0"
hilt = "2.60.1"
androidxHilt = "1.4.0"
coroutines = "1.11.0"
turbine = "1.2.1"
junit = "4.13.2"
```

AGP 9 内置 Kotlin 编译，所以没有 `kotlin-android` 插件；Compose、序列化、KSP、Room、Hilt 插件仍需显式声明（第 12～15 课）。

## 五、组装：把各课代码接起来

各层的完整代码分别在第 12（Room）、13（Retrofit、Repository、UiState）、14（Hilt Module）、16（Screen）、17（NavHost、详情 ViewModel）课。这里只写"胶水"：

```kotlin
@HiltAndroidApp
class App : Application()

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme { AppNavHost() }
        }
    }
}

@Composable
fun AppNavHost(navController: NavHostController = rememberNavController()) {
    NavHost(navController, startDestination = UserListRoute) {
        composable<UserListRoute> {
            UserListScreen(onUserClick = { id -> navController.navigate(UserDetailRoute(id)) {
                launchSingleTop = true
            } })
        }
        composable<UserDetailRoute> {
            UserDetailScreen(onBack = { navController.popBackStack() })
        }
    }
}
```

列表页把第 11 课搜索和第 16 课 Snackbar 合进来：

```kotlin
@Composable
fun UserListScreen(onUserClick: (Long) -> Unit, vm: UserListViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(Unit) { vm.events.collect { snackbar.showSnackbar(it) } }   // 第 20 课 Channel

    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        Column(Modifier.padding(padding)) {
            SearchBar(query = query, onQueryChange = vm::onQueryChange)        // 第 16 课状态提升
            UserListContent(state = state, onRefresh = vm::refresh, onUserClick = onUserClick)
        }
    }
}
```

ViewModel 合体版（第 11、13、20 课的组合）：

```kotlin
@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
@HiltViewModel
class UserListViewModel @Inject constructor(
    private val repo: UserRepository
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _events = Channel<String>(Channel.BUFFERED)
    val events = _events.receiveAsFlow()

    private val refreshing = MutableStateFlow(false)

    val state: StateFlow<UiState<List<User>>> = _query
        .debounce(300)
        .map { it.trim() }
        .distinctUntilChanged()
        .flatMapLatest { q -> if (q.isEmpty()) repo.users else repo.search(q) }
        .combine(refreshing) { users, loading ->
            if (loading && users.isEmpty()) UiState.Loading else UiState.Success(users)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), UiState.Loading)

    init { refresh() }

    fun onQueryChange(text: String) { _query.value = text }

    fun refresh() {                                   // 返回 Unit，才能写 vm::refresh
        viewModelScope.launch {
            refreshing.value = true
            repo.refresh().onFailure { _events.send(it.toUserMessage()) }   // Snackbar 提示
            refreshing.value = false
        }
    }
}
```

这一个类里用到了：Hilt（14）、StateFlow（10）、Flow 操作符（11）、Channel 事件（20）、密封类 UiState（5、13）、`Result`（13）、扩展函数（3）、函数引用和 Lambda（4）。

最后别忘了：`AndroidManifest.xml` 加 `INTERNET` 权限和 `android:name=".App"`（第 13、14 课）。

## 六、技能清单 ⭐

逐项打勾，没把握的回到对应课复习：

**语言**
- [ ] 能分清 `val/var`、可空类型，日常不写 `!!`（1）
- [ ] 数据模型用 `data class` + `copy`，单例用 `object`（2）
- [ ] 能写扩展函数，知道它静态解析（3）
- [ ] 能写高阶函数，熟练使用集合操作符（4）
- [ ] 用密封类 + `when` 建模状态，会选作用域函数（5）
- [ ] 理解 `open/abstract/interface/sealed` 的开放度（6）
- [ ] 能解释 `out/in`，会用 `reified`（7）
- [ ] 理解 `by` 委托，能写自定义委托（18）
- [ ] 能读懂并写出简单 DSL，知道 `inline` 何时用（19）

**协程**
- [ ] 会 `launch/async/withContext`，知道 `suspend` 不等于后台（8）
- [ ] 正确处理异常，`CancellationException` 不吞（11）
- [ ] 熟练使用 Flow 操作符和 `stateIn`（11）
- [ ] 知道何时用 Channel、Mutex、原子类（20）

**Android**
- [ ] ViewModel 只装状态，不持有 View / Activity（9）
- [ ] StateFlow 私有可变、公开只读，安全收集（10）
- [ ] 能建 Room 表、写 DAO、写迁移（12）
- [ ] 能写 Retrofit 接口，Repository 实现单一数据源（13）
- [ ] 能用 Hilt 注入 ViewModel、Repository、第三方库（14）
- [ ] 能用 Compose 搭界面，做状态提升（15、16）
- [ ] 能用类型安全路由做页面跳转和传参（17）
- [ ] 能给 ViewModel 写协程测试（21）

## 七、接下来往哪走

1. **把本课 App 真正跑起来**：照第三节结构建项目，逐层粘入各课代码，再加一个"编辑用户"页面练习写库 + 导航回传（第 17 课第七节）。
2. **读官方示例**：Google 的 *Now in Android*（github.com/android/nowinandroid）用的正是本系列这套架构，规模更大，适合对照学习。
3. **Kotlin Multiplatform（KMP）**：同一份 Kotlin 业务代码（Repository、ViewModel、Flow）跑在 Android、iOS、桌面、Web。Room、Lifecycle ViewModel、kotlinx.serialization、协程都已支持多平台，本系列的数据层知识可以直接迁移。入口：kotlinlang.org/docs/multiplatform.html。
4. **Compose Multiplatform**：JetBrains 把 Compose 带到 iOS、桌面和 Web，第 15～16 课的 UI 写法基本通用。入口：jetbrains.com/compose-multiplatform。
5. **Navigation 3 / Ktor**：新项目可试 `androidx.navigation3`（第 17 课）；用 Ktor 写后端，协程知识完全复用。
6. **随手查**：Kotlin 官方文档 kotlinlang.org/docs、Android 开发者文档 developer.android.com、Kotlin Koans（kotlinlang.org/docs/koans.html）做小练习保持手感。

---

**全系列完结。** 从第 1 课的 `val name = "Android"`，到能独立搭一个分层、可测试的 Compose 应用——Kotlin 主线到此学完。之后遇到新库、新 API，都能按"它属于哪一层、状态怎么流、依赖怎么注入"这套框架去理解。
