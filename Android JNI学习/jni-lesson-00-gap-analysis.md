# Android JNI 笔记差距分析

> 对象：Obsidian「Android JNI学习」5 篇笔记——[[Android工程师C++入门教程]]、[[CMakeLists.txt详解]]、[[find_library详解]]、[[JNI学习大纲]]、[[JNI方法签名]]。
> 核对日期：2026-10-18；版本来源见文末。

## 一、已经写得好的（课程里只回顾、不重写）

- **C++ 入门**：类型、指针/引用、const、栈与堆、智能指针、头文件、日志宏，深度刚好够写 JNI。
- **CMake 基础**：`add_library` / `target_sources` / `target_include_directories` / `target_compile_features` / 宏 / 静态库与多 so，讲得清楚。
- **find_library**：`#include` 与链接的区别（`undefined reference`）讲得很到位。
- **方法签名**：基本类型、对象、数组、自定义类、常见错误，非常完整，可直接当速查表。
- **大纲**：JNI/NDK/CMake/so 的关系、静态注册、基本类型表、UnsatisfiedLinkError 排查思路、产物目录。

## 二、需要纠正或更新的

1. **「中文字符串要注意编码」说得不准**：`GetStringUTFChars` / `NewStringUTF` 用的是 **Modified UTF-8**。常用中文（BMP 内）和标准 UTF-8 字节一样；真正出问题的是 **emoji 等增补字符**（MUTF-8 用代理对，6 字节）和 `\0`。把文件/网络读来的标准 UTF-8 直接交给 `NewStringUTF`，开 CheckJNI 时会直接 abort。→ 第 3 课
2. **静态注册命名规则不完整**：没讲转义。包名/方法名里的 `_` 要写成 `_1`；Kotlin `companion object` 里的方法属于 `NativeLib$Companion`，`$` 要写成 `_00024`；重载方法要加 `__参数签名`。另外，「签名不匹配导致 UnsatisfiedLinkError」只对动态注册和重载方法成立，普通静态注册只按函数名匹配。→ 第 1、2 课
3. **find_library 笔记里「直接写 `log` 兼容性差」已过时**：当前 Android Studio Native C++ 模板就是 `target_link_libraries(${CMAKE_PROJECT_NAME} android log)`。两种写法都对，`find_library` 不是必须的。
4. **Gradle 配置是 Groovy 写法，也没有锁定 NDK 版本**：AGP 9.4 默认用 NDK `28.2.13676358`，当前 LTS 是 **r30（`30.0.16248370`）**，建议在 `build.gradle.kts` 里显式写 `ndkVersion`。CMake 可以选 SDK 稳定通道里的 3.22.1 / 3.31.6 / 4.1.2。→ 第 1 课
5. **`abiFilters` 里还写着 `x86`**：32 位 x86 模拟器已经基本不用了。现在的组合是 `arm64-v8a`（必需），加上 `armeabi-v7a`（老设备）、`x86_64`（模拟器）。
6. **「线程结束前要 detach」不完整**：只能 detach 自己 attach 的线程，不能 detach Java 创建的线程。推荐用 `thread_local` RAII 或 `pthread_key` 析构函数自动 detach。→ 第 7 课
7. **异常处理只写了 Describe + Clear**：`ExceptionDescribe` 只适合调试。正式代码要么把异常留给 Kotlin（直接 return），要么转换处理。原生代码主动抛异常用 `ThrowNew`。→ 第 6 课

## 三、偏薄的

- 数组释放模式只有一句话：缺 `0 / JNI_COMMIT / JNI_ABORT`、`isCopy`、`Get/SetArrayRegion`、Critical。
- 调用 Java 只讲了 `GetMethodID`：缺静态方法、构造对象（`<init>`）、ID 缓存、Kotlin 属性和 getter 的对应关系。
- 引用管理：缺循环里的局部引用泄漏、`PushLocalFrame`、弱全局引用、`IsSameObject`。
- 崩溃排查：只提了 tombstone，缺符号化工具链。

## 四、完全缺失的（课程重点补充）

| 主题 | 课 |
|---|---|
| AGP 9 + `build.gradle.kts` 的 NDK 配置、Kotlin `external` 的各种写法（class / object / companion / 顶层函数） | 1 |
| Kotlin 类型 → JNI 签名对照（`Int?`、`IntArray`、函数类型）、`javap -s`、`-fvisibility=hidden`、R8 | 2 |
| Modified UTF-8、`GetStringUTFRegion`、direct `ByteBuffer` 零拷贝 | 3 |
| 缓存 `jclass` / `jmethodID`、**native 线程上 FindClass 的 ClassLoader 问题**、`@Keep` / R8 规则、`fun interface` 回调 | 4 |
| 弱全局引用、局部帧、RAII 封装 | 5 |
| `ThrowNew`、C++ 异常不能越过 JNI 边界 | 6 |
| Attach 的 RAII、native 线程回调转 Kotlin `callbackFlow` | 7 |
| **C++ 对象生命周期**：`jlong` 句柄、`AutoCloseable`、`Cleaner`、与 ViewModel 和协程配合 | 8 |
| ndk-stack、llvm-addr2line、LLDB、CheckJNI、**HWASan**（ASan 自 2023 年起不再受支持）、`debugSymbolLevel` | 9 |
| 预编译 so（IMPORTED）、jniLibs 重复打包问题、Prefab、STL 选择（`c++_shared`）、**16 KB 页大小** | 10 |
| JNI 性能模型与最佳实践 | 11 |
| 综合项目：`AndroidBitmap` 原生灰度图 + Kotlin 协程 + Compose | 12 |

## 五、版本与来源

- NDK：当前 LTS **r30 = `30.0.16248370`**（developer.android.com/ndk/downloads）；r29 发布于 2025 年 10 月（NDK revision history）。
- AGP 9.4：默认 NDK `28.2.13676358`，需要 Gradle 9.6.0、JDK 17（developer.android.com/build/releases/gradle-plugin）。
- CMake：SDK 稳定通道有 3.22.1 / 3.31.6 / 4.0.x / 4.1.2（dl.google.com/android/repository/repository2-3.xml）。
- 16 KB：NDK r28+ 默认 16 KB 对齐，AGP 8.5.1+ 打包对齐；Play 要求 target ≥ 35 的应用支持 16 KB，**2027-02-01 起**不支持的更新将无法发布（developer.android.com/guide/practices/page-sizes）。
- ASan：自 2023 年起不再受支持，改用 HWASan（arm64、Android 14+ 可用 wrap.sh）（developer.android.com/ndk/guides/asan、/hwasan）。
