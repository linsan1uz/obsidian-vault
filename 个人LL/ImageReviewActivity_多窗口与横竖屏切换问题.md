 ImageReviewActivity 多窗口与横竖屏切换问题总结

## 问题背景

在 `ImageReviewActivity` 中遇到三个相关问题：
1. `onMultiWindowModeChanged` 回调不触发
2. 横竖屏切换后 Bitmap 为空
3. 竖屏切横屏没有自动加载横屏布局

---

## 问题一：onMultiWindowModeChanged 回调不触发

### 原因分析

**缺少 `screenSize`（已解决但非根因）：**

`ImageReviewActivity` 的 `configChanges` 缺少 `screenSize`，进入多窗口时系统触发 `screenSize` 配置变更，Activity 被销毁重建，`onMultiWindowModeChanged` 不会在旧实例上调用。

```xml
<!-- 修改前 -->
android:configChanges="orientation|uiMode|screenLayout|smallestScreenSize|navigation|keyboardHidden|keyboard"

<!-- 修改后（添加 screenSize） -->
android:configChanges="orientation|screenSize|uiMode|screenLayout|smallestScreenSize|navigation|keyboardHidden|keyboard"
```

**缺少 `resizeableActivity="true"`（根因）：**

对比主 Activity `CameraActivity` 的声明：

| 属性 | CameraActivity | ImageReviewActivity |
|---|---|---|
| `resizeableActivity` | `"true"` | **缺失** |

没有 `resizeableActivity="true"`，系统不会将该 Activity 视为支持多窗口，因此不会触发 `onMultiWindowModeChanged()` 回调。

### 修复

在 AndroidManifest.xml 中为 `ImageReviewActivity` 添加：

```xml
android:resizeableActivity="true"
```

---

## 问题二：横竖屏切换后 Bitmap 为空

### 原因分析

`onConfigurationChanged` 调用 `applyLayout()`，而 `applyLayout()` 内部调用 `setContentView()` 重建了整个 View 树。但 `onConfigurationChanged` 没有重新绑定 Bitmap：

```java
// onConfigurationChanged 只调了 applyLayout，没有重新设置图片
public void onConfigurationChanged(...) {
    applyLayout();  // ← setContentView 重建了所有 View，mReview 变成旧引用
    // ← 缺少重新加载 Bitmap 的代码
}
```

而 `onCreate` 中有完整的流程：

```java
applyLayout();
initViews();                              // ← 重新 findViewById
Bitmap picture = Utils.decodeReviewImage(...); // ← 解码 Bitmap
setReviewImage(isVisible, mUri, picture, reload); // ← 设置到 ImageView
```

`mBitmap` 是成员变量，横竖屏切换时不会丢失，只是需要重新绑定到新的 `ImageView` 上。

### 修复

在 `onConfigurationChanged` 和 `onMultiWindowModeChanged` 中添加重新绑定逻辑：

```java
@Override
public void onConfigurationChanged(@NonNull Configuration newConfig) {
    super.onConfigurationChanged(newConfig);
    // ...
    applyLayout();
    initViews();
    if (mBitmap != null && mReview != null) {
        mReview.setImageBitmap(mBitmap);
    }
}
```

---

## 问题三：竖屏切横屏没有自动加载横屏布局

### 原因分析

**原因一：`configChanges` 包含 `orientation`**

当 Activity 声明了 `android:configChanges="orientation|..."` 时：
- 系统**不会销毁重建** Activity
- **不会自动切换** `layout/` vs `layout-land/` 布局资源
- 只有 Activity 被销毁重建时，系统才会根据配置自动选择对应资源目录

**原因二：`layout-land/` 中没有 `layout_review.xml`**

```
layout-land/
├── activity_crop.xml
├── activity_widget_setting.xml
├── camera_widget_preview.xml
├── dialog_edit.xml
├── dialog_edit_widget.xml
├── layout_review_retry_ok_container.xml   ← 只有子布局有横屏版本
└── scanner3_corner.xml
```

主布局 `layout_review.xml` 没有横屏版本。

### 修复

**从 `configChanges` 中移除 `orientation`：**

```xml
<!-- 修改前 -->
android:configChanges="orientation|screenSize|uiMode|screenLayout|smallestScreenSize|navigation|keyboardHidden|keyboard"

<!-- 修改后（移除 orientation） -->
android:configChanges="screenSize|uiMode|screenLayout|smallestScreenSize|navigation|keyboardHidden|keyboard"
```

移除后，横竖屏切换时系统销毁重建 Activity，自动根据资源限定符选择布局：
- **竖屏** → `layout/layout_review.xml`（内含 `layout/layout_review_retry_ok_container.xml`）
- **横屏** → `layout/layout_review.xml`（内含 `layout-land/layout_review_retry_ok_container.xml`）

不需要手动创建 `layout-land/layout_review.xml`，因为 `include` 标签会自动使用横屏版本的子布局。

---

## configChanges 中 orientation 的作用

| | 有 `orientation` | 没有 `orientation` |
|---|---|---|
| 旋转时 | Activity **不销毁**，调 `onConfigurationChanged()` | Activity **销毁重建**，走 `onCreate()` |
| 布局切换 | 手动调 `setContentView()` | 系统自动选择 `layout/` 或 `layout-land/` |
| 内存中变量 | 保留（`mBitmap`、`mUri` 等不变） | 丢失，需要重新赋值 |

**删掉 `orientation` 的影响：**
- Intent 数据不丢 — `mUri`、`isVisible`、`mLastOrientation` 等都从 `getIntent()` 读取
- Bitmap 会重新解码 — `onCreate` 中有完整的解码流程
- 动画会重播 — 每次重建会重新播放滑入动画

---

## 最终 AndroidManifest 配置

```xml
<activity
    android:name="com.ts.camera.view.activity.ImageReviewActivity"
    android:configChanges="screenSize|uiMode|screenLayout|smallestScreenSize|navigation|keyboardHidden|keyboard"
    android:exported="false"
    android:launchMode="singleTask"
    android:resizeableActivity="true"
    android:theme="@style/ImageReviewFullscreenTheme" />
```

---

## 最终流程总结

| 场景 | 触发方式 | 结果 |
|---|---|---|
| 正常横竖屏切换 | Activity 重建 → `onCreate` → `applyLayout()` | 系统自动选择 `layout/` 或 `layout-land/` |
| 进入小窗 | `onMultiWindowModeChanged` → `applyLayout()` | 手动加载 `layout_preview_port` |
| 小窗中旋转 | Activity 重建 → `onCreate` → 检测到 `isMultiWindow=true` → `applyLayout()` | 手动加载 `layout_preview_port` |

---

## 涉及修改的文件

1. **`main/src/main/AndroidManifest.xml`** — 移除 `orientation`，添加 `screenSize`、`resizeableActivity="true"`
2. **`main/src/main/java/com/ts/camera/view/activity/ImageReviewActivity.java`** — `onConfigurationChanged` 和 `onMultiWindowModeChanged` 中添加 `initViews()` 和 Bitmap 重新绑定
