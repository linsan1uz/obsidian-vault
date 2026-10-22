# Kotlin 第 16 课：Compose 状态与 ViewModel

> 适用读者：已完成第 15 课（Compose 基础组件）和第 10、14 课（StateFlow、Hilt）。
> 核心收获：理解"重组"，会用 `remember` / `mutableStateOf` / `rememberSaveable` 管理界面内状态，掌握状态提升，用 `collectAsStateWithLifecycle()` + `hiltViewModel()` 接上 ViewModel，用 `LaunchedEffect` 等处理副作用。

---

## 一、重组：Compose 怎么刷新界面 ⭐

**重组（recomposition）**：Composable 读取的状态变了，Compose **重新调用这个函数**，用新数据算出新界面。

```kotlin
@Composable
fun Counter() {
    var count = 0                            // ❌ 普通变量
    Button(onClick = { count++ }) {
        Text("点了 $count 次")               // 永远显示 0
    }
}
```

两个问题：

1. 普通变量变了，Compose **不知道**，不会重组。
2. 就算重组了，函数重新执行，`var count = 0` 又从 0 开始。

需要两样东西：**能被 Compose 观察的状态**（`mutableStateOf`）+ **跨重组记住它**（`remember`）。

重组的特点：

- **只重组读了该状态的部分**，没变的跳过，所以很快。
- 可能**频繁执行、任意顺序、被中途取消**——所以 Composable 函数体里**不能直接做副作用**（发请求、写数据库、打日志计数），见第六节。

## 二、`remember` + `mutableStateOf`

```kotlin
@Composable
fun Counter() {
    var count by remember { mutableStateOf(0) }    // ⭐ 最常用写法
    Button(onClick = { count++ }) {
        Text("点了 $count 次")
    }
}
```

拆开看：

- `mutableStateOf(0)`：创建一个 `MutableState<Int>`，读它的 `.value` 会被 Compose 记录，写它会触发重组。
- `remember { }`：第一次组合时执行并存起来，之后重组直接返回存好的那个。
- `by`：属性委托（第 18 课细讲），让你直接写 `count` 而不是 `count.value`。需要 `import androidx.compose.runtime.getValue` 和 `setValue`。

其他写法：

```kotlin
val count = remember { mutableStateOf(0) }     // 用 count.value 读写
val (text, setText) = remember { mutableStateOf("") }   // 解构（第 2 课）
val list = remember { mutableStateListOf<String>() }    // 可观察的列表
```

`remember` 也能带 key：`remember(userId) { ... }`，key 变了就重新计算。

## 三、`rememberSaveable`：扛住转屏

`remember` 的值跟着 Composable 走，**Activity 重建（转屏）就丢了**——和第 9 课的问题一模一样。

```kotlin
var query by rememberSaveable { mutableStateOf("") }   // 转屏、进程被杀后恢复都在
```

| | `remember` | `rememberSaveable` | ViewModel |
|---|---|---|---|
| 重组 | ✅ 保留 | ✅ | ✅ |
| 转屏 | ❌ 丢 | ✅ 保留 | ✅ 保留 |
| 进程被杀后恢复 | ❌ | ✅（存进 Bundle） | ❌（除非 SavedStateHandle） |
| 适合 | 动画、临时展开状态 | 输入框文字、选中 Tab | 业务数据、网络结果 |

`rememberSaveable` 只能存 Bundle 能装的类型（基本类型、String、Parcelable）；复杂对象要写 `Saver`。

## 四、状态提升（State Hoisting）⭐

**有状态的 Composable 难复用、难预览、难测试**。做法：把状态"提"到调用方，组件只接收 **值 + 事件回调**。

```kotlin
// ❌ 有状态：搜索框自己存文字，外面拿不到
@Composable
fun SearchBar() {
    var text by remember { mutableStateOf("") }
    OutlinedTextField(value = text, onValueChange = { text = it })
}

// ✅ 无状态：值从上面来，事件往上走
@Composable
fun SearchBar(query: String, onQueryChange: (String) -> Unit, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        label = { Text("搜索用户") },
        modifier = modifier.fillMaxWidth()
    )
}
```

**单向数据流**：

```
ViewModel（状态）──── state ────▶ Screen ──▶ SearchBar / UserList
      ▲                                        │
      └──────────── 事件（onQueryChange）◀──────┘
```

口诀：**状态往下传，事件往上抛；组件只吃参数，不藏状态。** 这和第 9 课"`_count` 私有、对外只读、改值走方法"是同一个思想。

## 五、接上 ViewModel ⭐

### 1. 依赖

```kotlin
implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")        // collectAsStateWithLifecycle
implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")      // viewModel()
implementation("androidx.hilt:hilt-lifecycle-viewmodel-compose:1.4.0")       // hiltViewModel()
```

`hiltViewModel()` 从 androidx.hilt 1.3.0 起放在 `hilt-lifecycle-viewmodel-compose`（包名 `androidx.hilt.lifecycle.viewmodel.compose`）；老教程里的 `hilt-navigation-compose` 是旧位置。

### 2. Screen = 有状态入口，Content = 无状态界面

```kotlin
@Composable
fun UserListScreen(
    onUserClick: (Long) -> Unit,
    vm: UserListViewModel = hiltViewModel()          // 第 14 课 @HiltViewModel
) {
    val state by vm.state.collectAsStateWithLifecycle()   // ⭐ StateFlow → Compose State
    UserListContent(state = state, onRefresh = vm::refresh, onUserClick = onUserClick)
}

@Composable
fun UserListContent(
    state: UiState<List<User>>,
    onRefresh: () -> Unit,
    onUserClick: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    when (state) {                                        // 第 5 课密封类
        UiState.Loading -> Box(modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator()
        }
        is UiState.Error -> Column(modifier) {
            Text(state.message)
            Button(onClick = onRefresh) { Text("重试") }
        }
        is UiState.Success -> UserList(state.data, onUserClick = { onUserClick(it.id) }, modifier = modifier)
    }
}
```

- `collectAsStateWithLifecycle()`：界面不可见时停止收集，等于第 10 课 `repeatOnLifecycle(STARTED)` 的 Compose 版。比 `collectAsState()` 更省资源，Android 上优先用它。
- `hiltViewModel()` 需要所在 Activity 标了 `@AndroidEntryPoint`；没用 Hilt 时用 `viewModel()`（带参数要传 factory）。
- `UserListContent` 只吃参数，可以直接 `@Preview`、可以测试——ViewModel 只出现在最外层。
- `vm::refresh` 是函数引用，等价于 `{ vm.refresh() }`。

## 六、副作用：`LaunchedEffect` 等 ⭐

**副作用** = Composable 之外的事情：弹 Snackbar、发请求、注册监听。不能写在函数体里（重组会反复执行），要用 Effect API：

```kotlin
@Composable
fun UserListScreen(vm: UserListViewModel = hiltViewModel()) {
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {                         // 进入组合时启动一个协程，离开时取消
        vm.events.collect { msg ->                 // 第 10 课 SharedFlow 一次性事件
            snackbarHostState.showSnackbar(msg)    // suspend 函数，必须在协程里
        }
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbarHostState) }) { padding ->
        UserListContent(/* ... */, modifier = Modifier.padding(padding))
    }
}
```

| API | 用途 | 例子 |
|---|---|---|
| `LaunchedEffect(key)` | 进入组合时跑一个协程；key 变了就取消重来 | 收集事件、根据 userId 加载 |
| `rememberCoroutineScope()` | 拿一个协程作用域，在**点击回调里**启动协程 | 点按钮滚动到顶部 |
| `DisposableEffect(key)` | 需要成对的"注册 / 注销" | 注册传感器、生命周期监听 |
| `SideEffect { }` | 每次成功重组后执行 | 把 Compose 状态同步给非 Compose 对象 |
| `derivedStateOf { }` | 由别的状态算出来、变化不频繁的值 | 列表滚动超过第一项才显示"回到顶部" |

```kotlin
val scope = rememberCoroutineScope()
val listState = rememberLazyListState()
Button(onClick = { scope.launch { listState.animateScrollToItem(0) } }) { Text("回到顶部") }
```

key 的选择：`LaunchedEffect(Unit)` 只跑一次；`LaunchedEffect(userId)` 在 userId 变化时重跑。

口诀：**函数体只描述界面；要干活用 Effect。协程跟着组合走，key 变了就重来。**

## 七、易错点

1. **`var x = 0` 当状态**：不触发重组，重组后又归零。用 `remember { mutableStateOf(0) }`。
2. **`mutableStateOf` 没包 `remember`**：每次重组都新建，值永远是初始值。
3. **用 `by` 却缺 import**：报 `getValue` 找不到，补 `androidx.compose.runtime.getValue` / `setValue`。
4. **输入框文字用 `remember`**：转屏就丢。用 `rememberSaveable` 或放进 ViewModel。
5. **在函数体里直接 `vm.load()` / 发请求**：每次重组都发一次。放进 `LaunchedEffect` 或 ViewModel 的 `init`。
6. **把 ViewModel 一路传进底层小组件**：难预览、难复用。只在 Screen 层拿，往下传值和回调。
7. **用 `collectAsState()` 而不是 `collectAsStateWithLifecycle()`**：后台还在收集。
8. **`mutableStateOf(list)` 后直接 `list.add()`**：引用没变，Compose 不知道。用不可变 List 整体替换，或 `mutableStateListOf`。
9. **`LaunchedEffect` 的 key 乱写成会频繁变化的值**：协程不停取消重启。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 界面内状态 | `var x by remember { mutableStateOf(初始值) }` |
| 扛转屏 | `rememberSaveable { mutableStateOf("") }` |
| 可观察列表 | `remember { mutableStateListOf<T>() }` |
| 状态提升 | `fun Bar(value: T, onValueChange: (T) -> Unit)` |
| 收集 StateFlow | `val s by vm.state.collectAsStateWithLifecycle()` |
| 拿 ViewModel | `hiltViewModel()` / `viewModel()` |
| 进入时执行协程 | `LaunchedEffect(key) { ... }` |
| 点击里启动协程 | `val scope = rememberCoroutineScope(); scope.launch { }` |
| 注册 / 注销 | `DisposableEffect(key) { ...; onDispose { } }` |
| 派生状态 | `val show by remember { derivedStateOf { ... } }` |

---

**下一课预告（第 17 课）：Navigation 页面导航** —— 点击列表里的用户，跳到详情页：用 `@Serializable` 定义类型安全的路由，传 id，详情页 ViewModel 用 `SavedStateHandle.toRoute()` 取参数。
