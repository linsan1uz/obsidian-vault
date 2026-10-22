# Kotlin 第 12 课：Room 本地数据库

> 适用读者：已完成第 10、11 课（StateFlow、Flow 操作符、`stateIn`）。
> 核心收获：会用 `@Entity` / `@Dao` / `@Database` 三件套建库，配好 KSP，用 `suspend` 写入、用 `Flow` 查询，在 ViewModel 里 `stateIn` 成 UI 状态，知道主线程规则和数据库迁移。

---

## 一、Room 是什么？为什么不直接用 SQLite

Android 自带 SQLite，但原生 API 要手写 `Cursor`、拼 SQL 字符串、自己转对象，SQL 写错只能运行时发现。

**Room = SQLite 之上的官方封装**：

- 用注解声明表和查询，**编译期检查 SQL**（表名、列名写错直接编译报错）。
- 自动把查询结果转成 Kotlin 对象。
- 原生支持 `suspend` 和 `Flow`：**数据变了，Flow 自动发新值**，界面跟着刷新。

本课延续第 11 课的"用户列表"：`repo.observeUsers()` 的 Flow 就由 Room 提供。

## 二、配置：KSP + Room（AGP 9 内置 Kotlin）⭐

Room 的注解处理器靠 **KSP** 生成代码。AGP 9 起 Android 插件**内置 Kotlin 支持**，模块里不再写 `org.jetbrains.kotlin.android`，但 **KSP 是独立插件，仍要自己加**。

```kotlin
// 根目录 build.gradle.kts
plugins {
    id("com.android.application") version "9.4.1" apply false
    id("com.google.devtools.ksp") version "2.3.12" apply false
    id("androidx.room") version "2.8.5" apply false
}

// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("com.google.devtools.ksp")      // 内置 Kotlin 不包含 KSP，必须显式加
    id("androidx.room")                // Room Gradle 插件：管理 schema 导出
}

room {
    schemaDirectory("$projectDir/schemas")   // 导出表结构 JSON，迁移要用
}

dependencies {
    implementation("androidx.room:room-runtime:2.8.5")
    implementation("androidx.room:room-ktx:2.8.5")
    ksp("androidx.room:room-compiler:2.8.5")    // 注意是 ksp(...)，不是 implementation
}
```

**KSP 版本说明**：KSP 从 2.3.0 起改了版本号规则，不再写成 `2.x.y-1.0.z` 这种"Kotlin 版本 + KSP 版本"的形式（那是老 KSP1 的写法，必须和 Kotlin 版本逐字匹配）。KSP 2.3.x 是独立版本号，能配合 Kotlin 2.x 使用。本项目 Kotlin 2.3.21 搭配 KSP 2.3.12，升级 Kotlin 时顺手看一眼 KSP release notes 是否兼容即可。

## 三、三件套：Entity / Dao / Database

### 1. `@Entity`：一张表

```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: Long,                 // 主键（用服务器 id，第 13 课要用）
    val name: String,
    val email: String,
    @ColumnInfo(name = "is_active") val active: Boolean = true
)
```

- 就是一个 `data class`（第 2 课），每个属性一列。
- 本地自增主键写 `@PrimaryKey(autoGenerate = true) val id: Long = 0`。

### 2. `@Dao`：增删改查

```kotlin
@Dao
interface UserDao {

    @Query("SELECT * FROM users ORDER BY name")
    fun observeAll(): Flow<List<UserEntity>>          // ⭐ 不加 suspend，返回 Flow

    @Query("SELECT * FROM users WHERE name LIKE '%' || :q || '%'")
    fun search(q: String): Flow<List<UserEntity>>     // :q 绑定参数

    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun getById(id: Long): UserEntity?        // 一次性查询用 suspend

    @Upsert
    suspend fun upsertAll(users: List<UserEntity>)    // 有则更新，无则插入

    @Delete
    suspend fun delete(user: UserEntity)

    @Query("DELETE FROM users")
    suspend fun clear()
}
```

规则：

| 返回类型 | 写法 | 含义 |
|---|---|---|
| `Flow<T>` | **不加** `suspend` | 持续观察，表一变就重新查询并发射 |
| 普通值 / `Unit` | **加** `suspend` | 只执行一次 |

`interface` 只写声明，实现由 KSP 生成（第 6 课接口）。

### 3. `@Database`：数据库入口

```kotlin
@Database(entities = [UserEntity::class], version = 1, exportSchema = true)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao
}
```

创建实例：**整个 App 只要一个**（第 2 课 object 单例思路）。第 14 课交给 Hilt，这里先手写：

```kotlin
class App : Application() {
    val database: AppDatabase by lazy {
        Room.databaseBuilder(this, AppDatabase::class.java, "app.db").build()
    }
}
// AndroidManifest.xml：<application android:name=".App" ...>
```

## 四、主线程规则 ⭐

**Room 默认禁止在主线程做数据库操作**，否则抛 `IllegalStateException`：数据库读写可能耗时，会卡 UI。

好消息是按第三节写法，你**不用自己切线程**：

- `suspend` DAO 函数：Room 自动在后台线程执行，主线程调用也安全（"main-safe"）。
- 返回 `Flow` 的查询：查询在 Room 的后台线程跑，结果发给收集者。

```kotlin
viewModelScope.launch {
    dao.upsertAll(users)               // ✅ 不需要 withContext(Dispatchers.IO)
}
```

`allowMainThreadQueries()` 能关掉检查，**只在临时测试里用，正式代码不要写**。

## 五、在 ViewModel 里观察

```kotlin
class UserListViewModel(private val dao: UserDao) : ViewModel() {

    val users: StateFlow<List<UserEntity>> = dao.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun addSample() {
        viewModelScope.launch {
            dao.upsertAll(listOf(UserEntity(System.currentTimeMillis(), "Jerry", "j@x.com")))
        }
    }

    companion object {
        val Factory = viewModelFactory {           // lifecycle-viewmodel-ktx 提供
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as App
                UserListViewModel(app.database.userDao())
            }
        }
    }
}
```

Activity：

```kotlin
private val vm: UserListViewModel by viewModels { UserListViewModel.Factory }

lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        vm.users.collect { adapter.submitList(it) }
    }
}
```

数据流：**点击 → `upsertAll` 写库 → Room 发现 users 表变了 → `observeAll()` 自动发新列表 → StateFlow → 界面刷新**。写入方不用通知任何人。

为什么要 `Factory`？ViewModel 构造函数有参数（`dao`），默认的 `by viewModels()` 不知道怎么传。手写工厂有点啰嗦——这正是第 14 课 Hilt 要解决的问题。

## 六、数据库迁移（简要）

改了表结构（加列、改表）就要**升版本号**，并告诉 Room 怎么把旧数据搬过去，否则老用户升级 App 后启动就崩。

```kotlin
// 1. UserEntity 加一列：val age: Int = 0
// 2. version = 1 → version = 2

val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE users ADD COLUMN age INTEGER NOT NULL DEFAULT 0")
    }
}

Room.databaseBuilder(this, AppDatabase::class.java, "app.db")
    .addMigrations(MIGRATION_1_2)
    .build()
```

- 简单的加列可以用**自动迁移**：`@Database(version = 2, autoMigrations = [AutoMigration(from = 1, to = 2)])`，前提是 `exportSchema = true` 并配了 `schemaDirectory`（第二节）。
- `fallbackToDestructiveMigration(dropAllTables = true)`：找不到迁移就**清空重建**。只适合纯缓存数据，用户数据别这么干。

## 七、易错点

1. **`ksp` 写成 `implementation`**：`room-compiler` 必须用 `ksp(...)`，否则不生成代码，运行时报找不到 `AppDatabase_Impl`。
2. **AGP 9 下以为不用加 KSP 插件**：内置的是 Kotlin 编译，不含 KSP，`com.google.devtools.ksp` 要显式加。
3. **返回 `Flow` 的 DAO 函数加了 `suspend`**：语义混乱，Flow 查询不加 `suspend`。
4. **主线程直接调非 suspend 的 DAO 方法**：`IllegalStateException`。用 `suspend` 或 `Flow`。
5. **每次 `Room.databaseBuilder(...).build()` 新建实例**：多个实例开销大，Flow 失效通知也不一致。全局一个。
6. **改表不升版本号**：启动崩溃，提示 schema 变了但版本号没变。
7. **用 `fallbackToDestructiveMigration` 处理用户数据**：升级 App 用户数据全没。
8. **DAO 里 SQL 写成 `WHERE name LIKE '%:q%'`**：参数不能放在引号里，要用 `'%' || :q || '%'`。

## 八、对照速查表

| 需求 | 写法 |
|---|---|
| 定义表 | `@Entity(tableName = "users") data class UserEntity(@PrimaryKey val id: Long, ...)` |
| 持续观察 | `@Query("SELECT ...") fun observeAll(): Flow<List<UserEntity>>` |
| 一次性查询 | `@Query(...) suspend fun getById(id: Long): UserEntity?` |
| 插入或更新 | `@Upsert suspend fun upsertAll(list: List<UserEntity>)` |
| 数据库类 | `@Database(entities = [...], version = 1) abstract class AppDatabase : RoomDatabase()` |
| 创建实例 | `Room.databaseBuilder(context, AppDatabase::class.java, "app.db").build()` |
| ViewModel 暴露 | `dao.observeAll().stateIn(viewModelScope, WhileSubscribed(5000), emptyList())` |
| 带参 ViewModel | `viewModelFactory { initializer { ... } }` + `by viewModels { Factory }` |
| 迁移 | `Migration(1, 2)` + `addMigrations(...)`，或 `AutoMigration` |
| 注解处理 | `ksp("androidx.room:room-compiler:2.8.5")` |

---

**下一课预告（第 13 课）：Retrofit 网络请求与 Repository 分层** —— 用户数据从服务器拉下来，写进本课的 Room，界面只读数据库：这就是"单一数据源"。
