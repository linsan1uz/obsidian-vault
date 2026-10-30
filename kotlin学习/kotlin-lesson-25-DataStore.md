# Kotlin 第 25 课：DataStore

> 适用读者：已完成第 10、11 课（Flow、`stateIn`）和第 16 课（Compose 收集状态）。
> 核心收获：用 Preferences DataStore 读写键值；用 Flow 观察变化；知道 Proto DataStore 适合什么；会从 SharedPreferences 迁移。

---

## 一、为什么不用 SharedPreferences 了？

`SharedPreferences` 问题：

- `apply()` 异步但**没有失败回调**；`commit()` 会卡线程。
- 监听靠 `OnSharedPreferenceChangeListener`，和协程/Flow 不搭。
- 类型靠字符串 key，易拼错；多进程行为历史包袱重。

**DataStore** 是官方继任者：

- 所有读写在后台，**基于 Flow / 协程**。
- 事务式 `edit { }`，一致性更好。
- 两种实现：**Preferences**（类 SP 的键值）和 **Proto**（强类型 schema）。

口诀：**新代码用 DataStore；读旧代码才碰 SharedPreferences。**

## 二、依赖（2026-10 稳定版）

```kotlin
dependencies {
    implementation("androidx.datastore:datastore-preferences:1.3.0")
    // Proto 方案再加：
    // implementation("androidx.datastore:datastore:1.3.0")
    // 以及 protobuf / 官方 datastore-proto 插件（见文档）
}
```

版本见 [DataStore 发布页](https://developer.android.com/jetpack/androidx/releases/datastore)。本课以 Preferences 为主，Proto 只做概览。

## 三、创建 Preferences DataStore

```kotlin
// 顶层属性：每个文件名全局一个实例
val Context.userPrefs: DataStore<Preferences> by preferencesDataStore(name = "user_prefs")
```

- `preferencesDataStore` 是委托，挂在 `Context` 上；**同名只能创建一个**，否则崩。
- 一般放在独立文件 `UserPreferences.kt`，Application / Repository 通过 `context.userPrefs` 访问。

## 四、定义 key、读取 Flow ⭐

```kotlin
object UserPrefKeys {
    val DARK_MODE = booleanPreferencesKey("dark_mode")
    val USERNAME = stringPreferencesKey("username")
    val LAUNCH_COUNT = intPreferencesKey("launch_count")
}

class UserPreferencesRepository(
    private val dataStore: DataStore<Preferences>
) {
    val darkMode: Flow<Boolean> = dataStore.data
        .map { prefs -> prefs[UserPrefKeys.DARK_MODE] ?: false }
        .distinctUntilChanged()

    val username: Flow<String?> = dataStore.data
        .map { it[UserPrefKeys.USERNAME] }

    val launchCount: Flow<Int> = dataStore.data
        .map { it[UserPrefKeys.LAUNCH_COUNT] ?: 0 }
}
```

- `dataStore.data` 是 **`Flow<Preferences>`**：每次变更发射新快照。
- 缺省 key 时返回 `null`，用 `?: 默认值`。
- ViewModel 里照旧 `stateIn(viewModelScope, WhileSubscribed(5000), false)` 给 Compose 用。

## 五、写入：`edit` 事务

```kotlin
suspend fun setDarkMode(enabled: Boolean) {
    dataStore.edit { prefs ->
        prefs[UserPrefKeys.DARK_MODE] = enabled
    }
}

suspend fun bumpLaunchCount() {
    dataStore.edit { prefs ->
        val cur = prefs[UserPrefKeys.LAUNCH_COUNT] ?: 0
        prefs[UserPrefKeys.LAUNCH_COUNT] = cur + 1
    }
}

suspend fun clearUsername() {
    dataStore.edit { it.remove(UserPrefKeys.USERNAME) }
}
```

- `edit` 是 **suspend**，在协程里调（`viewModelScope.launch`）。
- 块内修改是原子的：读-改-写不会和别的 `edit` 交错坏数据。
- 不要在 `edit` 里做网络请求等重活——只改 Preferences。

Compose 示例：

```kotlin
@Composable
fun SettingsScreen(vm: SettingsViewModel = hiltViewModel()) {
    val dark by vm.darkMode.collectAsStateWithLifecycle()
    Switch(checked = dark, onCheckedChange = { vm.setDarkMode(it) })
}
```

## 六、从 SharedPreferences 迁移

```kotlin
val Context.userPrefs by preferencesDataStore(
    name = "user_prefs",
    produceMigrations = { context ->
        listOf(
            SharedPreferencesMigration(
                context = context,
                sharedPreferencesName = "old_user_prefs"
                // 可选：keysToMigrate = setOf("dark_mode", "username")
            )
        )
    }
)
```

- 第一次读 DataStore 时自动把旧 SP 搬过来，然后可删除旧文件（Migration 会处理）。
- 迁移只跑一次；key 名默认按同名映射。

## 七、Proto DataStore 概览

Preferences 的 key 仍是字符串，复杂对象要自己拆字段。**Proto DataStore** 用 protobuf schema 定义强类型：

```protobuf
// user_settings.proto（示意）
message UserSettings {
  bool dark_mode = 1;
  string username = 2;
  int32 launch_count = 3;
}
```

```kotlin
val Context.userSettings: DataStore<UserSettings> by dataStore(
    fileName = "user_settings.pb",
    serializer = UserSettingsSerializer  // 实现 Serializer<UserSettings>
)

// 读
val darkMode: Flow<Boolean> = context.userSettings.data.map { it.darkMode }

// 写
suspend fun setDarkMode(v: Boolean) {
    context.userSettings.updateData { current ->
        current.toBuilder().setDarkMode(v).build()
    }
}
```

| | Preferences | Proto |
|---|---|---|
| 模型 | 键值，类似 SP | 强类型 message |
| 上手 | 快，少配置 | 要 .proto + Serializer |
| 适合 | 开关、token、简单计数 | 嵌套配置、多字段一体读写 |

小项目 Preferences 足够；配置项一多、要版本演进，再上 Proto。

## 八、和 Repository / Hilt 的摆放

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object DataStoreModule {
    @Provides @Singleton
    fun provideUserPrefs(@ApplicationContext context: Context): DataStore<Preferences> =
        context.userPrefs
}
```

Repository 只依赖 `DataStore<Preferences>`，不直接拿 Activity Context——和 Room/Retrofit 同一分层（第 13～14 课）。

**别存什么**：密码明文、大数据 blob、频繁变的列表。敏感信息用 EncryptedSharedPreferences / Keystore 方案；大数据用 Room / 文件。

## 九、易错点

1. **同名 `preferencesDataStore` 创建两次**：直接异常。全局一个委托属性。
2. **在主线程调用阻塞式 API**：DataStore 没有 `getSync` 官方推荐用法；用 Flow / `first()`。
3. **`runBlocking { dataStore.data.first() }` 放在主线程**：可能 ANR。初始化路径用注入后的协程。
4. **在 `edit` 里做 IO/网络**：拉长锁持有时间；先算好值再 `edit`。
5. **把 DataStore 当数据库**：复杂查询、关联表 → Room。
6. **key 字符串魔法值散落各处**：收进 `object XxxKeys`。
7. **迁移后仍读写旧 SP**：两套数据源会分裂。

## 十、对照速查表

| 需求 | 写法 |
|---|---|
| 依赖 | `datastore-preferences:1.3.0` |
| 创建 | `val Context.xxx by preferencesDataStore("file")` |
| 定义 key | `booleanPreferencesKey("dark_mode")` |
| 读 | `dataStore.data.map { it[KEY] ?: default }` |
| 写 | `dataStore.edit { it[KEY] = value }` |
| 删 key | `edit { it.remove(KEY) }` |
| 从 SP 迁 | `SharedPreferencesMigration(...)` 放进 `produceMigrations` |
| 结构化 | Proto DataStore + `updateData` |

## 十一、本课练习

1. 实现 `darkMode: Flow<Boolean>` + `setDarkMode`，Compose 里一个 Switch 双向绑定。
2. 启动时 `bumpLaunchCount()`，Text 显示累计次数。
3. （选做）写一个假的旧 SP，配 `SharedPreferencesMigration`，确认首次安装后 DataStore 能读到旧值。

---

**下一课预告（第 26 课）：运行时权限与通知** —— 申请相机/通知权限，创建 Notification Channel，在 Android 13+ 正确处理 `POST_NOTIFICATIONS`。
