# Kotlin 第 29 课：Compose UI 测试

> 适用读者：已完成第 15～16 课（Compose、状态提升）和第 21 课（ViewModel 单元测试、Turbine）。
> 核心收获：用 `createComposeRule` / `createAndroidComposeRule` 写 UI 测试；靠语义（Semantics）与 `testTag` 找节点；和 VM 单测分工清楚。

---

## 一、和第 21 课怎么分工？

| 层级 | 测什么 | 放哪 | 工具 |
|---|---|---|---|
| ViewModel / Repository | 状态流转、错误、刷新 | `src/test`（JVM） | JUnit、`runTest`、Turbine、Fake |
| Compose UI | 文本是否显示、按钮能否点、错误态 UI | `src/androidTest` | Compose Test |

口诀：**逻辑进单测；"屏幕上看起来对不对"进 UI 测。**  
UI 测更慢，只覆盖关键路径；能在 VM 测清的别堆到 UI。

第 16 课强调把 `UserListContent(state, onRetry)` 做成**无状态**：UI 测时直接塞假状态，不必起 Hilt / 真网络。

## 二、依赖

```kotlin
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")  // 测试用 Activity 清单
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
```

版本跟 BOM（第 15 课 `2026.09.00` → ui 1.12.1 一带）。跑在模拟器 / 真机上（instrumented）。

## 三、第一条测试 ⭐

```kotlin
class UserListContentTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun 成功态显示用户名() {
        composeRule.setContent {
            MaterialTheme {
                UserListContent(
                    state = UiState.Success(listOf(User(1, "Jerry"))),
                    onRetry = {}
                )
            }
        }
        composeRule.onNodeWithText("Jerry").assertIsDisplayed()
    }

    @Test
    fun 错误态点击重试() {
        var retried = false
        composeRule.setContent {
            UserListContent(
                state = UiState.Error("网络错误"),
                onRetry = { retried = true }
            )
        }
        composeRule.onNodeWithText("重试").performClick()
        assertTrue(retried)
    }
}
```

- `createComposeRule()`：不启你的 Activity，只测 Composable——**首选**。
- `createAndroidComposeRule<MainActivity>()`：要测 Activity 级导航 / 权限时再用。

## 四、语义（Semantics）：测试如何"看见"控件

Compose 测试不靠 Android View id，而靠**语义树**：文本、角色、是否可点击、自定义属性。

```kotlin
// 常用匹配
composeRule.onNodeWithText("保存")
composeRule.onNodeWithContentDescription("返回")
composeRule.onNodeWithTag("user_list")          // 自定义 testTag
composeRule.onAllNodesWithText("删除")[0]

// 断言
assertIsDisplayed()
assertIsEnabled()
assertIsOff() / assertIsOn()                    // Switch / Checkbox
assertTextEquals("Jerry")

// 操作
performClick()
performTextInput("hello")
performScrollToIndex(20)
```

给列表等无障碍文本的组件打 tag：

```kotlin
LazyColumn(Modifier.testTag("user_list")) { /* ... */ }

// 测试
composeRule.onNodeWithTag("user_list").assertExists()
```

`mergeDescendants`、自定义 `semantics { }` 属于进阶；先把 Text / ContentDescription / testTag 用熟。

## 五、等待异步 UI

UI 测里若状态会延迟更新：

```kotlin
composeRule.onNodeWithTag("loading").assertIsDisplayed()
// 假 VM 发射 Success 后：
composeRule.onNodeWithText("Jerry").assertIsDisplayed()
```

Compose Rule 在多数断言前会**自动等待**重组完成；若仍偶发失败：

```kotlin
composeRule.waitUntil(timeoutMillis = 5_000) {
    composeRule.onAllNodesWithText("Jerry").fetchSemanticsNodes().isNotEmpty()
}
```

真正的时间推进逻辑仍应在第 21 课的 `runTest` 里测，不要在 UI 测里 `Thread.sleep`。

## 六、带 ViewModel 的屏幕怎么测？

优先：**抽无状态 Content + 测 Content**。

若一定要测整页：

```kotlin
@Test
fun 列表屏展示假仓库数据() {
    val fake = FakeUserRepository(users = listOf(User(1, "Jerry")))
    composeRule.setContent {
        val vm = remember { UserListViewModel(fake) }  // 或手动造
        UserListScreen(vm = vm)
    }
    composeRule.onNodeWithText("Jerry").assertIsDisplayed()
}
```

Hilt 的 `@HiltAndroidTest` + 替换 Module 可以，但成本高——留给少量冒烟；日常回归靠 Fake + Content 测试。

## 七、易错点

1. **UI 测里复测全部业务分支**：又慢又脆。分支逻辑放 VM 单测。
2. **靠模糊文本匹配**：多语言 / 改文案就挂。关键控件加 `testTag` 或稳定 contentDescription。
3. **忘记 `ui-test-manifest`**：debug 包缺测试 Activity，跑不起来。
4. **在 JVM `src/test` 写 Compose UI 测**：需要 instrumented，放 `androidTest`。
5. **`onNodeWithText` 找到多个**：改用 tag，或 `onAllNodes` + 下标，或更紧的匹配（`useUnmergedTree`）。
6. **测试里直接依赖真网络**：翻车；Fake / Success 状态注入。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| Rule | `@get:Rule val composeRule = createComposeRule()` |
| 设置 UI | `composeRule.setContent { ... }` |
| 按文本找 | `onNodeWithText("Jerry")` |
| 按 tag 找 | `Modifier.testTag("x")` + `onNodeWithTag("x")` |
| 点击 | `performClick()` |
| 断言可见 | `assertIsDisplayed()` |
| 等待 | `waitUntil { ... }` |
| 依赖 | BOM + `ui-test-junit4` + `ui-test-manifest` |

## 九、本课练习

1. 给 `UserListContent` 的三种 `UiState` 各写一条 UI 测试。
2. 给"重试"按钮加 `Modifier.testTag("retry")`，测试改用 tag 点击。
3. 对比：同一错误分支，VM 单测断言 `UiState.Error`，UI 测断言看到"重试"——体会两层分工。

---

**下一课预告（第 30 课）：Deep Link 与启动流程** —— 外链打开指定页、Intent Filter、SplashScreen API。
