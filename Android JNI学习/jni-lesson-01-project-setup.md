# JNI 第 1 课：工程搭建与第一个 native 方法

> 适用读者：学完 Kotlin 系列课（会写 Kotlin、Gradle kts），看过自己的笔记 [[JNI学习大纲]] 第 1～4 节、[[CMakeLists.txt详解]]。
> 核心收获：在 AGP 9 + `build.gradle.kts` 下配好 NDK、CMake、ABI，掌握 Kotlin `external` 的四种写法和它们对应的 JNI 函数名（含转义规则），会检查 so 有没有打进 APK、符号有没有导出。

---

## 一、回顾：四个角色（详见 [[JNI学习大纲]] §1）

```
Kotlin external fun ──JNI 规范──▶ C++ 函数
        ▲                            │ NDK（clang 工具链）+ CMake 编译
        └──── System.loadLibrary ◀── libndk4study.so（按 ABI 打进 APK）
```

一句话：**JNI 是协议，NDK 是编译器，CMake 是构建脚本，so 是产物。** 这部分笔记已经讲清楚，本课重点补"现代工程配置"和"Kotlin 侧写法"。

## 二、Gradle 配置（AGP 9，kts）⭐

```kotlin
// app/build.gradle.kts
android {
    namespace = "com.fqf.ndk4study"
    compileSdk = 36
    ndkVersion = "30.0.16248370"          // ⭐ 显式锁定：r30 LTS

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")   // 多个 so 用 C++ 时需要（第 10 课）
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"            // SDK Manager 里装的版本
        }
    }
}
```

要点：

- **`ndkVersion` 一定要写**。不写的话 AGP 9.4 用它的默认版本 `28.2.13676358`，换台电脑、换个 AGP 版本，NDK 就跟着变，编译结果不可复现。
- **两个 `externalNativeBuild`**：`android { }` 里那个指定 CMakeLists 在哪；`defaultConfig { }` 里那个传 CMake 参数和编译选项。
- **ABI 选择**：`arm64-v8a` 是现在的主力，必选；`armeabi-v7a` 用于老 32 位设备；`x86_64` 用于模拟器。笔记里的 `x86`（32 位）可以删掉了。每多一个 ABI，编译时间和包体积都会增加；用 App Bundle 发布时，Play 只会把对应 ABI 下发给用户。
- CMake 版本：SDK 稳定通道目前有 3.22.1、3.31.6、4.1.2，选一个写死就行。`cmake_minimum_required` 写不高于它的版本。
- AGP 9 已经内置 Kotlin 编译，NDK 这部分配置和 Kotlin 插件无关。

## 三、CMakeLists：当前模板写法

```cmake
cmake_minimum_required(VERSION 3.22.1)
project("ndk4study")

add_library(${CMAKE_PROJECT_NAME} SHARED
        native-lib.cpp)

target_compile_features(${CMAKE_PROJECT_NAME} PRIVATE cxx_std_17)

target_link_libraries(${CMAKE_PROJECT_NAME}
        android
        log)
```

- `${CMAKE_PROJECT_NAME}` 就是 `project()` 里的名字，所以生成 `libndk4study.so`。也可以像你笔记里那样直接写库名，效果一样。
- **更正 [[find_library详解]]**：直接写 `log`、`android` 就是 Android Studio 当前模板的写法，不存在兼容性问题；`find_library` 能用，但不是必须的。
- 其他命令（`target_sources`、头文件目录、宏、多库）见 [[CMakeLists.txt详解]]。

## 四、Kotlin 侧：`external` 的四种写法 ⭐

Kotlin 用 `external` 关键字声明 native 方法（Java 用的是 `native`）。**Kotlin 代码写在哪里，决定了编译后的 Java 类名和方法是否 static**，JNI 函数名也就跟着不同：

```kotlin
package com.fqf.ndk4study

// ① 普通类的成员
class NativeLib {
    external fun stringFromJNI(): String
    companion object {
        init { System.loadLibrary("ndk4study") }   // 类加载时执行一次
    }
}

// ② object 单例（Kotlin 课第 2 课）
object NativeBridge {
    init { System.loadLibrary("ndk4study") }
    external fun add(a: Int, b: Int): Int
    @JvmStatic external fun version(): String
}

// ③ companion object
class Codec {
    companion object {
        external fun encode(x: Int): Int            // 不加 @JvmStatic
        @JvmStatic external fun decode(x: Int): Int // 加 @JvmStatic
    }
}

// ④ 顶层函数，文件名 Native.kt
external fun nativeHash(s: String): Long
```

对应的 C++ 函数（静态注册）：

| 写法 | 编译后的 Java 方法 | JNI 函数名 | 第二个参数 |
|---|---|---|---|
| ① 类成员 | `NativeLib.stringFromJNI()` 实例方法 | `Java_com_fqf_ndk4study_NativeLib_stringFromJNI` | `jobject thiz` |
| ② object | `NativeBridge.add()` 实例方法（在 INSTANCE 上） | `Java_com_fqf_ndk4study_NativeBridge_add` | `jobject`（INSTANCE） |
| ② + `@JvmStatic` | static 方法 | `Java_com_fqf_ndk4study_NativeBridge_version` | `jclass` |
| ③ 不加 `@JvmStatic` | `Codec$Companion.encode()` | `Java_com_fqf_ndk4study_Codec_00024Companion_encode` | `jobject` |
| ③ 加 `@JvmStatic` | `Codec.decode()` static | `Java_com_fqf_ndk4study_Codec_decode` | `jclass` |
| ④ 顶层函数 | `NativeKt.nativeHash()` static | `Java_com_fqf_ndk4study_NativeKt_nativeHash` | `jclass` |

推荐写法：**用 `object NativeXxx` 统一收纳 native 方法，在 `init` 里加载库**，Kotlin 调用方直接写 `NativeBridge.add(1, 2)`。

## 五、静态注册命名与转义规则 ⭐

[[JNI学习大纲]] §4 讲了 `Java_包名_类名_方法名`，但漏掉了转义规则：

| 原字符 | 在 JNI 函数名里写成 | 例子 |
|---|---|---|
| `.` 和 `/` | `_` | `com.fqf` → `com_fqf` |
| `_` | `_1` | 包名 `my_app` → `my_1app`；方法 `get_name` → `get_1name` |
| `$`（内部类、Companion） | `_00024` | `Codec$Companion` → `Codec_00024Companion` |
| `;` / `[` | `_2` / `_3` | 只在重载的签名部分出现 |
| 非 ASCII 字符 | `_0xxxx`（4 位十六进制） | 很少见 |

**重载方法**：同名 native 方法有多个时，函数名后面加 `__` 和参数签名：

```cpp
// external fun add(a: Int, b: Int): Int   和   external fun add(a: Long, b: Long): Long
extern "C" JNIEXPORT jint  JNICALL Java_com_fqf_ndk4study_NativeBridge_add__II(JNIEnv*, jobject, jint, jint);
extern "C" JNIEXPORT jlong JNICALL Java_com_fqf_ndk4study_NativeBridge_add__JJ(JNIEnv*, jobject, jlong, jlong);
```

这些规则很容易写错，所以正式项目一般用**动态注册**（第 2 课），完全不用管函数名。在 Android Studio 里对 `external fun` 按 Alt+Enter，可以自动生成正确的函数名，适合入门阶段。

## 六、第一个完整例子

```cpp
// src/main/cpp/native-lib.cpp
#include <jni.h>
#include <string>

extern "C" JNIEXPORT jint JNICALL
Java_com_fqf_ndk4study_NativeBridge_add(JNIEnv* env, jobject /* thiz */, jint a, jint b) {
    return a + b;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_fqf_ndk4study_NativeBridge_version(JNIEnv* env, jclass /* clazz */) {
    std::string v = "ndk4study 1.0";
    return env->NewStringUTF(v.c_str());
}
```

```kotlin
// Compose 里直接用（Kotlin 课第 15 课）
Text("1 + 2 = ${NativeBridge.add(1, 2)}，${NativeBridge.version()}")
```

- `extern "C"`：关闭 C++ 的名字改编（name mangling），让导出的符号名就是你写的函数名。
- `JNIEXPORT`：设成默认可见性，确保函数被导出，系统才找得到。`JNICALL` 在 Android 上是空宏，写上只是保持规范。

## 七、检查产物：so 打进去了吗，符号导出了吗

```bash
# 1. APK 里有哪些 so（Android Studio：Build > Analyze APK 也能看）
unzip -l app/build/outputs/apk/debug/app-debug.apk | grep '\.so'
#   lib/arm64-v8a/libndk4study.so
#   lib/arm64-v8a/libc++_shared.so

# 2. 导出了哪些 JNI 符号（NDK 自带的 llvm-nm）
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm -D --defined-only \
    app/build/intermediates/cxx/Debug/*/obj/arm64-v8a/libndk4study.so | grep Java_
```

Windows 上 `prebuilt` 目录是 `windows-x86_64`，PowerShell 查找 so 的命令见 [[JNI学习大纲]] §14.2。

`UnsatisfiedLinkError` 排查顺序：

1. `dlopen failed: library "libxxx.so" not found` → 库名写错，或者当前设备的 ABI 没有打包。
2. `No implementation found for ... NativeBridge.add` → 库已经加载，但函数名对不上：先用 `llvm-nm` 看导出名，对照第五节的转义规则。
3. 函数确实存在但名字被改编了（`_Z...` 开头）→ 漏了 `extern "C"`。

## 八、易错点

1. **不写 `ndkVersion`**：编译结果随 AGP 默认 NDK 变化，CI 和本地不一致。
2. **`System.loadLibrary("libndk4study.so")`**：只写 `"ndk4study"`。
3. **Kotlin `companion object` 里的方法按外部类名写 JNI 函数名**：没加 `@JvmStatic` 的话，类名是 `Xxx$Companion`，要写 `_00024Companion`。
4. **包名或方法名里有下划线，没写成 `_1`**：`No implementation found`。
5. **漏写 `extern "C"`**：符号被改编，找不到函数。
6. **object 里的方法当成 static，第二个参数写成 `jclass`**：类型对不上，虽然通常不会崩，但语义错了；加了 `@JvmStatic` 才是 `jclass`。
7. **在 `init` 之外的地方也调用 `loadLibrary`**：重复调用没有坏处，但应该集中在一个地方，方便管理。
8. **模拟器跑不起来**：模拟器是 `x86_64`，而 `abiFilters` 里没有它。

## 九、速查表

| 需求 | 写法 |
|---|---|
| 锁定 NDK | `ndkVersion = "30.0.16248370"` |
| 指定 CMakeLists | `externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }` |
| 选 ABI | `ndk { abiFilters += listOf("arm64-v8a", "x86_64") }` |
| 传 CMake 参数 | `defaultConfig.externalNativeBuild.cmake.arguments += "-DXXX=1"` |
| 声明 native 方法 | `external fun add(a: Int, b: Int): Int` |
| 加载库 | `init { System.loadLibrary("ndk4study") }` |
| 下划线转义 | `_` → `_1`，`$` → `_00024` |
| 重载 | `Java_..._add__II` |
| 看导出符号 | `llvm-nm -D --defined-only libxxx.so` |

---

**下一课预告（第 2 课）：动态注册、JNI_OnLoad 与 JavaVM** —— 你的笔记里已经有 `RegisterNatives` 的代码。下一课讲怎么按 Kotlin 类拆分注册、Kotlin 类型怎么对应 JNI 签名、用 `-fvisibility=hidden` 隐藏符号，以及 R8 会不会把 native 方法改名。
