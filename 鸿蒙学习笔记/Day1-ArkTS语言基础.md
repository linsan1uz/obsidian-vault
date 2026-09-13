---
tags:
  - 鸿蒙
  - ArkTS
  - 学习笔记
  - 复习
course: 鸿蒙应用开发15天计划
day: 1
date: 2026-09-12
status: 已完成（异步部分欠账）
---

# Day 1 · ArkTS 语言基础（总笔记）

> [!abstract] Day 1 知识地图
> ```
> ArkTS 语言基础
> ├── ① 变量与基础类型          ── 一切的地基
> ├── ② 联合类型与类型收窄 ★核心 ── 编译器保护你的方式
> ├── ③ 函数与箭头函数          ── ArkUI 回调的形态
> ├── ④ interface / class / 泛型 ── 鸿蒙 API 的构成方式
> ├── ⑤ ArkTS 硬规则清单        ── 和 JS/TS 的分界线
> ├── ⑥ 装饰器认脸              ── @Entry @Component @State
> └── ⑦ Promise / async ⏳ 欠账 ── Day 2 补
> ```

---

## ① 变量与基础类型

```typescript
let count: number = 0        // let = 可重新赋值
const MAX: number = 100      // const = 只能赋值一次
let ids: number[] = [1, 2, 3]
let x = 5                    // 类型推断：x 从此被钉死为 number
// x = 'hello'               // ❌ 声明后类型不可变
```

> [!tip] 口诀
> **默认 `const`，需要重新赋值才用 `let`**；类型在第一次赋值时确定，之后不可更换。

## ② 联合类型与类型收窄 ★ Day 1 核心

联合类型表示「可能是几种之一」。**编译器拒绝的不是「值不是数字」，而是「你没能证明它此刻是数字」**——所以使用前必须收窄：

| 收窄手段 | 证明什么 | 典型场景 |
|---|---|---|
| `typeof v === 'number'` | 基础类型身份 | number / string / boolean |
| `v instanceof SomeClass` | 是某个类的实例 | 自定义类、捕获的 err |
| `'prop' in v` | 对象有某属性 | 区分结构不同的对象 |

```typescript
function render(id: number | string | null): string {
  if (id === null) return '无ID'          // 收窄为 null
  if (typeof id === 'number') {
    return id.toFixed(2)                  // 收窄为 number，方法才能调
  }
  return 'ID: ' + id                      // 剩下一定是 string
}
```

## ③ 函数与箭头函数

```typescript
function add(a: number, b: number): number { return a + b }   // 标准写法
function greet(name: string, title?: string): string { ... }  // 可选参数
function repeat(text: string, times: number = 2): string {...} // 默认参数
const multiply = (a: number, b: number): number => a * b      // 箭头函数
```

> [!tip] 认脸
> ArkUI 事件回调全是箭头函数形态：`onClick={() => { ... }}`——把函数当参数传。

## ④ interface / class / 泛型

**interface = 能力的契约**（只声明不实现，`implements` 承诺兑现）：

```typescript
interface IExportable {
  toSummary(): string          // 方法签名
  readonly id: string          // 必须提供且不可改
  label?: string               // 可选属性
}
```

**class = 具体的东西**：

```typescript
class Order implements IExportable {
  private amount: number                    // 类外不可访问
  readonly createdAt: Date = new Date()     // ⚠️ 必须在声明处或构造函数初始化！
  status: OrderStatus = OrderStatus.CREATED

  constructor(id: string, amount: number) { /* this.id = id */ }

  pay(): void { this.status = OrderStatus.PAID }        // ⚠️ 必须 this. 开头
  toSummary(): string {
    return `订单${this.id}，金额¥${this.amount.toFixed(2)}`   // ⚠️ 反引号才插值
  }
}
```

**泛型 = 类型的形参**（放进去是什么，取出来就是什么）：

```typescript
class Box<T> {
  private items: T[] = []
  add(item: T): void { this.items.push(item) }
  getAll(): T[] { return this.items }
}
const orders = new Box<Order>()   // orders.add('x') ❌ 编译器拦截

function printAll<T extends IExportable>(box: Box<T>): void { }  // 泛型约束
```

## ⑤ ArkTS 硬规则清单（撞到 `arkts-no-...` 就查这里）

| # | 规则 | 正确替代 |
|---|---|---|
| 1 | 禁止 `any` / `unknown` | 明确的具体类型 |
| 2 | 对象字面量必须标注类型 | `const p: Point = { x: 1, y: 2 }` |
| 3 | 对象建好后不能动态加属性 | 属性写进 interface/class |
| 4 | 动态键值对 | `Record<string, T>` 或 `Map<K,V>` |
| 5 | 类属性必须初始化（声明处或构造函数） | `readonly createdAt: Date = new Date()` |
| 6 | 相等判断用 `===` / `!==` | 不用 `==` / `!=` |
| 7 | 模板字符串必须用反引号 `` ` `` | `"..."` 里的 `${}` 不会插值 |

## ⑥ 装饰器认脸（Day 3 正式拆解）

`@Entry`（页面入口）、`@Component`（组件）、`@State`（状态变量，赋值后 UI 自动刷新）——编译期附加能力的标记，见到 `@Xxx` 不慌即可。

## ⑦ Promise / async ⏳ 欠账（Day 2 补）

- 已知概念：Promise 三态 **pending → fulfilled / rejected**，单向不可逆；`.then/.catch/.finally` 处理
- 待学：`async/await` 使用规则、`Promise.all` 并发、错误处理实践

---

## 📕 错题本（按时间序，复习重点）

> [!warning] 1. `formatPrice` 三连错（Block 1）
> `'￥' + n`：没用 `toFixed(2)`（输出 `¥3.5` 而非 `¥3.50`）＋ 全角 ￥ 应为半角 ¥ ＋ `==` 应为 `===`
> **处方**：拼接前先格式化；符号/标点注意全半角；严格相等。

> [!warning] 2. 死代码意识（Block 1）
> `arr.length == 0 || arr[0] == null` 后半段永远不执行；`describe` 的 `else return 'error'` 不可达。
> **处方**：写条件分支时问一句「这个分支有可能走到吗」。

> [!warning] 3. `createdAt` 赋值语句没写完（Block 2）
> `readonly createdAt: Date =` 等号后空着就换行——语法错误还污染下一行解析。
> **处方**：报错行定位的不一定是真凶，往上下各看一行。

> [!warning] 4. 漏 `this.`（Block 2）
> `pay()` 里写 `status = ...`，应为 `this.status = ...`。
> **处方**：**类方法里碰自己的属性，永远 `this.` 开头**。

> [!warning] 5. 双引号不插值（Block 2）
> `"订单$id,金额${¥amount},状态${createdAt}"`：双引号里 `$` 是字面字符；`${}` 里只能放表达式（¥ 应放外面）；输出属性选错（应为 `status` 不是 `createdAt`）。
> **处方**：**要插值就用反引号** `` ` ``；`${}` 内只写纯表达式。

> [!success] 真实编译案例：alignRules 类型错位
> 给首页加按钮时把 `HorizontalAlign`（水平，`middle` 槽位）和 `VerticalAlign`（垂直，`center` 槽位）塞反，编译报 `Type 'HorizontalAlign' is not assignable to type 'VerticalAlign'`——联合类型 + 编译器提前拦截的活教材。

> [!success] 复习自测记录（2026-09-13）
> Q1（let/const/类型不可变）✅ 全对　Q3（Promise 三态）✅ 基本正确
> Q2（收窄的 why 与 how）⚠️ 半对——三种收窄手段要背
> Q4/Q5/Q6/Q7 未完成 → 并入 Day 2

---

## ⚡ 代码速查表

```typescript
// 空安全判断
if (arr.length === 0) return null

// 两位小数格式化
`${n.toFixed(2)}`

// 枚举 + 状态流转
enum TaskStatus { TODO = 0, DOING = 1, DONE = 2 }

// 泛型容器 + 约束
class Box<T> { ... }
function pick<T extends ITask>(tasks: T[], s: TaskStatus): T[] { ... }

// Promise 包裹 setTimeout（Day 2 会用到）
return new Promise<void>((resolve) => { setTimeout(() => resolve(), ms) })
```

## ✅ Day 1 验收清单

- [x] Practice1：formatPrice / firstOrNull / describe（已修复通过）
- [x] Practice2：订单系统（编译通过、状态流转正确）
- [ ] Practice3：sleep + mockFetchOrders（**欠账**）
- [ ] 综合练习：TaskManager + UI 联动（**欠账**）
- [ ] 口述验收：Promise 三态 ✅ / await 规则 ⏳ / ArkTS 差异 ≥4 条 ⏳

## 🔧 命令行编译备忘

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p module=entry@default assembleHap --no-daemon
# 黄色警告 "No signingConfigs" 属正常（命令行构建不签名）
```
