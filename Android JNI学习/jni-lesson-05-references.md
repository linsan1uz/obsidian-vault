# JNI 第 5 课：引用管理

> 适用读者：完成 JNI 第 1～4 课；看过 [[JNI学习大纲]] §10。
> 核心收获：理解局部、全局、弱全局三种引用的生命周期，知道循环里不 `DeleteLocalRef` 为什么会溢出，会用 `PushLocalFrame` / `PopLocalFrame` 和 RAII 封装管理引用，会安全使用弱全局引用，知道全局引用泄漏会抓住整个 Activity 不放。

---

## 一、回顾：引用不是对象

笔记 §10 的结论是对的：大多数 JNI 返回值都是局部引用，跨方法、跨线程要用全局引用，用完都要释放。

先把概念说清楚：**`jobject` 不是对象本身，而是 JNI 给你的一个"句柄"**，对象实体在 Java 堆上。GC 会移动对象，句柄保证你始终能找到它。只要句柄还存在，对象就不会被回收。

| | 局部引用 | 全局引用 | 弱全局引用 |
|---|---|---|---|
| 怎么来 | 参数、几乎所有返回对象的 JNI 函数 | `NewGlobalRef` | `NewWeakGlobalRef` |
| 有效范围 | **当前线程、当前 native 方法**，返回后自动释放 | 直到 `DeleteGlobalRef` | 直到 `DeleteWeakGlobalRef` |
| 阻止 GC | ✅ | ✅ | ❌ |
| 能跨线程 | ❌ | ✅ | ✅ |
| 典型用途 | 临时变量 | 缓存 jclass、保存回调 listener | "如果对象还在就通知它" |

`jmethodID`、`jfieldID`、`GetStringUTFChars` 拿到的 `const char*` 都**不是**引用，不受这些规则约束。

## 二、局部引用：为什么要手动删 ⭐

native 方法返回时，局部引用会自动释放。那为什么还要 `DeleteLocalRef`？因为**局部引用表有上限**，在一次调用里创建太多就会溢出：

```cpp
jint countLong(JNIEnv* env, jobject, jobjectArray names) {
    jsize n = env->GetArrayLength(names);
    jint count = 0;
    for (jsize i = 0; i < n; ++i) {
        auto s = static_cast<jstring>(env->GetObjectArrayElement(names, i));   // 每次 +1 个局部引用
        if (env->GetStringLength(s) > 5) ++count;
        env->DeleteLocalRef(s);                    // ⭐ 循环里必须删
    }
    return count;
}
```

不删的话，数组有几万个元素时就会崩：`JNI ERROR (app bug): local reference table overflow`。老版本 Android 的上限只有 512，新版本大得多，但不要依赖它——**native 线程里长期运行的循环，attach 之后不返回 Java，局部引用永远不会自动释放**（第 7 课）。

需要删的情况：

- 循环里创建的引用。
- 长时间运行、不返回 Java 的函数里。
- 工具函数内部创建的引用（调用方不知道它创建了多少）。

## 三、`PushLocalFrame` / `PopLocalFrame`：成批释放

一段代码里创建了很多局部引用，逐个删很麻烦，可以用"局部帧"：

```cpp
for (jsize i = 0; i < n; ++i) {
    if (env->PushLocalFrame(16) != JNI_OK) return;      // 预留 16 个，失败时挂起 OOM
    jobject user  = env->GetObjectArrayElement(users, i);
    jstring name  = static_cast<jstring>(env->GetObjectField(user, gUserNameField));  // 假设已在 OnLoad 缓存
    jclass  cls   = env->GetObjectClass(user);
    // ... 随便用 ...
    env->PopLocalFrame(nullptr);                         // 这一帧里的所有局部引用一次释放
}
```

想把其中一个对象带出帧外，就作为参数传给 `PopLocalFrame`：

```cpp
jobject result = env->PopLocalFrame(localResult);   // 返回一个在外层帧里有效的新局部引用
```

`EnsureLocalCapacity(n)`：提前确认还能再创建 n 个局部引用，失败时返回负数。

## 四、RAII 封装：不会忘记删

第 3 课的 `ScopedUtfChars` 是同一个思路——**用 C++ 析构函数自动释放**：

```cpp
template <typename T>
class ScopedLocalRef {
public:
    ScopedLocalRef(JNIEnv* env, T ref) : env_(env), ref_(ref) {}
    ~ScopedLocalRef() { if (ref_) env_->DeleteLocalRef(ref_); }
    T get() const { return ref_; }
    T release() { T r = ref_; ref_ = nullptr; return r; }   // 要返回给 Kotlin 时用
    ScopedLocalRef(const ScopedLocalRef&) = delete;
    ScopedLocalRef& operator=(const ScopedLocalRef&) = delete;
private:
    JNIEnv* env_; T ref_;
};

for (jsize i = 0; i < n; ++i) {
    ScopedLocalRef<jstring> s(env, static_cast<jstring>(env->GetObjectArrayElement(names, i)));
    if (env->GetStringLength(s.get()) > 5) ++count;
}   // 每轮结束自动 DeleteLocalRef，中途 continue / return 也不会漏
```

全局引用同理，写一个 `GlobalRef` 类，在析构函数里 `DeleteGlobalRef`（需要能拿到 env，第 7 课会用 `JavaVM` 获取）。

口诀：**循环里必删，长函数必删，用 RAII 就不会忘。**

## 五、全局引用：泄漏会抓住整个页面 ⭐

```cpp
jobject gListener = nullptr;

void setListener(JNIEnv* env, jobject, jobject listener) {
    if (gListener) env->DeleteGlobalRef(gListener);   // ⭐ 替换前先删旧的
    gListener = listener ? env->NewGlobalRef(listener) : nullptr;
}

void clearListener(JNIEnv* env, jobject) {
    if (gListener) { env->DeleteGlobalRef(gListener); gListener = nullptr; }
}
```

全局引用让对象**永远不会被 GC**。如果 listener 是 Activity 里的匿名对象（它持有 Activity 的引用），就会：

- 转屏后旧 Activity 回收不了 → **内存泄漏**（和 Kotlin 课第 9 课"ViewModel 不要持有 Activity"是同一个问题）。
- C++ 之后回调到一个已经销毁的界面。
- 全局引用数量也有上限，泄漏多了会报 `global reference table overflow`。

做法：在 Kotlin 侧和生命周期配对——`onStart` 注册、`onStop` 调用 `clearListener`；或者在 ViewModel 的 `onCleared()` 里清理（第 8 课）。

## 六、弱全局引用：不阻止 GC

只想"对象还活着就通知它，死了就算了"，用弱全局引用：

```cpp
jweak gWeakListener = nullptr;

void setWeakListener(JNIEnv* env, jobject, jobject listener) {
    gWeakListener = env->NewWeakGlobalRef(listener);
}

void notify(JNIEnv* env, jint value) {
    jobject strong = env->NewLocalRef(gWeakListener);   // ⭐ 先升级成局部（强）引用
    if (strong == nullptr) return;                      // 对象已被回收
    env->CallVoidMethod(strong, gOnValue, value);        // gOnValue：缓存的 jmethodID
    env->DeleteLocalRef(strong);
}
```

⚠️ 不要这样写：

```cpp
if (!env->IsSameObject(gWeakListener, nullptr)) {      // 检查时还活着……
    env->CallVoidMethod(gWeakListener, ...);           // ……调用时可能已经被回收了
}
```

检查和使用之间 GC 可能刚好发生。**先 `NewLocalRef` 拿到强引用再用**，拿到了就保证不会被回收。

## 七、比较引用：`IsSameObject`

同一个对象的两个引用，句柄值可能不同：

```cpp
if (a == b) { }                         // ❌ 比较的是句柄，不是对象
if (env->IsSameObject(a, b)) { }        // ✅
```

缓存全局引用，再和 Kotlin 新传进来的对象比较时，常会踩这个坑。

## 八、易错点

1. **循环里 `GetObjectArrayElement` / `NewStringUTF` 不删**：局部引用表溢出。
2. **把局部引用存进全局变量或 static 变量**：方法返回后失效，之后使用会崩（CheckJNI：`use of deleted local reference`）。
3. **在 native 线程里长时间运行，从不返回 Java**：局部引用永远不会自动释放，必须手动删或用局部帧。
4. **保存 listener 时 `NewGlobalRef`，却从不 `DeleteGlobalRef`**：Activity 泄漏。
5. **替换全局引用前没删旧的**：每设置一次就泄漏一个。
6. **直接用 `jweak` 调用方法**：对象可能已被回收。先 `NewLocalRef`。
7. **用 `==` 比较两个 jobject**：要用 `IsSameObject`。
8. **对 `jmethodID` 调用 `DeleteLocalRef`**：它不是引用，会出错。
9. **`PushLocalFrame` 和 `PopLocalFrame` 不配对**：中途 return 了，帧没有弹出。

## 九、速查表

| 需求 | API |
|---|---|
| 删局部引用 | `DeleteLocalRef(ref)` |
| 成批释放 | `PushLocalFrame(cap)` … `PopLocalFrame(result)` |
| 预留容量 | `EnsureLocalCapacity(n)` |
| 全局引用 | `NewGlobalRef` / `DeleteGlobalRef` |
| 弱全局引用 | `NewWeakGlobalRef` / `DeleteWeakGlobalRef` |
| 弱引用转强引用 | `NewLocalRef(weak)`，返回 null 表示已被回收 |
| 比较对象 | `IsSameObject(a, b)` |
| 查引用类型 | `GetObjectRefType(ref)` |
| 自动释放 | `ScopedLocalRef<T>` RAII 封装 |

---

**下一课预告（第 6 课）：异常处理** —— 异常挂起时哪些 JNI 函数还能调用？怎样用 `ThrowNew` 从 C++ 抛出 Kotlin 能 catch 的异常？为什么 C++ 异常绝对不能越过 JNI 边界？
