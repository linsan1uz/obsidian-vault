# JNI 第 4 课：调用 Kotlin 方法、字段与对象创建

> 适用读者：完成 JNI 第 1～3 课；看过 [[JNI学习大纲]] §8 和 [[JNI方法签名]] §10（`GetFieldID` 读 User 字段的例子）。
> 核心收获：会从 C++ 调用 Kotlin 的实例方法、静态方法、构造函数，知道 Kotlin 属性、`object`、`companion` 编译后长什么样，在 `JNI_OnLoad` 里缓存 `jclass` / `jmethodID`，理解 native 线程上 `FindClass` 找不到类的原因，用 `@Keep` 防止回调被 R8 改名，用 `fun interface` 设计回调。

---

## 一、回顾：四步走

笔记里的流程是对的：

```cpp
jclass cls = env->GetObjectClass(obj);                          // 1. 拿类
jmethodID mid = env->GetMethodID(cls, "methodName", "()V");     // 2. 拿方法 ID（要签名）
env->CallVoidMethod(obj, mid);                                  // 3. 调用
env->DeleteLocalRef(cls);                                       // 4. 释放局部引用
```

本课补：**静态方法、构造对象、Kotlin 的特殊情况、缓存、ClassLoader、R8**。

## 二、Kotlin 类编译后长什么样 ⭐

```kotlin
package com.fqf.ndk4study

class User(val name: String, var age: Int) {
    var isVip: Boolean = false
    fun greet(prefix: String): String = "$prefix, $name"

    companion object {
        @JvmStatic fun create(name: String): User = User(name, 0)
        fun guest(): User = User("guest", 0)     // 没加 @JvmStatic
    }
}
```

| Kotlin | JVM 层面 | JNI 访问方式 |
|---|---|---|
| `val name: String` | private 字段 `name` + 方法 `getName()` | `GetFieldID(cls, "name", "Ljava/lang/String;")` 或调用 `getName` |
| `var age: Int` | 字段 `age` + `getAge()` / `setAge(I)V` | 字段或 getter/setter 都行 |
| `var isVip: Boolean` | 字段 `isVip` + `isVip()` / `setVip(Z)V` | ⚠️ getter 名是 `isVip`，不是 `getIsVip` |
| 主构造函数 | `<init>(Ljava/lang/String;I)V` | `GetMethodID(cls, "<init>", ...)` + `NewObject` |
| `@JvmStatic fun create` | `User` 上的 static 方法 | `GetStaticMethodID` + `CallStaticObjectMethod` |
| companion 里的 `guest()` | `User$Companion` 的实例方法 | 先拿静态字段 `Companion`，再调实例方法 |
| `object Foo` 的方法 | `Foo` 的实例方法，单例在静态字段 `INSTANCE` | 拿 `INSTANCE`，再调实例方法 |

- **JNI 不检查访问权限**，private 字段也能直接读写。但读字段会绕过 Kotlin 的 getter/setter 逻辑；加 `@JvmField` 可以让意图更明确。
- 记不住编译后的样子，就用 `javap -s -p User.class` 看（第 2 课）。

## 三、静态方法与构造对象

```cpp
// 调用 @JvmStatic fun create(name: String): User
jclass userCls = env->FindClass("com/fqf/ndk4study/User");
jmethodID create = env->GetStaticMethodID(userCls, "create",
        "(Ljava/lang/String;)Lcom/fqf/ndk4study/User;");
jstring name = env->NewStringUTF("Jerry");
jobject u1 = env->CallStaticObjectMethod(userCls, create, name);

// 直接调构造函数：User("Tom", 18)
jmethodID ctor = env->GetMethodID(userCls, "<init>", "(Ljava/lang/String;I)V");
jstring tom = env->NewStringUTF("Tom");
jobject u2 = env->NewObject(userCls, ctor, tom, 18);

// 调 setter：u2.isVip = true
jmethodID setVip = env->GetMethodID(userCls, "setVip", "(Z)V");
env->CallVoidMethod(u2, setVip, JNI_TRUE);
```

调用函数按**返回类型**选：

| 返回类型 | 实例方法 | 静态方法 |
|---|---|---|
| `Unit` | `CallVoidMethod` | `CallStaticVoidMethod` |
| `Int` / `Long` / `Boolean` | `CallIntMethod` / `CallLongMethod` / `CallBooleanMethod` | `CallStatic...` |
| 对象（String、User…） | `CallObjectMethod` | `CallStaticObjectMethod` |
| 构造对象 | `NewObject(cls, ctorId, ...)` | — |

每个都有 `...A`（参数放 `jvalue[]` 数组）和 `...V`（`va_list`）两个变体，平时用可变参数版就够了。

⚠️ 可变参数版要传**正确的 JNI 类型**：`jint`、`jlong`、`jboolean` 不能混用。传 `long` 型参数时要写 `static_cast<jlong>(x)`，否则在 32 位 ABI 上会读错。

## 四、缓存 ID：在 `JNI_OnLoad` 里一次性查好 ⭐

`FindClass`、`GetMethodID` 要按字符串查找，比较慢。`jmethodID` / `jfieldID` **在类没被卸载前一直有效**（App 的类基本不会卸载），所以查一次、缓存起来：

```cpp
// user_jni.h
struct UserClassInfo {
    jclass clazz;          // ⚠️ 必须是全局引用
    jmethodID ctor;
    jmethodID greet;
    jfieldID age;
};
extern UserClassInfo gUser;

// user_jni.cpp
UserClassInfo gUser{};

bool cacheUserClass(JNIEnv* env) {
    jclass local = env->FindClass("com/fqf/ndk4study/User");
    if (!local) return false;
    gUser.clazz = static_cast<jclass>(env->NewGlobalRef(local));   // ⭐ 局部 → 全局
    env->DeleteLocalRef(local);
    gUser.ctor  = env->GetMethodID(gUser.clazz, "<init>", "(Ljava/lang/String;I)V");
    gUser.greet = env->GetMethodID(gUser.clazz, "greet", "(Ljava/lang/String;)Ljava/lang/String;");
    gUser.age   = env->GetFieldID(gUser.clazz, "age", "I");
    return gUser.ctor && gUser.greet && gUser.age;
}

// 在 JNI_OnLoad 里调用 cacheUserClass(env)
```

使用时：

```cpp
jobject u = env->NewObject(gUser.clazz, gUser.ctor, name, 18);
jint age  = env->GetIntField(u, gUser.age);
```

- `FindClass` 返回的是**局部引用**，函数返回后就失效，所以 `jclass` 必须转成全局引用才能缓存（第 5 课）。
- `jmethodID` / `jfieldID` **不是引用**，直接存，不需要也不能 `NewGlobalRef`。
- 好处：查找失败会在加载 so 时暴露，不会等到运行时；顺带解决了第五节的 ClassLoader 问题。

## 五、native 线程上 `FindClass` 找不到你的类 ⭐

现象：在 `std::thread` / `pthread` 创建的线程里 attach（第 7 课）后调用 `FindClass("com/fqf/ndk4study/User")`，返回 null，日志里是 `ClassNotFoundException` / `NoClassDefFoundError`。

原因：`FindClass` 会用"当前调用栈上那个 Java 方法所属的 ClassLoader"去查类。

- 在 native 方法里（Kotlin 调进来的）：栈上有你 App 的方法 → 用 App 的 ClassLoader → 找得到。
- 在 `JNI_OnLoad` 里：使用调用 `System.loadLibrary` 的那个类的 ClassLoader → 找得到。
- **在自己创建、刚 attach 的 native 线程里**：栈上没有任何 App 方法 → 用**系统 ClassLoader** → 只能找到 `java.*`、`android.*`，**找不到你的类**。

解决（按推荐顺序）：

1. **在 `JNI_OnLoad` 里把要用的 `jclass` 缓存成全局引用**（第四节）。最常用。
2. 缓存 App 的 `ClassLoader` 对象，在 native 线程里调用 `loadClass("com.fqf.ndk4study.User")`（注意用 `.`）。
3. 让 Kotlin 把需要的对象或 Class 作为参数传进来。

口诀：**类在 OnLoad 里找好，native 线程里别 FindClass。**

## 六、回调设计：用 `fun interface`

C++ 想通知 Kotlin 进度。如果直接传 Kotlin 的 Lambda：

```kotlin
external fun process(onProgress: (Int) -> Unit)
// 签名是 Lkotlin/jvm/functions/Function1;
// C++ 要调用 invoke(Ljava/lang/Object;)Ljava/lang/Object;，还得把 int 装箱成 Integer
```

麻烦而且慢。改用 **`fun interface`**（Kotlin 的 SAM 接口），签名干净，调用时也不装箱：

```kotlin
fun interface ProgressListener {
    fun onProgress(percent: Int)
}

object NativeBridge {
    external fun process(data: ByteArray, listener: ProgressListener)
}

// 调用方仍然能用 Lambda（Kotlin 课第 4 课 SAM 转换）
NativeBridge.process(bytes) { p -> Log.d("TAG", "进度 $p") }
```

```cpp
void process(JNIEnv* env, jobject, jbyteArray data, jobject listener) {
    jclass cls = env->GetObjectClass(listener);
    jmethodID onProgress = env->GetMethodID(cls, "onProgress", "(I)V");
    env->DeleteLocalRef(cls);
    for (int p = 0; p <= 100; p += 10) {
        // ... 处理一段 ...
        env->CallVoidMethod(listener, onProgress, static_cast<jint>(p));
        if (env->ExceptionCheck()) return;        // Kotlin 回调抛了异常，立即返回（第 6 课）
    }
}
```

注意：`GetObjectClass(listener)` 拿到的是 Lambda 生成的那个具体类，每次可能不一样，所以这里**按对象查 ID**；也可以对接口类 `ProgressListener` 查一次并缓存，接口方法的 ID 对所有实现类都有效。

## 七、R8：保护被 C++ 调用的成员

第 2 课说过，R8 默认只保护 `native` 方法。**C++ 反向调用的方法、读写的字段、用到的构造函数，Release 包里会被改名或者被当成没用到而删掉**，运行时 `GetMethodID` 返回 null，抛 `NoSuchMethodError`。

```kotlin
import androidx.annotation.Keep

@Keep                                        // 整个类连同成员都保留
class User(val name: String, var age: Int) { ... }

fun interface ProgressListener {
    @Keep fun onProgress(percent: Int)       // 或者只保留某个成员
}
```

或者在 `proguard-rules.pro` 里写：

```
-keep class com.fqf.ndk4study.User {
    <init>(java.lang.String, int);
    java.lang.String greet(java.lang.String);
    int age;
}
```

**Debug 包没问题、Release 包崩溃** → 第一个要怀疑的就是 R8。

## 八、易错点

1. **缓存了 `FindClass` 返回的局部引用**：方法返回后就失效，之后使用会崩，CheckJNI 报 `use of invalid jobject`。
2. **给 `jmethodID` 调用 `NewGlobalRef`**：它不是引用，直接存就行。
3. **静态方法用 `GetMethodID` 查**：返回 null，要用 `GetStaticMethodID`，调用也要用 `CallStatic...`。
4. **Boolean 属性的 getter 写成 `getIsVip`**：Kotlin 生成的是 `isVip()` / `setVip()`。
5. **调用 companion 里没加 `@JvmStatic` 的方法时当成静态方法**：它在 `Xxx$Companion` 上。
6. **在 native 线程里 `FindClass` 你自己的类**：用的是系统 ClassLoader，找不到。
7. **Release 包回调崩溃**：R8 改名或删除了成员，加 `@Keep` 或 keep 规则。
8. **可变参数传错类型**：`long` 型参数传了 `int`，32 位上读出来是垃圾值。
9. **调用 Kotlin 后不检查异常**：带着挂起的异常继续调用 JNI，CheckJNI 会 abort（第 6 课）。

## 九、速查表

| 需求 | API |
|---|---|
| 从对象拿类 | `GetObjectClass(obj)` |
| 按名字找类 | `FindClass("com/fqf/ndk4study/User")`（尽量只在 OnLoad 里用） |
| 实例方法 / 静态方法 ID | `GetMethodID` / `GetStaticMethodID` |
| 字段 / 静态字段 ID | `GetFieldID` / `GetStaticFieldID` |
| 调用 | `Call<Type>Method` / `CallStatic<Type>Method` |
| 构造对象 | `GetMethodID(cls, "<init>", "(...)V")` + `NewObject` |
| 读写字段 | `Get/Set<Type>Field`、`Get/SetObjectField` |
| 拿 object 单例 | `GetStaticFieldID(cls, "INSTANCE", "Lpkg/Foo;")` + `GetStaticObjectField` |
| 缓存 jclass | `(jclass) env->NewGlobalRef(local)` |
| 防止 R8 改名 | `@Keep` / `-keep class ... { ... }` |

---

**下一课预告（第 5 课）：引用管理** —— 局部引用什么时候会溢出？全局引用为什么会造成泄漏？弱全局引用怎么安全使用？`PushLocalFrame` 和 RAII 封装。
