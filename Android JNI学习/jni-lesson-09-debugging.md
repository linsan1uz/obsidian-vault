# JNI 第 9 课：Native 崩溃排查与调试

> 适用读者：完成 JNI 第 1～8 课。笔记 [[JNI学习大纲]] 只提到 `UnsatisfiedLinkError`，本课补全 native 崩溃这一整块。
> 核心收获：看得懂 logcat 里的 `Fatal signal` 和 tombstone，能用 `ndk-stack` / `llvm-addr2line` 把地址还原成源码行，会给 Release 包上传 native 符号，会用 Android Studio 的 LLDB 调试 C++，会用 CheckJNI 和 HWASan 抓 JNI 误用和内存错误。

---

## 一、native 崩溃长什么样

Kotlin 崩溃有异常栈；**C++ 崩溃是操作系统发出的信号**，进程直接被杀，`try/catch` 接不住。logcat 里搜 `DEBUG` 或 `Fatal signal`：

```
F libc    : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0 in tid 12345 (ndk-worker), pid 12300 (fqf.ndk4study)
F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
F DEBUG   : ABI: 'arm64'
F DEBUG   : backtrace:
F DEBUG   :       #00 pc 000000000001a2b4  /data/app/~~xx/com.fqf.ndk4study-yy/lib/arm64/libndk4study.so (process(_JNIEnv*, _jobject*, _jobject*)+52)
F DEBUG   :       #01 pc 0000000000355e30  /apex/com.android.art/lib64/libart.so (art_quick_generic_jni_trampoline+144)
```

怎么读：

- **信号**：告诉你是哪一类错误（见下表）。
- **`fault addr 0x0`**：访问了地址 0 附近 → 几乎一定是**空指针**。
- **`tid ... (ndk-worker)`**：崩溃的线程名，第 7 课的 `JavaVMAttachArgs` 名字在这里发挥作用。
- **backtrace**：`#00` 是崩溃点。`pc` 后面是 **so 内的偏移地址**，还原源码行全靠它。括号里有函数名说明 so 带了符号表，没有的话只能看到地址。

| 信号 | 常见原因 |
|---|---|
| `SIGSEGV`（11）`SEGV_MAPERR` | 空指针、野指针、访问已释放的内存 |
| `SIGSEGV` `SEGV_ACCERR` | 写只读内存，比如修改 `GetStringUTFChars` 返回的字符串 |
| `SIGABRT`（6） | 主动 abort：CheckJNI 报错、C++ 异常越过边界、`assert`、HWASan 报告 |
| `SIGBUS`（7） | 未对齐访问、mmap 的文件被截断 |
| `SIGILL`（4） | 非法指令：so 的 ABI / CPU 特性不匹配，或者调用了 `__builtin_trap` |

`SIGABRT` 时**往上翻几行**，`Abort message:` 或 `JNI DETECTED ERROR IN APPLICATION` 那一行才是真正的原因。

完整的 tombstone 保存在 `/data/tombstones/`，普通设备上需要 root 才能读，可以用 `adb bugreport` 导出。线上崩溃可以用 `ActivityManager.getHistoricalProcessExitReasons()`（API 30+）查到 `ApplicationExitInfo.REASON_CRASH_NATIVE`。

## 二、把地址还原成源码行 ⭐

关键：要用**未 strip 的 so**（带调试信息的版本）。打包进 APK 的 so 默认会被 strip 掉符号。AGP 构建的未 strip 版本在：

```
app/build/intermediates/cxx/<构建类型>/<随机目录>/obj/<abi>/libndk4study.so
```

`<构建类型>` 是 `Debug`、`RelWithDebInfo` 等。不确定时用 `find app/build -name libndk4study.so` 找，用 `file` 命令看输出里有没有 `with debug_info, not stripped`。

**方法 A：`ndk-stack`**——直接处理整段 logcat：

```bash
adb logcat | $NDK/ndk-stack -sym app/build/intermediates/cxx/Debug/xxxx/obj/arm64-v8a
# 或者先保存再处理
adb logcat -d > crash.txt
$NDK/ndk-stack -sym app/build/intermediates/cxx/Debug/xxxx/obj/arm64-v8a -dump crash.txt
```

输出：`#00 ... process(...) native_bridge.cpp:42`。复制日志时**要带上那行星号**，否则 ndk-stack 识别不出来。

**方法 B：`llvm-addr2line`**——只还原一个地址：

```bash
$NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-addr2line -C -f -e path/to/libndk4study.so 0x1a2b4
# -C 还原 C++ 函数名  -f 显示函数名  -e 指定 so
```

`<host>` 是 `darwin-x86_64`、`linux-x86_64` 或 `windows-x86_64`。⚠️ 用来还原的 so 必须是**和崩溃包同一次构建的产物**，代码改过、重新编译过，地址就对不上了。

口诀：**看信号定类型，看 pc 找偏移，用未 strip 的 so 还原行号。**

## 三、Release 包：上传 native 符号

线上崩溃要在 Play Console 里看到行号，需要上传符号文件：

```kotlin
android {
    buildTypes {
        release {
            ndk {
                debugSymbolLevel = "FULL"     // 或 "SYMBOL_TABLE"：只有函数名，没有行号，文件更小
            }
        }
    }
}
```

构建 AAB 时符号会自动打进包里，Play Console 用它来还原栈（底层就是 ndk-stack）。**自己归档好每个发布版本的未 strip so**，Firebase Crashlytics 等工具也需要它们。

## 四、LLDB：在 Android Studio 里断点调试 C++

1. Run/Debug Configurations → Debugger → Debug type 选 **Dual (Java + Native)**（默认的 Detect Automatically 一般也能识别）。
2. 在 `.cpp` 文件里打断点，点 Debug。
3. 停下后，Debug 窗口切到 **LLDB** 标签，可以输入命令：

| 命令 | 作用 |
|---|---|
| `bt` | 当前线程的调用栈 |
| `frame variable` | 当前帧的所有局部变量 |
| `p len`、`p *ptr` | 打印表达式 |
| `memory read -c 16 ptr` | 读 16 字节内存 |
| `thread list` | 所有线程 |
| `process handle SIGSEGV -s true` | 收到 SIGSEGV 时停下 |

调试 Release 构建时变量常显示 `<optimized out>`：用 Debug 构建调试，或者临时把 `-O0` 加到编译参数。

## 五、CheckJNI：抓 JNI 误用 ⭐

CheckJNI 是 ART 的"JNI 严格模式"：检查每个 JNI 调用的参数，发现问题就 abort 并打印清楚的原因。

- **模拟器默认开启。**
- 真机：`adb shell setprop debug.checkjni 1`，然后**重启 App**（只对之后启动的进程生效）。
- 官方文档说明：App 的 `android:debuggable` 属性也会为该 App 开启 CheckJNI，Debug 构建会自动带上这个属性。所以**真正"默认关闭"的是真机上的 Release / 非 debuggable 构建**。

典型报错，大部分都是前几课讲过的坑：

| CheckJNI 报错 | 原因 | 课 |
|---|---|---|
| `input is not valid Modified UTF-8` | `NewStringUTF` 传入了含 emoji 的标准 UTF-8 | 第 3 课 |
| `use of deleted local reference` / `invalid jobject` | 缓存了局部引用 | 第 4、5 课 |
| `called with pending exception` | 有异常没处理就继续调用 JNI | 第 6 课 |
| `thread exited without detaching` | native 线程退出前没 detach | 第 7 课 |
| `jarray was NULL` / `jclass is NULL` | `FindClass` 失败没检查 | 第 4、6 课 |

**发布前用模拟器或开启 CheckJNI 跑一遍关键流程**（尤其是 R8 之后的 Release 构建），很多问题在关闭 CheckJNI 时会"碰巧不崩"，到用户手里才崩。

## 六、HWASan：抓内存错误

越界读写、use-after-free、double free 这类问题，崩溃点往往离出错点很远，甚至不崩、只是数据错乱。用 **HWASan**（硬件辅助地址检查）：

- ⚠️ 老的 **ASan 从 2023 年起已不再支持**用于 Android 应用开发，现在用 HWASan。
- 只支持 **arm64**；Android 14+ 的设备可以用 `wrap.sh`，更早的系统需要刷 HWASan 系统镜像。
- CPU 约 2 倍开销，内存开销 10%～35%，**只在专门的调试构建中开启**。

配置（Kotlin DSL）：

```kotlin
android {
    defaultConfig {
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",          // ⭐ 必须是共享 STL，不能是 c++_static
                    "-DANDROID_SANITIZE=hwaddress",      // NDK 27+ 可用，不用改 CMakeLists
                )
            }
        }
    }
}
```

或者在 `CMakeLists.txt` 里对每个 target：

```cmake
target_compile_options(${CMAKE_PROJECT_NAME} PUBLIC -fsanitize=hwaddress -fno-omit-frame-pointer)
target_link_options(${CMAKE_PROJECT_NAME} PUBLIC -fsanitize=hwaddress)
```

再添加 `app/src/main/resources/lib/arm64-v8a/wrap.sh`（App 需要是 debuggable 的）：

```sh
#!/system/bin/sh
LD_HWASAN=1 exec "$@"
```

发现错误时 App 以 `SIGABRT` 崩溃，logcat 里会打印 `ERROR: HWAddressSanitizer: tag-mismatch`，还有出错位置和**这块内存在哪里分配、在哪里释放**的栈——这正是普通崩溃给不了的信息。

## 七、排查流程

```
崩溃
 ├─ Java 异常栈（UnsatisfiedLinkError 等）→ 第 1、2 课
 └─ Fatal signal
     ├─ SIGABRT → 找 Abort message / JNI DETECTED ERROR → CheckJNI 表
     └─ SIGSEGV / SIGBUS → ndk-stack 还原行号
           └─ 行号看起来没问题、偶现 → 上 HWASan
```

## 八、易错点

1. **用打包进 APK 的 so 还原地址**：已 strip，没有行号。要用 `intermediates/cxx/.../obj/` 下的版本。
2. **用新编译的 so 还原旧版本的崩溃**：地址对不上，结果是错的。
3. **只看 `Fatal signal` 那一行**：真正原因常在 `Abort message` 里。
4. **只用真机上的 Release 构建测试**：那里不开 CheckJNI，很多错误被掩盖。
5. **用 `c++_static` 开 HWASan**：不工作，必须 `c++_shared`。
6. **还在找 ASan 的教程**：已不再支持，用 HWASan。
7. **Release 包没配 `debugSymbolLevel`**：Play Console 里线上 native 崩溃只有地址。
8. **调试优化过的代码**：变量 `<optimized out>`、断点跳行，换 Debug 构建。

## 九、速查表

| 需求 | 工具 / 命令 |
|---|---|
| 看崩溃 | logcat 搜 `Fatal signal` / `DEBUG` / `Abort message` |
| 整段还原 | `adb logcat \| $NDK/ndk-stack -sym <obj/abi 目录>` |
| 单个地址还原 | `llvm-addr2line -C -f -e lib.so 0xOFFSET` |
| 未 strip 的 so | `app/build/intermediates/cxx/<类型>/<随机>/obj/<abi>/` |
| 线上符号 | `buildTypes.release.ndk.debugSymbolLevel = "FULL"` |
| 断点调试 | Android Studio Dual 调试 + LLDB（`bt`、`frame variable`） |
| JNI 误用 | CheckJNI：`adb shell setprop debug.checkjni 1` |
| 内存错误 | HWASan：`c++_shared` + `-DANDROID_SANITIZE=hwaddress` + `wrap.sh` |
| 线上退出原因 | `ApplicationExitInfo.REASON_CRASH_NATIVE`（API 30+） |

---

**下一课预告（第 10 课）：预编译库、第三方库与打包** —— 怎样接入别人给的 `.so` / `.a`？`jniLibs` 和 `IMPORTED` 能不能同时用？Prefab 是什么？`c++_static` 和 `c++_shared` 怎么选？16 KB 页大小要求如何检查？
