# Kotlin 第 14 课：Hilt 依赖注入

> 适用读者：已完成第 12、13 课（Room、Retrofit、Repository）。
> 核心收获：理解依赖注入要解决什么问题，会用 `@HiltAndroidApp`、`@AndroidEntryPoint`、`@HiltViewModel` + `@Inject constructor`，用 `@Module` / `@Provides` / `@Binds` 提供第 12～13 课的 Retrofit、Room、Repository，看懂作用域注解。

---

## 一、为什么需要依赖注入？⭐

回看第 13 课，要创建一个 `UserListViewModel`，得这样拼：

```kotlin
val json = Json { ignoreUnknownKeys = true }
val retrofit = Retrofit.Builder().baseUrl("https://...").addConverterFactory(...).build()
val api = retrofit.create(UserApi::class.java)
val db = Room.databaseBuilder(context, AppDatabase::class.java, "app.db").build()
val repo = UserRepository(api, db.userDao())
val vm = UserListViewModel(repo)          // 还得写 Factory 才能 by viewModels()
```

问题：每个页面都要重复这一串；`Retrofit` 和 `AppDatabase` 要保证全局一个；单测想换成假的 `UserApi` 很难。

**第一步：构造函数注入（不用框架）**。类不自己 new 依赖，而是**从构造函数接收**：

```kotlin
class UserRepository(private val api: UserApi, private val dao: UserDao)   // ✅ 依赖从外面传
class UserRepository { private val api = Retrofit.Builder()...create() }   // ❌ 自己造，写死了
```

第 13 课其实已经这么写了。剩下的问题是**谁来负责把这些对象 new 出来、按正确顺序传进去**。

**Hilt 就是这个"谁"**：你告诉它每样东西怎么造，它在编译期生成代码，自动创建、自动传递、管理单例。Hilt 基于 Dagger，是 Android 官方推荐的 DI 方案。

口诀：**类只声明"我需要什么"，Hilt 负责"给你什么"。**

## 二、配置（KSP + AGP 9）

```kotlin
// 根 build.gradle.kts
plugins {
    id("com.android.application") version "9.4.1" apply false
    id("com.google.devtools.ksp") version "2.3.12" apply false
    id("com.google.dagger.hilt.android") version "2.60.1" apply false
}

// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
}

dependencies {
    implementation("com.google.dagger:hilt-android:2.60.1")
    ksp("com.google.dagger:hilt-compiler:2.60.1")         // 和 Room 一样走 KSP
}
```

- Hilt Gradle 插件从 2.59 起要求 **AGP 9.0+**；本项目 AGP 9 正好对上。
- 处理器用 `ksp(...)`，不要和旧教程里的 `kapt` 混用。
- 用 Compose 时还会加 `androidx.hilt:hilt-lifecycle-viewmodel-compose:1.4.0` 来用 `hiltViewModel()`；本课用 View 体系 + `by viewModels()`，不需要它。

## 三、四个入口注解

### 1. `@HiltAndroidApp`：在 Application 上开启 Hilt

```kotlin
@HiltAndroidApp
class App : Application()       // 第 12 课里手写的 database by lazy 可以删掉了
```

`AndroidManifest.xml` 里 `<application android:name=".App">` 必须指向它。

### 2. `@AndroidEntryPoint`：让 Activity / Fragment 能接收注入

```kotlin
@AndroidEntryPoint
class UserListActivity : AppCompatActivity() {
    private val vm: UserListViewModel by viewModels()      // ⭐ 不用再写 Factory
}
```

Fragment 也要加；**Fragment 加了，它所在的 Activity 也必须加**。

### 3. `@HiltViewModel` + `@Inject constructor`：ViewModel

```kotlin
@HiltViewModel
class UserListViewModel @Inject constructor(
    private val repo: UserRepository,
    private val savedState: SavedStateHandle          // 第 9 课的，Hilt 自动提供
) : ViewModel() {
    // 第 13 课的 state / refresh() 原样不动
}
```

第 12 课的 `companion object { val Factory = viewModelFactory { ... } }` **整段删掉**。

### 4. `@Inject constructor`：自己写的普通类

```kotlin
class UserRepository @Inject constructor(
    private val api: UserApi,
    private val dao: UserDao
) { /* 第 13 课代码不动 */ }
```

`@Inject constructor` 告诉 Hilt："要我的时候，用这个构造函数造，参数你去找。"Hilt 会顺藤摸瓜：要 `UserRepository` → 要 `UserApi` 和 `UserDao` → 去 Module 里找（第四节）。

## 四、Module：教 Hilt 造"不是你写的类" ⭐

`Retrofit`、`OkHttpClient`、`AppDatabase` 是库里的类，没法在它们的构造函数上加 `@Inject`；接口也没有构造函数。这时写 **Module**。

### 1. `@Provides`：用函数告诉 Hilt 怎么造

```kotlin
@Module
@InstallIn(SingletonComponent::class)             // 装在全局容器里，整个 App 可用
object NetworkModule {                            // 第 2 课 object

    @Provides @Singleton
    fun provideJson(): Json = Json { ignoreUnknownKeys = true }

    @Provides @Singleton
    fun provideOkHttp(): OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BODY   // 需 buildFeatures { buildConfig = true }
                    else HttpLoggingInterceptor.Level.NONE
        })
        .build()

    @Provides @Singleton
    fun provideRetrofit(client: OkHttpClient, json: Json): Retrofit =   // 参数也由 Hilt 注入
        Retrofit.Builder()
            .baseUrl("https://jsonplaceholder.typicode.com/")
            .client(client)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()

    @Provides @Singleton
    fun provideUserApi(retrofit: Retrofit): UserApi = retrofit.create(UserApi::class.java)
}

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, "app.db")
            .addMigrations(MIGRATION_1_2)                 // 第 12 课
            .build()

    @Provides                                             // DAO 本身很轻，不必单例
    fun provideUserDao(db: AppDatabase): UserDao = db.userDao()
}
```

- `@ApplicationContext`：Hilt 自带的限定符，拿到 Application Context，不会泄漏（第 9 课红线）。
- 参数列表就是依赖声明：`provideRetrofit` 要 `OkHttpClient` 和 `Json`，Hilt 先造好再传进来。

### 2. `@Binds`：接口 → 实现

想让 ViewModel 依赖**接口**（方便测试时换成假实现）：

```kotlin
interface UserRepository {
    val users: Flow<List<User>>
    fun search(q: String): Flow<List<User>>       // 第 11 课搜索用
    suspend fun refresh(): Result<Unit>
}

class DefaultUserRepository @Inject constructor(
    private val api: UserApi,
    private val dao: UserDao
) : UserRepository { /* 第 13 课实现 */ }

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {                         // 第 6 课 abstract
    @Binds @Singleton
    abstract fun bindUserRepository(impl: DefaultUserRepository): UserRepository
}
```

| | `@Provides` | `@Binds` |
|---|---|---|
| 写在 | `object` 里的普通函数 | `abstract class` 里的抽象函数 |
| 用途 | 第三方类、需要 Builder 配置的对象 | 把接口绑到已有 `@Inject` 构造的实现 |
| 有函数体 | 有，自己写怎么造 | 没有，只声明对应关系 |

口诀：**自己的类 `@Inject constructor`；别人的类 `@Provides`；接口 `@Binds`。**

## 五、作用域：对象活多久

默认**不加作用域注解 = 每次注入都新造一个**。加了作用域，在对应容器里**只造一次、反复复用**。

| 容器（Component） | 作用域注解 | 活多久 | 典型对象 |
|---|---|---|---|
| `SingletonComponent` | `@Singleton` | 整个 App 进程 | Retrofit、OkHttp、AppDatabase、Repository |
| `ActivityRetainedComponent` | `@ActivityRetainedScoped` | Activity 含转屏 | 跨转屏共享的页面级对象 |
| `ViewModelComponent` | `@ViewModelScoped` | 一个 ViewModel | 只给这个 ViewModel 用的 UseCase |
| `ActivityComponent` | `@ActivityScoped` | 一个 Activity 实例 | 和界面绑定的工具 |
| `FragmentComponent` | `@FragmentScoped` | 一个 Fragment | 同上 |

规则：作用域注解必须和 `@InstallIn` 的容器对应——`@InstallIn(SingletonComponent::class)` 的 Module 里只能用 `@Singleton`，不能写 `@ActivityScoped`。

`Retrofit` / `AppDatabase` 必须 `@Singleton`：不加的话，每个 Repository 都会新建一个数据库实例（第 12 课易错点 5）。

## 六、整体回看：从手动拼装到自动注入

```
@HiltAndroidApp App
   └─ SingletonComponent
        ├─ Json / OkHttpClient / Retrofit / UserApi     （NetworkModule）
        ├─ AppDatabase / UserDao                        （DatabaseModule）
        └─ UserRepository → DefaultUserRepository        （RepositoryModule）
              ↓ 注入
@HiltViewModel UserListViewModel(repo, savedState)
              ↓ by viewModels()
@AndroidEntryPoint UserListActivity
```

Activity 里只剩一行 `by viewModels()`；第一节那一串手动 new 全部消失。单测时可以用 `@TestInstallIn` 把 `NetworkModule` 换成返回假数据的 Module（了解即可）。

## 七、易错点

1. **忘了 `@HiltAndroidApp` 或 Manifest 没写 `android:name`**：启动崩溃，提示 Hilt 组件未生成。
2. **Fragment 加了 `@AndroidEntryPoint`，宿主 Activity 没加**：运行时崩溃。
3. **ViewModel 写了 `@HiltViewModel` 但忘了 `@Inject constructor`**：编译报错。
4. **注入接口却没写 `@Binds`**：编译报 `cannot be provided without an @Provides-annotated method`——读这条报错就知道缺了谁。
5. **需要 Context 时直接写 `context: Context` 参数**：Hilt 不知道给哪个 Context，要加 `@ApplicationContext`。
6. **Retrofit / Room 忘加 `@Singleton`**：每处注入都新建一个，浪费资源，Room 失效通知也会出问题。
7. **作用域和容器不匹配**：如在 `SingletonComponent` 的 Module 里用 `@ActivityScoped`，编译报错。
8. **`kapt` 和 `ksp` 混用**：Room 和 Hilt 都统一走 `ksp(...)`。
9. **字段注入写成 `private`**：`@Inject lateinit var x: X` 不能是 private。优先用构造函数注入，Activity 里才偶尔用字段注入。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 开启 Hilt | `@HiltAndroidApp class App : Application()` + Manifest `android:name` |
| Activity / Fragment | `@AndroidEntryPoint`，`by viewModels()` 直接用 |
| ViewModel | `@HiltViewModel class Vm @Inject constructor(...) : ViewModel()` |
| 自己的类 | `class Repo @Inject constructor(private val api: UserApi)` |
| 第三方类 | `@Module @InstallIn(SingletonComponent::class) object M { @Provides fun ... }` |
| 接口绑定 | `abstract class M { @Binds abstract fun bind(impl: Impl): Api }` |
| 全局单例 | `@Singleton`（配 `SingletonComponent`） |
| 需要 Context | `@ApplicationContext context: Context` |
| 注解处理 | `ksp("com.google.dagger:hilt-compiler:2.60.1")` |

---

**下一课预告（第 15 课）：Jetpack Compose 入门** —— 数据层（Room + Retrofit + Repository + Hilt）已经齐了，下一步换 UI 层：用 `@Composable` 函数写界面，`collectAsStateWithLifecycle()` 直接吃本系列一路写的 StateFlow，`hiltViewModel()` 一行拿 ViewModel。
