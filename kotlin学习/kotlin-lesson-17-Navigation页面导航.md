# Kotlin 第 17 课：Navigation 页面导航

> 适用读者：已完成第 15、16 课（Compose、状态提升、`hiltViewModel()`）和第 13 课（kotlinx.serialization）。
> 核心收获：用 Navigation Compose + `@Serializable` 路由做**类型安全**导航，传参、在 ViewModel 里用 `SavedStateHandle.toRoute()` 取参数，管理返回栈，完成"用户列表 → 用户详情"。

---

## 一、为什么需要 Navigation

Compose 里一个 Activity 就能装下整个 App，"页面"只是不同的 Composable。自己用 `if (screen == ...)` 切换的话，要手写：返回键处理、返回栈、参数传递、转屏后恢复在哪一页、每页的 ViewModel 生命周期……

**Navigation Compose** 把这些全包了：

- **NavController**：管返回栈，负责 `navigate` / `popBackStack`。
- **NavHost**：声明"有哪些页面"，显示栈顶那一页。
- **路由（Route）**：每个页面的"地址"。

旧写法用字符串路由 `"user/{id}"`，参数名拼错只有运行时才发现。Navigation 2.8 起支持**用 `@Serializable` 类当路由**，编译期检查——本课只教这种。

## 二、配置

```kotlin
// app/build.gradle.kts（序列化插件第 13 课已加）
dependencies {
    implementation("androidx.navigation:navigation-compose:2.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("androidx.hilt:hilt-lifecycle-viewmodel-compose:1.4.0")   // 第 16 课
}
```

**关于 Navigation 3**：Google 另有一套全新的 `androidx.navigation3`（已出 1.2.0 稳定版），思路是"返回栈就是你自己持有的一个 List，`NavDisplay` 负责显示"。它更灵活，适合新项目和大屏多窗格。但目前教程、示例、现有项目主流仍是 Navigation Compose 2.x，本课先学它；两者概念（路由、返回栈、按页面划分 ViewModel）相通，以后迁移不难。

## 三、定义路由 ⭐

```kotlin
@Serializable
object UserListRoute                          // 无参数页面：object（第 2 课）

@Serializable
data class UserDetailRoute(val userId: Long)  // 有参数页面：data class，参数就是属性

@Serializable
data class EditUserRoute(val userId: Long, val focusEmail: Boolean = false)  // 可带默认值
```

- 路由类**只放简单参数**：基本类型、String、枚举，以及它们的可空、默认值形式。
- **不要传整个 `User` 对象**：传 id，目标页自己去 Repository / Room 取。原因：对象可能很大、会过时，进程恢复时还要能从 Bundle 重建。

口诀：**路由传 id，不传对象；数据从单一数据源再取。**

## 四、NavHost：声明页面

```kotlin
@Composable
fun AppNavHost(navController: NavHostController = rememberNavController()) {
    NavHost(navController = navController, startDestination = UserListRoute) {

        composable<UserListRoute> {
            UserListScreen(
                onUserClick = { id -> navController.navigate(UserDetailRoute(id)) }
            )
        }

        composable<UserDetailRoute> { backStackEntry ->
            val route: UserDetailRoute = backStackEntry.toRoute()    // 取参数
            UserDetailScreen(
                userId = route.userId,
                onBack = { navController.popBackStack() }
            )
        }
    }
}

// MainActivity（@AndroidEntryPoint）
setContent { MaterialTheme { AppNavHost() } }
```

- `composable<T> { }`：注册一个页面，泛型就是路由类型（第 7 课泛型 + reified 的实际应用）。
- `navigate(UserDetailRoute(id))`：**直接 new 路由对象**，参数类型错了编译不过。
- **Screen 不直接拿 `navController`**，只暴露 `onUserClick`、`onBack` 回调——第 16 课状态提升，页面才能单独预览和测试。

## 五、在 ViewModel 里取参数 ⭐

详情页的 ViewModel 需要 `userId` 去查数据。`hiltViewModel()` 在 NavHost 里会**按页面（NavBackStackEntry）创建 ViewModel**，并把路由参数放进 `SavedStateHandle`：

```kotlin
@HiltViewModel
class UserDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,             // 第 9 课，Hilt 自动提供
    private val repo: UserRepository
) : ViewModel() {

    private val route = savedStateHandle.toRoute<UserDetailRoute>()   // ⭐ 类型安全取参

    val user: StateFlow<User?> = repo.observeUser(route.userId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)
}

@Composable
fun UserDetailScreen(onBack: () -> Unit, vm: UserDetailViewModel = hiltViewModel()) {
    val user by vm.user.collectAsStateWithLifecycle()
    UserDetailContent(user = user, onBack = onBack)
}
```

Repository / DAO 补一个按 id 观察的方法（第 12～13 课）：

```kotlin
@Query("SELECT * FROM users WHERE id = :id")
fun observeById(id: Long): Flow<UserEntity?>

fun observeUser(id: Long): Flow<User?> = dao.observeById(id).map { it?.toDomain() }
```

有了 ViewModel 取参，第四节的 `UserDetailScreen` 就不用再传 `userId`。两种方式选一种：**简单页面用 `backStackEntry.toRoute()` 传给 Composable；要加载数据的页面让 ViewModel 用 `SavedStateHandle.toRoute()` 自己取**（推荐，转屏、进程恢复都安全）。

ViewModel 作用域：每个返回栈条目一个。从列表进详情 A，再返回，详情 A 的 ViewModel `onCleared()`；列表的 ViewModel 一直都在。

## 六、返回栈操作

```
navigate(Detail(1))        [List, Detail(1)]
navigate(Detail(2))        [List, Detail(1), Detail(2)]
popBackStack()             [List, Detail(1)]
```

```kotlin
navController.popBackStack()                  // 弹出栈顶，等于按返回键
navController.navigateUp()                    // 顶部栏"←"按钮

// 去首页，并清掉中间页（比如编辑完成后回列表）
navController.navigate(UserListRoute) {
    popUpTo<UserListRoute> { inclusive = false }   // 弹到 UserListRoute 为止，保留它
    launchSingleTop = true                         // 栈顶已经是它就不重复创建
}

// 登录成功后去首页，并把登录页从栈里删掉
navController.navigate(UserListRoute) {
    popUpTo<LoginRoute> { inclusive = true }
}
```

| 选项 | 作用 |
|---|---|
| `popUpTo<T>` | 导航前，先把栈弹到 T |
| `inclusive = true` | 连 T 自己一起弹掉 |
| `launchSingleTop` | 目标已在栈顶就不重复入栈（防止连点打开两次） |
| `restoreState` / `saveState` | 底部导航栏切 Tab 时保留各 Tab 的状态 |

系统返回键由 NavHost 自动处理，不用写 `onBackPressed`。

## 七、详情页回传结果（简要）

编辑页保存后让上一页知道，最干净的做法是**不回传**：编辑页写 Room → 列表页本来就在观察 Room 的 Flow → 自动刷新（第 13 课单一数据源）。

确实要回传临时值时，用上一页的 `SavedStateHandle`：

```kotlin
// 编辑页
navController.previousBackStackEntry?.savedStateHandle?.set("saved", true)
navController.popBackStack()

// 列表页
val saved by navController.currentBackStackEntry!!.savedStateHandle
    .getStateFlow("saved", false).collectAsStateWithLifecycle()
```

## 八、易错点

1. **路由类忘加 `@Serializable`**：运行时崩溃，找不到序列化器。
2. **路由里传 `User` 对象 / List**：不支持复杂类型（或要自定义 NavType），而且违背单一数据源。传 id。
3. **把 `navController` 一路传进 Screen 和 ViewModel**：难预览难测试，ViewModel 还可能泄漏。Screen 暴露回调，NavHost 里调 `navigate`。
4. **在 Composable 函数体里直接 `navigate`**：每次重组都跳一次。只在回调里，或 `LaunchedEffect` 收到导航事件时跳。
5. **连点列表项打开两个详情页**：加 `launchSingleTop = true`，或在 ViewModel 里防抖。
6. **`rememberNavController()` 写在 NavHost 内部的页面里**：每页一个新 controller，导航失效。在最外层创建一次。
7. **`popUpTo` 的 `inclusive` 搞反**：要么删多了首页，要么登录页没删掉，按返回又回登录页。
8. **以为 `toRoute()` 能在非导航创建的 ViewModel 里用**：`SavedStateHandle` 里没有路由参数。ViewModel 要在 NavHost 的 `composable { }` 里用 `hiltViewModel()` 创建。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 无参页面 | `@Serializable object UserListRoute` |
| 带参页面 | `@Serializable data class UserDetailRoute(val userId: Long)` |
| 创建控制器 | `val navController = rememberNavController()` |
| 声明页面 | `NavHost(navController, startDestination = UserListRoute) { composable<T> { } }` |
| 跳转 | `navController.navigate(UserDetailRoute(id))` |
| Composable 里取参 | `backStackEntry.toRoute<UserDetailRoute>()` |
| ViewModel 里取参 | `savedStateHandle.toRoute<UserDetailRoute>()` |
| 返回 | `popBackStack()` / `navigateUp()` |
| 清栈跳转 | `navigate(X) { popUpTo<Y> { inclusive = true }; launchSingleTop = true }` |
| 依赖 | `androidx.navigation:navigation-compose:2.10.2` |

---

**下一课预告（第 18 课）：委托** —— 一路写过的 `by lazy`、`by viewModels()`、`by remember { mutableStateOf() }`，背后都是同一个关键字 `by`。下一课拆开它，并自己写一个委托。
