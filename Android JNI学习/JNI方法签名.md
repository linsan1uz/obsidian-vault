# JNI 方法签名速查

> JNI 方法签名用于描述 Java native 方法的参数类型和返回值类型。动态注册 `RegisterNatives` 时，签名必须和 Java 方法完全一致。

## 1. 基本格式

JNI 方法签名格式固定为：

```text
(参数签名)返回值签名
```

例如 Java 方法：

```java
public native int add(int a, int b);
```

对应 JNI 签名：

```text
(II)I
```

含义：

```text
(int int) int
```

## 2. 常用类型签名

| Java 类型 | JNI 签名 |
|---|---|
| void | `V` |
| boolean | `Z` |
| byte | `B` |
| char | `C` |
| short | `S` |
| int | `I` |
| long | `J` |
| float | `F` |
| double | `D` |
| String | `Ljava/lang/String;` |
| Object | `Ljava/lang/Object;` |
| int[] | `[I` |
| String[] | `[Ljava/lang/String;` |
| Object[] | `[Ljava/lang/Object;` |

## 3. 基本类型示例

### 3.1 无参数，返回 String

Java：

```java
public native String stringFromJNI();
```

JNI 签名：

```text
()Ljava/lang/String;
```

动态注册：

```cpp
{"stringFromJNI", "()Ljava/lang/String;", reinterpret_cast<void*>(stringFromJNI)}
```

### 3.2 两个 int 参数，返回 int

Java：

```java
public native int add(int a, int b);
```

JNI 签名：

```text
(II)I
```

动态注册：

```cpp
{"add", "(II)I", reinterpret_cast<void*>(add)}
```

### 3.3 String 参数，无返回值

Java：

```java
public native void java2CString(String value);
```

JNI 签名：

```text
(Ljava/lang/String;)V
```

动态注册：

```cpp
{"java2CString", "(Ljava/lang/String;)V", reinterpret_cast<void*>(java2CString)}
```

### 3.4 多个参数

Java：

```java
public native boolean check(int age, String name);
```

JNI 签名：

```text
(ILjava/lang/String;)Z
```

含义：

```text
(int String) boolean
```

## 4. 数组类型

数组签名规则：

```text
[元素类型签名
```

### 4.1 int 数组

Java：

```java
public native int sumArray(int[] nums);
```

JNI 签名：

```text
([I)I
```

含义：

```text
(int[]) int
```

### 4.2 String 数组

Java：

```java
public native void printNames(String[] names);
```

JNI 签名：

```text
([Ljava/lang/String;)V
```

含义：

```text
(String[]) void
```

### 4.3 二维 int 数组

Java：

```java
public native void printMatrix(int[][] matrix);
```

JNI 签名：

```text
([[I)V
```

含义：

```text
(int[][]) void
```

## 5. 自定义类型

Java 自定义类在 JNI 签名中写成：

```text
L包名/类名;
```

注意：

- 前面有 `L`
- 包名使用 `/`，不是 `.`
- 最后有 `;`

例如 Java 类：

```java
package com.fqf.ndk4study;

public class User {
    public String name;
    public int age;
}
```

完整类名是：

```text
com.fqf.ndk4study.User
```

JNI 类型签名是：

```text
Lcom/fqf/ndk4study/User;
```

## 6. 自定义类型作为参数

Java：

```java
public native void printUser(User user);
```

JNI 签名：

```text
(Lcom/fqf/ndk4study/User;)V
```

动态注册：

```cpp
{"printUser", "(Lcom/fqf/ndk4study/User;)V", reinterpret_cast<void*>(printUser)}
```

C++ 函数：

```cpp
static void printUser(JNIEnv* env, jobject thiz, jobject user) {
    // user 就是 Java 传入的 User 对象
}
```

## 7. 自定义类型作为返回值

Java：

```java
public native User createUser();
```

JNI 签名：

```text
()Lcom/fqf/ndk4study/User;
```

动态注册：

```cpp
{"createUser", "()Lcom/fqf/ndk4study/User;", reinterpret_cast<void*>(createUser)}
```

## 8. 自定义类型数组

Java：

```java
public native void printUsers(User[] users);
```

JNI 签名：

```text
([Lcom/fqf/ndk4study/User;)V
```

含义：

```text
(User[]) void
```

## 9. 混合参数示例

Java：

```java
public native boolean updateUser(int id, User user, String tag);
```

JNI 签名：

```text
(ILcom/fqf/ndk4study/User;Ljava/lang/String;)Z
```

含义：

```text
(int User String) boolean
```

动态注册：

```cpp
{"updateUser", "(ILcom/fqf/ndk4study/User;Ljava/lang/String;)Z", reinterpret_cast<void*>(updateUser)}
```

## 10. C++ 中访问自定义对象字段

Java：

```java
public class User {
    public String name;
    public int age;
}
```

C++：

```cpp
static void printUser(JNIEnv* env, jobject thiz, jobject user) {
    jclass userClass = env->GetObjectClass(user);

    jfieldID nameField = env->GetFieldID(
            userClass,
            "name",
            "Ljava/lang/String;"
    );

    jfieldID ageField = env->GetFieldID(
            userClass,
            "age",
            "I"
    );

    jstring name = static_cast<jstring>(env->GetObjectField(user, nameField));
    jint age = env->GetIntField(user, ageField);

    const char* nameChars = env->GetStringUTFChars(name, nullptr);

    LOGD("name=%s, age=%d", nameChars, age);

    env->ReleaseStringUTFChars(name, nameChars);
    env->DeleteLocalRef(name);
    env->DeleteLocalRef(userClass);
}
```

## 11. 记忆规则

### 11.1 基本类型

基本类型大多是一个大写字母：

```text
int -> I
boolean -> Z
void -> V
long -> J
double -> D
```

### 11.2 类类型

类类型格式：

```text
L包名/类名;
```

例如：

```text
java.lang.String -> Ljava/lang/String;
com.fqf.ndk4study.User -> Lcom/fqf/ndk4study/User;
```

### 11.3 数组类型

数组在元素签名前加 `[`：

```text
int[] -> [I
String[] -> [Ljava/lang/String;
User[] -> [Lcom/fqf/ndk4study/User;
int[][] -> [[I
```

## 12. 常见错误

### 12.1 忘记分号

错误：

```text
(Ljava/lang/String)V
```

正确：

```text
(Ljava/lang/String;)V
```

### 12.2 包名使用了点号

错误：

```text
(Lcom.fqf.ndk4study.User;)V
```

正确：

```text
(Lcom/fqf/ndk4study/User;)V
```

### 12.3 返回值漏写

错误：

```text
(II)
```

正确：

```text
(II)I
```

### 12.4 参数顺序写错

Java：

```java
public native boolean updateUser(int id, String tag);
```

正确签名：

```text
(ILjava/lang/String;)Z
```

如果写成：

```text
(Ljava/lang/String;I)Z
```

就会注册失败或找不到方法。

## 13. RegisterNatives 完整示例

Java：

```java
public native String stringFromJNI();
public native int add(int a, int b);
public native void java2CString(String value);
public native void printUser(User user);
```

C++：

```cpp
static const JNINativeMethod gMethods[] = {
        {"stringFromJNI", "()Ljava/lang/String;", reinterpret_cast<void*>(stringFromJNI)},
        {"add", "(II)I", reinterpret_cast<void*>(add)},
        {"java2CString", "(Ljava/lang/String;)V", reinterpret_cast<void*>(java2CString)},
        {"printUser", "(Lcom/fqf/ndk4study/User;)V", reinterpret_cast<void*>(printUser)}
};
```

## 14. 一句话总结

JNI 方法签名就是：

```text
(Java 参数类型签名)Java 返回值类型签名
```

自定义类型记住：

```text
L完整包名/类名;
```

数组类型记住：

```text
[元素类型签名
```

