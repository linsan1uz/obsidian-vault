# Kotlin 第 15 课：Compose 入门

> 适用读者：已完成第 12～14 课（Room、Retrofit、Hilt），数据层已齐。
> 核心收获：理解"声明式 UI"，会写 `@Composable` 函数，用 `Column/Row/Box` + `Modifier` 布局，用 `Text/Button/TextField/LazyColumn` 搭出用户列表界面，配好 Compose BOM 和 Compose 编译器插件，会用 `@Preview` 预览。

---

## 一、为什么是 Compose？⭐

前面一直用 XML 布局 + `findViewById`：

```kotlin
// 命令式：数据变了，你要亲手去改每个 View
vm.count.collect { count ->
    countText.text = count.toString()
    resetButton.isEnabled = count > 0
}
```

**Compose 是声明式 UI**：你只描述"数据是这样时，界面长这样"，数据变了，Compose 自动重新执行相关函数、更新界面：

```kotlin
@Composable
fun Counter(count: Int, onAdd: () -> Unit) {
    Column {
        Text("点了 $count 次")
        Button(onClick = onAdd, enabled = count < 10) { Text("+1") }
    }
}
```

- 不再有 XML、`findViewById`、`ViewBinding`，界面就是 Kotlin 函数。
- 第 4 课的 Lambda、第 19 课会讲的"带接收者的 Lambda"是 Compose 的语法基础。
- 第 10～11 课的 StateFlow 可以直接喂给界面（第 16 课）。

口诀：**XML 是"去改 View"，Compose 是"描述界面"；数据驱动，界面自己刷新。**

## 二、配置：BOM + Compose 编译器插件（AGP 9）

Kotlin 2.0 起，Compose 编译器随 Kotlin 一起发布，用插件 `org.jetbrains.kotlin.plugin.compose`，**版本号 = 项目 Kotlin 版本**。AGP 9 内置 Kotlin 编译，但**这个插件仍要显式加**。

```kotlin
// 根 build.gradle.kts
plugins {
    id("com.android.application") version "9.4.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21" apply false   // = Kotlin 版本
}

// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    buildFeatures { compose = true }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")                    // 不写版本，BOM 统一管
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")       // @Preview 渲染
    implementation("androidx.activity:activity-compose:1.13.0") // setContent
}
```

**BOM（Bill of Materials）**：一个"版本清单"。引入后，Compose 各库不写版本号，由 BOM 保证彼此兼容（2026.09.00 对应 ui 1.12.1、material3 1.4.0）。

## 三、`setContent` 与 `@Composable`

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {                       // 替代 setContentView(R.layout.xxx)
            MaterialTheme {
                Greeting(name = "Jerry")
            }
        }
    }
}

@Composable
fun Greeting(name: String) {
    Text(text = "你好，$name")
}
```

`@Composable` 函数的规则：

- 函数名**大写开头**（像类名），表示"一块界面"。
- **没有返回值**：它不是"返回一个 View"，而是"把界面发射出去"。
- **只能在其他 `@Composable` 里调用**，和第 8 课 `suspend` 只能在协程里调是一个道理。
- 参数就是这块界面依赖的数据。

## 四、布局：`Column` / `Row` / `Box`

| 组件 | 排列方式 | 对应 XML |
|---|---|---|
| `Column` | 竖着排 | `LinearLayout vertical` |
| `Row` | 横着排 | `LinearLayout horizontal` |
| `Box` | 叠在一起 | `FrameLayout` |

```kotlin
@Composable
fun UserRow(user: User) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier.size(40.dp).background(Color.LightGray, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(user.name.take(1))                     // 头像：名字首字
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(user.name, style = MaterialTheme.typography.titleMedium)
            Text(user.email, style = MaterialTheme.typography.bodySmall)
        }
    }
}
```

`Column { ... }` 后面的大括号是**尾随 Lambda**（第 4 课），里面写子元素。

## 五、`Modifier`：尺寸、间距、点击、背景 ⭐

几乎每个组件都有 `modifier` 参数，用**链式调用**叠加效果：

```kotlin
Text(
    text = user.name,
    modifier = Modifier
        .fillMaxWidth()                 // 占满宽度
        .clickable { onClick(user) }    // 可点击
        .padding(16.dp)                 // 内边距
        .background(Color.White)
)
```

**顺序有意义**：Modifier 从外到内依次包裹。

```kotlin
Modifier.padding(16.dp).clickable { }   // 先留边距，再设点击：边距区域点不到
Modifier.clickable { }.padding(16.dp)   // 先设点击，再留边距：整块都能点 ✅ 列表项常用
```

约定：**自定义 Composable 的第一个可选参数写 `modifier: Modifier = Modifier`**，让调用方能从外面调整：

```kotlin
@Composable
fun UserRow(user: User, modifier: Modifier = Modifier) {
    Row(modifier = modifier.padding(16.dp)) { /* ... */ }
}
```

口诀：**Modifier 链从外往里包；点击放前面，整块都能点。**

## 六、基础组件：`Text` / `Button` / `TextField`

```kotlin
Text("标题", fontSize = 20.sp, fontWeight = FontWeight.Bold)

Button(onClick = { onRefresh() }) {
    Text("刷新")                               // 按钮里放什么由你决定
}

var query by remember { mutableStateOf("") }  // 第 16 课细讲，先照抄
OutlinedTextField(
    value = query,
    onValueChange = { query = it },            // 输入时回调，你负责更新 value
    label = { Text("搜索用户") },
    singleLine = true
)
```

`TextField` 不会自己存文字：**`value` 显示什么、`onValueChange` 收到新文字后改不改，都由你决定**。只写 `value = ""` 不处理回调，打字没反应——这就是声明式："界面 = 状态的样子"。

## 七、`LazyColumn`：列表 ⭐

替代 `RecyclerView` + `Adapter` + `ViewHolder`：

```kotlin
@Composable
fun UserList(users: List<User>, onUserClick: (User) -> Unit, modifier: Modifier = Modifier) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 8.dp)
    ) {
        item { Text("共 ${users.size} 人", Modifier.padding(16.dp)) }   // 单个头部
        items(users, key = { it.id }) { user ->                         // ⭐ key 用稳定 id
            UserRow(
                user = user,
                modifier = Modifier.clickable { onUserClick(user) }
            )
            HorizontalDivider()
        }
    }
}
```

- **Lazy**：只组合屏幕上看得见的项，滚动时复用，几千条也不卡。
- `key = { it.id }`：数据增删、排序时 Compose 能认出"哪一项还是那一项"，动画和状态不会错位。和第 12 课 Room 主键对应。
- `LazyRow` 横向列表，`LazyVerticalGrid` 网格，用法相同。
- **不要**在 `Column` 里用 `forEach` 放几百条数据，它会一次性全部组合。

## 八、`@Preview`：不跑 App 就看界面

```kotlin
@Preview(showBackground = true)
@Composable
private fun UserListPreview() {
    MaterialTheme {
        UserList(
            users = listOf(User(1, "Jerry", "j@x.com"), User(2, "Tom", "t@x.com")),
            onUserClick = {}
        )
    }
}
```

- Android Studio 右侧直接渲染，改代码即时刷新。
- Preview 函数**不能有参数**（要用 `@PreviewParameter` 才行），所以给它传假数据。
- 这也逼你把 Composable 写成"只吃参数"的形式：不直接依赖 ViewModel，才好预览——第 16 课状态提升的核心思想。

## 九、易错点

1. **忘了加 `org.jetbrains.kotlin.plugin.compose` 插件或 `buildFeatures.compose = true`**：编译报错，`@Composable` 无法处理。插件版本必须等于 Kotlin 版本（2.3.21）。
2. **Compose 库各写各的版本号**：容易不兼容。用 BOM 统一。
3. **在普通函数里调 `@Composable`**：编译报错。只能在 Composable 或 `setContent { }` 里调。
4. **Modifier 顺序写反**：`padding` 在 `clickable` 前面，边距区域点不到。
5. **自定义组件不暴露 `modifier` 参数**：调用方没法调整外边距、尺寸。
6. **`TextField` 只给 `value`，`onValueChange` 不更新状态**：打字没反应。
7. **`LazyColumn` 不写 `key`**：删除、排序时项状态错位。
8. **长列表用 `Column` + `forEach`**：全部一次组合，卡顿。用 `LazyColumn`。
9. **`dp` 和 `sp` 混用**：尺寸、间距用 `dp`，文字大小用 `sp`。

## 十、对照速查表

| XML / View | Compose |
|---|---|
| `setContentView(R.layout.x)` | `setContent { MaterialTheme { ... } }` |
| `LinearLayout vertical/horizontal` | `Column` / `Row` |
| `FrameLayout` | `Box` |
| `TextView` / `Button` / `EditText` | `Text` / `Button` / `OutlinedTextField` |
| `RecyclerView` + Adapter | `LazyColumn { items(list, key = { it.id }) { } }` |
| `layout_width="match_parent"` | `Modifier.fillMaxWidth()` |
| `padding` / `onClick` / `background` | `Modifier.padding()` / `.clickable { }` / `.background()` |
| 布局预览 | `@Preview @Composable fun XxxPreview()` |
| 依赖版本 | `platform("androidx.compose:compose-bom:2026.09.00")` |

---

**下一课预告（第 16 课）：Compose 状态与 ViewModel** —— `remember`、`mutableStateOf` 到底是什么，什么叫"重组"，怎样用 `collectAsStateWithLifecycle()` 把第 13～14 课 `UserListViewModel` 的 StateFlow 接到本课的 `UserList` 上。
