# JNI 第 10 课：预编译库、第三方库与打包

> 适用读者：完成 JNI 第 1～9 课；看过 [[CMakeLists.txt详解]]（多个库、静态库）和 [[find_library详解]]。
> 核心收获：会用 `jniLibs` 和 CMake `IMPORTED` 两种方式接入别人给的 `.so` / `.a`，知道两者不能同时用；会用源码和 Prefab 引入第三方库；会选 STL；理解 so 加载顺序、ABI 与包体积；能检查并满足 Google Play 的 16 KB 页大小要求。

---

## 一、回顾：自己的库已经会了

[[CMakeLists.txt详解]] 已经讲清楚了 `add_library`、`target_link_libraries`、一个工程里构建多个库、静态库链接到动态库。本课解决的是**别人的库**：只给了你编译好的二进制，或者给了源码，或者发布在 Maven 上。

补充一条纠正（gap-analysis 里也提到了）：[[find_library详解]] 说直接写 `target_link_libraries(... log android)` 兼容性差，这个说法已经过时。NDK 的工具链会自动找到系统库，**Android Studio 现在的新建模板就是直接写库名**。`find_library` 能用，但不是必须的。

## 二、方式一：`jniLibs`——只打包，不链接

别人给的 `libfoo.so`，你的 C++ **不需要直接调用它**（比如它自己带 JNI 接口，Kotlin 直接 `System.loadLibrary("foo")`）：

```
app/src/main/jniLibs/
├── arm64-v8a/libfoo.so
├── armeabi-v7a/libfoo.so
└── x86_64/libfoo.so
```

AGP 会把它原样打包进 APK 的 `lib/<abi>/`。**每个你声明支持的 ABI 都要放一份**，少了的 ABI 在对应设备上会 `UnsatisfiedLinkError`。

## 三、方式二：CMake `IMPORTED`——你的 C++ 要调用它 ⭐

你的 `libndk4study.so` 要调用 `libfoo.so` 里的函数，就要在 CMake 里**链接**它：

```
app/src/main/cpp/
├── CMakeLists.txt
└── third_party/foo/
    ├── include/foo.h
    └── lib/
        ├── arm64-v8a/libfoo.so
        ├── armeabi-v7a/libfoo.so
        └── x86_64/libfoo.so
```

```cmake
set(FOO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/foo)

add_library(foo SHARED IMPORTED)                    # IMPORTED：不编译，只声明"它已经存在"
set_target_properties(foo PROPERTIES
    IMPORTED_LOCATION ${FOO_DIR}/lib/${ANDROID_ABI}/libfoo.so     # ⭐ ${ANDROID_ABI} 按当前 ABI 选文件
    INTERFACE_INCLUDE_DIRECTORIES ${FOO_DIR}/include)

target_link_libraries(${CMAKE_PROJECT_NAME} foo android log)
```

- 静态库同理：`add_library(foo STATIC IMPORTED)`，路径指向 `libfoo.a`。静态库会被合并进你的 so，不需要单独打包。
- 设置了 `INTERFACE_INCLUDE_DIRECTORIES` 后，链接它的 target 自动获得头文件路径。

⚠️ **AGP 4.0 起，CMake 里 `IMPORTED` 的 SHARED 库会被自动打包进 APK。** 如果你又把同一个 so 放进了 `jniLibs`，构建会报错：`2 files found with path 'lib/arm64-v8a/libfoo.so'`。**二选一**：要链接就用 `IMPORTED`，并且不要放进 `jniLibs`。

口诀：**只加载放 jniLibs，要链接用 IMPORTED，两者别重复。**

## 四、方式三：源码集成与 Prefab

**有源码，并且它自带 CMakeLists**：直接作为子项目编译，ABI 和编译参数与你的工程完全一致，最省心：

```cmake
add_subdirectory(third_party/tinyjson)              # 里面定义了 target tinyjson
target_link_libraries(${CMAKE_PROJECT_NAME} tinyjson)
```

**发布在 Maven 上的 native 库：Prefab**。AAR 里同时带头文件和各 ABI 的 so，Gradle 下载后自动生成 CMake 配置。以 Google 的音频库 Oboe 为例：

```kotlin
android {
    buildFeatures { prefab = true }
}
dependencies {
    implementation("com.google.oboe:oboe:<最新稳定版>")    // 版本以 Maven 上为准
}
```

```cmake
find_package(oboe REQUIRED CONFIG)                 # Prefab 生成的配置
target_link_libraries(${CMAKE_PROJECT_NAME} oboe::oboe android log)
```

不用手动管理 so 和头文件，升级时只改版本号。能用 Prefab 就优先用 Prefab。

## 五、STL：`c++_static` 还是 `c++_shared` ⭐

C++ 标准库（`std::string`、`std::vector`……）本身也是一个库，NDK 用的是 LLVM 的 libc++：

| | `c++_static`（默认） | `c++_shared` |
|---|---|---|
| 怎么链接 | 编译进你的 so | 单独的 `libc++_shared.so`，AGP 自动打包 |
| 适合 | App 里**只有一个**使用 C++ 的 so | **多个** so 都用 C++，或者要用 HWASan |
| 风险 | 多个 so 各带一份，全局状态（异常、`new`/`delete`、静态变量）不共享 | 和其他 SDK 带的 `libc++_shared.so` 版本冲突 |

规则：**一个 App 里多个使用 C++ 的 so，必须统一用 `c++_shared`**；否则跨 so 传递 `std::string`、抛 C++ 异常都可能出错。第 1 课的配置已经写了 `-DANDROID_STL=c++_shared`。

第三方给的 so 如果是用别的 NDK 版本、`c++_static` 编译的，要让对方**只在 C 接口上暴露函数**（`extern "C"`，不传 STL 类型），这样最安全。

## 六、加载顺序与 ABI

`libndk4study.so` 依赖 `libfoo.so`：**API 23 起**，动态链接器会自动在 App 的 lib 目录里找依赖，只需要：

```kotlin
init { System.loadLibrary("ndk4study") }     // libfoo.so 会被自动加载
```

（API 22 及以下需要先手动 `loadLibrary("foo")`。第 1 课的 minSdk 是 24，不用担心。）

ABI 选择：

- `arm64-v8a`：现在几乎所有真机。
- `armeabi-v7a`：老的 32 位设备，按用户分布决定是否保留。
- `x86_64`：模拟器、部分 Chromebook。纯 32 位的 `x86` 基本可以不要了（gap-analysis 第二部分提到过）。

**用 AAB 上传 Play**：Play 会按设备只下发对应 ABI 的 so，用户下载的体积不会因为多 ABI 而增加。

## 七、16 KB 页大小 ⭐

Android 15 起部分设备使用 16 KB 内存页，so 的 LOAD 段必须按 16 KB 对齐，否则在这些设备上加载失败。**Google Play 要求 targetSdk 35+ 的 App 支持 16 KB；从 2027-02-01 起，不支持的更新将无法发布。**

| 情况 | 做法 |
|---|---|
| 你自己的 so，NDK r28+ | **默认就是 16 KB 对齐**，不用做任何事（第 1 课用的是 r30） |
| 你自己的 so，NDK r27 及以下 | 加链接参数 `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` |
| 打包 | AGP 8.5.1+ 默认以不压缩、16 KB 对齐的方式打包 so |
| **第三方给的 so** | ⚠️ 最容易出问题，要逐个检查，不对齐就让对方重新编译 |

检查：

```bash
# so 的 LOAD 段对齐，Align 一列应为 0x4000（或更大）
$NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf -l libfoo.so | grep LOAD

# APK 里 so 的 zip 对齐
zipalign -c -P 16 -v 4 app-release.apk
```

Android Studio 的 APK Analyzer 也会对不对齐的 so 给出警告。官方文档还提到可以用 `bundletool` 检查 AAB。

## 八、打包方式与包体积

- AGP 默认**不压缩** so，并直接从 APK 里加载（不解压到磁盘）。这正是 16 KB 对齐的前提。
- `packaging { jniLibs { useLegacyPackaging = true } }` 改回"压缩 + 安装时解压"的旧方式：APK 更小，但安装后占用更多空间。只在确实需要时用。

减小 so 体积：

```cmake
target_compile_options(${CMAKE_PROJECT_NAME} PRIVATE -fvisibility=hidden -ffunction-sections -fdata-sections)
target_link_options(${CMAKE_PROJECT_NAME} PRIVATE -Wl,--gc-sections)
```

- `-fvisibility=hidden`：只导出 `JNI_OnLoad` 和标了 `JNIEXPORT` 的函数（第 2 课）。
- `--gc-sections`：删除没有用到的函数和数据。
- Release 构建会自动 strip 调试信息；对体积敏感的库可以用 `-Os`，或尝试 `-flto`（链接时优化）。

## 九、易错点

1. **`IMPORTED` 的 so 又放进了 `jniLibs`**：`2 files found with path`。
2. **只放了一个 ABI 的 so**：其他 ABI 的设备上 `UnsatisfiedLinkError`。
3. **`IMPORTED_LOCATION` 写死了 `arm64-v8a`**：其他 ABI 链接到错误架构的文件。要用 `${ANDROID_ABI}`。
4. **多个 C++ so 都用 `c++_static`**：跨 so 传 STL 对象、抛异常时出现奇怪的崩溃。
5. **第三方 so 没检查 16 KB 对齐**：在 16 KB 设备上加载失败，Play 拒绝更新。
6. **以为 `find_library` 是必需的**：直接写系统库名即可。
7. **第三方 so 的头文件和 so 版本不一致**：编译通过，运行时崩溃或找不到符号。
8. **为了包体积开 `useLegacyPackaging`**：AAB 已经按 ABI 拆分，通常不需要。

## 十、速查表

| 需求 | 写法 |
|---|---|
| 只打包 so | `src/main/jniLibs/<abi>/libx.so` |
| 链接预编译 so | `add_library(x SHARED IMPORTED)` + `IMPORTED_LOCATION .../${ANDROID_ABI}/libx.so` |
| 链接预编译 .a | `add_library(x STATIC IMPORTED)` |
| 源码集成 | `add_subdirectory(dir)` |
| Maven 上的 native 库 | `buildFeatures { prefab = true }` + `find_package(x REQUIRED CONFIG)` + `x::x` |
| 多个 C++ so | `-DANDROID_STL=c++_shared` |
| 检查 16 KB | `llvm-readelf -l`（Align 0x4000）、`zipalign -c -P 16 -v 4` |
| 老 NDK 对齐 | `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384` |
| 减小体积 | `-fvisibility=hidden`、`--gc-sections`、`-Os`、LTO |

---

**下一课预告（第 11 课）：性能与最佳实践** —— 一次 JNI 调用到底有多贵？为什么"逐个元素回调 Kotlin"是性能杀手？什么时候根本不该用 JNI？怎样正确测量？
