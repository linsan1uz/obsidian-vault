# Kotlin 第 10b 课：LiveData 示例与老办法对比

> 适用读者：看过第 9 课 ViewModel、第 10 课 LiveData / StateFlow 讲解；手上有 `coroutineStudy` 工程。
> 核心收获：亲手点一遍"老办法为什么危险"和"LiveData 怎样自动绑生命周期"，看懂 `map` / `switchMap` / `liveData{}` / `asLiveData`，以及粘性事件的坑和 SharedFlow / Channel 修法。

---

## 一、Demo 在哪

工程：`C:\Users\Linsan\AndroidStudioProjects\coroutineStudy`，包名 `com.fqf.coroutinestudy`。

| 文件 | 作用 |
|---|---|
| `app/.../livedata/OldWayActivity.kt` | 老办法 ①②③ 可点击演示；④ RxJava 仅注释 |
| `app/.../livedata/OldWayDataSource.kt` | ② 用的应用内单例监听列表 |
| `app/.../livedata/LiveDataDemoViewModel.kt` | LiveData / map / switchMap / liveData{} / asLiveData / 事件 |
| `app/.../livedata/LiveDataDemoActivity.kt` | 观察 ViewModel，演示旋转与粘性坑 |
| `app/.../livedata/RxJavaDemoActivity.kt` | RxJava 3 可运行示例：正确 dispose vs 忘记 dispose，Rx→LiveData 桥接 |
| `app/.../res/layout/activity_rxjava_demo.xml` | RxJava 页布局 |
| `app/.../res/layout/activity_old_way.xml` | 老办法页布局 |
| `app/.../res/layout/activity_livedata_demo.xml` | LiveData 页布局 |
| `app/.../test/.../livedata/LiveDataDemoViewModelTest.kt` | map / switchMap / load 单测 |
| `MainActivity` + `activity_main.xml` | 「老办法示例」「LiveData 示例」「RxJava 示例」按钮 |
| `AndroidManifest.xml` | 注册了两个新 Activity |

Logcat 统一过滤 tag：**`LiveDataDemo`**。

依赖：`lifecycle-livedata-ktx 2.11.0`；Loader 经 `appcompat → fragment → loader:1.0.0` 传递；RxJava **`io.reactivex.rxjava3:rxjava:3.1.12`** + **`rxandroid:3.0.2`**；桥接用 `lifecycle-reactivestreams-ktx:2.11.0`。

---

## 二、老办法怎么点、会看到什么

主界面点 **「老办法示例」**。

### ① 回调 + Handler

1. 点「① 回调 + Handler（3s）」。
2. **立刻旋转屏幕或按返回**。
3. Logcat 大约 3 秒后出现：

```
① 回调到达 Activity@旧hash isDestroyed=true
① ⚠️ 死 Activity 仍被回调（真实项目里改 UI 就可能崩）
```

原因：`Thread` + `Handler.post` 抓住了旧 Activity 的回调，**生命周期管不着它**。

关键片段：

```kotlin
Thread {
    Thread.sleep(3000)
    mainHandler.post { callback.onLoaded(result) }  // 不检查 isDestroyed
}.start()
```

### ② 手动监听 DataSource

1. 点「② 手动监听 DataSource（3s）」，等结果（本 demo **正确**在 `onStart`/`onStop` 配对注册注销）。
2. 源码里注释写了：若去掉 `onStop` 的 `unregister`，反复进出页面 → `listenerCount` 只增不减 → **泄漏**。

```kotlin
override fun onStart() {
    OldWayDataSource.register(dataListener)   // 可见时注册
}
override fun onStop() {
    OldWayDataSource.unregister(dataListener) // ⚠️ 忘了这一行就泄漏
    super.onStop()
}
```

### ③ AsyncTaskLoader（已废弃）

1. 点「③ AsyncTaskLoader」。
2. 它比裸 Handler 好一点：配置变化后结果会交给新 Activity。
3. 但 API 啰嗦，官方已推荐 **ViewModel + LiveData** 替代；代码里 `@Suppress("DEPRECATION")`。

### ④ RxJava（可运行 Demo）

主界面点 **「RxJava 示例」** → `RxJavaDemoActivity`。

| 按钮 | 行为 |
|---|---|
| ✅ Single / Observable | `subscribeOn(IO)` + `observeOn(Main)`，订阅丢进 `CompositeDisposable`，`onDestroy` 里 `clear()` |
| ❌ 忘记 dispose | 订阅**不**放进袋子；点完立刻返回 → 约 3s 后 Logcat：`死 Activity 仍被 Rx 回调` |
| 桥接 Rx → LiveData | `Observable.toFlowable()` + `Publisher.toLiveData()`（lifecycle-reactivestreams 2.11），观察者销毁时自动取消上游 |

正确写法要点：

```kotlin
private val disposables = CompositeDisposable()

val d = Single.fromCallable { Thread.sleep(3000); "数据" }
    .subscribeOn(Schedulers.io())
    .observeOn(AndroidSchedulers.mainThread())
    .subscribe { text -> tvResult.text = text }
disposables.add(d)

override fun onDestroy() {
    disposables.clear()   // ⭐ 页面销毁必须清
    super.onDestroy()
}
```

版本：`rxjava 3.1.12`、`rxandroid 3.0.2`（Maven Central 当前稳定版）。

---

## 三、LiveData 怎么点、会看到什么

主界面点 **「LiveData 示例」**。

### 存活旋转 + 销毁后不再回调

1. 看顶部 `Activity@…` / `ViewModel@…` 的 hashCode。
2. 点「开始加载」，**立刻旋转**。
3. 新页面 hashCode 变了，**ViewModel 的 hashCode 不变**；约 3 秒后 `message` 更新。
4. Logcat：**不会**再出现对旧 Activity 的 observe 回调（对比①的警告）。

```kotlin
private val _message = MutableLiveData("尚未加载")
val message: LiveData<String> = _message

fun load() {
    viewModelScope.launch {
        _loading.value = true
        val result = withContext(Dispatchers.IO) {
            delay(3000)
            "LiveData 加载完成 @…"
        }
        _message.value = result          // 主线程；后台线程用 postValue
        _loading.value = false
    }
}

// Activity：
vm.message.observe(this) { text -> tvMessage.text = "message：$text" }
```

### map / switchMap / liveData{} / asLiveData

| 控件 / 日志 | 对应 API |
|---|---|
| `display` 行自动带「【展示】」前缀 | `message.map { }` |
| 「switchMap #1 / #2」 | `_userId.switchMap { id -> liveData {…} }` |
| 进入页面就出现的问候语 | `val autoGreeting = liveData(Dispatchers.IO) {…}` |
| 每 2 秒跳一下的 ticker | `flow {…}.asLiveData()` |

### 粘性事件坑

1. 点「粘性Toast」→ 弹出一次。
2. **旋转屏幕** → Toast **再弹一次**（新观察者立刻收到最后一次值）。
3. 再分别点「SharedFlow」「Channel」后旋转 → **不会**再弹。

```kotlin
// ❌ 粘性
_stickyEvent.value = msg

// ✅ SharedFlow（replay=0）
_toastShared.emit(msg)

// ✅ Channel（每条只消费一次）
_toastChannel.send(msg)
```

Activity 侧用 `repeatOnLifecycle(STARTED)` 收集 SharedFlow / Channel。

---

## 四、对比表

| | 回调+Handler | 手动监听 | Loader | RxJava 3 | LiveData | 再往后 |
|---|---|---|---|---|---|---|
| 旋转后数据 | 易丢 / 打到死页面 | 看你怎么存 | 能交给新页面 | 看你怎么存 | ViewModel 里还在 | StateFlow 同理 |
| 销毁后自动停 | ❌ | 靠自己 unregister | 部分 | 靠自己 dispose | ✅ observe 自动移除 | ✅ |
| 忘了解绑 | 泄漏/崩 | 泄漏 | — | 泄漏 | 很难忘 | 很难忘 |
| 官方态度 | 旧 | 旧 | **Deprecated** | 可用但偏重 | 仍支持 | **新代码优先 StateFlow** |

口诀：**数据放 ViewModel，界面用 observe；事件别用 LiveData，改 SharedFlow / Channel；Rx 订阅必须 dispose。**

---

## 五、单测

```
app/src/test/java/com/fqf/coroutinestudy/livedata/LiveDataDemoViewModelTest.kt
```

- `InstantTaskExecutorRule`：LiveData 在当前线程同步执行。
- `Dispatchers.setMain(UnconfinedTestDispatcher())`：让 `viewModelScope` 能跑。
- 三个用例：`map_prefixes_message`、`switchMap_loads_user_for_id`、`load_sets_message_value`。

运行：`gradlew assembleDebug testDebugUnitTest`（`JAVA_HOME` 指向 Android Studio 的 JBR）。

`app/build.gradle.kts` 里加了 `testOptions { unitTests.isReturnDefaultValues = true }`，否则 JVM 单测调用 `Log.d` 会报 `Method d not mocked`。现有 9 个单测 + 本课 3 个 = **12 个全部通过**。

---

## 六、和第 10 课的衔接

本课是第 10 课的**动手对照**：先感受老办法的痛，再确认 LiveData 解了什么。新业务仍然更推荐第 10 课的 **StateFlow + `repeatOnLifecycle`**；LiveData 懂原理、能读旧代码即可。

---

**下一课预告**：继续第 11 课协程进阶 / Flow（若已学过可直接做 Room）。


---

## 💬 课后问答：`load()` 和 `loadWithPostValue()` 有什么区别？

两个方法做的事一样，都是假加载完以后更新 `_message`。区别在**协程跑在哪个线程上**，所以写 LiveData 的方式也不一样。

```kotlin
// load()：主线程启动，耗时部分切到 IO，回到主线程用 value
viewModelScope.launch {                       // 默认在主线程
    _loading.value = true
    val result = withContext(Dispatchers.IO) { delay(3000); "..." }  // 只有这段在 IO
    _message.value = result                   // 已经回到主线程
}

// loadWithPostValue()：整个协程都在 IO 线程，只能用 postValue
viewModelScope.launch(Dispatchers.IO) {
    _loading.postValue(true)
    delay(2000)
    _message.postValue("...")                 // 子线程写 value 会崩溃
}
```

| | `value =` | `postValue()` |
|---|---|---|
| 能在哪个线程调用 | 只能在主线程 | 任何线程 |
| 生效时机 | 同步，立刻生效，下一行就能读到新值 | 异步，排进主线程队列，稍后才生效 |
| 连续调用 | 每次都通知观察者 | ⭐ 主线程还没处理时连发多次，只有最后一次生效 |

- `postValue(true)` 后面紧跟着 `postValue(false)`，界面可能根本不会显示 loading。
- `load()` 开头有 `if (_loading.value == true) return`，可以防止连点重复加载；`loadWithPostValue()` 没有。
- **推荐 `load()` 的写法**：在主线程启动，耗时部分用 `withContext(IO)` 包起来，状态都用 `value` 改。`postValue` 只在确实身处后台线程、拿不到协程时使用，比如老的回调 API。

> 口诀：**主线程 value，子线程 post；post 是异步、会合并，连发只认最后一次。**


---

## 💬 课后问答：`_loading.value = true` 是在 setValue 吗？这是 Kotlin 的写法吗？

是的，**这就是在调用 `setValue(true)`**，是 Kotlin 访问 Java getter/setter 的写法。

LiveData 是用 Java 写的，类里只有一对普通方法：

```java
public T getValue() { ... }
protected void setValue(T value) { ... }   // 到了 MutableLiveData 里改成 public
```

⭐ Kotlin 的规则：Java 类里有 `getXxx()` / `setXxx()` 这样的方法，在 Kotlin 里就能当成属性 `xxx` 来用，编译后还是调那两个方法。

```kotlin
_loading.value = true          // 编译后等于 _loading.setValue(true)
val v = _loading.value         // 编译后等于 _loading.getValue()
_loading.setValue(true)        // 也对，只是 IDE 会提示你改成属性写法
```

同理：`textView.text = "hi"` 实际调的是 `setText()`，`intent.extras` 调的是 `getExtras()`。

### 两个细节

- **为什么对外暴露 `LiveData` 后，外面改不了值？** `LiveData.setValue` 是 `protected`，在外面只能用 `value` 读，写不了；只有 `MutableLiveData` 把它改成了 `public`。这就是"私有 Mutable、公开 LiveData"能起作用的原因。
- **为什么要写 `_count.value ?: 0`？** Java 的 `getValue()` 可能返回 null，所以 Kotlin 里拿到的 `value` 是可空的 `Int?`，要用 `?:` 给一个默认值。
- `postValue` 没有对应的 `getXxx`，它就只是个普通方法，只能写成 `postValue(...)`。

> 口诀：**Java 的 get/set 到了 Kotlin 就是属性；`.value =` 就是 setValue。**


---

## 💬 课后问答：observe 的参数、LiveData 与 EventBus

### ① `observe` 还能传什么参数？

```kotlin
fun observe(owner: LifecycleOwner, observer: Observer<in T>)
fun observeForever(observer: Observer<in T>)        // 没有 owner
```

第一个参数只要是 **`LifecycleOwner`** 就行，不一定是 Activity：

| 传入 | 说明 |
|---|---|
| `this`（`ComponentActivity` / `AppCompatActivity`） | 最常见 |
| `viewLifecycleOwner`（Fragment 里）⭐ | Fragment 里应该用这个，跟着 View 的生命周期走 |
| `this`（Fragment 本身） | 能用但不推荐，View 重建时会重复观察 |
| `navBackStackEntry` | 跟着导航页的生命周期走 |
| `ProcessLifecycleOwner.get()` | 整个 App 的前后台生命周期 |
| `LifecycleService` | 能观察 LiveData 的 Service |
| 自定义 `LifecycleOwner`（内部用 `LifecycleRegistry`） | 自己控制生命周期 |

`observeForever` 不绑定生命周期，一直收数据，**用完必须手动 `removeObserver`**，否则会泄漏。

### ② 为什么说 LiveData 能代替 EventBus？

以前很多人用 EventBus 只是为了"后台拿到数据通知界面"或者"Fragment 之间传数据"。这两件事现在可以这样做：
- ViewModel 加 LiveData/StateFlow：数据变了界面自动收到，还懂生命周期，不用手动 register/unregister。
- 共享 ViewModel（`by activityViewModels()`）：同一个 Activity 下的多个 Fragment 观察同一份数据。

所以替代的是**页面内、页面之间**的那部分通信。LiveData 是粘性的，也不适合做全局事件总线。

### ③ 跨模块、多对多的解耦通信，谁来代替？

自己写一个单例，里面放 `SharedFlow`：

```kotlin
// common 模块
sealed interface AppEvent {
    data object LoggedOut : AppEvent
    data class CartChanged(val count: Int) : AppEvent
}

@Singleton
class AppEventBus @Inject constructor() {
    private val _events = MutableSharedFlow<AppEvent>(extraBufferCapacity = 16)
    val events: SharedFlow<AppEvent> = _events
    suspend fun emit(e: AppEvent) = _events.emit(e)
}

// 任意模块：发
bus.emit(AppEvent.LoggedOut)

// 任意模块：收（跟着生命周期）
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        bus.events.collect { e -> /* ... */ }
    }
}
```

如果是"共享状态"，比如登录状态、购物车数量，更推荐放进 **Repository 里的 StateFlow**，让它当唯一数据源，而不是发事件。

### ④ Hilt 不是解决依赖注入的吗？

对，Hilt 本身不负责通信。它在这里只做一件事：**把同一个 `@Singleton` 的 `AppEventBus` 实例交给每个模块**。各模块只依赖 common 模块里的这个类，彼此不直接引用，这样就解耦了。真正收发事件的是 SharedFlow。

### ⑤ 安卓官方有没有自己的 EventBus 替代？

**没有现成的库。** 以前官方的 `LocalBroadcastManager` 已经废弃。官方建议按场景用：

| 场景 | 官方方案 |
|---|---|
| ViewModel → 界面 | StateFlow / LiveData |
| Fragment ↔ Fragment | 共享 ViewModel，或 Fragment Result API（`setFragmentResult`） |
| 页面回传结果 | Activity Result API（`registerForActivityResult`） |
| 一次性事件 | 用 UI 状态表示，或用 Channel / SharedFlow |
| 跨模块、全局 | Repository 的 StateFlow，或自己写的 SharedFlow 单例（交给 Hilt 注入） |
| 跨进程 | 系统广播 / AIDL |

> 口诀：**页面内用 StateFlow，Fragment 间用共享 ViewModel 或 FragmentResult，全局用 SharedFlow 单例，Hilt 只负责把同一个实例送到各处。**
