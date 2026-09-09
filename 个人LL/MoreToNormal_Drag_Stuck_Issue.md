# More→Normal 拖拽时 Item 卡住不动的问题分析与解决

## 问题现象

在相机模式编辑界面中，用户将 item 从下方 More 网格拖拽到上方 Normal 模式栏时，item 在跨越两个 RecyclerView 边界后**卡住不动**——手指继续移动，但 item 不跟随移动。

---

## 背景知识：Android 触摸事件分发机制

理解此 bug 前，需要理清 Android 触摸事件的分发链：

```
用户手指触摸屏幕
  → Activity.dispatchTouchEvent
    → ViewGroup.dispatchTouchEvent              (MoreRecyclerView 的父布局)
      → MoreRecyclerView.dispatchTouchEvent
        → MoreRecyclerView.onInterceptTouchEvent
        → MoreRecyclerView.onTouchEvent
          → onTouchListener.onTouch              ← CameraModeSwitchManager 中设置的监听器
```

**关键规则**：`View.dispatchTouchEvent` 会先调用 `onTouchListener.onTouch`：
- `onTouch` 返回 `true` → 事件被消费，**不再**走 `onTouchEvent`
- `onTouch` 返回 `false` → 事件**继续**走 `onTouchEvent`

`ItemTouchHelper` 通过 `RecyclerView.addOnItemTouchListener` 注册，它在 `RecyclerView.onInterceptTouchEvent` 和 `onTouchEvent` 中接收事件。**如果事件根本没走到 `onTouchEvent`，ItemTouchHelper 就收不到。**

---

## More→Normal 拖拽的完整时序

```
时间轴:
────────────────────────────────────────────────────────────────────

t=0ms   用户在 More 网格中拖拽 item A，手指进入 Normal 区域
        MoreRecyclerView.onTouch 触发
          → isDrag = true (touchY 越界)
          → mMoreFilterDraw = true (More item 需要淡出)
          → mMoreItemMove && isDrag 条件满足
          → 进入跨列表转移逻辑

t=0ms   数据操作:
          mNormalModeList.add(postion, captureMode)
          mNormalAdapter.notifyItemInserted(postion + 1)
          → 新 item 出现在 Normal 栏

t=0ms   设置标记:
          mNormalDetect = true

t=0ms   ★ 合成 ACTION_DOWN 分发给 Normal RecyclerView:
          event.setAction(MotionEvent.ACTION_DOWN)
          mRecyclerView.dispatchTouchEvent(event)    ← 关键！走哪条路？

t=40ms  延迟 handler 执行:
          mIsDetect = true
          event.setAction(MotionEvent.ACTION_DOWN)
          mRecyclerView.dispatchTouchEvent(event)    ← 再次分发

t=60ms  内层延迟 handler 执行:
          mNormalTouchHelper.startDrag(viewHolder)   ← 启动拖拽
          mRecyclerView.dispatchTouchEvent(event)    ← 分发事件

t=60ms+ 用户继续移动手指
          → MoreRecyclerView.onTouch 持续触发
          → ACTION_MOVE 转发给 Normal RecyclerView
          → ItemTouchHelper 应该处理 ACTION_MOVE，更新拖拽位置
          → ★ 如果 ItemTouchHelper 没收到事件 → item 卡住！
```

---

## 问题根因

### 第一层：`ModeRecyclerView.dispatchTouchEvent` 拦截了合成事件

当 `mRecyclerView.dispatchTouchEvent(event)` 被调用时，走的是 `ModeRecyclerView.dispatchTouchEvent`：

```java
@Override
public boolean dispatchTouchEvent(MotionEvent ev) {
    // ① 前置检查：isEnable / mScrollDisable / mTriggerSwitchTime / mInVolumeState
    //    假设都通过了

    // ② 编辑模式分支
    if (mListener != null) {
        if (!mEditCallback.isInEditModeState()) {
            // 非编辑模式 → 正常处理
            return super.dispatchTouchEvent(ev);
        }

        // ★★★ 编辑模式走这里 ★★★
        if (!hasConsumed) {
            hasConsumed = mListener.onViewTouch(NORMAL_MODE_TOUCH, ev.getAction(), ...);
        }

        // 判断是否进入"放行"分支
        if (hasConsumed || mEditCallback.isModeDetect()) {
            // ★ 放行分支：事件能到达 RecyclerView → ItemTouchHelper 能收到
            if (mSecTouch) return false;
            return super.dispatchTouchEvent(ev);  // ✓ 事件到达
        } else {
            // ★★★ 拦截分支：检查多个条件，都不满足则事件被吞掉 ★★★
            if (hasTriggerEvent) {
                return super.dispatchTouchEvent(ev);
            } else if (isQuicklyDown() && !isMoreModeSelected()) {
                return super.dispatchTouchEvent(ev);
            }
            if (isModeViewFocusedParam()) {
                return super.dispatchTouchEvent(ev);
            }
            return false;  // ★ 所有条件都不满足 → 事件被拦截！
        }
    }
}
```

**为什么合成的 ACTION_DOWN 会走拦截分支？**

逐一检查条件：

| 条件                             | 值             | 原因                                                           |
| ------------------------------ | ------------- | ------------------------------------------------------------ |
| `hasConsumed`                  | **false**（首次） | 首次调用 `mListener.onViewTouch`，但返回值为 false                     |
| `mEditCallback.isModeDetect()` | **false**     | 对应 `mModeDetect`，只在 Normal→More 时为 true，More→Normal 时为 false |
| `hasTriggerEvent`              | **false**     | 只在非编辑模式的 ACTION_DOWN 时设置，合成事件没走那条路                           |
| `isQuicklyDown()`              | **false**     | 与快速触摸相关，拖拽场景不满足                                              |
| `isModeViewFocusedParam()`     | **false**     | 与焦点相关，合成事件不触发                                                |

**所有条件都不满足 → 走到 `return false` → 事件被拦截，无法到达 RecyclerView 内部的 `onTouchEvent`，ItemTouchHelper 收不到。**

### 第二层：ItemTouchHelper 内部状态未建立

ItemTouchHelper 的 `onItemTouch` 方法处理触摸事件：

```java
// ItemTouchHelper.onItemTouch 内部大致逻辑:
case MotionEvent.ACTION_DOWN:
    // 找到触摸位置的 child view
    View child = findChildViewUnder(x, y);
    if (child != null) {
        ViewHolder vh = getChildViewHolder(child);
        // 计算触摸偏移，准备拖拽
        select(vh, ACTION_STATE_DRAG);
        // → mSelectedViewHolder = vh
        // → mActivePointerId = ev.getPointerId(0)  ← 从 MotionEvent 获取
    }

case MotionEvent.ACTION_MOVE:
    if (mActivePointerId == ACTIVE_POINTER_ID_NONE) {
        return;  // ★ 没有活跃的拖拽 → 忽略 ACTION_MOVE
    }
    // 计算移动距离
    // 调用 moveIfNecessary → onChildDraw → 更新 item 位置
```

因为 ACTION_DOWN 被拦截，ItemTouchHelper 没有调用 `select` 方法，`mActivePointerId` 保持为无效值 `ACTIVE_POINTER_ID_NONE`。

### 第三层：`startDrag` 救不了

在 t=60ms 时调用了 `mNormalTouchHelper.startDrag(viewHolder)`：

```java
// ItemTouchHelper.startDrag 内部大致逻辑:
public void startDrag(ViewHolder viewHolder) {
    // 1. 检查 getMovementFlags 是否允许拖拽
    int flags = mCallback.getMovementFlags(mRecyclerView, viewHolder);
    if (flags == 0) return;  // 不允许 → 直接返回

    // 2. 选中 item，设置拖拽状态
    select(viewHolder, ACTION_STATE_DRAG);
    // → mSelectedViewHolder = viewHolder
    // → mActivePointerId = ... (尝试从 MotionEvent 获取)
}
```

`select` 方法需要从当前的 `MotionEvent` 中获取 `mActivePointerId`。但 `startDrag` 是在延迟 handler 中手动调用的，此时没有有效的触摸事件与之关联，`mActivePointerId` 被设为无效值。

### 第四层：后续 ACTION_MOVE 也被忽略

后续的 ACTION_MOVE 被转发到 Normal RecyclerView 时：

```java
// ModeRecyclerView.dispatchTouchEvent:
if (!hasConsumed) {
    hasConsumed = mListener.onViewTouch(...);  // 首次设为 true
}
if (hasConsumed || isModeDetect()) {  // hasConsumed=true → 进入放行分支
    // → super.dispatchTouchEvent(ev)  ✓ 事件到达 RecyclerView
}
```

第一次 ACTION_MOVE 能到达 RecyclerView。但 ItemTouchHelper 内部：

```java
case MotionEvent.ACTION_MOVE:
    if (mActivePointerId == ACTIVE_POINTER_ID_NONE) {
        return;  // ★ 仍然无效 → 忽略
    }
```

`mActivePointerId` 仍然无效 → 所有 ACTION_MOVE 被忽略 → **item 卡住不动**。

---

## 完整因果链

```
用户在 More 网格拖拽 item 进入 Normal 区域
    │
    ▼
CameraModeSwitchManager 合成 ACTION_DOWN 转发给 Normal RecyclerView
    │
    ▼
ModeRecyclerView.dispatchTouchEvent 拦截事件 (return false)
    │  原因: hasConsumed=false, isModeDetect()=false,
    │        hasTriggerEvent=false → 所有条件不满足
    ▼
ItemTouchHelper 没收到 ACTION_DOWN
    → 没有调用 select() → mActivePointerId = INVALID
    │
    ▼
startDrag(viewHolder) 被调用
    → 内部调用 select()，但没有有效的 MotionEvent
    → mActivePointerId 仍然无效
    │
    ▼
后续 ACTION_MOVE 转发到 Normal RecyclerView
    → ModeRecyclerView.dispatchTouchEvent 放行 (hasConsumed=true)
    → ItemTouchHelper.onItemTouch 收到 ACTION_MOVE
    → 检查 mActivePointerId == INVALID → 忽略
    │
    ▼
item 卡住不动
```

---

## 解决方案

### 核心思路

让转发的触摸事件绕过 `ModeRecyclerView.dispatchTouchEvent` 的拦截逻辑，直接调用 `RecyclerView.dispatchTouchEvent`（父类方法），这样事件能到达 ItemTouchHelper。

### 改动一：ModeRecyclerView — 添加转发标记

```java
private boolean mForwardingTouch = false;

/**
 * 设置是否为转发触摸事件（More→Normal 拖拽时使用）
 * 转发事件绕过 ModeRecyclerView 的拦截逻辑，直接交给 RecyclerView 处理
 */
public void setForwardingTouch(boolean forwarding) {
    mForwardingTouch = forwarding;
}

@Override
public boolean dispatchTouchEvent(MotionEvent ev) {
    // ★ 转发事件：跳过所有拦截逻辑，直接交给 RecyclerView
    if (mForwardingTouch) {
        return super.dispatchTouchEvent(ev);
    }
    // ... 原有逻辑不变
}
```

### 改动二：CameraModeSwitchManager — 4 处转发调用包裹标记

所有从 More 转发到 Normal 的 `dispatchTouchEvent` 调用都需要包裹：

```java
mRecyclerView.setForwardingTouch(true);
mRecyclerView.dispatchTouchEvent(event);
mRecyclerView.setForwardingTouch(false);
```

涉及的 4 处位置：

| # | 位置 | 场景 |
|---|------|------|
| 1 | More onTouch → `mIsDetect && ACTION_UP` | 拖拽结束时转发 ACTION_UP |
| 2 | More onTouch → `else if (mIsDetect)` | 拖拽过程中转发 ACTION_MOVE |
| 3 | 延迟 handler (40ms) | 合成 ACTION_DOWN 分发 |
| 4 | 内层延迟 handler (20ms) | startDrag 后的事件分发 |

### 修复后的事件流

```
合成 ACTION_DOWN → setForwardingTouch(true)
  → ModeRecyclerView.dispatchTouchEvent
    → mForwardingTouch=true → super.dispatchTouchEvent(ev)
    → RecyclerView.dispatchTouchEvent
    → ItemTouchHelper.onItemTouch(ACTION_DOWN)
    → select() ✓ 建立拖拽状态，mActivePointerId = 有效值

后续 ACTION_MOVE → setForwardingTouch(true)
  → super.dispatchTouchEvent(ev)
  → ItemTouchHelper.onItemTouch(ACTION_MOVE)
  → mActivePointerId 有效 → moveIfNecessary
  → onChildDraw(dX, dY) → item 位置更新 ✓

ACTION_UP → setForwardingTouch(true)
  → super.dispatchTouchEvent(ev)
  → ItemTouchHelper.onItemTouch(ACTION_UP)
  → 结束拖拽 → clearView ✓
```

---

## 经验总结

1. **自定义 `dispatchTouchEvent` 时要小心**：`ModeRecyclerView` 重写了 `dispatchTouchEvent` 并添加了多层拦截逻辑，这会阻止外部程序化分发的触摸事件到达内部处理器（如 ItemTouchHelper）。

2. **`return false` 的含义比想象的更严重**：在 `dispatchTouchEvent` 中 `return false` 不仅表示"我不处理"，还会导致事件无法传递给子 View 的内部处理器。

3. **手动 `dispatchTouchEvent` 不等于用户触摸**：通过代码调用 `view.dispatchTouchEvent(event)` 分发的事件，会走和用户触摸相同的分发链，但缺少用户触摸时自然触发的状态（如 `hasTriggerEvent`、`hasConsumed` 的初始化）。

4. **`ItemTouchHelper.startDrag` 依赖有效的触摸事件**：`startDrag` 只是设置拖拽状态，后续的拖拽移动仍然依赖 `ACTION_MOVE` 事件到达 ItemTouchHelper。如果 ACTION_MOVE 被拦截，item 不会移动。

5. **跨 View 的触摸事件转发需要特殊处理**：当需要将触摸事件从一个 View 转发到另一个 View 时，目标 View 的 `dispatchTouchEvent` 可能有自定义拦截逻辑。需要提供绕过机制（如 `mForwardingTouch` 标记）。

---

## 涉及文件

| 文件                             | 改动内容                                                                                |
| ------------------------------ | ----------------------------------------------------------------------------------- |
| `ModeRecyclerView.java`        | 添加 `mForwardingTouch` 标记和 `setForwardingTouch()` 方法；`dispatchTouchEvent` 开头判断是否绕过拦截 |
| `CameraModeSwitchManager.java` | 4 处 `mRecyclerView.dispatchTouchEvent(event)` 调用包裹 `setForwardingTouch(true/false)` |
