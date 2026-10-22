# JNI 第 12 课：综合项目——原生图片灰度处理

> 适用读者：完成 JNI 第 1～11 课，以及 Kotlin 课的 ViewModel、StateFlow、Compose 部分。
> 核心收获：用 `jnigraphics` 直接读写 `Bitmap` 像素，把前面学的动态注册、异常转换、引用管理、协程后台执行、ViewModel + Compose 串成一个完整功能，并和纯 Kotlin 实现比较速度。

---

## 一、目标与结构

点击按钮 → 在后台把一张图片转成灰度 → 显示结果和耗时。

```
app/src/main/cpp/
├── CMakeLists.txt
├── jni_helper.h          // 第 2 课的 registerNatives + 第 6 课的 throwJava
├── jni_onload.cpp        // 第 2 课：调用 register_NativeBridge、register_ImageNative
└── image_native.cpp      // ⭐ 本课新增
app/src/main/java/com/fqf/ndk4study/
├── ImageNative.kt
├── GrayViewModel.kt
└── GrayScreen.kt
```

## 二、CMake：链接 `jnigraphics`

```cmake
add_library(${CMAKE_PROJECT_NAME} SHARED
    jni_onload.cpp
    native_bridge.cpp
    image_native.cpp)

target_link_libraries(${CMAKE_PROJECT_NAME}
    jnigraphics          # ⭐ AndroidBitmap_* 函数在这里
    android
    log)
```

`jnigraphics` 是 NDK 自带的系统库，直接写名字即可（第 10 课）。

## 三、C++：锁定像素，逐行处理 ⭐

```cpp
// image_native.cpp
#include <jni.h>
#include <android/bitmap.h>
#include <cstdint>
#include <iterator>
#include "jni_helper.h"

namespace {

void toGrayscale(JNIEnv* env, jclass, jobject bitmap) {
    AndroidBitmapInfo info{};
    if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS) {
        throwJava(env, "java/lang/IllegalArgumentException", "无法读取 Bitmap 信息");
        return;
    }
    if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {          // ⭐ 只支持 ARGB_8888
        throwJava(env, "java/lang/IllegalArgumentException", "只支持 ARGB_8888");
        return;
    }

    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS) {
        throwJava(env, "java/lang/IllegalArgumentException", "lockPixels 失败（Bitmap 已回收或是硬件 Bitmap？）");
        return;
    }

    auto* row = static_cast<uint8_t*>(pixels);
    for (uint32_t y = 0; y < info.height; ++y) {
        auto* px = reinterpret_cast<uint32_t*>(row);
        for (uint32_t x = 0; x < info.width; ++x) {
            uint32_t c = px[x];                      // 内存中字节顺序：R G B A
            uint32_t r = c & 0xFF;
            uint32_t g = (c >> 8) & 0xFF;
            uint32_t b = (c >> 16) & 0xFF;
            uint32_t a = c & 0xFF000000;
            uint32_t gray = (r * 77 + g * 150 + b * 29) >> 8;      // 整数近似 0.299R + 0.587G + 0.114B
            px[x] = a | (gray << 16) | (gray << 8) | gray;
        }
        row += info.stride;                          // ⭐ 按 stride 换行，不是 width * 4
    }

    AndroidBitmap_unlockPixels(env, bitmap);         // ⭐ 一定要解锁
}

const JNINativeMethod kMethods[] = {
    {"toGrayscaleNative", "(Landroid/graphics/Bitmap;)V", reinterpret_cast<void*>(toGrayscale)},
};

}  // namespace

bool register_ImageNative(JNIEnv* env) {
    return registerNatives(env, "com/fqf/ndk4study/ImageNative", kMethods, std::size(kMethods));
}
```

要点逐条对应前面的课：

| 代码 | 知识点 | 课 |
|---|---|---|
| `register_ImageNative` + `JNINativeMethod` | 动态注册 | 第 2 课 |
| `throwJava` + 立即 `return` | 从 C++ 抛出 Kotlin 能接住的异常 | 第 6 课 |
| 参数是 `jclass` | Kotlin 侧用 `@JvmStatic` | 第 1 课 |
| 一次调用处理整张图 | 批量、粗粒度 | 第 11 课 |

关于像素：

- `stride` 是每行的**字节数**，可能大于 `width * 4`（行尾有填充），所以要按 `stride` 移动行指针。
- `ARGB_8888` 在内存里的字节顺序是 **R、G、B、A**，按小端 `uint32_t` 读出来，R 在最低字节。
- Bitmap 的像素默认是**预乘 alpha** 的（RGB 已经乘过 A）。灰度计算是线性的，预乘后直接算仍然正确；如果要做非线性的处理（比如调亮度曲线），要先除回 alpha。
- **硬件 Bitmap**（`Bitmap.Config.HARDWARE`，图片库经常默认用它）无法 lock，所以 Kotlin 侧要先 copy 成 `ARGB_8888`。

口诀：**先查格式，再 lock，按 stride 走，最后 unlock。**

## 四、Kotlin 封装

```kotlin
// ImageNative.kt
object ImageNative {
    init { System.loadLibrary("ndk4study") }

    @JvmStatic private external fun toGrayscaleNative(bitmap: Bitmap)

    /** 返回一张新的灰度图，不修改原图 */
    suspend fun toGrayscale(src: Bitmap): Bitmap = withContext(Dispatchers.Default) {
        val copy = requireNotNull(src.copy(Bitmap.Config.ARGB_8888, /* isMutable = */ true)) { "无法复制 Bitmap" }
        toGrayscaleNative(copy)              // 失败时抛出 IllegalArgumentException
        copy
    }
}
```

- `withContext(Dispatchers.Default)`：在后台线程执行，ART 已经 attach 了这些线程，不需要第 7 课的 attach 代码。
- `copy(ARGB_8888, true)`：解决了格式问题和硬件 Bitmap 问题，同时不修改原图。
- `external` 方法是 `private` 的，外部只能看到安全的 `suspend` API（第 8 课的封装思想）。
- `object` 加 `@JvmStatic`：native 函数第二个参数是 `jclass`。

## 五、ViewModel + Compose

```kotlin
data class GrayUiState(
    val original: Bitmap? = null,
    val result: Bitmap? = null,
    val costMs: Long? = null,
    val loading: Boolean = false,
    val error: String? = null,
)

class GrayViewModel : ViewModel() {
    private val _state = MutableStateFlow(GrayUiState())
    val state: StateFlow<GrayUiState> = _state.asStateFlow()

    fun setImage(bitmap: Bitmap) = _state.update { it.copy(original = bitmap, result = null) }

    fun convert() {
        val src = _state.value.original ?: return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                val start = SystemClock.elapsedRealtime()
                val gray = ImageNative.toGrayscale(src)
                val cost = SystemClock.elapsedRealtime() - start
                _state.update { it.copy(result = gray, costMs = cost, loading = false) }
            } catch (e: IllegalArgumentException) {
                _state.update { it.copy(error = e.message, loading = false) }   // ⭐ C++ 抛出的异常在这里接住
            }   // 不要 catch RuntimeException / Exception：会把协程的 CancellationException 也吞掉
        }
    }
}
```

```kotlin
@Composable
fun GrayScreen(vm: GrayViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    Column(Modifier.padding(16.dp)) {
        Button(onClick = vm::convert, enabled = !state.loading && state.original != null) {
            Text(if (state.loading) "处理中…" else "转成灰度")
        }
        state.costMs?.let { Text("耗时 $it ms") }
        state.error?.let { Text("出错：$it", color = MaterialTheme.colorScheme.error) }
        state.result?.let {
            Image(bitmap = it.asImageBitmap(), contentDescription = "灰度结果")
        }
    }
}
```

图片可以用 `BitmapFactory.decodeResource(resources, R.drawable.sample)` 读入，再调用 `vm.setImage(...)`。

## 六、和 Kotlin 实现比一比

```kotlin
fun toGrayscaleKotlin(src: Bitmap): Bitmap {
    val w = src.width; val h = src.height
    val pixels = IntArray(w * h)
    src.getPixels(pixels, 0, w, 0, 0, w, h)        // Kotlin 的 Int 是 ARGB 顺序，和内存顺序不同
    for (i in pixels.indices) {
        val c = pixels[i]
        val r = (c shr 16) and 0xFF; val g = (c shr 8) and 0xFF; val b = c and 0xFF
        val gray = (r * 77 + g * 150 + b * 29) shr 8
        pixels[i] = (c and 0xFF000000.toInt()) or (gray shl 16) or (gray shl 8) or gray
    }
    return Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
}
```

用第 11 课的方法比较（Release 构建、预热、多次运行取中位数）。结果因机器而异，你通常会看到：

- **Kotlin 版的大部分时间花在 `getPixels` / `createBitmap` 的拷贝上**，而 native 版直接在原内存上修改。
- 纯计算循环本身，两者差距往往没有想象中大——这正是第 11 课"先测再说"的意义。

## 七、扩展方向

- 加一个"亮度/对比度"参数，体会预乘 alpha 的影响。
- 把进度回调给 Kotlin（第 4、7 课），每处理 10% 行回调一次。
- 对大图分块，用多个线程并行处理。
- 用 `<arm_neon.h>` 改写内层循环，对比自动向量化的结果。
- 换成 `HardwareBuffer` / OpenGL ES 在 GPU 上处理。

## 八、整门课回顾清单

| 课 | 你现在应该会 |
|---|---|
| 1 | AGP 9 + NDK r30 工程配置，`external` 的几种写法和 JNI 函数名 |
| 2 | `JNI_OnLoad` + `RegisterNatives` 动态注册，`-fvisibility=hidden` |
| 3 | Modified UTF-8、字符串和数组的各种访问方式 |
| 4 | 从 C++ 调用 Kotlin，缓存 ID，ClassLoader 问题，R8 |
| 5 | 局部 / 全局 / 弱全局引用，泄漏和溢出 |
| 6 | 挂起异常、`ThrowNew`、C++ 异常不越界 |
| 7 | native 线程 attach / detach，回调包装成 Flow |
| 8 | `jlong` 句柄、`AutoCloseable`、可取消的 `suspend` |
| 9 | ndk-stack、addr2line、LLDB、CheckJNI、HWASan |
| 10 | 预编译库、Prefab、STL 选择、16 KB 页大小 |
| 11 | 性能原则与测量 |
| 12 | 综合项目 |

**接下来可以学：** OpenGL ES / Vulkan（图形）、Oboe / AAudio（低延迟音频）、FFmpeg（音视频编解码）、OpenCV（计算机视觉）。它们都建立在这门课的基础上：CMake 接入、JNI 封装、线程与生命周期管理。

## 九、易错点

1. **没有链接 `jnigraphics`**：链接时报 `undefined symbol: AndroidBitmap_getInfo`。
2. **不检查格式**：`RGB_565` 每像素 2 字节，按 4 字节处理会越界。
3. **用 `width * 4` 换行**：有行填充时图片错位、甚至越界。
4. **lock 之后中途 return 忘了 unlock**：可以用 RAII 封装，在析构函数里 unlock。
5. **直接处理硬件 Bitmap**：`lockPixels` 失败，要先 `copy(ARGB_8888, true)`。
6. **在主线程调用**：大图会卡住 UI，要用 `withContext(Dispatchers.Default)`。
7. **混淆字节顺序**：C++ 里按内存是 RGBA，Kotlin `getPixels` 的 Int 是 ARGB。
8. **用 Debug 构建比较速度**：结论不可信。

## 十、速查表

| 需求 | 写法 |
|---|---|
| 链接 | `target_link_libraries(... jnigraphics)` |
| 头文件 | `#include <android/bitmap.h>` |
| 读信息 | `AndroidBitmap_getInfo(env, bmp, &info)` → width / height / stride / format |
| 锁定像素 | `AndroidBitmap_lockPixels(env, bmp, &pixels)` |
| 解锁 | `AndroidBitmap_unlockPixels(env, bmp)` |
| 换行 | `row += info.stride` |
| 灰度 | `(r*77 + g*150 + b*29) >> 8` |
| Kotlin 侧准备 | `src.copy(Bitmap.Config.ARGB_8888, true)` |
| 显示 | `Image(bitmap.asImageBitmap(), ...)` |

---

🎉 **JNI 课程到这里就全部结束了。** 回到第 1 课的那个 `add(a, b)`，现在你已经能写出一个后台执行、能报错、不泄漏、可调试的完整 native 功能了。
