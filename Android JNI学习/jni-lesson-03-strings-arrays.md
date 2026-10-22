# JNI 第 3 课：字符串与数组深入

> 适用读者：完成 JNI 第 1、2 课；看过 [[JNI学习大纲]] §6～7 和 [[Android工程师C++入门教程]] §9～10。
> 核心收获：搞懂 Modified UTF-8 到底会在哪里出问题，掌握字符串的几种取法，掌握数组释放的三种模式和 `Get/SetArrayRegion`、Critical 的使用条件，学会用 direct `ByteBuffer` 零拷贝传大块数据，能根据场景选对 API。

---

## 一、回顾

笔记里的基本写法是对的：

```cpp
const char* s = env->GetStringUTFChars(jstr, nullptr);
// 使用 s
env->ReleaseStringUTFChars(jstr, s);        // 必须配对

jint* data = env->GetIntArrayElements(arr, nullptr);
env->ReleaseIntArrayElements(arr, data, 0); // 必须配对
```

本课补三件事：**编码到底有什么坑、释放模式怎么选、怎样少拷贝**。

## 二、字符串：Modified UTF-8 ⭐

Java/Kotlin 的 `String` 内部是 **UTF-16**。JNI 的 `...UTF...` 系列函数用的不是标准 UTF-8，而是 **Modified UTF-8（MUTF-8）**，有两处不同：

| 字符 | 标准 UTF-8 | MUTF-8 |
|---|---|---|
| ASCII、常用中文（BMP 内，U+0001～U+FFFF） | 1～3 字节 | **完全一样** |
| `\0`（U+0000） | `00` | `C0 80`（两字节，所以 C 字符串里不会出现 0） |
| emoji 等增补字符（U+10000 以上） | **4 字节** | 拆成 UTF-16 代理对，**每半个 3 字节，共 6 字节** |

所以要**更正笔记的说法**：日常中文没问题，**出问题的是 emoji 和生僻字（增补平面）**：

```cpp
// ❌ 从文件、网络或 C 库拿到的标准 UTF-8，里面有 😀（F0 9F 98 80）
return env->NewStringUTF(utf8FromNetwork);
// 开 CheckJNI（第 9 课）时直接 abort：input is not valid Modified UTF-8
// 不开的话，可能得到乱码
```

正确做法（三选一）：

```kotlin
// ① 最简单：传字节，让 Kotlin 解码（推荐）
external fun loadText(): ByteArray
val text = String(NativeBridge.loadText(), Charsets.UTF_8)
```

```cpp
// ② C++ 侧把 UTF-8 转成 UTF-16，再用 NewString（不是 NewStringUTF）
std::u16string u16 = utf8ToUtf16(input);            // 自己实现或用第三方库
return env->NewString(reinterpret_cast<const jchar*>(u16.data()), u16.size());

// ③ 能保证全是 ASCII / BMP 字符时，NewStringUTF 没问题
```

反方向也一样：`GetStringUTFChars` 拿到的 emoji 是 6 字节的 MUTF-8 格式，直接交给要求标准 UTF-8 的 C 库（JSON 解析、写文件）会出错。需要标准 UTF-8 时，Kotlin 侧先 `str.encodeToByteArray()`，传 `ByteArray` 给 C++。

口诀：**ASCII 和中文随便用；有 emoji 就传字节，别用 UTF 函数。**

## 三、字符串的几种取法

```cpp
// 1. 长度：注意单位不同
jsize u16Len  = env->GetStringLength(jstr);      // UTF-16 码元数（≈ Kotlin 的 str.length）
jsize mutfLen = env->GetStringUTFLength(jstr);   // MUTF-8 字节数（不含 \0）

// 2. Get/Release：拿到整个字符串，可能拷贝，必须 Release
const char* s = env->GetStringUTFChars(jstr, nullptr);
if (s == nullptr) return nullptr;                // ⚠️ 内存不足时返回 null，并挂起 OutOfMemoryError
std::string value(s);
env->ReleaseStringUTFChars(jstr, s);

// 3. Region：拷贝到你自己的缓冲区，不需要 Release（短字符串首选）
char buf[128] = {};                              // 先清零：规范不保证一定补 \0
jsize len = env->GetStringLength(jstr);          // start / len 的单位是 UTF-16 码元
if (len < 40) {                                  // 每个码元最多 3 字节，40*3 < 128，留得出结尾的 0
    env->GetStringUTFRegion(jstr, 0, len, buf);
}
```

再写一个 RAII 小工具，**不会忘记 Release，提前 return 也安全**（C++ 入门笔记 §13 的智能指针是同一思路）：

```cpp
class ScopedUtfChars {
public:
    ScopedUtfChars(JNIEnv* env, jstring s) : env_(env), s_(s),
        chars_(s ? env->GetStringUTFChars(s, nullptr) : nullptr) {}
    ~ScopedUtfChars() { if (chars_) env_->ReleaseStringUTFChars(s_, chars_); }
    const char* c_str() const { return chars_; }
    ScopedUtfChars(const ScopedUtfChars&) = delete;
    ScopedUtfChars& operator=(const ScopedUtfChars&) = delete;
private:
    JNIEnv* env_; jstring s_; const char* chars_;
};

jstring greet(JNIEnv* env, jobject, jstring name) {
    ScopedUtfChars n(env, name);
    if (n.c_str() == nullptr) return nullptr;    // name 为 null 或内存不足
    std::string r = std::string("Hello, ") + n.c_str();
    return env->NewStringUTF(r.c_str());
}
```

**`String?` 参数一定要判空**：Kotlin 传 `null` 过来就是 `nullptr`，直接 `GetStringUTFChars(nullptr)` 会崩。

## 四、数组：三种释放模式 ⭐

`Get<Type>ArrayElements` 可能给你**原数组的指针**（pinned，固定在内存里不被 GC 移动），也可能给你**一份拷贝**，由运行时决定，第二个参数 `isCopy` 会告诉你是哪种。`Release` 的 `mode` 参数决定改动要不要写回：

| mode | 拿到的是拷贝时 | 拿到的是原数组时 | 用在 |
|---|---|---|---|
| `0` | 写回 + 释放拷贝 | 解除固定 | **改了数组，要同步给 Kotlin**（最常用） |
| `JNI_COMMIT` | 写回，**不释放** | 什么都不做 | 中途同步一次，之后还要用（最后必须再用 0 或 ABORT 释放） |
| `JNI_ABORT` | **不写回** + 释放 | 解除固定（已改的内容**撤不回**） | **只读**，省掉一次写回拷贝 |

```cpp
jint sum(JNIEnv* env, jobject, jintArray arr) {
    jsize n = env->GetArrayLength(arr);
    jint* p = env->GetIntArrayElements(arr, nullptr);
    if (p == nullptr) return 0;
    jint total = 0;
    for (jsize i = 0; i < n; ++i) total += p[i];
    env->ReleaseIntArrayElements(arr, p, JNI_ABORT);   // ⭐ 只读用 ABORT
    return total;
}
```

注意：`JNI_ABORT` 不能用来"撤销修改"——拿到的是原数组时，你写进去的内容已经生效了。

## 五、`Get/SetArrayRegion`：最简单、最安全

```cpp
// 读：拷贝一段到 C++ 缓冲区，不需要 Release
std::vector<jint> buf(n);
env->GetIntArrayRegion(arr, 0, n, buf.data());

// 写：把 C++ 数据拷回 Kotlin 数组
env->SetIntArrayRegion(arr, 0, n, buf.data());

// 返回新数组给 Kotlin
jintArray out = env->NewIntArray(n);
if (out == nullptr) return nullptr;              // OOM
env->SetIntArrayRegion(out, 0, n, buf.data());
return out;
```

- 不用配对 Release，提前 return 也不会泄漏。
- 越界时抛 `ArrayIndexOutOfBoundsException`（不会悄悄写坏内存）。
- 数组不大，或者本来就要拷到 `std::vector` 里处理时，**首选 Region**。

## 六、Critical：最快，但限制最多

```cpp
void* p = env->GetPrimitiveArrayCritical(arr, nullptr);
// ⚠️ 在 Release 之前：不能调用任何其他 JNI 函数，不能阻塞，不能等锁，时间要短
memcpy(dst, p, bytes);
env->ReleasePrimitiveArrayCritical(arr, p, JNI_ABORT);
```

拿到原数组指针的概率最高（少一次拷贝），代价是期间可能会暂停 GC。只适合"拿到 → 快速 memcpy 或简单计算 → 立刻释放"。`GetStringCritical` 同理。

## 七、direct `ByteBuffer`：零拷贝传大数据 ⭐

图像帧、音频缓冲这类数据很大（MB 级），每次调用都拷贝一遍太浪费。direct ByteBuffer 的内存**本来就在 native 堆上**，C++ 直接读写：

```kotlin
val buffer = ByteBuffer.allocateDirect(width * height * 4)
    .order(ByteOrder.nativeOrder())               // 和 C++ 字节序一致
NativeBridge.fillGradient(buffer, width, height)  // C++ 直接往里写
```

```cpp
void fillGradient(JNIEnv* env, jobject, jobject buffer, jint w, jint h) {
    auto* p = static_cast<uint8_t*>(env->GetDirectBufferAddress(buffer));
    jlong cap = env->GetDirectBufferCapacity(buffer);
    if (p == nullptr || cap < static_cast<jlong>(w) * h * 4) return;   // 不是 direct，或容量不够
    for (jint i = 0; i < w * h; ++i) {
        p[i * 4] = static_cast<uint8_t>(i % 256);  // R
        p[i * 4 + 3] = 255;                        // A
    }
}
```

- 不用 Get/Release，指针在 buffer 被 GC 回收之前一直有效。
- `ByteBuffer.allocate()`（非 direct）的 `GetDirectBufferAddress` 返回 `nullptr`。
- 反方向：C++ 有一块内存想给 Kotlin 看，用 `env->NewDirectByteBuffer(ptr, size)`。⚠️ 这块内存要由 C++ 保证一直有效，Kotlin 用完之前不能 free（第 8 课生命周期）。

## 八、怎么选

| 场景 | 推荐 |
|---|---|
| 短字符串、只读 | `GetStringUTFRegion` 拷到栈缓冲区 |
| 一般字符串 | `GetStringUTFChars` + RAII 自动 Release |
| 含 emoji 的文本 | 传 `ByteArray`，Kotlin 侧 UTF-8 编解码 |
| 小数组 / 要拷到 vector | `Get/SetArrayRegion` |
| 大数组，原地修改 | `Get<Type>ArrayElements` + mode `0` |
| 大数组，只读 | `Get<Type>ArrayElements` + `JNI_ABORT`，或 Critical |
| 很大的数据、反复传 | direct `ByteBuffer` |
| 对象数组 `Array<String>` | `GetObjectArrayElement` 逐个取，**用完 `DeleteLocalRef`**（第 5 课） |

## 九、易错点

1. **有 emoji 的标准 UTF-8 交给 `NewStringUTF`**：CheckJNI 下 abort，否则乱码。
2. **`String?` 参数为 null 时直接 `GetStringUTFChars`**：崩溃。先判空。
3. **忘了 `GetStringUTFChars` 可能返回 null**：OOM 时会，此时直接 return。
4. **Get 和 Release 不配对**（中途 return、异常分支）：泄漏或数组一直被固定。用 RAII 或 Region。
5. **只读数组用 mode `0`**：拿到拷贝时会多写回一次，白白浪费。
6. **以为 `JNI_ABORT` 能撤销修改**：拿到原数组时撤不回。
7. **Critical 区间里调用 JNI 函数或加锁**：可能死锁或崩溃。
8. **`GetDirectBufferAddress` 用在 `ByteBuffer.allocate()` 上**：返回 null。要用 `allocateDirect`。
9. **`GetStringLength` 当字节数用**：它返回的是 UTF-16 码元数，字节数要用 `GetStringUTFLength`。

## 十、速查表

| 需求 | API |
|---|---|
| String → C 字符串 | `GetStringUTFChars` / `ReleaseStringUTFChars` |
| 拷到缓冲区 | `GetStringUTFRegion(s, start, len, buf)` |
| UTF-16 长度 / MUTF-8 字节数 | `GetStringLength` / `GetStringUTFLength` |
| C 字符串 → String | `NewStringUTF`（仅限 MUTF-8）/ `NewString`（UTF-16） |
| 数组长度 | `GetArrayLength` |
| 整段读写 | `Get/Set<Type>ArrayRegion` |
| 指针访问 | `Get/Release<Type>ArrayElements(arr, p, 0 / JNI_COMMIT / JNI_ABORT)` |
| 最快访问 | `Get/ReleasePrimitiveArrayCritical` |
| 新建数组 | `New<Type>Array(n)` / `NewObjectArray(n, cls, init)` |
| 零拷贝 | `GetDirectBufferAddress` / `NewDirectByteBuffer` |

---

**下一课预告（第 4 课）：调用 Kotlin 方法、字段与对象创建** —— C++ 怎样调用 Kotlin 的静态方法、构造对象、读属性；为什么要缓存 `jmethodID`；为什么在 native 线程里 `FindClass` 会找不到你的类；R8 会把你的回调方法改名吗。
