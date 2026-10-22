# JNI 第 7 课：线程、JavaVM 与回调

> 适用读者：完成 JNI 第 1～6 课；看过 [[JNI学习大纲]] §12（`AttachCurrentThread` / `DetachCurrentThread`）。
> 核心收获：会在任意 native 线程上安全拿到 `JNIEnv`，用 RAII 或 `pthread_key` 保证线程退出前一定 detach，能写一个"C++ 工作线程 → 回调 Kotlin"的完整示例，并用 `callbackFlow` 把它包装成 Kotlin `Flow`。

---

## 一、回顾：为什么要 attach

笔记 §12 讲清楚了：**`JNIEnv` 跟线程绑定，不能跨线程传递**；自己创建的线程要先 `AttachCurrentThread` 才能调用 JNI，用完 `DetachCurrentThread`。第 2 课已经在 `JNI_OnLoad` 里保存了 `JavaVM* gVm`，**`JavaVM` 是进程唯一的，可以在任何线程上使用**。

本课补三件事：**判断当前线程是否已 attach**、**保证一定 detach**、**完整的回调示例**。

## 二、`GetEnv`：先问再 attach ⭐

```cpp
JNIEnv* getEnv() {
    JNIEnv* env = nullptr;
    jint r = gVm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (r == JNI_OK) return env;            // 已经 attach（比如 Kotlin 线程、主线程）
    if (r == JNI_EDETACHED) {               // 纯 native 线程，还没 attach
        JavaVMAttachArgs args{JNI_VERSION_1_6, "ndk-worker", nullptr};   // ⭐ 线程名会出现在 trace / ANR 里
        if (gVm->AttachCurrentThread(&env, &args) == JNI_OK) return env;
    }
    return nullptr;
}
```

- Android 的 `AttachCurrentThread` 第一个参数是 `JNIEnv**`；网上标准 JDK 的写法是 `void**`，照抄会编译报错。
- 对已经 attach 的线程再调用 `AttachCurrentThread`，什么都不会发生（返回同一个 env）。问题在于 **detach**：你没法知道该不该 detach。所以要先 `GetEnv`。

## 三、保证 detach：两种写法

线程 attach 之后不 detach 就退出，ART 会 abort：`thread exited without detaching`。中途 return、抛 C++ 异常都可能漏掉 detach。

**写法 A：`thread_local` + RAII**（推荐，简单）

```cpp
class ThreadEnv {
public:
    ThreadEnv() {
        jint r = gVm->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6);
        if (r == JNI_EDETACHED) {
            JavaVMAttachArgs args{JNI_VERSION_1_6, "ndk-worker", nullptr};
            if (gVm->AttachCurrentThread(&env_, &args) == JNI_OK) attached_ = true;
            else env_ = nullptr;
        }
    }
    ~ThreadEnv() { if (attached_) gVm->DetachCurrentThread(); }   // ⭐ 只 detach 自己 attach 的
    JNIEnv* get() const { return env_; }
private:
    JNIEnv* env_ = nullptr;
    bool attached_ = false;
};

JNIEnv* currentEnv() {
    thread_local ThreadEnv te;     // 每个线程第一次调用时 attach，线程退出时自动 detach
    return te.get();
}
```

**写法 B：`pthread_key_create` 析构函数**（官方 JNI tips 推荐的思路，适合 C 代码）

```cpp
static pthread_key_t gKey;
// JNI_OnLoad 里：
pthread_key_create(&gKey, [](void*) { gVm->DetachCurrentThread(); });
// attach 成功后：
pthread_setspecific(gKey, env);    // 值非空，线程退出时就会调用上面的析构函数
```

⚠️ **永远不要 detach Java 创建的线程**（主线程、Kotlin `Thread`、协程线程池的线程）。它们是 ART 自己 attach 的，由 ART 管理。两种写法都只 detach 自己 attach 的线程。

口诀：**先 GetEnv 问一下，自己 attach 的自己 detach，别人的不动。**

## 四、完整示例：C++ 工作线程回调 Kotlin ⭐

Kotlin 侧：

```kotlin
fun interface TickListener {
    @Keep fun onTick(count: Int)
}

object Ticker {
    external fun nativeStart(listener: TickListener)
    external fun nativeStop()
}
```

C++ 侧（`ticker.cpp`，在 `JNI_OnLoad` 里注册）：

```cpp
namespace {
std::thread gWorker;
std::atomic<bool> gRunning{false};
jobject gListener = nullptr;         // 全局引用（第 5 课）
jmethodID gOnTick = nullptr;          // 缓存（第 4 课）

void nativeStart(JNIEnv* env, jobject, jobject listener) {
    if (gRunning.exchange(true)) return;                 // 已经在运行
    gListener = env->NewGlobalRef(listener);             // ⭐ 局部引用不能带到别的线程
    jclass cls = env->GetObjectClass(listener);
    gOnTick = env->GetMethodID(cls, "onTick", "(I)V");
    env->DeleteLocalRef(cls);

    gWorker = std::thread([] {
        JNIEnv* wenv = currentEnv();                     // 本线程第一次调用会 attach
        if (!wenv) return;
        for (int i = 0; gRunning.load(); ++i) {
            wenv->CallVoidMethod(gListener, gOnTick, static_cast<jint>(i));
            if (wenv->ExceptionCheck()) { wenv->ExceptionDescribe(); wenv->ExceptionClear(); break; }
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    });                                                  // 线程结束 → thread_local 析构 → detach
}

void nativeStop(JNIEnv* env, jobject) {
    if (!gRunning.exchange(false)) return;
    if (gWorker.joinable()) gWorker.join();              // ⭐ 等线程结束后再删引用
    env->DeleteGlobalRef(gListener);
    gListener = nullptr;
}
}  // namespace
```

要点：

1. 传给 worker 线程的是**全局引用**，不是参数里的局部引用。
2. `std::atomic<bool>` 作为停止标志，不能用普通 `bool`（数据竞争）。
3. **先 join，再 `DeleteGlobalRef`**，否则 worker 可能还在使用 listener。
4. 不要在**主线程**调用会长时间阻塞的 `join`，否则可能 ANR；这里 worker 最多睡 500 ms，可以接受。
5. 在 worker 线程里，这个例子用的 jmethodID 是在 Kotlin 线程上查好的；如果要 `FindClass`，必须用第 4 课的缓存（系统 ClassLoader 问题）。

## 五、包装成 Kotlin `Flow`

Kotlin 课第 11 课学过 `callbackFlow`，正好用来包装 native 回调：

```kotlin
fun ticks(): Flow<Int> = callbackFlow {
    Ticker.nativeStart { count -> trySend(count) }   // 回调在 native 线程上执行，trySend 是线程安全的
    awaitClose { Ticker.nativeStop() }               // ⭐ 收集结束 / 取消时停止 native 线程
}

// ViewModel 里
val tickState = ticks().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)
```

回调在 `ndk-worker` 线程上执行，**不能直接更新 UI**。用 Flow 时，收集端在 `lifecycleScope` / Compose 里自然运行在主线程，不用手动切换。不用 Flow 的话，在 Kotlin 回调里用 `Handler(Looper.getMainLooper()).post { }` 或 `withContext(Dispatchers.Main)`。

## 六、更简单的选择：让 Kotlin 管线程

很多时候**根本不需要在 C++ 里创建线程**：

```kotlin
suspend fun heavyWork(data: ByteArray): Int = withContext(Dispatchers.Default) {
    NativeBridge.compute(data)       // 普通同步 native 方法，跑在协程线程池上
}
```

- 线程已经由 ART attach，不用管 attach / detach。
- `FindClass` 能用 App 的 ClassLoader。
- 取消、超时直接用协程那一套（第 8 课会讲怎样让 native 响应取消）。

**只有当 C++ 库自带线程（音视频解码、网络库、传感器回调）时，才需要本课第四节那套写法。**

## 七、易错点

1. **把 `JNIEnv*` 存成全局变量，在别的线程使用**：崩溃。要存 `JavaVM*`。
2. **native 线程没 attach 就调用 JNI**：崩溃。
3. **attach 之后线程退出前没 detach**：`thread exited without detaching`，abort。
4. **detach 了 Java 线程**（比如在 native 方法里随手调用 `DetachCurrentThread`）：ART 报错崩溃。
5. **把参数里的 `jobject` 直接交给 worker 线程**：局部引用不能跨线程，要先 `NewGlobalRef`。
6. **worker 线程里 `FindClass` 自己的类**：返回 null（第 4 课）。
7. **停止时先删全局引用再 join**：worker 使用已删除的引用，崩溃。
8. **worker 线程里长时间循环，不释放局部引用**：attach 的线程不会返回 Java，局部引用一直累积（第 5 课）。
9. **在回调里直接改 View**：`CalledFromWrongThreadException`。

## 八、速查表

| 需求 | 写法 |
|---|---|
| 保存 JavaVM | `JNI_OnLoad(JavaVM* vm, void*)` 里 `gVm = vm` |
| 判断是否已 attach | `gVm->GetEnv(..)` → `JNI_OK` / `JNI_EDETACHED` |
| attach 并命名 | `JavaVMAttachArgs{JNI_VERSION_1_6, "name", nullptr}` + `AttachCurrentThread(&env, &args)` |
| 自动 detach | `thread_local` RAII 或 `pthread_key_create` 析构函数 |
| 跨线程传对象 | `NewGlobalRef`，join 之后 `DeleteGlobalRef` |
| 停止标志 | `std::atomic<bool>` |
| 包装成 Flow | `callbackFlow { start { trySend(it) }; awaitClose { stop() } }` |
| 最省心的做法 | Kotlin `withContext(Dispatchers.Default)` 调用同步 native 方法 |

---

**下一课预告（第 8 课）：C++ 对象生命周期与 Kotlin 封装** —— 怎样让 Kotlin 对象"拥有"一个 C++ 对象？`jlong` 句柄、`AutoCloseable` + `use {}`、`Cleaner`；怎样把耗时的 native 调用包装成可取消的 `suspend` 函数。
