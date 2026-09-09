# JNI 学习大纲

> 目标：掌握 Android 中 Java/Kotlin 与 C/C++ 互相调用的能力，能独立编写、编译、调试和排查常见 JNI 问题。

## 1. 基础概念

### 1.1 JNI 是什么

- JNI 全称是 Java Native Interface。
- 它允许 Java/Kotlin 调用 C/C++ 代码。
- 在 Android 中，JNI 通常配合 NDK、CMake、`.so` 动态库使用。

**重点：**

- Java/Kotlin 调用的是 native 方法。
- C/C++ 编译后的产物是 `.so` 文件。
- Android 通过 `System.loadLibrary()` 加载 `.so`。

### 1.2 JNI、NDK、CMake、so 的关系

- JNI：Java 和 C/C++ 之间的调用规范。
- NDK：Android 提供的 C/C++ 开发工具链。
- CMake：负责描述如何编译 C/C++ 源码。
- `.so`：最终生成的动态库文件。

**重点：**

- JNI 是接口规范。
- NDK 是工具链。
- CMake 是构建脚本。
- `.so` 是编译结果。

## 2. Android Studio NDK 工程结构

### 2.1 常见目录

```text
app/
  src/
    main/
      cpp/
        CMakeLists.txt
        native-lib.cpp
      java/
        ...
```

### 2.2 Gradle 配置

需要关注 `app/build.gradle` 中的：

```gradle
externalNativeBuild {
    cmake {
        path file('src/main/cpp/CMakeLists.txt')
    }
}
```

以及：

```gradle
ndk {
    abiFilters "armeabi-v7a", "arm64-v8a", "x86", "x86_64"
}
```

**重点：**

- `externalNativeBuild` 决定是否启用 CMake。
- `abiFilters` 决定生成哪些 CPU 架构的 `.so`。
- 真机常用 `arm64-v8a`。
- 模拟器常用 `x86_64` 或 `arm64-v8a`，取决于模拟器镜像。

## 3. 第一个 JNI 方法

### 3.1 Java/Kotlin 声明 native 方法

Java 示例：

```java
public class MainActivity extends AppCompatActivity {
    static {
        System.loadLibrary("native-lib");
    }

    public native String stringFromJNI();
}
```

Kotlin 示例：

```kotlin
class MainActivity : AppCompatActivity() {
    external fun stringFromJNI(): String

    companion object {
        init {
            System.loadLibrary("native-lib")
        }
    }
}
```

### 3.2 C++ 实现 native 方法

```cpp
#include <jni.h>

extern "C"
JNIEXPORT jstring JNICALL
Java_com_fqf_ndk4study_MainActivity_stringFromJNI(JNIEnv* env, jobject thiz) {
    return env->NewStringUTF("Hello from JNI");
}
```

**重点：**

- `System.loadLibrary("native-lib")` 对应文件名 `libnative-lib.so`。
- `extern "C"` 用于避免 C++ 函数名被改编。
- `JNIEnv* env` 是 JNI 操作的核心入口。
- `jobject thiz` 对应 Java/Kotlin 当前对象。
- 函数名必须符合 JNI 命名规则。

## 4. JNI 命名规则

### 4.1 静态注册

JNI 默认使用函数名匹配：

```text
Java_包名_类名_方法名
```

例如：

```text
com.fqf.ndk4study.MainActivity.stringFromJNI()
```

对应：

```cpp
Java_com_fqf_ndk4study_MainActivity_stringFromJNI
```

**重点：**

- 包名中的 `.` 变成 `_`。
- Java 方法名也拼在函数名后面。
- 方法签名不匹配会导致 `UnsatisfiedLinkError`。

### 4.2 动态注册

通过 `RegisterNatives` 手动绑定 Java 方法和 C/C++ 函数。

**重点：**

- 静态注册适合入门。
- 动态注册更适合正式项目。
- 动态注册可以避免函数名过长，也更利于混淆和维护。

## 5. JNI 基本数据类型

### 5.1 Java 类型和 JNI 类型对应关系

| Java 类型 | JNI 类型 |
|---|---|
| boolean | jboolean |
| byte | jbyte |
| char | jchar |
| short | jshort |
| int | jint |
| long | jlong |
| float | jfloat |
| double | jdouble |
| String | jstring |
| Object | jobject |
| int[] | jintArray |
| Object[] | jobjectArray |

**重点：**

- Java 的 `int` 对应 `jint`。
- Java 的 `String` 对应 `jstring`，不能直接当作 C 字符串使用。
- Java 数组需要通过 JNI API 访问。

## 6. 字符串处理

### 6.1 Java String 转 C 字符串

```cpp
const char* str = env->GetStringUTFChars(jstr, nullptr);

// 使用 str

env->ReleaseStringUTFChars(jstr, str);
```

### 6.2 C 字符串转 Java String

```cpp
return env->NewStringUTF("hello");
```

**重点：**

- `GetStringUTFChars` 后必须调用 `ReleaseStringUTFChars`。
- 不要长期保存 `const char*`。
- 中文字符串要注意编码问题。

## 7. 数组处理

### 7.1 访问 int 数组

```cpp
jint* data = env->GetIntArrayElements(array, nullptr);
jsize len = env->GetArrayLength(array);

for (int i = 0; i < len; i++) {
    data[i] += 1;
}

env->ReleaseIntArrayElements(array, data, 0);
```

**重点：**

- 数组访问后必须释放。
- `ReleaseIntArrayElements` 的最后一个参数会影响是否把修改同步回 Java。
- 大数组频繁拷贝会影响性能。

## 8. 对象、字段和方法调用

### 8.1 获取类和方法

```cpp
jclass clazz = env->GetObjectClass(thiz);
jmethodID methodId = env->GetMethodID(clazz, "methodName", "()V");
env->CallVoidMethod(thiz, methodId);
```

### 8.2 获取字段

```cpp
jfieldID fieldId = env->GetFieldID(clazz, "count", "I");
jint count = env->GetIntField(thiz, fieldId);
```

**重点：**

- `jclass` 表示 Java 类。
- `jmethodID` 表示 Java 方法。
- `jfieldID` 表示 Java 字段。
- 方法签名非常重要，写错会找不到方法。

## 9. JNI 方法签名

### 9.1 常见签名

| Java 类型 | 签名 |
|---|---|
| void | V |
| boolean | Z |
| byte | B |
| char | C |
| short | S |
| int | I |
| long | J |
| float | F |
| double | D |
| String | Ljava/lang/String; |
| int[] | [I |
| String[] | [Ljava/lang/String; |

### 9.2 示例

Java 方法：

```java
String getName(int id, boolean cache)
```

JNI 签名：

```text
(IZ)Ljava/lang/String;
```

**重点：**

- 参数放在 `()` 中。
- 返回值放在 `()` 后面。
- 对象类型格式是 `L包名/类名;`。
- 数组类型以 `[` 开头。

## 10. 引用管理

### 10.1 局部引用

JNI 方法中创建的大多数对象都是局部引用。

```cpp
jstring str = env->NewStringUTF("hello");
env->DeleteLocalRef(str);
```

### 10.2 全局引用

需要跨方法、跨线程保存对象时使用全局引用。

```cpp
jobject globalObj = env->NewGlobalRef(obj);
env->DeleteGlobalRef(globalObj);
```

**重点：**

- 局部引用不能无限创建。
- 跨线程保存 Java 对象必须使用全局引用。
- 全局引用不用时必须释放，否则会内存泄漏。

## 11. 线程和 JNIEnv

### 11.1 JNIEnv 的线程限制

`JNIEnv*` 只在当前线程有效，不能直接传给其他线程使用。

### 11.2 Native 线程调用 Java

Native 创建的线程如果要调用 Java，需要：

```cpp
javaVM->AttachCurrentThread(&env, nullptr);

// 调用 Java

javaVM->DetachCurrentThread();
```

**重点：**

- `JNIEnv*` 不能跨线程保存和使用。
- 可以保存 `JavaVM*`。
- Native 线程调用 Java 前要 attach。
- 线程结束前要 detach。

## 12. 异常处理

### 12.1 检查异常

```cpp
if (env->ExceptionCheck()) {
    env->ExceptionDescribe();
    env->ExceptionClear();
}
```

**重点：**

- JNI 调用 Java 方法可能抛异常。
- 一旦有异常未处理，后续很多 JNI 调用会失败。
- 调试阶段可以用 `ExceptionDescribe()` 输出异常。

## 13. 日志调试

### 13.1 C++ 输出 Logcat 日志

```cpp
#include <android/log.h>

#define LOG_TAG "NativeDemo"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

LOGD("value = %d", value);
```

CMake 中需要链接 `log`：

```cmake
find_library(log-lib log)
target_link_libraries(native-lib ${log-lib})
```

**重点：**

- Native 层调试优先用 Logcat。
- 崩溃时查看 `Fatal signal`、`backtrace`、`tombstone`。
- CMake 必须链接 `log` 库才能使用 Android 日志 API。

## 14. 常见错误排查

### 14.1 UnsatisfiedLinkError

常见原因：

- `.so` 没有被加载。
- `System.loadLibrary()` 名字写错。
- native 方法没有实现。
- JNI 函数名和包名、类名、方法名不匹配。
- ABI 不匹配。

**重点：**

- `System.loadLibrary("native-lib")` 对应 `libnative-lib.so`。
- 真机是 `arm64-v8a` 时，APK 里必须有对应 ABI 的 `.so`。

### 14.2 找不到 .so

检查目录：

```text
app/build/intermediates/cxx/
app/build/intermediates/merged_native_libs/
app/build/intermediates/stripped_native_libs/
```

命令：

```powershell
Get-ChildItem -Recurse app\build -Include *.so
```

**重点：**

- Android Studio 项目视图不一定直接显示 `.so`。
- `intermediates/cxx` 是 CMake 编译产物。
- `merged_native_libs` 是打包前合并产物。
- `stripped_native_libs` 是去符号后的产物。

### 14.3 Native 崩溃

常见原因：

- 空指针。
- 数组越界。
- 使用已经释放的指针。
- `JNIEnv*` 跨线程使用。
- 忘记释放字符串或数组资源。

**重点：**

- Native 崩溃会直接导致 App 崩溃。
- JNI 层要特别注意生命周期和线程。

## 15. CMake 学习重点

### 15.1 最小 CMakeLists

```cmake
cmake_minimum_required(VERSION 3.22.1)

project("ndk4study")

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    native-lib
    ${log-lib}
)
```

**重点：**

- `add_library(... SHARED ...)` 生成 `.so`。
- 第一个参数 `native-lib` 决定生成 `libnative-lib.so`。
- `target_link_libraries` 用来链接依赖库。

## 16. 推荐学习路线

### 阶段一：跑通基础

- 创建 NDK 项目。
- 成功生成 `.so`。
- Java/Kotlin 调用 C++ 返回字符串。
- C++ 输出 Logcat 日志。

**重点：**

- 先跑通完整链路，不要一开始纠结所有细节。

### 阶段二：掌握常用数据交互

- 基本类型传递。
- String 传递。
- 数组传递。
- 对象字段读取。
- 调用 Java 方法。

**重点：**

- String、数组、对象是 JNI 高频内容。
- 一定要掌握资源释放。

### 阶段三：理解引用和线程

- 局部引用。
- 全局引用。
- `JNIEnv*` 的线程限制。
- Native 线程调用 Java。

**重点：**

- 这是 JNI 从入门到能写稳定代码的关键。

### 阶段四：工程化能力

- 动态注册。
- 多 `.cpp` 文件组织。
- 多 `.so` 依赖。
- ABI 管理。
- Debug/Release 区分。
- Native 崩溃排查。

**重点：**

- 正式项目中动态注册、ABI、崩溃排查非常重要。

## 17. 建议练习

### 练习 1：返回字符串

Java/Kotlin 调用 native 方法，返回 `"Hello JNI"`。

**重点：**

- 熟悉 `System.loadLibrary()`。
- 熟悉 JNI 函数命名。

### 练习 2：两个整数相加

Java/Kotlin 传入两个 `int`，C++ 返回相加结果。

**重点：**

- 掌握基本类型传参和返回。

### 练习 3：字符串拼接

Java/Kotlin 传入一个 `String`，C++ 拼接后返回新字符串。

**重点：**

- 掌握 `GetStringUTFChars` 和 `ReleaseStringUTFChars`。

### 练习 4：数组求和

Java/Kotlin 传入 `int[]`，C++ 返回数组元素和。

**重点：**

- 掌握数组长度获取和数组元素访问。

### 练习 5：Native 调用 Java 方法

C++ 调用 Java/Kotlin 中的普通方法或静态方法。

**重点：**

- 掌握 `GetMethodID`、`CallVoidMethod`、方法签名。

### 练习 6：动态注册

使用 `RegisterNatives` 替代静态 JNI 函数名。

**重点：**

- 掌握正式项目中更常见的 JNI 绑定方式。

### 练习 7：Native 线程回调 Java

C++ 创建线程，并在子线程中回调 Java/Kotlin。

**重点：**

- 掌握 `JavaVM`、`AttachCurrentThread`、`DetachCurrentThread`。

## 18. 必须掌握的核心清单

- [ ] 会配置 NDK、CMake。
- [ ] 会生成 `.so` 文件。
- [ ] 会使用 `System.loadLibrary()`。
- [ ] 会写静态注册 JNI 方法。
- [ ] 会看懂 JNI 方法签名。
- [ ] 会处理 `String`。
- [ ] 会处理数组。
- [ ] 会调用 Java/Kotlin 方法。
- [ ] 会管理局部引用和全局引用。
- [ ] 知道 `JNIEnv*` 不能跨线程使用。
- [ ] 会排查 `UnsatisfiedLinkError`。
- [ ] 会使用 Logcat 调试 Native 代码。
- [ ] 会排查基础 Native 崩溃。
- [ ] 了解动态注册。

## 19. 学习优先级

### 必学

- JNI 基本调用流程。
- CMake 生成 `.so`。
- Java/Kotlin 和 C++ 基本类型交互。
- String、数组、对象处理。
- JNI 方法签名。
- `UnsatisfiedLinkError` 排查。

### 重点进阶

- 动态注册。
- 引用管理。
- 线程中的 JNI 调用。
- Native 崩溃分析。
- ABI 和打包流程。

### 后续扩展

- OpenGL ES。
- 音视频处理。
- FFmpeg 接入。
- OpenCV 接入。
- 性能优化。
- Native Hook。
- C++ 跨平台库移植。

