# JNI 第 8 课：C++ 对象生命周期与 Kotlin 封装

> 适用读者：完成 JNI 第 1～7 课。你的笔记里还没有这一部分，本课从零讲起。
> 核心收获：会用 `jlong` 句柄让 Kotlin 对象持有一个 C++ 对象，用 `AutoCloseable` + `use {}` 确定性地释放，用 `Cleaner` 兜底，避免 use-after-free 和 double free，并把耗时的 native 调用包装成可取消的 `suspend` 函数，接入 ViewModel。

---

## 一、问题：C++ 对象谁来管

前几课的 native 方法都是"无状态"的：传参、计算、返回。真实场景里 C++ 端常常有**状态**：一个解码器、一个数据库连接、一个图像处理管线。它们用 `new` 创建，必须 `delete`。

Kotlin 有 GC，C++ 没有。**GC 只管 Java 堆，看不到 C++ 堆**，Kotlin 对象被回收时，C++ 对象不会跟着释放。我们需要一座桥。

## 二、`jlong` 句柄模式 ⭐

把 C++ 指针转成 64 位整数，存在 Kotlin 对象里：

```cpp
// counter.cpp
class Counter {
public:
    explicit Counter(int start) : value_(start) {}
    int increment() { return ++value_; }
private:
    int value_;
};

jlong nativeCreate(JNIEnv*, jclass, jint start) {
    return reinterpret_cast<jlong>(new Counter(start));          // 指针 → jlong
}

jint nativeIncrement(JNIEnv*, jclass, jlong handle) {
    return reinterpret_cast<Counter*>(handle)->increment();      // jlong → 指针
}

void nativeDestroy(JNIEnv*, jclass, jlong handle) {
    delete reinterpret_cast<Counter*>(handle);
}
```

- 用 **`jlong`**，不要用 `jint`：64 位设备上指针是 8 字节，`jint` 会截断。
- 函数参数是 `jclass`，因为 Kotlin 侧会写成 `@JvmStatic`（见下文）。**把句柄作为参数传进来**，比在 C++ 里用 `GetLongField` 读 Kotlin 字段更快、更简单，也不怕 R8 改字段名。

## 三、Kotlin 封装：`AutoCloseable` + `use {}` ⭐

```kotlin
class NativeCounter(start: Int) : AutoCloseable {
    private var handle: Long = nativeCreate(start)

    fun increment(): Int {
        check(handle != 0L) { "NativeCounter 已关闭" }          // ⭐ 防止 use-after-free
        return nativeIncrement(handle)
    }

    override fun close() {
        if (handle != 0L) {
            nativeDestroy(handle)
            handle = 0L                                          // ⭐ 防止 double free
        }
    }

    private companion object {
        @JvmStatic external fun nativeCreate(start: Int): Long
        @JvmStatic external fun nativeIncrement(handle: Long): Int
        @JvmStatic external fun nativeDestroy(handle: Long)
    }
}

// 用法：离开代码块时自动 close，即使中途抛异常
NativeCounter(10).use { c ->
    println(c.increment())    // 11
}
```

- `use {}` 是 Kotlin 标准库对 `AutoCloseable` 的扩展，相当于 Java 的 try-with-resources。
- 静态注册时，companion 里的 `@JvmStatic external` 方法在 `NativeCounter` 类上，签名是 `(I)J`、`(J)I`、`(J)V`。
- 对外**只暴露 Kotlin API**，`external` 方法全部 `private`，调用方不会接触到裸句柄。

口诀：**句柄用 jlong，关闭后清零，调用前检查。**

## 四、兜底：`Cleaner`（不要用 `finalize`）

调用方忘了 `close()` 怎么办？`finalize()` 已被废弃，执行时机和线程都不确定，还会拖慢 GC。API 33+ 可以用 `java.lang.ref.Cleaner`：

```kotlin
class NativeCounter(start: Int) : AutoCloseable {
    private val handle = nativeCreate(start)
    private val cleanable = CLEANER.register(this, Releaser(handle))   // ⭐ this 被 GC 时执行

    fun increment(): Int = nativeIncrement(handle)    // 简化，实际需要和 close 互斥
    override fun close() = cleanable.clean()          // clean() 最多只会执行一次

    private class Releaser(private val h: Long) : Runnable {
        override fun run() = nativeDestroy(h)
    }

    private companion object {
        val CLEANER: Cleaner = Cleaner.create()
        @JvmStatic external fun nativeCreate(start: Int): Long
        @JvmStatic external fun nativeIncrement(handle: Long): Int
        @JvmStatic external fun nativeDestroy(handle: Long)
    }
}
```

⚠️ `Releaser` **不能引用 `NativeCounter` 本身**（不能是内部类，也不能用捕获了 `this` 的 Lambda），否则对象永远不会被回收。所以只把 `handle` 传进去。

`Cleaner` 只是**兜底**：时机不确定，C++ 对象可能占用大量内存（比如图片缓冲区），GC 根本感觉不到压力。**主路径永远是显式 `close()`。** minSdk 低于 33 时只用 `close()`，或者在 Debug 包里检测"忘记关闭"并打日志。

## 五、线程安全与 use-after-free

```kotlin
// 线程 A                          // 线程 B
counter.increment()                counter.close()
//  ↑ 检查 handle != 0 通过……       //  ↑ ……这时 delete 了
//  ↑ 然后使用已删除的指针 → 崩溃
```

`check(handle != 0L)` 只能防止单线程里的误用。多个线程共享一个 native 对象时，至少要：

- Kotlin 侧给 `increment` 和 `close` 加同一把锁（`synchronized(lock)` 或 `Mutex`）；或者
- 规定这个对象只能在一个线程（一个协程上下文）里使用，像 Kotlin 课第 20 课的"线程封闭"。

C++ 对象内部如果被多个线程同时调用，还要用 `std::mutex` 保护自己的状态。

## 六、包装成可取消的 `suspend` 函数 ⭐

耗时操作（比如处理一张大图要 2 秒）应该放到后台，并且能被取消：

```cpp
class Processor {
public:
    std::atomic<bool> cancelled{false};
    int run() {
        for (int step = 0; step < 100; ++step) {
            if (cancelled.load()) return -1;          // ⭐ 定期检查取消标志
            std::this_thread::sleep_for(std::chrono::milliseconds(20));   // 模拟一步工作
        }
        return 42;
    }
};

jint nativeRun(JNIEnv*, jclass, jlong h)    { return reinterpret_cast<Processor*>(h)->run(); }
void nativeCancel(JNIEnv*, jclass, jlong h) { reinterpret_cast<Processor*>(h)->cancelled = true; }
```

```kotlin
suspend fun process(): Int = coroutineScope {
    val work = async(Dispatchers.Default) { nativeRun(handle) }   // 阻塞一个后台线程
    try {
        work.await()
    } catch (e: CancellationException) {
        nativeCancel(handle)       // ⭐ 外部取消时 await 立即抛出，这里通知 C++ 停下
        throw e                    // coroutineScope 会等 work 真正返回后才结束（结构化并发）
    }
}
```

- 协程的取消是**协作式**的（Kotlin 课第 11 课）：native 代码在跑时，协程没法打断它，只能**设置标志，让 C++ 自己退出**。
- `nativeCancel` 只写一个 atomic，不会和 `run` 冲突；`coroutineScope` 保证 `process()` 返回时 `run` 已经结束，之后 `close()` 才安全（第五节）。
- ⚠️ 不要用 `job.invokeOnCompletion`：它要等协程**完全结束**才回调，而协程正卡在 native 里结束不了。

## 七、接入 ViewModel

```kotlin
class CounterViewModel : ViewModel() {
    private val counter = NativeCounter(0)
    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count.asStateFlow()

    fun onClick() { _count.value = counter.increment() }

    override fun onCleared() {
        counter.close()          // ⭐ ViewModel 销毁时释放 C++ 对象
    }
}
```

ViewModel 的生命周期比 Activity 长，正好用来持有 native 对象：转屏时不会重建，页面真正退出时 `onCleared()` 释放（Kotlin 课第 9 课）。如果 `viewModelScope` 里还有协程在使用它，要先取消、等协程结束再 close。

## 八、易错点

1. **用 `jint` 存指针**：64 位设备上截断，崩溃。
2. **`close()` 之后不清零**：再调用 `close()` → double free；再调用方法 → use-after-free。
3. **依赖 `finalize` 或 `Cleaner` 释放大块内存**：GC 不知道 native 内存的压力，迟迟不回收。
4. **`Cleaner` 的清理动作引用了被追踪的对象本身**：对象永远不会被回收，等于泄漏。
5. **一个线程在 `run`，另一个线程 `close`**：use-after-free，要加锁或线程封闭。
6. **以为取消协程就能打断 native 代码**：只能让 C++ 检查标志位自己退出。
7. **在 C++ 里用 `GetLongField` 读 Kotlin 的 `handle` 字段**：慢，还怕 R8 改名。直接作为参数传。
8. **把 `external` 方法暴露给外部**：调用方可能传一个随便写的 `Long`。

## 九、速查表

| 需求 | 写法 |
|---|---|
| 创建 | `reinterpret_cast<jlong>(new T(...))` |
| 使用 | `reinterpret_cast<T*>(handle)->method()` |
| 销毁 | `delete reinterpret_cast<T*>(handle)` |
| Kotlin 封装 | `class X : AutoCloseable`，`handle` 私有，`close()` 后清零 |
| 自动关闭 | `X().use { ... }` |
| 兜底释放 | `Cleaner.create().register(this, releaser)`（API 33+） |
| 可取消 | `async(Default) { nativeRun }` + `await` 处 catch `CancellationException` → `nativeCancel` 设置 atomic 标志 |
| 生命周期 | ViewModel 持有，在 `onCleared()` 中 `close()` |

---

**下一课预告（第 9 课）：Native 崩溃排查与调试** —— 看懂 `Fatal signal 11 (SIGSEGV)` 和 tombstone，用 `ndk-stack` / `llvm-addr2line` 把地址还原成代码行，用 LLDB 断点调试 C++，用 CheckJNI 和 HWASan 抓内存错误。
