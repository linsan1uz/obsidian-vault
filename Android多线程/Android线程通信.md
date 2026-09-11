---
lark_doc_url: https://longcheer.feishu.cn/docx/FRDedn6W0osbGnxLTJScoeEknOe
---

## 一、主线程与渲染线程的关系
### 1.1 职责划分
| 线程 | 角色 | 核心职责 |
|------|------|----------|
| **主线程（Main Thread）** | "大脑" | 处理生命周期、用户交互事件、业务逻辑 |
| **渲染线程（Render Thread）** | "画笔" | 将View数据转换为GPU指令，执行绘制与合成 |
### 1.2 协作关系
- **生产者-消费者模式**：主线程准备绘制数据（View树），渲染线程负责执行绘制。
- **Vsync信号调度**：系统每16.6ms（60Hz屏幕）发出一次垂直同步信号，触发主线程准备数据，渲染线程执行绘制。
- **如果主线程在16.6ms内未完成数据准备 → 掉帧（UI卡顿）**。
### 1.3 功耗影响
| 问题 | 表现 | 优化方向 |
|------|------|----------|
| 主线程负载过重 | CPU长时间高负载 | 异步处理耗时任务 |
| 渲染线程负载过重 | GPU长时间高频运行 | 减少过度绘制、优化Shader |
## 二、耗时操作的处理：子线程与线程池
### 2.1 为什么需要子线程？
- 主线程执行耗时操作（网络请求、数据库读写、复杂计算）会阻塞UI，导致**ANR（应用无响应）**。
- 所有耗时操作必须放到子线程执行。
### 2.2 方式一：直接创建新线程
```java
new Thread(new Runnable() {
    @Override
    public void run() {
        // 执行耗时操作
        String result = doHeavyWork();
        // 通过Handler或runOnUiThread切回主线程更新UI
    }
}).start();

```
### 2.3 方式二：使用线程池（推荐）

**优势**：

- 复用线程，避免频繁创建/销毁开销
    
- 控制最大并发数，防止资源耗尽
    
- 降低功耗（减少线程创建销毁的CPU开销）
    

**常用线程池创建方式**：

```java
// 1. 固定大小线程池（根据CPU核心数）
int coreCount = Runtime.getRuntime().availableProcessors();
ExecutorService threadPool = Executors.newFixedThreadPool(coreCount);
// 2. 缓存线程池（按需创建，复用空闲线程）
ExecutorService cachedPool = Executors.newCachedThreadPool();
// 3. 单线程线程池（保证任务顺序执行）
ExecutorService singlePool = Executors.newSingleThreadExecutor();
```

**提交任务**：

```java
threadPool.execute(new Runnable() {
    @Override
    public void run() {
        // 耗时操作
        String result = doHeavyWork();
        // 切回主线程更新UI
    }
});
// 关闭线程池（一般在Application或Activity onDestroy中）
threadPool.shutdown();

```
## 三、Handler机制详解

### 3.1 核心组件

|组件|作用|
|---|---|
|**Message**|承载数据/任务的消息对象|
|**MessageQueue**|消息队列，FIFO存储待处理消息|
|**Looper**|消息循环器，不断从MessageQueue取出消息分发|
|**Handler**|发送消息 + 处理消息|

### 3.2 Handler、Looper、MessageQueue 协作流程

1. Handler发送消息 → 消息进入MessageQueue
    
2. Looper循环不断取出消息
    
3. 消息分发回Handler的`handleMessage()`方法执行
    

> **每个线程最多只有一个Looper**。主线程的Looper由系统自动创建，子线程需手动调用`Looper.prepare()`。

### 3.3 Handler的标准写法（避免内存泄漏）

```java
public class MainActivity extends AppCompatActivity {
    // 静态内部类 + 弱引用，避免内存泄漏
    private static class SafeHandler extends Handler {
        private final WeakReference<MainActivity> mActivityRef;
        SafeHandler(MainActivity activity) {
            super(Looper.getMainLooper());
            mActivityRef = new WeakReference<>(activity);
        }
        @Override
        public void handleMessage(Message msg) {
            MainActivity activity = mActivityRef.get();
            if (activity != null) {
                // Activity存活时才更新UI
                activity.updateUI((String) msg.obj);
            }
        }
    }
    private final SafeHandler mHandler = new SafeHandler(this);
    private void updateUI(String data) {
        textView.setText(data);
    }
    @Override
    protected void onDestroy() {
        super.onDestroy();
        // 移除所有待处理消息，防止悬挂消息导致泄漏
        mHandler.removeCallbacksAndMessages(null);
    }
}
```

## 四、线程间通信方式

### 4.1 场景一：子线程 → 主线程（最常用）

**方式一：runOnUiThread**

```java
new Thread(new Runnable() {
    @Override
    public void run() {
        String result = fetchData();
        // 切回主线程更新UI
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                textView.setText(result);
            }
        });
    }
}).start();
```

**方式二：主线程Handler**

```java

// 主线程中创建Handler
private Handler mainHandler = new Handler(Looper.getMainLooper()) {
    @Override
    public void handleMessage(Message msg) {
        textView.setText((String) msg.obj);
    }
};
// 子线程中发送消息
new Thread(new Runnable() {
    @Override
    public void run() {
        String result = fetchData();
        Message msg = Message.obtain();
        msg.obj = result;
        mainHandler.sendMessage(msg);
    }
}).start();
```

**方式三：使用View.post()**

```java

new Thread(new Runnable() {
    @Override
    public void run() {
        String result = fetchData();
        textView.post(new Runnable() {
            @Override
            public void run() {
                textView.setText(result);
            }
        });
    }
}).start();
```

### 4.2 场景二：主线程 → 子线程（较少用，适用于常驻后台任务队列）

**使用HandlerThread（推荐）**：

```java

public class MainActivity extends AppCompatActivity {
    private HandlerThread mHandlerThread;
    private Handler mChildHandler;
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 1. 创建并启动HandlerThread
        mHandlerThread = new HandlerThread("BackgroundThread");
        mHandlerThread.start();
        
        // 2. 获取子线程的Handler
        mChildHandler = new Handler(mHandlerThread.getLooper());
        
        // 3. 主线程向子线程派发任务
        findViewById(R.id.btn_send).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mChildHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        // 在子线程执行的任务
                        doBackgroundWork();
                    }
                });
            }
        });
    }
    @Override
    protected void onDestroy() {
        super.onDestroy();
        // 停止子线程，释放资源
        if (mHandlerThread != null) {
            mHandlerThread.quitSafely();
        }
    }
}
```

**手动创建子线程Handler**：

```java

private Handler childHandler;
private void startChildThread() {
    new Thread(new Runnable() {
        @Override
        public void run() {
            Looper.prepare();
            
            childHandler = new Handler(Looper.myLooper()) {
                @Override
                public void handleMessage(Message msg) {
                    // 处理主线程发来的消息
                }
            };
            
            Looper.loop(); // 阻塞循环，保持线程存活
        }
    }).start();
}
```

### 4.3 场景三：主线程 ↔ 子线程 双向通信

```java

public class MainActivity extends AppCompatActivity {
    private Handler mChildHandler;
    private Handler mMainHandler = new Handler(Looper.getMainLooper()) {
        @Override
        public void handleMessage(Message msg) {
            // 收到子线程的结果
            String result = (String) msg.obj;
            textView.setText(result);
            
            // 可以继续向子线程派发新任务
            if (mChildHandler != null) {
                mChildHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        // 子线程继续执行后续任务
                    }
                });
            }
        }
    };
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        startChildThread();
    }
    private void startChildThread() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                Looper.prepare();
                mChildHandler = new Handler(Looper.myLooper()) {
                    @Override
                    public void handleMessage(Message msg) {
                        // 处理主线程发来的任务
                        String task = (String) msg.obj;
                        String result = processTask(task);
                        
                        // 将结果发回主线程
                        Message resultMsg = Message.obtain();
                        resultMsg.obj = result;
                        mMainHandler.sendMessage(resultMsg);
                    }
                };
                Looper.loop();
            }
        }).start();
    }
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (mChildHandler != null) {
            mChildHandler.getLooper().quit();
        }
        mMainHandler.removeCallbacksAndMessages(null);
    }
}
```

## 五、线程池与通信

### 5.1 线程池怎么用？

```java

// 创建线程池
ExecutorService executor = Executors.newFixedThreadPool(4);
// 提交任务（不关心结果）
executor.execute(new Runnable() {
    @Override
    public void run() {
        // 耗时操作
    }
});
// 提交任务（需要获取返回结果）
Future<String> future = executor.submit(new Callable<String>() {
    @Override
    public String call() throws Exception {
        return fetchData();
    }
});
// 获取结果（会阻塞当前线程，谨慎使用）
String result = future.get();


```
### 5.2 线程池里的线程如何与主线程通信？

**与普通子线程完全一样**，通过Handler、runOnUiThread、View.post()等方式。



```java
ExecutorService executor = Executors.newSingleThreadExecutor();
final Handler mainHandler = new Handler(Looper.getMainLooper());
executor.execute(new Runnable() {
    @Override
    public void run() {
        String result = fetchData();
        
        // 方式一：Handler
        Message msg = Message.obtain();
        msg.obj = result;
        mainHandler.sendMessage(msg);
        
        // 方式二：runOnUiThread（需要Activity上下文）
        // runOnUiThread(() -> textView.setText(result));
    }
});
```
### 5.3 线程池中的线程之间需要互相通信吗？

**极少需要，且应尽量避免。**

- **线程池设计原则**：线程间相互独立、无状态，各自从任务队列取任务执行。
    
- **如果需要协作**：通常通过主线程中转，或使用`Future` / `CountDownLatch`等同步工具。
    

**反例（应避免）**：

```java

// ❌ 错误：线程间直接依赖，易死锁
executor.execute(() -> {
    // 需要等待另一个线程完成，但不知道什么时候完成
});

```
**正确做法**：

```java

// ✅ 各自独立执行，结果汇总到主线程
List<Future<String>> futures = new ArrayList<>();
for (int i = 0; i < 3; i++) {
    futures.add(executor.submit(() -> fetchDataFromServer(i)));
}
// 主线程等待所有结果完成（在子线程中执行汇总）
executor.execute(() -> {
    for (Future<String> f : futures) {
        try {
            String result = f.get(); // 阻塞获取，但在子线程中执行
            // 汇总结果...
        } catch (Exception e) { }
    }
});
```

## 六、runOnUiThread 详解

### 6.1 本质

`runOnUiThread` 是 `Activity` 提供的方法，底层通过主线程的 `Handler` 实现。

```java

// Activity中的源码逻辑
public final void runOnUiThread(Runnable action) {
    if (Thread.currentThread() == Looper.getMainLooper().getThread()) {
        action.run();      // 已在主线程，直接执行
    } else {
        mHandler.post(action); // 在子线程，发到主线程队列
    }
}

```
### 6.2 使用示例



```java
// 在子线程中更新UI
new Thread(new Runnable() {
    @Override
    public void run() {
        String result = fetchData();
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                textView.setText(result);
            }
        });
    }
}).start();
```

### 6.3 runOnUiThread vs Handler

|对比维度|runOnUiThread|Handler|
|---|---|---|
|使用位置|必须在Activity/Fragment中|任何地方|
|代码简洁度|高，无需声明|需先声明Handler对象|
|灵活性|仅支持切到主线程，只能post Runnable|支持延迟、取消、发送Message|
|内存泄漏风险|较低|较高（需用静态内部类+弱引用）|
|适用场景|简单的UI更新|复杂消息队列、延迟任务|

## 七、总结：通信方式选择指南

|通信方向|推荐方式|说明|
|---|---|---|
|主线程 → 子线程（一次性任务）|`new Thread().start()` 或 `线程池.execute()`|用完即回收|
|主线程 → 子线程（频繁派发）|`HandlerThread`|常驻后台，队列处理|
|子线程 → 主线程（更新UI）|`runOnUiThread` 或 `View.post()`|简单场景首选|
|子线程 → 主线程（复杂通信）|`Handler` + `Message`|支持延迟、携带数据|
|线程池内线程之间|尽量避免，通过主线程中转|防止死锁和逻辑混乱|

> **现代Android开发建议**：如果项目使用Kotlin，优先使用**协程** + `withContext(Dispatchers.Main)`，它封装了所有线程切换逻辑，更安全、更简洁。Handler机制作为底层实现仍然存在，但业务层代码可以逐步用协程替代。