# Kotlin 第 30 课：Deep Link 与启动流程

> 适用读者：已完成第 17 课（Navigation Compose）和第 26 课（PendingIntent / 通知点击）。
> 核心收获：为 Compose Navigation 配置 deep link；在 Manifest 写 intent-filter；理解 App Links 与自定义 scheme；用 SplashScreen API 做合规启动页。

---

## 一、Deep Link 是什么？

**Deep Link**：用一个 URI 直接打开 App 里的某一页（而不是只到桌面图标对应的默认 Activity）。

常见来源：

- 通知点击（第 26 课 PendingIntent）
- 短信 / 邮件 / 网页链接
- 别的 App 的 `startActivity(Intent.ACTION_VIEW, uri)`

| 类型 | 例子 | 说明 |
|---|---|---|
| 自定义 scheme | `myapp://user/42` | 实现简单；可能与别的 App 冲突 |
| HTTPS App Link | `https://example.com/user/42` | 需域名 + `assetlinks.json` 验证，体验最好 |
| 意图动作 | 自定义 action | 较少给"打开某页"用 |

本课以 **Navigation deepLinks + intent-filter** 为主；App Links 验证步骤点到为止。

## 二、依赖

```kotlin
dependencies {
    implementation("androidx.navigation:navigation-compose:2.10.2")   // 第 17 课
    implementation("androidx.core:core-splashscreen:1.2.0")
}
```

## 三、Navigation 声明 deepLink ⭐

延续第 17 课的类型安全路由：

```kotlin
@Serializable
data class UserDetailRoute(val userId: Long)

NavHost(navController, startDestination = UserListRoute) {
    composable<UserListRoute> { UserListScreen(...) }

    composable<UserDetailRoute>(
        deepLinks = listOf(
            navDeepLink<UserDetailRoute>(
                basePath = "https://example.com/user"
                // 生成 https://example.com/user/{userId}
            ),
            navDeepLink<UserDetailRoute>(
                basePath = "myapp://user"
            )
        )
    ) {
        UserDetailScreen(...)
    }
}
```

若你项目仍用字符串路由：

```kotlin
composable(
    route = "user/{userId}",
    arguments = listOf(navArgument("userId") { type = NavType.LongType }),
    deepLinks = listOf(
        navDeepLink { uriPattern = "https://example.com/user/{userId}" },
        navDeepLink { uriPattern = "myapp://user/{userId}" }
    )
) { ... }
```

外链进来时，Navigation 会解析参数并**直接把目标页放到返回栈**（可配 `NavController.handleDeepLink` 行为）。`NavHost` 所在 Activity 必须能收到该 VIEW Intent。

## 四、Manifest：`intent-filter`

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop">   <!-- 已存在时走 onNewIntent，避免多实例 -->

    <!-- 桌面启动 -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>

    <!-- 自定义 scheme -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="myapp"
            android:host="user"
            android:pathPrefix="/" />
    </intent-filter>

    <!-- HTTPS App Link（还需网站 Digix 验证） -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="https"
            android:host="example.com"
            android:pathPrefix="/user" />
    </intent-filter>
</activity>
```

Activity 侧把新 Intent 交给 Navigation：

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()   // 见第五节；须在 super.onCreate 前
        super.onCreate(savedInstanceState)
        setContent {
            val navController = rememberNavController()
            // NavHost(...)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // 若持有 navController 引用：navController.handleDeepLink(intent)
    }
}
```

`singleTop` / `singleTask` + `onNewIntent`：用户已在 App 内再点链接时，不会叠多个 MainActivity。

## 五、App Links 验证（概要）

`android:autoVerify="true"` 时，系统会访问：

```
https://example.com/.well-known/assetlinks.json
```

文件需声明你的包名与签名证书 SHA-256。验证通过后，链接**直接进 App**，不再弹"用浏览器还是 App"。细节见官方 App Links 文档；本课能配 filter + Navigation 即达标。

调试：`adb shell am start -a android.intent.action.VIEW -d "myapp://user/42"`。

## 六、SplashScreen API ⭐

Android 12+ 系统自带启动画面；乱自定义主题窗体容易和系统打架。用官方 AndroidX：

```kotlin
// Application 主题 / Activity 主题
// themes.xml
<style name="Theme.MyApp.Splash" parent="Theme.SplashScreen">
    <item name="windowSplashScreenBackground">@color/brand</item>
    <item name="windowSplashScreenAnimatedIcon">@drawable/ic_splash</item>
    <item name="postSplashScreenTheme">@style/Theme.MyApp</item>
</style>
```

```xml
<activity
    android:name=".MainActivity"
    android:theme="@style/Theme.MyApp.Splash"
    ... />
```

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    val splashScreen = installSplashScreen()
    super.onCreate(savedInstanceState)

    // 可选：等关键数据就绪再关闭（别拖太久）
    var keep = true
    splashScreen.setKeepOnScreenCondition { keep }
    lifecycleScope.launch {
        appContainer.warmUp()          // 读 DataStore、预热 DB 等
        keep = false
    }

    setContent { /* ... */ }
}
```

原则：

- **快**：启动屏不是广告位；长时间阻塞会被用户反感，也可能触发 ANR 观感。
- 品牌露出靠图标 + 背景即可。
- 逻辑初始化能延后到首帧之后的，不要塞进 `keep` 条件。

## 七、和通知、冷热启动的关系

1. **冷启动 + 通知 deep link**：进程不在 → 启 Activity → Intent 带 URI → Navigation 解析到详情。
2. **热启动**：Activity 在 → `onNewIntent` → `handleDeepLink`。
3. **只想打开列表再手动进详情**：PendingIntent 可只指向 `MainActivity` 不带 URI；带 URI 则直达。

返回栈：从外链直达详情时，按返回键是否应回到列表？可用 `navOptions { popUpTo(...) }` 或在 graph 里设 `startDestination` 与 deep link 默认行为；产品定，技术跟。

## 八、易错点

1. **只写了 `navDeepLink` 没写 Manifest filter**：系统根本不会把 URI 交给你。
2. **`exported="false"` 又想收外部 VIEW**：外部无法拉起。
3. **HTTPS filter 未验证**：用户每次被追问打开方式；或仍进浏览器。
4. **`launchMode` 默认 standard 导致多实例**：返回栈混乱。常用 `singleTop`。
5. **`installSplashScreen()` 放在 `super.onCreate` 之后**：官方要求之前调用。
6. **启动屏里做重网络**：拖慢首启；改为进首页后再加载（第 13 课刷新模式）。
7. **路由参数类型与 URI 不一致**：解析失败，落在 startDestination。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| Nav deep link | `composable<Route>(deepLinks = listOf(navDeepLink(...)))` |
| Manifest | `intent-filter` + `VIEW` + `BROWSABLE` + `data` |
| 调试 | `adb shell am start -a VIEW -d "myapp://user/42"` |
| 热启动 | `singleTop` + `onNewIntent` + `handleDeepLink` |
| Splash 依赖 | `core-splashscreen:1.2.0` |
| 安装闪屏 | `installSplashScreen()` 在 `super.onCreate` 前 |
| 主题 | `Theme.SplashScreen` → `postSplashScreenTheme` |

## 十、本课练习

1. 为 `UserDetailRoute` 加 `myapp://user/{id}`，Manifest 写好 filter，用 adb 验证直达详情。
2. 从通知 PendingIntent 带上同一 URI，冷启动确认能打开对应用户。
3. 接上 SplashScreen：主题换品牌色，`setKeepOnScreenCondition` 最多保持 500ms 的假 warmUp。

---

**本批收尾**：第 23～30 课补齐 Paging、WorkManager、DataStore、权限通知、多模块、Fragment、Compose UI 测试、Deep Link。可与第 22 课综合项目对照，按需把分页 / 后台同步 / 设置存储加进用户列表 App。
