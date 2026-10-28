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
| `app/.../res/layout/activity_old_way.xml` | 老办法页布局 |
| `app/.../res/layout/activity_livedata_demo.xml` | LiveData 页布局 |
| `app/.../test/.../livedata/LiveDataDemoViewModelTest.kt` | map / switchMap / load 单测 |
| `MainActivity` + `activity_main.xml` | 多了「老办法示例」「LiveData 示例」两个按钮 |
| `AndroidManifest.xml` | 注册了两个新 Activity |

Logcat 统一过滤 tag：**`LiveDataDemo`**。

依赖：`lifecycle-livedata-ktx 2.11.0`（已有）；Loader 通过 `appcompat → fragment → androidx.loader:loader:1.0.0` 传递进来，**没有新增 RxJava**。

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

### ④ RxJava（不引入依赖）

```kotlin
// 仅作对照，本工程未添加 RxJava
Observable.fromCallable { Thread.sleep(3000); "Rx 数据" }
    .subscribeOn(Schedulers.io())
    .observeOn(AndroidSchedulers.mainThread())
    .subscribe { text -> tvResult.text = text }  // 必须保存 Disposable，销毁时 dispose()
```

忘了 `dispose()` = 和忘记 `unregister` 同一类问题。

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

| | 回调+Handler | 手动监听 | Loader | RxJava（仅推 UI） | LiveData | 再往后 |
|---|---|---|---|---|---|---|
| 旋转后数据 | 易丢 / 打到死页面 | 看你怎么存 | 能交给新页面 | 看你怎么存 | ViewModel 里还在 | StateFlow 同理 |
| 销毁后自动停 | ❌ | 靠自己 unregister | 部分 | 靠自己 dispose | ✅ observe 自动移除 | ✅ |
| 忘了解绑 | 泄漏/崩 | 泄漏 | — | 泄漏 | 很难忘 | 很难忘 |
| 官方态度 | 旧 | 旧 | **Deprecated** | 可用但偏重 | 仍支持 | **新代码优先 StateFlow** |

口诀：**数据放 ViewModel，界面用 observe；事件别用 LiveData，改 SharedFlow / Channel。**

---

## 五、单测

```
app/src/test/java/com/fqf/coroutinestudy/livedata/LiveDataDemoViewModelTest.kt
```

- `InstantTaskExecutorRule`：LiveData 在当前线程同步执行。
- `Dispatchers.setMain(UnconfinedTestDispatcher())`：让 `viewModelScope` 能跑。
- 三个用例：`map_prefixes_message`、`switchMap_loads_user_for_id`、`load_sets_message_value`。

运行：`gradlew assembleDebug testDebugUnitTest`（`JAVA_HOME` 指向 Android Studio 的 JBR）。

---

## 六、和第 10 课的衔接

本课是第 10 课的**动手对照**：先感受老办法的痛，再确认 LiveData 解了什么。新业务仍然更推荐第 10 课的 **StateFlow + `repeatOnLifecycle`**；LiveData 懂原理、能读旧代码即可。

---

**下一课预告**：继续第 11 课协程进阶 / Flow（若已学过可直接做 Room）。
