# Kotlin 第 24 课：WorkManager 后台任务

> 适用读者：已完成第 8、11 课（协程、`Dispatchers`）和第 13 课（Repository / 网络）。
> 核心收获：分清"进程内协程"和"可持久化后台任务"；会写 `CoroutineWorker`；配置 `OneTime` / `Periodic`、约束条件、唯一工作与链式任务。

---

## 一、什么时候用 WorkManager？

| 场景 | 推荐 |
|---|---|
| 点按钮后立刻拉接口、更新 UI | 协程 + `viewModelScope`（第 8～11 课） |
| 上传崩溃日志、同步收藏、压缩图片——**即使 App 被杀掉也要做完** | **WorkManager** |
| 精确闹钟、前台常驻播放 | `AlarmManager` / Foreground Service（本课不讲） |

WorkManager 是 Android 官方的**可延迟、可约束、可持久化**任务调度：存进自己的数据库，进程死后重启仍会跑；会尊重 Doze、电量、厂商限制。

口诀：**要保证最终执行 → WorkManager；只要当前界面活着时执行 → 协程。**

## 二、依赖（2026-09 稳定版）

```kotlin
dependencies {
    implementation("androidx.work:work-runtime-ktx:2.12.0")
}
```

有 Hilt 时还可加 `androidx.hilt:hilt-work` + `@HiltWorker`（与第 14 课同一套思路）；本课先手写，把概念讲清。

## 三、`CoroutineWorker`：协程风格的 Worker ⭐

```kotlin
class SyncFavoritesWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val userId = inputData.getString(KEY_USER_ID) ?: return Result.failure()
        return try {
            // 这里可调 Repository / Retrofit；已在后台线程的协程里
            val repo = (applicationContext as App).favoriteRepository
            repo.sync(userId)
            Result.success(workDataOf("syncedAt" to System.currentTimeMillis()))
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        } catch (e: Exception) {
            Result.failure()
        }
    }

    companion object {
        const val KEY_USER_ID = "user_id"
        const val UNIQUE_NAME = "sync_favorites"
    }
}
```

| `Result` | 含义 |
|---|---|
| `success` | 完成；可带 `outputData` 给下一个 Worker |
| `retry` | 按退避策略稍后再试 |
| `failure` | 失败结束（链式里后续默认不跑，除非你另配） |

优先 `CoroutineWorker`，少用旧的回调式 `Worker`。

## 四、约束条件 `Constraints`

```kotlin
val constraints = Constraints.Builder()
    .setRequiredNetworkType(NetworkType.CONNECTED)  // 要有网；可改 UNMETERED
    .setRequiresBatteryNotLow(true)                 // 电量别太低
    .setRequiresStorageNotLow(true)
    // .setRequiresCharging(true)
    // .setRequiresDeviceIdle(true)                 // 仅空闲时（注意厂商差异）
    .build()
```

约束不满足时任务**等待**，满足后再执行——这正是 WorkManager 的价值。

## 五、一次性 vs 周期性

### 1. `OneTimeWorkRequest`：做一次

```kotlin
val request = OneTimeWorkRequestBuilder<SyncFavoritesWorker>()
    .setConstraints(constraints)
    .setInputData(workDataOf(SyncFavoritesWorker.KEY_USER_ID to "u_42"))
    .setBackoffCriteria(
        BackoffPolicy.EXPONENTIAL,
        30, TimeUnit.SECONDS          // 首次重试至少隔 30s（有系统下限）
    )
    .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST) // 尽快（配额内）
    .addTag("sync")
    .build()

WorkManager.getInstance(context).enqueue(request)
```

### 2. `PeriodicWorkRequest`：周期执行

```kotlin
val periodic = PeriodicWorkRequestBuilder<SyncFavoritesWorker>(
    repeatInterval = 6,            // 最少约 15 分钟，再小也会被抬到系统下限
    repeatIntervalTimeUnit = TimeUnit.HOURS
)
    .setConstraints(constraints)
    .setInputData(workDataOf(SyncFavoritesWorker.KEY_USER_ID to "u_42"))
    .build()

WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    SyncFavoritesWorker.UNIQUE_NAME,
    ExistingPeriodicWorkPolicy.KEEP,   // 已有则保留；也可用 UPDATE
    periodic
)
```

注意：周期任务**不能保证整点准点**，只保证间隔大致满足；精确调度不是它的职责。

## 六、唯一工作与链式任务 ⭐

### 唯一工作：避免重复排队

```kotlin
WorkManager.getInstance(context).enqueueUniqueWork(
    SyncFavoritesWorker.UNIQUE_NAME,
    ExistingWorkPolicy.REPLACE,    // REPLACE 换新；KEEP 保留旧的；APPEND 接到后面
    request
)
```

适合"同步收藏"这种：用户连点多次，只应保留合理的一次/一串。

### 链式：A 成功后再 B

```kotlin
val compress = OneTimeWorkRequestBuilder<CompressWorker>().build()
val upload = OneTimeWorkRequestBuilder<UploadWorker>().build()
val notify = OneTimeWorkRequestBuilder<NotifyWorker>().build()

WorkManager.getInstance(context)
    .beginUniqueWork("upload_chain", ExistingWorkPolicy.KEEP, compress)
    .then(upload)
    .then(notify)
    .enqueue()
```

上一个的 `outputData` 可成为下一个的 `inputData`。任一 `failure` 且未特殊处理时，后续不会执行。

并行扇出：`beginWith(listOf(a, b)).then(c)` —— a、b 都成功后再 c。

## 七、观察状态（可选）

```kotlin
WorkManager.getInstance(context)
    .getWorkInfosForUniqueWorkFlow(SyncFavoritesWorker.UNIQUE_NAME)
    .collect { infos ->
        val state = infos.firstOrNull()?.state
        // ENQUEUED / RUNNING / SUCCEEDED / FAILED / CANCELLED / BLOCKED
    }
```

在 Compose 里可 `collectAsStateWithLifecycle`；多数业务只关心"触发"，不必展示进度。

取消：

```kotlin
WorkManager.getInstance(context).cancelUniqueWork(SyncFavoritesWorker.UNIQUE_NAME)
WorkManager.getInstance(context).cancelAllWorkByTag("sync")
```

## 八、易错点

1. **能用协程却上 WorkManager**：增加延迟与复杂度。UI 内即时请求别用它。
2. **周期间隔设成 1 分钟**：会被抬到约 15 分钟下限，测的时候以为"坏了"。
3. **在 `doWork` 里开自己的全局协程然后立刻 `success`**：工作结束进程可能被杀，子任务没了。把逻辑写在 `doWork` 的 suspend 调用里。
4. **忽略约束**：没网也硬跑，只会失败重试耗电。
5. **不用 `enqueueUniqueWork`**：每次按钮点一下就多一个重复任务。
6. **把大批量 CPU 工作放进 Worker 且不做前台/分段**：可能被系统杀掉；大任务考虑分片或前台服务（进阶）。
7. **吞掉 `CancellationException`**：同协程纪律。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 依赖 | `work-runtime-ktx:2.12.0` |
| 实现任务 | `class X : CoroutineWorker(...) { override suspend fun doWork() }` |
| 一次性 | `OneTimeWorkRequestBuilder<X>().build()` |
| 周期 | `PeriodicWorkRequestBuilder<X>(6, HOURS)` |
| 约束 | `Constraints.Builder().setRequiredNetworkType(...).build()` |
| 入参 | `setInputData(workDataOf("k" to v))` |
| 唯一 | `enqueueUniqueWork(name, REPLACE/KEEP, request)` |
| 链式 | `beginWith(a).then(b).enqueue()` |
| 取消 | `cancelUniqueWork(name)` |

## 十、本课练习

1. 写一个 `LogUploadWorker`：约束为 `CONNECTED`，把本地假日志字符串"上传"（`delay` 模拟），返回 `success`。
2. 用 `enqueueUniqueWork` + `ExistingWorkPolicy.KEEP` 连点三次按钮，确认不会排队三个。
3. 做 `compress.then(upload)` 链，在 Logcat 打印两个 Worker 的先后顺序。

---

**下一课预告（第 25 课）：DataStore** —— 替代 SharedPreferences：用 Flow 读偏好设置，类型更安全，还能 Proto 存结构化数据。
