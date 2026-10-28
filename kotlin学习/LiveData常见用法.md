# LiveData 常见用法

> 配套项目：`coroutineStudy` 的 `livedata/` 包（Logcat tag `LiveDataDemo`）。详细讲解见 [[kotlin-lesson-10-LiveData与StateFlow]]、[[kotlin-lesson-10b-LiveData示例与老办法对比]]。

依赖（lifecycle 2.11.0）：

```kotlin
implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.11.0")          // LiveData、map/switchMap、asLiveData
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")
implementation("androidx.activity:activity-ktx:1.13.0")                     // by viewModels()
implementation("androidx.lifecycle:lifecycle-reactivestreams-ktx:2.11.0")   // Rx → LiveData
implementation("io.reactivex.rxjava3:rxjava:3.1.12")
implementation("io.reactivex.rxjava3:rxandroid:3.0.2")
```

---

## 1. 普通 value + observe

ViewModel 里用 `MutableLiveData` 存数据、对外只暴露只读的 `LiveData`；主线程用 `value =`（就是 `setValue`）修改，Activity 用 `observe` 接收。页面销毁后会自动停止回调。

```kotlin
class CounterViewModel : ViewModel() {
    private val _count = MutableLiveData(0)
    val count: LiveData<Int> = _count

    fun add() { _count.value = (_count.value ?: 0) + 1 }   // 主线程
}

class CounterActivity : AppCompatActivity() {
    private val vm: CounterViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_counter)
        vm.count.observe(this) { n -> findViewById<TextView>(R.id.tv).text = "点了 $n 次" }
        findViewById<Button>(R.id.btn).setOnClickListener { vm.add() }
    }
}
// Fragment 里用 observe(viewLifecycleOwner) { ... }
```

## 2. postValue（后台线程更新）

在子线程里不能用 `value =`（会抛异常），要用 `postValue`。它是**异步**的：把新值排进主线程队列稍后生效；主线程处理前连发多次，只有最后一次生效。

```kotlin
fun loadWithPostValue() {
    viewModelScope.launch(Dispatchers.IO) {        // 全程在 IO 线程
        _loading.postValue(true)
        delay(2000)                                // 假装网络请求
        _message.postValue("加载完成")
        _loading.postValue(false)
    }
}

// 更推荐：主线程启动，只把耗时部分切到 IO，回来后用 value
fun load() = viewModelScope.launch {
    _loading.value = true
    _message.value = withContext(Dispatchers.IO) { delay(2000); "加载完成" }
    _loading.value = false
}
```

## 3. Transformations：map、switchMap

把一个 LiveData 转成另一个。`map` 做**同步换算**；`switchMap` 每次源变化就**换一个新的 LiveData 数据源**，并丢弃旧的那个（适合"id 变了重新查询"）。

```kotlin
private val _userId = MutableLiveData<Int>()

// map：Int → String
val countText: LiveData<String> = count.map { "当前 $it 次" }

// switchMap：userId 变了，就换成查询新用户的 LiveData
val user: LiveData<String> = _userId.switchMap { id ->
    liveData(Dispatchers.IO) {
        emit("加载用户 #$id …")
        delay(1500)
        emit("用户#$id（假数据）")
    }
}

fun loadUser(id: Int) { _userId.value = id }
```

> 旧写法 `Transformations.map(source) { }` 已被 Kotlin 扩展函数 `source.map { }` 取代，效果一样。

## 4. MediatorLiveData（合并多个源）

`MediatorLiveData` 可以 `addSource` 监听多个 LiveData，任何一个变化都重新计算结果。例如：用户名和密码都不为空时才启用登录按钮。

```kotlin
class LoginViewModel : ViewModel() {
    val username = MutableLiveData("")
    val password = MutableLiveData("")

    val canLogin = MediatorLiveData<Boolean>().apply {
        fun update() {
            value = !username.value.isNullOrBlank() && !password.value.isNullOrBlank()
        }
        addSource(username) { update() }
        addSource(password) { update() }
    }
}

// Activity
vm.canLogin.observe(this) { enabled -> loginButton.isEnabled = enabled }
```

> `map`、`switchMap` 内部就是用 MediatorLiveData 实现的。注意：MediatorLiveData 只有在**自己被观察**时才会去监听它的源。

## 5. 把 Flow 或 Rx 转成 LiveData

- **Flow → LiveData**：用 `asLiveData()`，它在 `lifecycle-livedata-ktx` 里，**不需要** reactivestreams。
- **Rx → LiveData**：用 `lifecycle-reactivestreams-ktx` 的 `toLiveData()`，只接受 `Publisher`（即 `Flowable`），所以 `Observable`/`Single` 要先转成 `Flowable`。

```kotlin
// Flow → LiveData（有观察者时才收集，观察者全部离开 timeoutInMs 后停止）
private val tickerFlow = flow {
    var n = 0
    while (true) { emit("tick=$n"); n++; delay(2000) }
}
val ticker: LiveData<String> = tickerFlow.asLiveData(timeoutInMs = 2000L)

// Rx → LiveData
import androidx.lifecycle.toLiveData

val rxText: LiveData<String> =
    Single.fromCallable { Thread.sleep(2000); "Rx 加载完成" }
        .subscribeOn(Schedulers.io())
        .toFlowable()               // Single → Flowable（Publisher）
        .toLiveData()               // 页面销毁时自动取消订阅，不用手动 dispose
```

> Rx 的错误不会被 LiveData 处理，上游出错会直接崩溃，转换前要先 `onErrorReturn { ... }`。

---

## 速查表

| 用法 | 关键 API | 什么时候用 |
|---|---|---|
| 普通更新 | `value =` + `observe` | 主线程改数据，界面自动刷新 |
| 后台更新 | `postValue()` | 确实在子线程、拿不到协程时 |
| 换算 | `map { }` | 一个值派生出另一个值 |
| 换数据源 | `switchMap { }` | 参数变了重新查询 |
| 合并 | `MediatorLiveData.addSource` | 多个 LiveData 共同决定结果 |
| Flow 转换 | `asLiveData()` | Repository 返回 Flow，界面还用 LiveData |
| Rx 转换 | `Flowable.toLiveData()` | 老项目里的 Rx 接到 LiveData |

> 口诀：**私有 Mutable、公开 LiveData；主线程 value、子线程 post；换算 map、换源 switchMap、合并 Mediator；Flow 用 asLiveData，Rx 先转 Flowable 再 toLiveData。**
