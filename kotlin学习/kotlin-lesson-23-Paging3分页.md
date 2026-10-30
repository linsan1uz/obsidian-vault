# Kotlin 第 23 课：Paging 3 分页

> 适用读者：已完成第 12～16 课（Room、Retrofit、Repository、Compose、`LazyColumn`）和第 11 课（Flow）。
> 核心收获：理解 Paging 3 为什么比自己 `offset/limit` 更省心；会写 `PagingSource`，用 `Pager` 得到 `Flow<PagingData>`；在 Compose 里 `collectAsLazyPagingItems()` 接 `LazyColumn`；知道 `RemoteMediator` + Room 做网络+本地分页的高层套路。

---

## 一、为什么需要 Paging？

用户列表有几千条时，一次全拉：

- 首屏慢、内存炸、滚动卡。
- 自己写 `page++`、拼接列表、处理重复、下拉刷新、失败重试——容易漏边界。

**Paging 3** 帮你：按页加载、自动预取下一页、和 `LazyColumn`/`RecyclerView` 对接、刷新与重试有统一 API。

口诀：**UI 只关心"当前可见附近的数据"；何时加载下一页交给 Paging。**

## 二、依赖（2026-10 稳定版）

```kotlin
// app/build.gradle.kts
dependencies {
    val paging = "3.5.3"
    implementation("androidx.paging:paging-runtime:$paging")
    implementation("androidx.paging:paging-compose:$paging")   // Compose 集成
    // 若只测公共逻辑（无 Android）：
    // testImplementation("androidx.paging:paging-common:$paging")
}
```

版本以 [Paging 发布页](https://developer.android.com/jetpack/androidx/releases/paging) 为准；`paging-*` 与 `paging-compose` 同号（3.5.3）。

## 三、核心概念一览

```
PagingSource  ──►  Pager  ──►  Flow<PagingData<T>>  ──►  LazyPagingItems  ──►  LazyColumn
   (怎么取一页)     (配置)         (ViewModel 暴露)         (Compose 收集)
```

| 类型 | 职责 |
|---|---|
| `PagingSource<Key, Value>` | 定义"一页怎么加载"：入参是上一页的 key，返回本页数据和上一/下一页 key |
| `Pager` | 配置 `pageSize` 等，把 Source 变成 `Flow<PagingData>` |
| `PagingData` | 一股"可分页的数据流"，不要自己拆 |
| `LazyPagingItems` | Compose 侧：`itemCount`、`[index]`、加载状态、`refresh()` / `retry()` |
| `RemoteMediator` | **网络 + Room** 时：负责把远端一页写入本地，本地再用 `PagingSource` 喂 UI |

## 四、最简：内存 / 网络 `PagingSource` ⭐

假设接口：`GET /users?page=1&size=20`，返回 `{ data, totalPages }`。

```kotlin
class UserPagingSource(
    private val api: UserApi
) : PagingSource<Int, User>() {

    override suspend fun load(params: LoadParams<Int>): LoadResult<Int, User> {
        val page = params.key ?: 1
        return try {
            val resp = api.getUsers(page = page, size = params.loadSize)
            LoadResult.Page(
                data = resp.data.map { it.toDomain() },
                prevKey = if (page == 1) null else page - 1,
                nextKey = if (page >= resp.totalPages) null else page + 1
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            LoadResult.Error(e)
        }
    }

    override fun getRefreshKey(state: PagingState<Int, User>): Int? {
        // 刷新时尽量停在用户正在看的附近
        val anchor = state.anchorPosition ?: return null
        val page = state.closestPageToPosition(anchor)
        return page?.prevKey?.plus(1) ?: page?.nextKey?.minus(1)
    }
}
```

- `LoadParams.key`：要加载的页码；首次为 `null`，你自己定默认 `1`。
- `prevKey` / `nextKey`：没有了就返回 `null`，Paging 就不会再往那边请求。
- **取消异常必须重新抛出**（第 13 课同一纪律）。

## 五、ViewModel：`Pager` + `Flow<PagingData>`

```kotlin
class UserListViewModel @Inject constructor(
    private val api: UserApi
) : ViewModel() {

    val users: Flow<PagingData<User>> = Pager(
        config = PagingConfig(
            pageSize = 20,
            prefetchDistance = 5,     // 距底部还有 5 项就预加载
            enablePlaceholders = false
        ),
        pagingSourceFactory = { UserPagingSource(api) }
    ).flow.cachedIn(viewModelScope)   // ⭐ 缓存到 ViewModel，旋转屏幕不丢、不多请求
}
```

- **`cachedIn(viewModelScope)`**：几乎必加。否则每次 Compose 重组重新收集会新开 Source。
- `pagingSourceFactory` 是 **lambda**：每次 refresh 会 new 一个新的 Source。

## 六、Compose：`collectAsLazyPagingItems` + `LazyColumn` ⭐

```kotlin
@Composable
fun UserListScreen(vm: UserListViewModel = hiltViewModel()) {
    val items = vm.users.collectAsLazyPagingItems()

    when (val state = items.loadState.refresh) {
        is LoadState.Loading -> FullScreenLoading()
        is LoadState.Error -> ErrorPane(
            message = state.error.toUserMessage(),
            onRetry = { items.retry() }
        )
        else -> {
            LazyColumn {
                items(
                    count = items.itemCount,
                    key = { index -> items[index]?.id ?: "placeholder-$index" }
                ) { index ->
                    val user = items[index]
                    if (user != null) UserRow(user) else PlaceholderRow()
                }

                // 底部加载更多 / 失败
                when (val append = items.loadState.append) {
                    is LoadState.Loading -> item { FooterLoading() }
                    is LoadState.Error -> item {
                        FooterError(onRetry = { items.retry() })
                    }
                    else -> Unit
                }
            }
        }
    }
}
```

下拉刷新（Material3）：

```kotlin
val refreshing = items.loadState.refresh is LoadState.Loading
// PullToRefreshBox(isRefreshing = refreshing, onRefresh = { items.refresh() }) { ... }
```

| API | 作用 |
|---|---|
| `collectAsLazyPagingItems()` | 把 `Flow<PagingData>` 变成 Compose 可消费的 items |
| `items[index]` | 取一项；可能为 `null`（占位开启时） |
| `items.refresh()` | 整表刷新（新 Source） |
| `items.retry()` | 重试失败的那次 load |
| `loadState.refresh` / `append` / `prepend` | 首次、向后、向前的加载状态 |

## 七、Room + 网络：`RemoteMediator` 概览

**单一数据源**（第 13 课）在分页里的标准形态：

1. UI **只读 Room** 的 `PagingSource`（Room 能直接生成）。
2. `RemoteMediator` 在需要时请求网络，把结果 **写入 Room**。
3. Room 表一变，本地 `PagingSource` 自动吐新页。

```kotlin
@Dao
interface UserDao {
    @Query("SELECT * FROM users ORDER BY id")
    fun pagingSource(): PagingSource<Int, UserEntity>   // Room 生成实现

    @Upsert
    suspend fun upsertAll(users: List<UserEntity>)

    @Query("DELETE FROM users")
    suspend fun clear()
}

class UserRemoteMediator(
    private val api: UserApi,
    private val db: AppDatabase
) : RemoteMediator<Int, UserEntity>() {

    override suspend fun load(
        loadType: LoadType,
        state: PagingState<Int, UserEntity>
    ): MediatorResult {
        return try {
            val page = when (loadType) {
                LoadType.REFRESH -> 1
                LoadType.PREPEND -> return MediatorResult.Success(endOfPaginationReached = true)
                LoadType.APPEND -> /* 用 RemoteKeys 表算出下一页 */ nextPage()
            }
            val resp = api.getUsers(page, state.config.pageSize)
            db.withTransaction {
                if (loadType == LoadType.REFRESH) db.userDao().clear()
                db.userDao().upsertAll(resp.data.map { it.toEntity() })
                // 同时写入/更新 RemoteKeys……
            }
            MediatorResult.Success(endOfPaginationReached = page >= resp.totalPages)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            MediatorResult.Error(e)
        }
    }
}

// ViewModel
val users = Pager(
    config = PagingConfig(pageSize = 20),
    remoteMediator = UserRemoteMediator(api, db),
    pagingSourceFactory = { db.userDao().pagingSource() }
).flow.cachedIn(viewModelScope)
```

`RemoteKeys`（另建一张表记 `userId → nextKey`）是官方示例的常规做法，细节以文档为准。本课先建立心智模型：**Mediator 写库，Source 读库，UI 不直接碰网络。**

离线时：Mediator 失败，但 Room 里已有缓存，列表仍可滚动已缓存部分。

## 八、易错点

1. **忘了 `cachedIn(viewModelScope)`**：反复创建 Source，重复请求。
2. **在 `load` 里吞掉 `CancellationException`**：协程取消异常被当成业务错误。
3. **`nextKey` 永远不返回 `null`**：无限请求同一页或空页。
4. **把 `PagingData` 当普通 List 去 `map` 乱改**：要用 `PagingData.map { }` 等操作符，且仍保持 Flow 链条。
5. **`items[index]` 空指针**：开启 placeholder 时可能为 null，先判空。
6. **REFRESH 不清本地又 upsert**：旧数据残留；或清了却没在事务里——用 `withTransaction`。
7. **pageSize 和接口 page size 对不齐**：首屏请求量怪异；`PagingConfig.pageSize` 应与后端约定一致或可整除。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 依赖 | `paging-runtime:3.5.3` + `paging-compose:3.5.3` |
| 定义一页 | `PagingSource.load` → `LoadResult.Page/Error` |
| 产出流 | `Pager(config) { source }.flow` |
| 缓存 | `.cachedIn(viewModelScope)` |
| Compose 收集 | `flow.collectAsLazyPagingItems()` |
| 列表 | `LazyColumn { items(count) { items[it]?.let { ... } } }` |
| 刷新 / 重试 | `items.refresh()` / `items.retry()` |
| 网络+Room | `RemoteMediator` 写库 + DAO `PagingSource` 读库 |

## 十、本课练习

1. 给第 13 课的用户列表改成 `UserPagingSource` + `Pager`，Compose 用 `collectAsLazyPagingItems` 显示。
2. 故意让第 2 页抛异常，确认底部出现 Error，点 `retry()` 能恢复。
3. （选做）画一张图：`REFRESH` / `APPEND` 时 Mediator、Room、UI 各做什么。

---

**下一课预告（第 24 课）：WorkManager 后台任务** —— 上传日志、定期同步：即使用户划掉 App，任务也能在约束满足时执行。
