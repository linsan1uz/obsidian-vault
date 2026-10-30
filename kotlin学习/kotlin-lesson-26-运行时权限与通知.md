# Kotlin 第 26 课：运行时权限与通知

> 适用读者：已完成第 15～17 课（Compose / Activity）和第 9 课（生命周期意识）。
> 核心收获：用 Activity Result 合同申请运行时权限；创建通知渠道并用 `NotificationCompat` 弹出通知；在 API 33+ 正确处理 `POST_NOTIFICATIONS`。

---

## 一、权限模型速览

Android 把权限分成：

- **安装时权限**（如 `INTERNET`）：清单声明即可。
- **危险权限**（相机、麦克风、精确位置、通知…）：清单声明 + **运行时向用户申请**。

本课用官方 **`ActivityResultContracts`**，**不推荐**再手写 `onRequestPermissionsResult` 旧回调，也不强制上 Accompanist（其 permissions 库已逐步退役，官方合同足够）。

## 二、依赖

```kotlin
dependencies {
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("androidx.activity:activity-compose:1.13.0")  // 第 15 课已有则不必重复
    implementation("androidx.core:core-ktx:1.19.1")              // NotificationCompat 等
}
```

Compose 里用 `rememberLauncherForActivityResult`；View 体系用 `registerForActivityResult`。

## 三、清单声明（先写再申请）

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
<!-- Android 13 (API 33)+ 发通知必须 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

没在清单声明的权限，运行时申请会直接失败。

## 四、Activity Result 申请权限 ⭐

### View / Activity

```kotlin
class MainActivity : ComponentActivity() {

    private val requestCamera = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) openCamera() else showNeedPermissionRationale()
    }

    private val requestMulti = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val allOk = result.values.all { it }
        if (allOk) startRecorder() else /* 引导去设置 */
    }

    fun onPickPhotoClick() {
        when {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED -> openCamera()
            shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) -> {
                // 用户曾拒绝：先解释为什么需要，再 launch
                explainThen { requestCamera.launch(Manifest.permission.CAMERA) }
            }
            else -> requestCamera.launch(Manifest.permission.CAMERA)
        }
    }
}
```

### Compose

```kotlin
@Composable
fun CameraButton(onGranted: () -> Unit) {
    val context = LocalContext.current
    var showRationale by remember { mutableStateOf(false) }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) onGranted() else showRationale = true
    }

    Button(onClick = {
        when {
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED -> onGranted()
            else -> launcher.launch(Manifest.permission.CAMERA)
        }
    }) { Text("拍照") }

    if (showRationale) {
        AlertDialog(
            onDismissRequest = { showRationale = false },
            title = { Text("需要相机权限") },
            text = { Text("用于拍摄头像，可在系统设置中开启。") },
            confirmButton = {
                TextButton(onClick = {
                    showRationale = false
                    // 可 Intent 到应用设置页
                }) { Text("知道了") }
            }
        )
    }
}
```

流程口诀：**先 check → 已有就干事；否则 launch；被拒就解释或去设置。**

## 五、通知渠道 + `NotificationCompat` ⭐

Android 8.0（API 26）起，通知必须属于某个 **Channel**；用户可在系统设置里按渠道开关。

```kotlin
object NotifyIds {
    const val CHANNEL_SYNC = "sync"
    const val ID_SYNC_OK = 1001
}

fun createNotificationChannels(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val mgr = context.getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(
        NotifyIds.CHANNEL_SYNC,
        "同步消息",                          // 用户可见名称
        NotificationManager.IMPORTANCE_DEFAULT
    ).apply {
        description = "收藏/数据同步完成时的提醒"
    }
    mgr.createNotificationChannel(channel)
}

// Application.onCreate() 里调一次
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels(this)
    }
}
```

发通知：

```kotlin
fun showSyncOk(context: Context, title: String, body: String) {
    val pending = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val notification = NotificationCompat.Builder(context, NotifyIds.CHANNEL_SYNC)
        .setSmallIcon(R.drawable.ic_stat_sync)   // 必须是 monochrome 白底图标
        .setContentTitle(title)
        .setContentText(body)
        .setContentIntent(pending)
        .setAutoCancel(true)
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .build()

    NotificationManagerCompat.from(context).notify(NotifyIds.ID_SYNC_OK, notification)
}
```

## 六、API 33+：`POST_NOTIFICATIONS`

从 Android 13 起，发通知本身也是运行时权限。逻辑：

```kotlin
fun ensureNotificationPermission(
    activity: ComponentActivity,
    launcher: ActivityResultLauncher<String>,
    onReady: () -> Unit
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        onReady()
        return
    }
    val ok = ContextCompat.checkSelfPermission(
        activity, Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED
    if (ok) onReady() else launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

- 清单声明 + 运行时申请，两者缺一不可（API 33+）。
- 用户拒绝后，`notify` 会静默失败（或按厂商表现），应在 UI 上提示"未开启通知"。
- 可用 `NotificationManagerCompat.from(context).areNotificationsEnabled()` 做总开关检查。

## 七、和 WorkManager / 业务的结合

第 24 课 Worker 成功后弹通知是常见模式：

```kotlin
override suspend fun doWork(): Result {
    // ... 同步成功
    if (ApplicationProvider /* 或 applicationContext */ != null) {
        showSyncOk(applicationContext, "同步完成", "收藏已更新")
    }
    return Result.success()
}
```

注意：Worker 里同样受 `POST_NOTIFICATIONS` 约束——若用户没授权，通知出不来，但工作本身仍可 `success`。

## 八、易错点

1. **只改清单不申请运行时**：行为在高版本上直接被拒。
2. **`registerForActivityResult` 在 `onCreate` 之后才调**：必须在 STARTED 前注册（字段初始化 / `onCreate` 早期）。
3. **通知不建 Channel（API 26+）**：通知发不出来。
4. **`setSmallIcon` 用彩色大图**：显示异常；用专用白色状态栏图标。
5. **`PendingIntent` 忘了 `FLAG_IMMUTABLE`**：API 31+ 可能崩。
6. **API 33 不申请 `POST_NOTIFICATIONS`**：渠道都对，就是没有通知。
7. **一进 App 就连环弹权限**：体验差；在用户触发相关功能时再申请。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 检查权限 | `ContextCompat.checkSelfPermission(...)` |
| 申请单个 | `ActivityResultContracts.RequestPermission()` |
| 申请多个 | `RequestMultiplePermissions()` |
| Compose | `rememberLauncherForActivityResult(...)` |
| 建渠道 | `NotificationChannel(id, name, importance)` |
| 发通知 | `NotificationCompat.Builder(ctx, channelId).build()` + `notify` |
| 通知权限 33+ | 清单 + `POST_NOTIFICATIONS` 运行时申请 |
| 是否可通知 | `NotificationManagerCompat.from(ctx).areNotificationsEnabled()` |

## 十、本课练习

1. 给"拍照"按钮接上 `RequestPermission`，拒绝时弹出说明对话框。
2. 在 `Application` 创建同步渠道；点按钮发一条可点进 `MainActivity` 的通知。
3. 在 API 33 模拟器上验证：不授 `POST_NOTIFICATIONS` 时通知不出；授权后正常。

---

**下一课预告（第 27 课）：多模块 Gradle** —— 把越来越大的 `app` 拆成 `feature` / `core`，加快编译、理清依赖。
