# JNI 第 11 课：性能与最佳实践

> 适用读者：完成 JNI 第 1～10 课。
> 核心收获：知道 JNI 调用的成本花在哪里，掌握"批量传、少回调、缓存 ID、状态留在 native 侧"几条原则，会选择数据传递方式，了解编译优化和 NEON，会用正确的工具测量，并能判断一个需求是否值得用 JNI。

---

## 一、一次 JNI 调用贵在哪

很多人以为"C++ 一定比 Kotlin 快"，于是把小函数挪到 native，结果反而更慢了。一次 Kotlin → C++ 调用的成本来自：

1. **跨边界本身**：线程状态切换、参数整理。单次开销虽然不大，但比一次普通的 Kotlin 方法调用（往往会被 JIT 内联）贵得多。
2. **数据搬运**：`GetStringUTFChars` 要做转换、可能分配内存；`Get<Type>ArrayElements` 可能拷贝整个数组（第 3 课）。
3. **反向调用**：C++ → Kotlin 的 `Call*Method` 也是一次跨边界，还要检查异常。
4. **查找**：`FindClass`、`GetMethodID` 要按字符串查找。

结论：**JNI 适合"进去一次，干一大堆活，出来一次"**，不适合"频繁进出，每次干一点点"。

口诀：**粗粒度调用，批量传数据，少回头调 Kotlin。**

## 二、原则 1：批量，而不是逐个 ⭐

```kotlin
// ❌ 100 万次跨边界
for (i in pixels.indices) pixels[i] = NativeBridge.gray(pixels[i])

// ✅ 1 次跨边界
NativeBridge.grayAll(pixels)
```

```cpp
void grayAll(JNIEnv* env, jobject, jintArray arr) {
    jsize n = env->GetArrayLength(arr);
    jint* p = env->GetIntArrayElements(arr, nullptr);
    if (!p) return;
    for (jsize i = 0; i < n; ++i) p[i] = toGray(p[i]);
    env->ReleaseIntArrayElements(arr, p, 0);      // 0：写回并释放（第 3 课）
}
```

同理，**回调也要批量**：进度不要每处理一个元素回调一次，每 1% 或每 100 ms 回调一次；结果不要逐条 `CallVoidMethod`，攒成数组一次返回。

## 三、原则 2：缓存一切能缓存的

| 东西 | 做法 | 课 |
|---|---|---|
| `jclass` | `JNI_OnLoad` 里 `NewGlobalRef` | 第 4 课 |
| `jmethodID` / `jfieldID` | `JNI_OnLoad` 里查好，存进 struct | 第 4 课 |
| `JNIEnv`（native 线程） | `thread_local`，不要每次 attach / detach | 第 7 课 |
| C++ 侧的状态 | 留在 native 对象里，用 `jlong` 句柄 | 第 8 课 |

最后一条很重要：**让状态待在它被使用的那一侧**。如果 C++ 每次都要通过 `GetObjectField` 去读 Kotlin 对象的十几个字段，不如在创建 native 对象时把配置一次性传进来。

## 四、原则 3：选对数据传递方式

| 数据 | 推荐 | 原因 |
|---|---|---|
| 少量基本类型 | 直接作为参数 | 没有额外开销 |
| 小数组、只读 | `Get<Type>ArrayRegion` 拷到栈上 | 一次拷贝，不用 Release |
| 大数组、要修改 | `Get<Type>ArrayElements` / `GetPrimitiveArrayCritical` | 可能不拷贝；Critical 期间不能调用其他 JNI 函数 |
| 大块数据、反复使用 | **direct `ByteBuffer`**（`GetDirectBufferAddress`） | Kotlin 和 C++ 共享同一块内存，零拷贝 |
| 图片 | `Bitmap` + `AndroidBitmap_lockPixels` | 直接访问像素，第 12 课 |
| 字符串、高频 | 传 `ByteArray`（UTF-8） | 跳过 Modified UTF-8 转换，也没有 emoji 问题（第 3 课） |
| 复杂结构 | 拆成几个基本数组，或者序列化成字节 | 避免逐字段 `GetObjectField` |

## 五、编译优化

```kotlin
android {
    buildTypes {
        release {
            externalNativeBuild {
                cmake {
                    // AGP 默认 Release 使用 CMake 的 RelWithDebInfo（-O2 -g）或 Release（-O3）构建，
                    // 具体以 AGP 版本为准；需要时可以显式加参数
                    cppFlags += "-O3"
                }
            }
        }
    }
}
```

- **永远不要用 Debug 构建（`-O0`）测性能**，Debug 的 C++ 可能比 Kotlin 还慢好几倍。
- `-O2` / `-O3` 下 clang 会**自动向量化**简单循环（用 NEON 一次处理多个数据）。写成"简单的 for 循环 + 连续数组访问"，比手写复杂指针运算更容易被优化。
- arm64 上 NEON 是标配，需要极致性能时可以用 `<arm_neon.h>` 手写 intrinsics。一般先依赖自动向量化，测量后再决定。

## 六、测量：先测再优化 ⭐

| 工具 | 用途 |
|---|---|
| `System.nanoTime()` | 粗略对比，至少跑几十次、去掉前几次（JIT 预热） |
| **Jetpack Microbenchmark** | 可靠的微基准：自动预热、多次运行、锁频提示，输出中位数 |
| Android Studio **CPU Profiler** | 看 Kotlin 和 native 的调用栈和耗时占比（选 Callstack Sample） |
| **simpleperf** | NDK 自带的命令行采样工具，适合深入分析 native 热点 |

```kotlin
@get:Rule val benchmarkRule = BenchmarkRule()

@Test fun grayNative() {
    val pixels = IntArray(1_000_000) { it }
    benchmarkRule.measureRepeated {
        NativeBridge.grayAll(pixels)
    }
}
```

对比时要用**同等质量的 Kotlin 实现**：ART 的 JIT/AOT 编译出来的 Kotlin 循环并不慢。很多时候差距只有一两倍，甚至 Kotlin 更快。

## 七、什么时候不该用 JNI

**适合用 JNI：**

- 复用现成的 C/C++ 库：FFmpeg、OpenCV、SQLite 扩展、游戏引擎、加密库。
- 计算密集、数据量大：图像 / 音频处理、物理模拟、编解码。
- 需要底层 API：OpenGL ES / Vulkan、AAudio / Oboe、`AHardwareBuffer`。
- 跨平台共享核心逻辑（Android / iOS / 桌面同一份 C++）。

**不适合：**

- 普通业务逻辑、字符串处理、JSON 解析——Kotlin 足够快，而且安全得多。
- "为了防破解"——so 也能被反编译，只是门槛高一点。
- 很小、被频繁调用的函数——跨边界的开销比函数本身还大。

代价也要算进去：崩溃更难排查（第 9 课）、多 ABI 构建、包体积、内存安全问题、团队里能维护 C++ 的人。

## 八、易错点

1. **用 Debug 构建测性能**：得出"C++ 比 Kotlin 还慢"的错误结论。
2. **逐个元素调用 native 方法**：跨边界开销远大于计算本身。
3. **每处理一个元素回调一次 Kotlin**：比纯 Kotlin 实现还慢。
4. **每次调用都 `FindClass` / `GetMethodID`**：按字符串查找，浪费时间。
5. **native 线程每次回调都 attach / detach**：用 `thread_local` 保持 attach。
6. **只跑一次就下结论**：没有预热，JIT 还没编译 Kotlin 代码。
7. **在 Critical 区域内做耗时操作**：可能阻塞 GC，拖慢整个 App。
8. **为了"性能"把普通业务逻辑写成 C++**：收益很小，维护成本很高。

## 九、速查表

| 原则 | 做法 |
|---|---|
| 调用粒度 | 一次调用处理一整批数据 |
| 回调 | 节流、攒批，不要逐个元素回调 |
| 查找 | `jclass` / `jmethodID` 在 `JNI_OnLoad` 里缓存 |
| 状态 | 留在使用它的那一侧，用 `jlong` 句柄 |
| 大块数据 | direct `ByteBuffer`、`Bitmap`、`GetPrimitiveArrayCritical` |
| 构建 | Release 构建，`-O2`/`-O3`，让编译器自动向量化 |
| 测量 | Microbenchmark、CPU Profiler、simpleperf |
| 决策 | 有现成 C++ 库或计算密集才用 JNI |

---

**下一课预告（第 12 课）：综合项目——原生图片灰度处理** —— 把整门课串起来：`jnigraphics` 直接访问 `Bitmap` 像素，动态注册，异常转换，协程后台执行，ViewModel + Compose 显示结果，再和 Kotlin 实现比一比速度。
