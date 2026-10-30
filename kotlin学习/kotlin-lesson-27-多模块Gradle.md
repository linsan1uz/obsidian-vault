# Kotlin 第 27 课：多模块 Gradle

> 适用读者：已完成第 12～17 课，单个 `app` 模块能跑通 Room + Retrofit + Compose。
> 核心收获：理解为什么要模块化；搭出 `app` / `feature-*` / `core-*` 结构；定依赖方向规则；在 AGP 9 下会改 `settings.gradle.kts` 与各模块 `build.gradle.kts`。

---

## 一、为什么要拆模块？

单模块 `app` 初期爽，项目变大后：

- **编译慢**：改一行 UI，整包重编。
- **边界糊**：UI 直接摸数据库、Feature 互相引用，改一处炸一片。
- **复用难**：想做第二个 App（手表 / 车机）拷代码。
- **协作冲突**：大家改同一个 `build.gradle.kts`。

模块化目标：**编译更快、依赖单向、职责清晰**。不是为了"看起来企业级"而硬拆——两人以下的练手项目可以先单模块。

## 二、推荐结构（实用向）

```
MyApp/
  settings.gradle.kts
  build.gradle.kts                 // 插件版本 catalog / apply false
  gradle/libs.versions.toml        // 可选但强烈推荐
  app/                             // 壳：Application、导航组装、Hilt 入口
  core/
    common/                        // 纯 Kotlin：Result 扩展、Dispatcher 接口
    ui/                            // 公共 Compose 主题、组件
    data/                          // Retrofit/Room 实现、Repository 实现
    model/                         // 跨层数据类（User 等）
  feature/
    users/                         // 用户列表/详情 UI + 该特征 ViewModel
    settings/                      // 设置页
```

也可以更扁：`core:database`、`core:network`、`core:datastore`。原则比目录名重要。

## 三、依赖方向规则（死记）⭐

```
app  ──►  feature:*  ──►  core:ui / core:data  ──►  core:model / core:common
                │                                    ▲
                └────────────────────────────────────┘
                     ❌ feature 互依、❌ core 依赖 feature、❌ core:data 依赖 app
```

| 允许 | 禁止 |
|---|---|
| `app` 依赖所有 `feature`、`core` | `feature:users` 依赖 `feature:settings` |
| `feature` 依赖 `core:*` | `core:data` 依赖任何一个 `feature` |
| `core:data` 依赖 `core:model` | 循环依赖 |
| 纯 Kotlin 的 `core:common` 零 Android 依赖 | 把 Activity 放进 `core:model` |

Feature 之间要跳转：用 **导航接口 / 回调 / 路由登记在 app**，而不是直接依赖对方模块。

口诀：**依赖朝向内核；UI 特征彼此陌生；壳负责组装。**

## 四、`settings.gradle.kts` 与模块脚本

```kotlin
// settings.gradle.kts
rootProject.name = "MyApp"
include(
    ":app",
    ":core:common",
    ":core:model",
    ":core:data",
    ":core:ui",
    ":feature:users",
    ":feature:settings"
)
```

```kotlin
// core/model/build.gradle.kts —— 纯 JVM/Android library 均可
plugins {
    id("com.android.library")          // 若需 Android 资源；纯 Kotlin 可用 java-library / kotlin.jvm
    // AGP 9 内置 Kotlin；若用 Compose 再加 compose 插件
}
android {
    namespace = "com.example.core.model"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
}
dependencies {
    // 尽量少；data class 可零依赖
}
```

```kotlin
// feature/users/build.gradle.kts
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
}
dependencies {
    implementation(project(":core:model"))
    implementation(project(":core:ui"))
    implementation(project(":core:data"))   // 或只依赖 data 的接口模块
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.hilt:hilt-lifecycle-viewmodel-compose:1.4.0")
}
```

```kotlin
// app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
}
dependencies {
    implementation(project(":feature:users"))
    implementation(project(":feature:settings"))
    implementation(project(":core:data"))
    // Hilt、Navigation 组装……
}
```

AGP 版本与现有课一致示例：`com.android.application` / `library` **9.4.1**（以你工程为准）。Library 模块用 `com.android.library`，不能写 `applicationId`，用 `namespace`。

## 五、接口放哪？实现放哪？

进阶但很实用的一刀：

- `core:data-api`（或放在 `core:model`）：`interface UserRepository`
- `core:data`：`class UserRepositoryImpl` + Room/Retrofit
- `feature:users`：只依赖 **api**，方便测试替换 Fake（第 21 课）

小项目可以 api/impl 同模块，先保证**特征不互依、core 不依赖 feature**。

## 六、资源与导航组装

- 各 feature 可有自己的 `res` / Compose 屏幕。
- **导航图在 `app`**：`NavHost` 注册 `UsersRoute`、`SettingsRoute`，避免 feature 互相 `navigate`。
- Application / `@HiltAndroidApp` 只在 `app`。
- 若用 Navigation 深链（第 30 课），intent filter 也在 `app` 的 Manifest。

## 七、版本目录（可选加速）

```toml
# gradle/libs.versions.toml
[versions]
agp = "9.4.1"
composeBom = "2026.09.00"
paging = "3.5.3"

[libraries]
paging-runtime = { module = "androidx.paging:paging-runtime", version.ref = "paging" }
compose-bom = { module = "androidx.compose:compose-bom", version.ref = "composeBom" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
android-library = { id = "com.android.library", version.ref = "agp" }
```

各模块 `implementation(libs.paging.runtime)`，升级一处即可。

## 八、易错点

1. **为拆而拆**：三个文件也拆五模块，导航成本和收益倒挂。
2. **feature 互依**：很快变回"单体"，只是编译更痛。
3. **`core:ui` 依赖 `core:data`**：UI 公共组件被数据层拖下水；主题组件应只靠 `model` / 无依赖。
4. **多个模块重复 `preferencesDataStore("同名")`**：和第 25 课一样会崩——DataStore 实例放 data 模块单例。
5. **library 里写 `applicationId`**：应写 `namespace`。
6. **忽略 `api` vs `implementation`**：若 A `implementation` B，C 依赖 A 时看不到 B 的类型。需要透出类型时用 `api(project(":core:model"))`。
7. **Hilt 模块分散后忘了 `@InstallIn`**：注入失败；`SingletonComponent` 的 Module 放在 data / app。

## 九、对照速查表

| 需求 | 写法 |
|---|---|
| 注册模块 | `settings.gradle.kts` 里 `include(":feature:users")` |
| 依赖模块 | `implementation(project(":core:data"))` |
| 应用壳 | `com.android.application` |
| 特征/核心 | `com.android.library` |
| 依赖方向 | app → feature → core；禁止反向与 feature 互依 |
| 透出类型 | `api(...)`；仅内部用 `implementation` |
| 版本统一 | `libs.versions.toml` |

## 十、本课练习

1. 从现有单模块工程拆出 `:core:model`（只放 `User`）和 `:feature:users`（列表屏），`app` 只负责 `NavHost`。
2. 故意让 `feature:users` 依赖 `feature:settings`，画依赖图并改成通过 `app` 导航解耦。
3. 给 `UserRepository` 接口放到 core，Fake 放 test，确认 feature 单测不需 Room。

---

**下一课预告（第 28 课）：Fragment 与 XML View 体系** —— 维护旧项目时仍会碰到：ViewBinding、Fragment 生命周期、`activityViewModels`、Fragment Result。
