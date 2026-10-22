# Kotlin 第 13 课：Retrofit 网络请求与 Repository 分层

> 适用读者：已完成第 11、12 课（Flow 操作符、Room）。
> 核心收获：用 Retrofit + kotlinx.serialization 写 `suspend` 接口，用密封类 `UiState` 表达加载、成功、失败，用 Repository 把"网络 + Room 缓存"合成**单一数据源**，处理好网络错误。

---

## 一、Retrofit 是什么

**Retrofit = 把 HTTP 接口写成 Kotlin 接口**。你只声明"请求什么"，Retrofit 生成实现，底层用 OkHttp 发请求，用 Converter 把 JSON 转成对象。

```
ViewModel ──▶ Repository ──▶ UserApi（Retrofit）──▶ OkHttp ──▶ 服务器
                  │
                  └────────▶ UserDao（Room，第 12 课）
```

本课 JSON 解析选 **kotlinx.serialization**：Kotlin 官方库，编译期生成序列化代码，不走反射，对 Kotlin 默认值、可空类型支持最好。

## 二、配置

```kotlin
// 根 build.gradle.kts：序列化插件版本 = 项目 Kotlin 版本
plugins {
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.21" apply false
}

// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.serialization")   // AGP 9 内置 Kotlin 也要单独加
    id("com.google.devtools.ksp")                     // 第 12 课 Room 用
}

dependencies {
    implementation("com.squareup.retrofit2:retrofit:3.0.0")
    implementation("com.squareup.retrofit2:converter-kotlinx-serialization:3.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("com.squareup.okhttp3:logging-interceptor:5.5.1")   // 和 okhttp 同版本
}
```

**`AndroidManifest.xml` 必须声明网络权限**，否则请求直接失败：

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

另外 Android 9（API 28）起**默认禁止明文 HTTP**，接口一律用 `https://`。

## 三、定义数据和接口

```kotlin
@Serializable
data class UserDto(
    val id: Long,
    val name: String,
    val email: String,
    @SerialName("is_active") val active: Boolean = true   // JSON 字段名不同时映射
)

interface UserApi {
    @GET("users")
    suspend fun getUsers(): List<UserDto>                  // ⭐ suspend 直接返回结果

    @GET("users/{id}")
    suspend fun getUser(@Path("id") id: Long): UserDto

    @GET("users")
    suspend fun search(@Query("q") keyword: String): List<UserDto>
}
```

- `@Serializable` 让编译器插件生成解析代码，**少了它运行时会报找不到序列化器**。
- `suspend` 接口由 Retrofit 自己放到后台线程执行，**主线程调用安全，不用 `withContext(IO)`**（和第 12 课 Room 一样）。

创建实例（全局一个，第 14 课交给 Hilt）：

```kotlin
val json = Json { ignoreUnknownKeys = true }   // 服务器多给字段不报错

val okHttp = OkHttpClient.Builder()
    .addInterceptor(HttpLoggingInterceptor().apply {      // 第 5 课 apply
        level = HttpLoggingInterceptor.Level.BODY         // 打印请求/响应，只在 debug 用
    })
    .build()

val retrofit = Retrofit.Builder()
    .baseUrl("https://jsonplaceholder.typicode.com/")     // ⚠️ 必须以 / 结尾
    .client(okHttp)
    .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
    .build()

val api: UserApi = retrofit.create(UserApi::class.java)
```

## 四、错误处理与 UiState ⭐

网络请求一定会失败：没网、超时、服务器 500、JSON 格式不对。`suspend` 接口失败时**直接抛异常**：

| 异常 | 什么情况 |
|---|---|
| `IOException` | 没网、超时、连接断开 |
| `HttpException`（retrofit2） | 服务器返回非 2xx，`e.code()` 拿状态码 |
| `SerializationException` | JSON 和 `@Serializable` 类对不上 |

用第 5 课的**密封类**把结果建模，UI 用 `when` 穷尽处理：

```kotlin
sealed interface UiState<out T> {                  // 第 7 课 out：UiState<Nothing> 能当任意 UiState<T>
    data object Loading : UiState<Nothing>
    data class Success<T>(val data: T) : UiState<T>
    data class Error(val message: String) : UiState<Nothing>
}

fun Throwable.toUserMessage(): String = when (this) {     // 第 3 课扩展函数
    is IOException -> "网络连接失败，请检查网络"
    is HttpException -> "服务器错误（${code()}）"
    is SerializationException -> "数据格式错误"
    else -> message ?: "未知错误"
}
```

Kotlin 标准库还有 `Result<T>`，适合 Repository 返回"成功或失败"：

```kotlin
suspend fun refresh(): Result<Unit> = try {
    // ...
    Result.success(Unit)
} catch (e: CancellationException) {
    throw e                                    // 第 11 课：取消必须放行
} catch (e: Exception) {
    Result.failure(e)
}
```

不要图省事写 `runCatching { }`：它会把 `CancellationException` 一起吞掉。

## 五、Repository：单一数据源 ⭐

**Repository 是数据层的门面**：ViewModel 不知道数据来自网络还是数据库，只管向 Repository 要。

**单一数据源（Single Source of Truth）**：

- **界面只读 Room**（`Flow`），永远不直接显示网络结果。
- 网络只负责**刷新 Room**：拉下来 → 写库 → Room 的 Flow 自动发新值。
- 好处：离线也能显示上次的数据；只有一个地方存数据，不会出现"列表和详情显示的不一致"。

```kotlin
data class User(val id: Long, val name: String, val email: String)   // 领域模型，给 UI 用

fun UserDto.toEntity() = UserEntity(id, name, email, active)
fun UserEntity.toDomain() = User(id, name, email)

class UserRepository(
    private val api: UserApi,
    private val dao: UserDao
) {
    val users: Flow<List<User>> = dao.observeAll()
        .map { list -> list.map { it.toDomain() } }           // 第 11 课 map

    fun search(q: String): Flow<List<User>> = dao.search(q)
        .map { list -> list.map { it.toDomain() } }

    suspend fun refresh(): Result<Unit> = try {
        val remote = api.getUsers()                            // 1. 拉网络
        dao.upsertAll(remote.map { it.toEntity() })            // 2. 写数据库
        Result.success(Unit)                                   // 3. 界面通过 Flow 自动更新
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }
}
```

为什么分三种模型（`UserDto` / `UserEntity` / `User`）？各管一层：服务器字段变了只改 Dto 和映射，数据库表结构变了只改 Entity，UI 不受影响。小项目合并也行，但要知道分层的理由。

## 六、ViewModel：把列表和刷新状态合起来

```kotlin
class UserListViewModel(private val repo: UserRepository) : ViewModel() {

    private val refreshing = MutableStateFlow(false)
    private val error = MutableStateFlow<String?>(null)

    val state: StateFlow<UiState<List<User>>> =
        combine(repo.users, refreshing, error) { users, loading, err ->   // 第 11 课 combine
            when {
                err != null && users.isEmpty() -> UiState.Error(err)
                loading && users.isEmpty() -> UiState.Loading
                else -> UiState.Success(users)        // 有缓存就先显示缓存
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), UiState.Loading)

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            refreshing.value = true
            error.value = null
            repo.refresh().onFailure { error.value = it.toUserMessage() }
            refreshing.value = false
        }
    }
}
```

Activity 侧照第 10 课收集，`when (state)` 渲染：

```kotlin
when (val s = state) {
    UiState.Loading -> progress.visible()
    is UiState.Success -> { progress.gone(); adapter.submitList(s.data) }
    is UiState.Error -> { progress.gone(); toast(s.message) }   // 第 3 课扩展 toast
}
```

有缓存时刷新失败，界面仍显示旧数据；真想提示用户，用第 10 课的 SharedFlow 发一次性 Snackbar 事件。

## 七、易错点

1. **忘了 `INTERNET` 权限**：请求直接抛 `SecurityException` 或 `UnknownHostException`。
2. **`baseUrl` 不以 `/` 结尾**：Retrofit 直接抛 `IllegalArgumentException`。
3. **用 `http://`**：Android 9+ 默认拦截明文流量，改 https。
4. **DTO 忘加 `@Serializable` 或没加序列化插件**：运行时报找不到 serializer。
5. **不设 `ignoreUnknownKeys = true`**：服务器多返回一个字段，整个解析失败。
6. **用 `runCatching` 包 suspend 调用**：吞掉 `CancellationException`。
7. **UI 直接显示网络结果，又同时读数据库**：两份数据，显示不一致。网络只写库，界面只读库。
8. **release 包也开 `Level.BODY` 日志**：泄露用户数据、拖慢请求。只在 debug 开。
9. **在 ViewModel 里 `withContext(Dispatchers.IO)` 包 Retrofit/Room 的 suspend 调用**：不会出错但多余，它们已经 main-safe。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 网络权限 | `<uses-permission android:name="android.permission.INTERNET" />` |
| 定义接口 | `interface UserApi { @GET("users") suspend fun getUsers(): List<UserDto> }` |
| 路径 / 查询参数 | `@Path("id") id: Long` / `@Query("q") q: String` |
| JSON 模型 | `@Serializable data class UserDto(...)`，字段名不同用 `@SerialName` |
| 转换器 | `json.asConverterFactory("application/json".toMediaType())` |
| 创建 API | `Retrofit.Builder().baseUrl("https://.../").build().create(UserApi::class.java)` |
| 状态建模 | `sealed interface UiState<out T> { Loading / Success / Error }` |
| 失败返回 | `Result.success(...)` / `Result.failure(e)`，取消要 rethrow |
| 单一数据源 | UI 读 `dao.observeAll()`；`refresh()` = 拉网络 → `upsertAll` 写库 |
| 合并状态 | `combine(users, refreshing, error) { ... }.stateIn(...)` |

---

**下一课预告（第 14 课）：Hilt 依赖注入** —— 现在 `Retrofit`、`AppDatabase`、`UserRepository` 都要手动 new、手写 ViewModel Factory。Hilt 让它们自动创建、自动传进构造函数。
