# CMake 中的 `find_library` 详解

## 一、`find_library` 的作用

`find_library` 用来查找系统库或预编译库，并把查找结果保存到一个 CMake 变量中。

基本格式：

```cmake
find_library(变量名 库名)
```

例如：

```cmake
find_library(
        log-lib
        log
)
```

这里：

```text
log-lib：CMake 变量名，用来保存查找结果
log：要查找的 Android 系统库名称
```

查找成功后，`log-lib` 变量通常会保存 `liblog.so` 的实际路径。

## 二、链接查找到的库

找到库之后，需要使用 `target_link_libraries` 进行链接：

```cmake
target_link_libraries(
        ndk4study
        ${log-lib}
)
```

含义是：

```text
生成 ndk4study 时，需要链接 Android 的 log 库。
```

`${log-lib}` 表示取出变量 `log-lib` 保存的内容。

## 三、查找多个库

可以多次调用 `find_library`：

```cmake
find_library(
        log-lib
        log
)

find_library(
        android-lib
        android
)

find_library(
        jnigraphics-lib
        jnigraphics
)
```

然后统一链接：

```cmake
target_link_libraries(
        ndk4study
        ${log-lib}
        ${android-lib}
        ${jnigraphics-lib}
)
```

也可以写成单行形式：

```cmake
find_library(log-lib log)
find_library(android-lib android)
find_library(jnigraphics-lib jnigraphics)
```

## 四、常见 Android 系统库

| CMake 库名称 | 实际库文件 | 用途 |
|---|---|---|
| `log` | `liblog.so` | Android 日志 |
| `android` | `libandroid.so` | Android Native API |
| `jnigraphics` | `libjnigraphics.so` | Bitmap 操作 |
| `z` | `libz.so` | 压缩功能 |

完整示例：

```cmake
find_library(log-lib log)
find_library(android-lib android)
find_library(jnigraphics-lib jnigraphics)
find_library(z-lib z)

target_link_libraries(
        ndk4study
        ${log-lib}
        ${android-lib}
        ${jnigraphics-lib}
        ${z-lib}
)
```

## 五、可以不使用 `find_library` 吗？

部分 Android NDK/CMake 环境支持直接写库名：

```cmake
target_link_libraries(
        ndk4study
        log
        android
)
```

这种方式比较简单，但兼容性和可读性不如 `find_library`。

更推荐：

```cmake
find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(
        ndk4study
        ${log-lib}
        ${android-lib}
)
```

`find_library` 会让 CMake 在当前 Android NDK 环境中查找库，并保存实际路径。库不存在时，也更容易在 CMake 配置阶段发现问题。

## 六、直接链接自己的库

自己的 CMake 库不需要使用 `find_library`：

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

这里的 `native_utils` 是当前 CMake 项目中创建的库，可以直接写库名。

## 七、`#include` 和链接库的区别

```cpp
#include <android/log.h>
```

解决的是：

```text
编译器在哪里找到函数和类型的声明
```

```cmake
target_link_libraries(ndk4study ${log-lib})
```

解决的是：

```text
最终程序在哪里找到函数的真正实现
```

只写 `#include` 而不链接库，可能在编译阶段通过，但在链接阶段出现：

```text
undefined reference to __android_log_print
```

## 八、推荐记忆方式

```text
find_library()            查找库
target_link_libraries()   链接库
add_library()             创建自己的库
```

JNI 项目推荐保留这种写法：

```cmake
find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(
        ndk4study
        ${log-lib}
        ${android-lib}
)
```
