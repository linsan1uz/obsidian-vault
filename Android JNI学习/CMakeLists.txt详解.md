# CMakeLists.txt 详解

`CMakeLists.txt` 是 CMake 的构建配置文件，用来告诉 Android Gradle Plugin：

- 生成什么类型的库
- 编译哪些 C/C++ 文件
- 使用哪些系统库或第三方库
- 最终生成的 `.so` 叫什么名字

## 一、基本写法

```cmake
cmake_minimum_required(VERSION 3.22.1)

project("app")

add_library(
        ndk4study
        SHARED
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
)

find_library(
        log-lib
        log
)

target_link_libraries(
        ndk4study
        ${log-lib}
)
```

## 二、指定 CMake 最低版本

```cmake
cmake_minimum_required(VERSION 3.22.1)
```

表示项目至少需要 CMake 3.22.1。这个版本需要和 Android SDK 中安装的 CMake 版本兼容。

## 三、声明项目名称

```cmake
project("app")
```

声明当前 CMake 项目的名称。它主要用于标识项目，不决定最终生成的 `.so` 文件名。

## 四、创建动态库

```cmake
add_library(
        ndk4study
        SHARED
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
)
```

基本格式：

```cmake
add_library(库名称 库类型 源文件...)
```

`ndk4study` 是库名称，`SHARED` 表示生成动态库，也就是 Android 使用的 `.so` 文件。

实际文件名会自动添加 `lib` 前缀：

```text
libndk4study.so
```

Java 中对应的加载代码是：

```java
System.loadLibrary("ndk4study");
```

新增 C++ 源文件时，需要加入 `add_library`：

```cmake
add_library(
        ndk4study
        SHARED
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
        user_jni.cpp
)
```

否则新文件不会被编译进 `.so`。

## 五、使用变量保存源文件

```cmake
set(NATIVE_SOURCES
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
)

add_library(
        ndk4study
        SHARED
        ${NATIVE_SOURCES}
)
```

源文件较多时，这种写法更清晰。

## 六、使用 `target_sources`

```cmake
add_library(ndk4study SHARED)

target_sources(
        ndk4study
        PRIVATE
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
)
```

它和直接把源文件写进 `add_library` 的效果基本相同，更适合大型项目。

## 七、自动搜索 `.cpp` 文件

```cmake
file(GLOB NATIVE_SOURCES "*.cpp")

add_library(
        ndk4study
        SHARED
        ${NATIVE_SOURCES}
)
```

这种方式会自动搜索当前目录下的 `.cpp` 文件。

不过不建议长期使用。新增 `.cpp` 文件后，CMake 有时不会自动重新执行配置，需要手动执行项目同步或重新构建。

## 八、添加头文件目录

如果头文件放在：

```text
app/src/main/cpp/include/
```

可以配置：

```cmake
target_include_directories(
        ndk4study
        PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)
```

之后可以直接引用：

```cpp
#include "jni_register.h"
```

如果头文件和 `.cpp` 文件在同一个目录，通常不需要额外配置。

## 九、设置 C++ 标准

推荐针对具体库设置 C++17：

```cmake
target_compile_features(
        ndk4study
        PRIVATE
        cxx_std_17
)
```

也可以使用全局配置：

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
```

## 十、添加编译宏

```cmake
target_compile_definitions(
        ndk4study
        PRIVATE
        NATIVE_DEBUG
)
```

C++ 中可以这样使用：

```cpp
#ifdef NATIVE_DEBUG
LOGD("native debug enabled");
#endif
```

也可以定义带值的宏：

```cmake
target_compile_definitions(
        ndk4study
        PRIVATE
        APP_VERSION=1
)
```

## 十一、查找和链接 Android 系统库

查找日志库：

```cmake
find_library(
        log-lib
        log
)
```

链接日志库：

```cmake
target_link_libraries(
        ndk4study
        ${log-lib}
)
```

这样 C++ 中可以使用：

```cpp
#include <android/log.h>

__android_log_print(
        ANDROID_LOG_DEBUG,
        "NativeDemo",
        "value = %d",
        value
);
```

也可以链接多个系统库：

```cmake
find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(
        ndk4study
        ${log-lib}
        ${android-lib}
)
```

常见系统库包括：

| 库名称 | 用途 |
|---|---|
| `log` | Android 日志 |
| `android` | Android Native API |
| `jnigraphics` | Bitmap 图像操作 |
| `z` | zlib 压缩 |

## 十二、创建多个动态库

```cmake
add_library(
        ndk4study
        SHARED
        native-lib.cpp
)

add_library(
        utils
        SHARED
        utils.cpp
)

target_link_libraries(
        ndk4study
        utils
        ${log-lib}
)
```

这样会生成：

```text
libndk4study.so
libutils.so
```

Java 中可以分别加载：

```java
static {
    System.loadLibrary("utils");
    System.loadLibrary("ndk4study");
}
```

## 十三、创建静态库

```cmake
add_library(
        native_utils
        STATIC
        utils.cpp
)

target_link_libraries(
        ndk4study
        native_utils
        ${log-lib}
)
```

`STATIC` 生成静态库。静态库通常不会单独提供给 Java 加载，而是被链接进其他动态库。

## 十四、JNI 项目推荐写法

```cmake
cmake_minimum_required(VERSION 3.22.1)

project("app")

set(NATIVE_SOURCES
        native-lib.cpp
        jni_register.cpp
        jni_onload.cpp
)

add_library(
        ndk4study
        SHARED
        ${NATIVE_SOURCES}
)

target_compile_features(
        ndk4study
        PRIVATE
        cxx_std_17
)

find_library(
        log-lib
        log
)

target_link_libraries(
        ndk4study
        ${log-lib}
)
```

推荐的目录结构：

```text
app/src/main/cpp/
├── CMakeLists.txt
├── native-lib.cpp
├── jni_register.cpp
├── jni_register.h
└── jni_onload.cpp
```

## 十五、四个最重要的命令

```cmake
add_library()
find_library()
target_link_libraries()
target_include_directories()
```

它们分别表示：

```text
创建库
查找系统库
链接库
添加头文件搜索目录
```
