# Android App 工程师 C++ 入门教程

> 目标：面向已经会 Android Java/Kotlin 的开发者，快速掌握 JNI/NDK 开发中最常用、最容易踩坑的 C++ 知识。

## 1. C++ 在 Android 开发中的作用

Android App 工程师学习 C++，通常不是为了写完整桌面程序，而是为了：

- 写 JNI 方法。
- 调用 Native SDK。
- 接入 FFmpeg、OpenCV、OpenGL、音视频库。
- 做性能敏感逻辑。
- 复用跨平台 C/C++ 代码。
- 分析 Native 崩溃。

**重点：**

- Android 中 C++ 最终会被编译成 `.so` 动态库。
- Java/Kotlin 通过 JNI 调用 `.so` 中的函数。
- C++ 没有 Java/Kotlin 那样的自动垃圾回收，内存和生命周期更需要自己负责。

## 2. 最小 C++ 文件

```cpp
#include <iostream>

int main() {
    std::cout << "Hello C++" << std::endl;
    return 0;
}
```

在 Android JNI 中，你通常不会写 `main()`，而是写 JNI 函数：

```cpp
#include <jni.h>

static jint add(JNIEnv* env, jobject thiz, jint a, jint b) {
    return a + b;
}
```

**重点：**

- `.cpp` 是 C++ 源文件。
- `#include` 类似 Java/Kotlin 的 `import`。
- `int`、`jint` 这类类型必须明确写出来。
- JNI 函数一般会带 `JNIEnv* env` 参数。

## 3. 变量和基本类型

### 3.1 常见类型

```cpp
int age = 18;
long count = 1000;
float price = 12.5f;
double score = 99.8;
bool isVip = true;
char ch = 'A';
```

### 3.2 和 Java/Kotlin 的区别

Java/Kotlin：

```java
int age = 18;
String name = "Tom";
```

C++：

```cpp
int age = 18;
std::string name = "Tom";
```

**重点：**

- C++ 没有默认的 `String`，常用的是 `std::string`。
- C++ 变量不会自动初始化成你期待的值，局部变量最好立刻赋值。
- C++ 类型更贴近底层，不同平台上部分类型大小可能不同。

## 4. 函数

### 4.1 普通函数

```cpp
int add(int a, int b) {
    return a + b;
}
```

调用：

```cpp
int result = add(3, 4);
```

### 4.2 无返回值函数

```cpp
void logMessage() {
    // no return value
}
```

### 4.3 JNI 中的函数

```cpp
static jint nativeAdd(JNIEnv* env, jobject thiz, jint a, jint b) {
    return a + b;
}
```

**重点：**

- C++ 函数必须声明返回值类型。
- `void` 表示没有返回值。
- `static` 修饰的函数通常只在当前 `.cpp` 文件内部可见。
- JNI 函数的参数类型要和 Java/Kotlin native 方法签名对应。

## 5. 头文件和源文件

C++ 常见拆分方式：

```text
calculator.h
calculator.cpp
native-lib.cpp
```

头文件 `.h` 放声明：

```cpp
// calculator.h
#pragma once

int add(int a, int b);
```

源文件 `.cpp` 放实现：

```cpp
// calculator.cpp
#include "calculator.h"

int add(int a, int b) {
    return a + b;
}
```

其他文件使用：

```cpp
#include "calculator.h"
```

**重点：**

- `.h` 类似“对外说明书”。
- `.cpp` 是具体实现。
- `#pragma once` 用来防止头文件被重复包含。
- CMake 里要把新增的 `.cpp` 加进编译列表。

## 6. 指针

指针是 C++ 里最重要、也最容易出错的部分。

### 6.1 什么是指针

```cpp
int value = 10;
int* p = &value;
```

含义：

- `value` 是一个整数变量。
- `&value` 表示取 `value` 的内存地址。
- `int* p` 表示 `p` 是一个指向 `int` 的指针。

读取指针指向的值：

```cpp
int result = *p;
```

修改指针指向的值：

```cpp
*p = 20;
```

### 6.2 指针和 Java 引用的区别

Java：

```java
User user = new User();
```

C++ 指针：

```cpp
User* user = new User();
```

Java 引用由 JVM 管理，C++ 指针需要关注释放。

**重点：**

- `&` 是取地址。
- `*` 在声明时表示指针类型。
- `*` 在使用时表示解引用。
- 空指针用 `nullptr`。
- 使用空指针会导致 Native 崩溃。

## 7. 引用

C++ 引用可以理解为变量的别名。

```cpp
void increase(int& value) {
    value++;
}

int count = 1;
increase(count);
```

执行后 `count` 变成 `2`。

对比普通传值：

```cpp
void increase(int value) {
    value++;
}
```

这个不会修改外面的变量。

**重点：**

- `int&` 是引用。
- 引用常用于避免拷贝，或者让函数修改外部变量。
- JNI 里更多见的是指针，比如 `JNIEnv*`。

## 8. const

`const` 表示不可修改。

```cpp
const int value = 10;
```

函数参数中常见：

```cpp
void printName(const std::string& name) {
    // name cannot be modified
}
```

**重点：**

- `const` 能减少误修改。
- `const std::string&` 常用于传入字符串，避免拷贝。
- 从 JNI 获取到的 `const char*` 不应该被修改。

## 9. 字符串

### 9.1 std::string

```cpp
#include <string>

std::string name = "Tom";
std::string message = "Hello " + name;
```

### 9.2 C 字符串

```cpp
const char* text = "Hello";
```

### 9.3 JNI 字符串转换

Java `String` 到 C 字符串：

```cpp
const char* chars = env->GetStringUTFChars(jstr, nullptr);

std::string value = chars;

env->ReleaseStringUTFChars(jstr, chars);
```

C++ 字符串到 Java `String`：

```cpp
std::string result = "Hello";
return env->NewStringUTF(result.c_str());
```

**重点：**

- `std::string` 是 C++ 字符串。
- `const char*` 是 C 风格字符串。
- `std::string::c_str()` 可以拿到 C 风格字符串。
- `GetStringUTFChars` 后必须 `ReleaseStringUTFChars`。

## 10. 数组和 vector

### 10.1 普通数组

```cpp
int nums[3] = {1, 2, 3};
int first = nums[0];
```

普通数组长度不够灵活，NDK 开发里更推荐使用 `std::vector`。

### 10.2 vector

```cpp
#include <vector>

std::vector<int> nums = {1, 2, 3};
nums.push_back(4);

int first = nums[0];
int size = nums.size();
```

遍历：

```cpp
for (int value : nums) {
    // use value
}
```

**重点：**

- `std::vector` 类似 Java 的 `ArrayList`。
- C++ 数组越界不会像 Java 那样稳定抛异常，可能直接崩溃。
- Native 层一定要注意下标范围。

## 11. 类和对象

### 11.1 定义类

```cpp
class User {
public:
    std::string name;
    int age;

    void sayHello() {
        // do something
    }
};
```

使用：

```cpp
User user;
user.name = "Tom";
user.age = 18;
user.sayHello();
```

### 11.2 构造函数

```cpp
class User {
public:
    std::string name;
    int age;

    User(const std::string& name, int age) {
        this->name = name;
        this->age = age;
    }
};
```

使用：

```cpp
User user("Tom", 18);
```

**重点：**

- `class` 类似 Java/Kotlin 的类。
- `public` 表示外部可访问。
- `this->` 类似 Java/Kotlin 的 `this.`。
- C++ 对象可以创建在栈上，也可以创建在堆上。

## 12. 栈对象和堆对象

### 12.1 栈对象

```cpp
User user("Tom", 18);
```

函数结束后自动释放。

### 12.2 堆对象

```cpp
User* user = new User("Tom", 18);
delete user;
```

需要手动释放。

**重点：**

- 能用栈对象就优先用栈对象。
- 使用 `new` 后通常要对应 `delete`。
- 忘记 `delete` 会内存泄漏。
- 重复 `delete` 或使用已释放对象会导致崩溃。

## 13. 智能指针

现代 C++ 推荐用智能指针减少手动释放。

### 13.1 unique_ptr

```cpp
#include <memory>

std::unique_ptr<User> user = std::make_unique<User>("Tom", 18);
```

特点：

- 独占所有权。
- 离开作用域自动释放。
- 不能随便复制。

### 13.2 shared_ptr

```cpp
std::shared_ptr<User> user = std::make_shared<User>("Tom", 18);
```

特点：

- 多处共享所有权。
- 引用计数为 0 时自动释放。

**重点：**

- 新代码优先考虑智能指针。
- 简单场景优先 `std::unique_ptr`。
- 不要为了方便到处使用 `shared_ptr`。

## 14. 命名空间

C++ 标准库很多内容在 `std` 命名空间下：

```cpp
std::string name = "Tom";
std::vector<int> nums;
```

也可以写：

```cpp
using namespace std;
```

但在正式项目里不推荐在头文件中这样写。

**重点：**

- `std::` 表示来自 C++ 标准库。
- 头文件里避免写 `using namespace std;`。
- Android NDK 代码中直接写 `std::string`、`std::vector` 更清晰。

## 15. 日志

Android Native 日志：

```cpp
#include <android/log.h>

#define LOG_TAG "NativeDemo"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
```

使用：

```cpp
LOGD("count = %d", count);
LOGE("error code = %d", errorCode);
```

CMake 需要链接 `log`：

```cmake
find_library(log-lib log)
target_link_libraries(ndk4study ${log-lib})
```

**重点：**

- Native 调试常用 Logcat。
- `%d` 打印整数。
- `%s` 打印字符串。
- `std::string` 打印时要用 `.c_str()`。

示例：

```cpp
std::string name = "Tom";
LOGD("name = %s", name.c_str());
```

## 16. JNI 中常见 C++ 写法

### 16.1 RegisterNatives 动态注册

```cpp
static jstring nativeStringFromJNI(JNIEnv* env, jobject thiz) {
    return env->NewStringUTF("Hello");
}

static jint nativeAdd(JNIEnv* env, jobject thiz, jint a, jint b) {
    return a + b;
}

static const JNINativeMethod gMethods[] = {
        {"stringFromJNI", "()Ljava/lang/String;", reinterpret_cast<void*>(nativeStringFromJNI)},
        {"add", "(II)I", reinterpret_cast<void*>(nativeAdd)},
};
```

**重点：**

- `JNINativeMethod` 用于绑定 Java native 方法和 C++ 函数。
- 第二个参数是 JNI 方法签名。
- 第三个参数是 C++ 函数指针。

### 16.2 JNI_OnLoad

```cpp
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    JNIEnv* env = nullptr;

    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    jclass clazz = env->FindClass("com/fqf/ndk4study/MainActivity");
    if (clazz == nullptr) {
        return JNI_ERR;
    }

    int result = env->RegisterNatives(
            clazz,
            gMethods,
            sizeof(gMethods) / sizeof(gMethods[0])
    );

    env->DeleteLocalRef(clazz);

    if (result != JNI_OK) {
        return JNI_ERR;
    }

    return JNI_VERSION_1_6;
}
```

**重点：**

- `JNI_OnLoad` 会在 `System.loadLibrary()` 时自动执行。
- `JavaVM*` 可以理解为 JVM 虚拟机对象。
- `JNIEnv*` 是当前线程访问 JNI API 的入口。
- `FindClass` 中类名用 `/`，不是 `.`。

## 17. C++ 和 Java/Kotlin 思维差异

### 17.1 内存管理

Java/Kotlin：

- 大多数对象由 GC 回收。
- 空指针通常抛 `NullPointerException`。

C++：

- 很多资源需要明确释放。
- 空指针、野指针、数组越界可能直接导致 App 崩溃。

### 17.2 错误处理

Java/Kotlin：

- 常见异常机制。

C++：

- Android Native 开发中不建议大量依赖 C++ 异常。
- JNI 调用 Java 后要注意检查 Java 异常。

### 17.3 字符串和数组

Java/Kotlin：

- `String`、数组、集合使用简单。

C++：

- 字符串有 `std::string` 和 `const char*`。
- 数组越界风险更高。
- JNI 数组需要通过 JNI API 访问和释放。

**重点：**

- C++ 更自由，也更容易崩。
- 写 Native 代码时要更关注生命周期、线程和边界。

## 18. Android NDK 开发必会 C++ 清单

- [ ] 会写函数。
- [ ] 会使用 `int`、`bool`、`char`、`std::string`。
- [ ] 理解 `#include`。
- [ ] 理解 `.h` 和 `.cpp` 的区别。
- [ ] 理解指针 `*`。
- [ ] 理解取地址 `&`。
- [ ] 知道 `nullptr` 是空指针。
- [ ] 会使用 `std::vector`。
- [ ] 会使用 `const`。
- [ ] 知道 `new/delete` 的风险。
- [ ] 了解智能指针。
- [ ] 会写 Android Native 日志。
- [ ] 会看懂 JNI 函数参数。
- [ ] 会写 `RegisterNatives`。
- [ ] 知道 `JNIEnv*` 不能跨线程乱用。
- [ ] 知道字符串和数组资源要释放。

## 19. 推荐学习顺序

### 第一阶段：够写 JNI

- 变量和函数。
- `std::string`。
- 指针基础。
- `const`。
- JNI 基本类型。
- `RegisterNatives`。

### 第二阶段：够看懂项目

- `.h` 和 `.cpp`。
- 类和对象。
- `std::vector`。
- CMake 多文件编译。
- Native 日志。

### 第三阶段：减少崩溃

- 栈对象和堆对象。
- `new/delete`。
- 智能指针。
- 引用管理。
- 数组越界。
- 空指针检查。

### 第四阶段：工程实践

- 封装 Native 模块。
- 多 `.so` 依赖。
- ABI 管理。
- Native 崩溃分析。
- 第三方 C/C++ 库接入。

## 20. 练习路线

### 练习 1：写一个加法函数

```cpp
static jint nativeAdd(JNIEnv* env, jobject thiz, jint a, jint b) {
    return a + b;
}
```

目标：

- 熟悉函数。
- 熟悉 JNI 基本类型。

### 练习 2：字符串拼接

Java 传入 `String name`，C++ 返回 `"Hello " + name`。

目标：

- 熟悉 `jstring`。
- 熟悉 `GetStringUTFChars`。
- 熟悉 `ReleaseStringUTFChars`。

### 练习 3：数组求和

Java 传入 `int[]`，C++ 返回总和。

目标：

- 熟悉 JNI 数组。
- 注意释放数组资源。

### 练习 4：用 C++ 类封装计算器

写一个 `Calculator` 类：

```cpp
class Calculator {
public:
    int add(int a, int b) {
        return a + b;
    }
};
```

目标：

- 熟悉 C++ 类。
- 熟悉对象创建。

### 练习 5：Native 日志

在每个 JNI 方法里打印参数和返回值。

目标：

- 熟悉 Logcat。
- 学会排查 Native 层逻辑。

## 21. 最容易踩的坑

### 21.1 `System.loadLibrary` 名字写错

```java
System.loadLibrary("ndk4study");
```

对应：

```text
libndk4study.so
```

不能写成：

```java
System.loadLibrary("libndk4study.so");
```

### 21.2 JNI 签名写错

```java
public native int add(int a, int b);
```

签名是：

```text
(II)I
```

### 21.3 字符串忘记释放

```cpp
const char* chars = env->GetStringUTFChars(jstr, nullptr);
env->ReleaseStringUTFChars(jstr, chars);
```

### 21.4 指针为空

```cpp
if (ptr == nullptr) {
    return;
}
```

### 21.5 数组越界

```cpp
if (index >= 0 && index < nums.size()) {
    int value = nums[index];
}
```

**重点：**

- Native 层出错经常不是 Java 异常，而是 App 直接崩溃。
- 看到 `Fatal signal 11`，通常要怀疑空指针、野指针、越界访问。

## 22. Android 工程师该怎么学 C++

不建议一开始完整啃厚重 C++ 书。更适合的路线是：

1. 先学函数、指针、字符串、vector。
2. 再学 JNI 类型和 RegisterNatives。
3. 然后学类、头文件、CMake 多文件。
4. 最后补内存管理、智能指针、线程和崩溃分析。

**核心原则：**

- 先能写 JNI。
- 再能看懂 C++ 项目。
- 最后再深入现代 C++ 和性能优化。

