# JNI 第 2 课：动态注册、JNI_OnLoad 与 JavaVM

> 适用读者：完成 JNI 第 1 课；看过 [[Android工程师C++入门教程]] §16（RegisterNatives / JNI_OnLoad 代码）和 [[JNI方法签名]]。
> 核心收获：用工程化方式组织动态注册（按 Kotlin 类拆分文件），掌握 Kotlin 类型到 JNI 签名的对照，用 `javap -s` 查签名，保存 `JavaVM`，用 `-fvisibility=hidden` 只导出 `JNI_OnLoad`，搞清 R8 混淆和 native 方法的关系。

---

## 一、回顾：动态注册三件套

你的笔记里已有完整代码（[[Android工程师C++入门教程]] §16、[[JNI方法签名]] §13）：

1. 写 `static` C++ 函数（不需要 `extern "C"`，函数名随便起）。
2. 用 `JNINativeMethod` 数组列出 `{Kotlin 方法名, 签名, 函数指针}`。
3. 在 `JNI_OnLoad` 里 `FindClass` + `RegisterNatives`。

`System.loadLibrary` 加载 so 时，系统会自动调用 `JNI_OnLoad`。本课补充：**工程里怎么组织、签名怎么写对、出错时会发生什么**。

## 二、按 Kotlin 类拆分注册 ⭐

一个 `JNI_OnLoad` 里注册所有类，很快会变得一团乱。推荐**每个 Kotlin 类一个 cpp 文件 + 一个注册函数**：

```
src/main/cpp/
├── jni_onload.cpp          // 只负责总入口
├── jni_helper.h            // 公共工具：日志、注册宏
├── native_bridge.cpp       // 对应 Kotlin object NativeBridge
└── image_native.cpp        // 对应 Kotlin object ImageNative（第 12 课）
```

```cpp
// jni_helper.h
#pragma once
#include <jni.h>
#include <iterator>          // std::size
#include <android/log.h>
#define LOG_TAG "ndk4study"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

inline bool registerNatives(JNIEnv* env, const char* className,
                            const JNINativeMethod* methods, int count) {
    jclass clazz = env->FindClass(className);
    if (clazz == nullptr) {                      // 有 NoClassDefFoundError 挂着
        LOGE("FindClass failed: %s", className);
        return false;
    }
    bool ok = env->RegisterNatives(clazz, methods, count) == JNI_OK;
    if (!ok) LOGE("RegisterNatives failed: %s", className);   // 有 NoSuchMethodError 挂着
    env->DeleteLocalRef(clazz);
    return ok;
}
```

```cpp
// native_bridge.cpp
#include "jni_helper.h"

namespace {                                       // 匿名命名空间 = 只在本文件可见（同 static）
jint add(JNIEnv*, jobject, jint a, jint b) { return a + b; }
jstring version(JNIEnv* env, jclass) { return env->NewStringUTF("1.0"); }

const JNINativeMethod kMethods[] = {
    {"add",     "(II)I",                 reinterpret_cast<void*>(add)},
    {"version", "()Ljava/lang/String;",  reinterpret_cast<void*>(version)},
};
}

bool register_NativeBridge(JNIEnv* env) {
    return registerNatives(env, "com/fqf/ndk4study/NativeBridge",
                           kMethods, std::size(kMethods));   // C++17 std::size 替代 sizeof 除法
}
```

```cpp
// jni_onload.cpp
#include "jni_helper.h"

JavaVM* gVm = nullptr;                            // ⭐ 全局保存，第 7 课线程要用
bool register_NativeBridge(JNIEnv* env);
bool register_ImageNative(JNIEnv* env);

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    gVm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;

    if (!register_NativeBridge(env) || !register_ImageNative(env)) return JNI_ERR;
    return JNI_VERSION_1_6;
}
```

- `JNI_OnLoad` 已经在 `jni.h` 里声明为 C 链接，所以定义时不用再写 `extern "C"`（笔记里的写法是对的）。
- 返回 `JNI_ERR` 时，Kotlin 那边的 `System.loadLibrary` 会抛 `UnsatisfiedLinkError`。注册失败时，问题会在**加载库那一刻**就暴露出来，而不是等到调用方法时才崩，这是动态注册的一大好处。
- `RegisterNatives` 失败后会有 `NoSuchMethodError` 挂起，返回 `JNI_ERR` 后 Kotlin 会看到它，日志里能看出是哪个方法写错了。

## 三、Kotlin 类型 → JNI 签名 ⭐

[[JNI方法签名]] 是按 Java 类型写的。Kotlin 有几处要特别注意：

| Kotlin | 编译后 Java | 签名 | C++ 参数类型 |
|---|---|---|---|
| `Int` / `Long` / `Boolean` / `Double` | `int` / `long` / `boolean` / `double` | `I` / `J` / `Z` / `D` | `jint` / `jlong` / `jboolean` / `jdouble` |
| `Unit` | `void` | `V` | — |
| `String` / `String?` | `String` | `Ljava/lang/String;` | `jstring` |
| ⚠️ `Int?` | `Integer` | `Ljava/lang/Integer;` | `jobject` |
| `IntArray` | `int[]` | `[I` | `jintArray` |
| ⚠️ `Array<Int>` | `Integer[]` | `[Ljava/lang/Integer;` | `jobjectArray` |
| `ByteArray` | `byte[]` | `[B` | `jbyteArray` |
| `Array<String>` | `String[]` | `[Ljava/lang/String;` | `jobjectArray` |
| `List<String>` | `List` | `Ljava/util/List;` | `jobject` |
| `(Int) -> Unit` | `Function1` | `Lkotlin/jvm/functions/Function1;` | `jobject` |
| `Bitmap` | `Bitmap` | `Landroid/graphics/Bitmap;` | `jobject` |

口诀：**可空的基本类型会装箱，`Array<Int>` 也会装箱；要原始数组就用 `IntArray`。**

### 用 `javap -s` 查签名，不靠手写

```bash
# 找到 Kotlin 编译出来的 class 文件（不同 AGP 版本输出目录不同，用 find 找最稳）
find app/build -name 'NativeBridge.class'
javap -s -p path/to/com/fqf/ndk4study/NativeBridge.class
#   public final native int add(int, int);
#     descriptor: (II)I
```

`descriptor` 那一行就是 `RegisterNatives` 里要填的签名，直接复制。

## 四、只导出 JNI_OnLoad：`-fvisibility=hidden`

动态注册后，C++ 函数不再需要导出。把默认可见性改成 hidden：

```cmake
target_compile_options(${CMAKE_PROJECT_NAME} PRIVATE -fvisibility=hidden)
```

- so 里只剩 `JNIEXPORT` 标记的符号（`JNI_OnLoad`），体积更小，加载更快，也不容易被逆向看出函数名。
- ⚠️ 如果同一个库里还有**静态注册**的函数，它们必须带 `JNIEXPORT`，否则在 hidden 模式下找不到。
- 用第 1 课的 `llvm-nm -D --defined-only` 检查效果。

## 五、R8 / 混淆与 native 方法

Release 构建开启 R8 后，Kotlin 类名和方法名会被缩短。会影响 JNI 吗？

- AGP 默认的 `proguard-android-optimize.txt` 里有这一条：

```
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
```

  意思是**包含 native 方法的类，它的类名和 native 方法名都不会被改**。所以静态注册的函数名、动态注册里 `FindClass` 用的类名，都还能对上。
- **但 C++ 反过来调用的 Kotlin 方法和字段不在保护范围内**（第 4 课），需要自己加 `@Keep` 或 keep 规则。
- 签名里出现的自定义类（如 `Lcom/fqf/ndk4study/User;`）：`includedescriptorclasses` 会保留它们的类名。

## 六、`JavaVM` 与 `JNIEnv` 的分工

| | `JavaVM*` | `JNIEnv*` |
|---|---|---|
| 数量 | 进程里只有一个 | 每个线程一个 |
| 能否跨线程保存 | ✅ 存成全局变量 | ❌ 只能在当前线程用 |
| 从哪拿 | `JNI_OnLoad` 参数，或 `env->GetJavaVM(&vm)` | JNI 函数参数，或 `vm->GetEnv` / `AttachCurrentThread` |
| 用途 | 拿到某个线程的 env | 调用所有 JNI 函数 |

第 7 课的线程回调全靠第二节保存下来的 `gVm`。

`JNI_OnUnload`：只有加载这个 so 的 ClassLoader 被回收时才会调用，**App 里基本不会发生**，不要依赖它做清理。

## 七、易错点

1. **`FindClass` 用 `.` 写类名**：要写 `com/fqf/ndk4study/NativeBridge`。
2. **签名按 Kotlin 直觉手写**：`Int?`、`Array<Int>` 都会装箱，签名完全不同。用 `javap -s` 确认。
3. **`JNINativeMethod` 第一项写成 C++ 函数名**：它要的是 **Kotlin 方法名**。
4. **注册时 Kotlin 类名对了，但方法定义在 `companion object` 里且没加 `@JvmStatic`**：方法实际在 `Xxx$Companion` 类上，要么注册到 `com/fqf/ndk4study/Xxx$Companion`，要么加 `@JvmStatic`。
5. **`JNI_OnLoad` 失败了还返回 `JNI_VERSION_1_6`**：错误被藏起来，等到调用时才报 `UnsatisfiedLinkError`，很难查。
6. **开了 `-fvisibility=hidden`，静态注册函数却没加 `JNIEXPORT`**：找不到实现。
7. **把 `JNIEnv*` 存成全局变量给其他线程用**：要存的是 `JavaVM*`。
8. **依赖 `JNI_OnUnload` 释放资源**：它基本不会被调用。

## 八、速查表

| 需求 | 写法 |
|---|---|
| 方法表 | `JNINativeMethod m[] = {{"add", "(II)I", (void*)add}};` |
| 注册 | `env->RegisterNatives(clazz, m, std::size(m))` |
| 入口 | `JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*)`，成功返回 `JNI_VERSION_1_6` |
| 拿 env | `vm->GetEnv((void**)&env, JNI_VERSION_1_6)` |
| 查签名 | `javap -s -p Xxx.class` |
| 装箱陷阱 | `Int?` → `Ljava/lang/Integer;`，`Array<Int>` → `[Ljava/lang/Integer;` |
| 隐藏符号 | `target_compile_options(... -fvisibility=hidden)` |
| 文件内私有函数 | 匿名 `namespace { }` 或 `static` |

---

**下一课预告（第 3 课）：字符串与数组深入** —— 「中文要注意编码」到底是什么问题？Modified UTF-8、数组释放的三种模式、`GetArrayRegion`、Critical，以及零拷贝的 direct `ByteBuffer`。
