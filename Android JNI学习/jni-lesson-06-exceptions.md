# JNI 第 6 课：异常处理

> 适用读者：完成 JNI 第 1～5 课；看过 [[JNI学习大纲]] §11（`ExceptionCheck` / `ExceptionDescribe` / `ExceptionClear`）。
> 核心收获：理解"挂起异常"模型和异常挂起时允许调用的函数，会在调用 Kotlin 之后正确检查，会用 `ThrowNew` 抛出 Kotlin 能 `catch` 的异常并立即返回，会用统一封装防止 C++ 异常越过 JNI 边界。

---

## 一、回顾与纠正

笔记里的三个函数都对，但"`ExceptionDescribe` + `ExceptionClear`"只是**打印后吞掉**异常，相当于 Kotlin 里写 `catch (e: Exception) { e.printStackTrace() }`。真实项目里还需要：

1. 决定是**清除后自己处理**，还是**直接返回，让异常传回 Kotlin**。
2. 会**从 C++ 主动抛出**异常。
3. 处理 **C++ 自己的异常**（`std::bad_alloc`、`std::runtime_error`）。

## 二、挂起异常模型 ⭐

Kotlin 里抛异常会立即跳转。**JNI 不会**：Kotlin 方法抛出异常后，`CallVoidMethod` 照常返回到 C++，异常只是被"挂起"（pending）在当前线程上，C++ 代码继续往下执行。

```cpp
env->CallVoidMethod(listener, onProgress, 50);   // Kotlin 里抛了异常
// ⬇ C++ 照样往下执行，异常挂起中
env->CallVoidMethod(listener, onProgress, 60);   // ❌ 带着挂起的异常调用 JNI → CheckJNI 直接 abort
```

CheckJNI 报错：`JNI DETECTED ERROR IN APPLICATION: JNI CallVoidMethod called with pending exception java.lang.IllegalStateException`。

**规则：异常挂起时，只能调用少数几个 JNI 函数**，主要是：

- 检查和清除异常：`ExceptionCheck`、`ExceptionOccurred`、`ExceptionDescribe`、`ExceptionClear`
- 清理资源：`DeleteLocalRef`、`DeleteGlobalRef`、`DeleteWeakGlobalRef`、`ReleaseStringUTFChars`、`ReleaseStringChars`、`Release<Type>ArrayElements`、`ReleasePrimitiveArrayCritical`、`MonitorExit`、`PopLocalFrame`

其他函数一律先处理异常再调用。

口诀：**调完 Kotlin 先查异常；有异常只做清理，然后 return。**

## 三、哪些调用后需要检查

| 调用 | 失败时 |
|---|---|
| `Call*Method`、`NewObject` | Kotlin 代码抛出的任何异常 |
| `FindClass` | 返回 null，挂起 `NoClassDefFoundError` |
| `GetMethodID` / `GetFieldID` | 返回 null，挂起 `NoSuchMethodError` / `NoSuchFieldError` |
| `NewStringUTF`、`New<Type>Array` | 返回 null，挂起 `OutOfMemoryError` |
| `Get<Type>ArrayRegion` | 越界时挂起 `ArrayIndexOutOfBoundsException` |

返回指针或对象的，可以直接判断 null；返回 `void` 或基本类型的，用 `ExceptionCheck()`。

## 四、两种处理方式

**方式 A：直接返回，让 Kotlin 接住**（最常用、最简单）

```cpp
void process(JNIEnv* env, jobject, jobject listener) {
    for (int p = 0; p <= 100; p += 10) {
        env->CallVoidMethod(listener, gOnProgress, static_cast<jint>(p));
        if (env->ExceptionCheck()) return;    // ⭐ native 方法返回后，Kotlin 侧会收到这个异常
    }
}
```

```kotlin
try {
    NativeBridge.process { p -> check(p < 50) { "太快了" } }
} catch (e: IllegalStateException) {
    Log.e("TAG", "回调里抛出了", e)       // ✅ 能接到
}
```

**方式 B：在 C++ 里清除并处理**

```cpp
jobject result = env->CallObjectMethod(obj, gParse, input);
if (jthrowable ex = env->ExceptionOccurred()) {
    env->ExceptionClear();                    // ⭐ 先清除，之后才能调用其他 JNI 函数
    jclass cls = env->GetObjectClass(ex);
    jmethodID getMessage = env->GetMethodID(cls, "getMessage", "()Ljava/lang/String;");
    auto msg = static_cast<jstring>(env->CallObjectMethod(ex, getMessage));
    // ... 记录日志或者降级处理（msg 可能是 null）...
    env->DeleteLocalRef(msg);
    env->DeleteLocalRef(cls);
    env->DeleteLocalRef(ex);
    return fallbackValue;
}
```

## 五、从 C++ 抛出异常：`ThrowNew` ⭐

```cpp
bool throwJava(JNIEnv* env, const char* className, const char* msg) {
    jclass cls = env->FindClass(className);
    if (!cls) return false;                         // FindClass 失败本身已挂起 NoClassDefFoundError
    env->ThrowNew(cls, msg);
    env->DeleteLocalRef(cls);                       // 挂起时允许 DeleteLocalRef
    return true;
}

jint divide(JNIEnv* env, jobject, jint a, jint b) {
    if (b == 0) {
        throwJava(env, "java/lang/IllegalArgumentException", "除数不能为 0");
        return 0;                                   // ⭐ ThrowNew 不会跳转！必须自己 return
    }
    return a / b;
}
```

- **`ThrowNew` 只是"挂起"一个异常**，函数会继续往下执行，一定要紧跟着 `return`。返回值会被忽略，随便给一个默认值即可。
- Kotlin 侧看到的就是普通异常：`catch (e: IllegalArgumentException)`。
- 抛自定义异常：`"com/fqf/ndk4study/NativeException"`，记得用 `@Keep` 保护它的 `(String)` 构造函数（第 4 课）。
- 常用：`IllegalArgumentException`（参数错误）、`IllegalStateException`（状态错误）、`java/io/IOException`、`OutOfMemoryError`。

## 六、C++ 异常不能越过 JNI 边界 ⭐

NDK 默认开启 C++ 异常（`-fexceptions`），所以 `std::vector`、`std::stoi`、`new` 都可能抛异常。**C++ 异常如果从 native 方法里抛出、没被 catch，越过 JNI 边界回到 ART，会直接调用 `std::terminate`，进程 abort**，Kotlin 的 `try/catch` 接不住。

解决：**在每个 native 入口用 try/catch 包起来，转换成 Java 异常**：

```cpp
// jni_helper.h
template <typename F>
auto jniGuard(JNIEnv* env, F&& body) -> decltype(body()) {
    using R = decltype(body());
    try {
        return body();
    } catch (const std::bad_alloc&) {
        throwJava(env, "java/lang/OutOfMemoryError", "native 内存不足");
    } catch (const std::invalid_argument& e) {
        throwJava(env, "java/lang/IllegalArgumentException", e.what());
    } catch (const std::exception& e) {
        throwJava(env, "java/lang/RuntimeException", e.what());
    } catch (...) {
        throwJava(env, "java/lang/RuntimeException", "未知 native 异常");
    }
    if constexpr (!std::is_void_v<R>) return R{};
}
```

```cpp
jint parseInt(JNIEnv* env, jobject, jstring text) {
    return jniGuard(env, [&]() -> jint {
        ScopedUtfChars s(env, text);              // 第 3 课的 RAII 类
        if (!s.c_str()) throw std::runtime_error("字符串为空");
        return std::stoi(s.c_str());              // 非数字时抛 std::invalid_argument
    });
}
```

需要 `#include <type_traits>`、`<stdexcept>`、`<new>`。如果 `ScopedUtfChars` 里转换失败，JNI 已经挂起了 OOM，这时不要再 `ThrowNew`，可以在 `throwJava` 开头加 `if (env->ExceptionCheck()) return true;`。

反方向也一样：**Java 异常不会变成 C++ 异常**，`try/catch` 抓不到挂起的 Java 异常，只能用 `ExceptionCheck`。

## 七、调试：CheckJNI 会告诉你

模拟器默认开启 CheckJNI；真机执行 `adb shell setprop debug.checkjni 1` 后重启 App（第 9 课）。和异常相关的典型报错：

| 报错 | 含义 |
|---|---|
| `called with pending exception` | 有异常没处理，就继续调用了 JNI |
| `JNI FindClass called with pending exception` | 通常是前一个 `GetMethodID` 失败了没检查 |
| `terminating with uncaught exception of type std::...` | C++ 异常越过了边界 |

## 八、易错点

1. **`ThrowNew` 之后没有 return**：代码继续执行，后面的 JNI 调用又触发 pending exception 错误。
2. **调用 Kotlin 后不检查异常**：下一个 JNI 调用 abort。
3. **只 `ExceptionDescribe` + `ExceptionClear`**：异常被吞，Kotlin 侧无法感知。
4. **`ExceptionOccurred` 之后没先 `ExceptionClear`，就去调用 `getMessage`**：违反规则。
5. **以为 C++ 的 `try/catch` 能抓 Java 异常**：抓不到。
6. **C++ 异常没 catch 就越过边界**：进程直接 abort。
7. **`FindClass` 失败后又 `ThrowNew` 别的异常**：已经挂起了一个异常，不能再抛第二个。
8. **自定义异常被 R8 删掉了构造函数**：`ThrowNew` 失败。

## 九、速查表

| 需求 | API / 写法 |
|---|---|
| 有没有异常 | `ExceptionCheck()` → `jboolean` |
| 拿到异常对象 | `ExceptionOccurred()` → `jthrowable`（局部引用） |
| 打印到 logcat | `ExceptionDescribe()`（是否顺带清除因实现而异，要清除就显式 `ExceptionClear`） |
| 清除 | `ExceptionClear()` |
| 抛出 | `ThrowNew(cls, msg)` + **立即 return** |
| 抛出已有对象 | `Throw(jthrowable)` |
| 致命错误 | `FatalError("msg")`，直接终止进程 |
| C++ 异常转 Java | 每个入口包一层 `jniGuard` |

---

**下一课预告（第 7 课）：线程、JavaVM 与回调** —— native 线程怎么拿到 `JNIEnv`？什么时候 attach / detach？怎么把 C++ 工作线程的结果回调给 Kotlin，并包装成 `Flow`？
