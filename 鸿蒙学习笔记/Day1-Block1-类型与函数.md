---
tags:
  - 鸿蒙
  - ArkTS
  - 学习笔记
course: 鸿蒙应用开发10天计划
day: 1
block: 1
date: 2026-09-12
---

# Day 1 · Block 1：类型与函数

> [!info] 本课目标
> 掌握 ArkTS 的类型系统与函数写法，理解「联合类型必须先收窄再使用」这一核心规则。练习文件：`myapplication/entry/src/main/ets/pages/Practice1.ets`

## 1.1 变量与基础类型

ArkTS 的规矩：**每个变量都有类型，且声明后不许换类型**。

```typescript
let count: number = 0        // let = 可以重新赋值
const MAX: number = 100      // const = 只能赋值一次；默认优先用 const
let name: string = '鸿蒙'
let ok: boolean = true
let ids: number[] = [1, 2, 3]          // 数组两种写法等价
let tags: Array<string> = ['a', 'b']

let x = 5                    // 类型推断：x 自动是 number
// x = 'hello'               // ❌ 编译报错：number 不能换成 string
```

**为什么这么严？** JS 的类型错误是运行时才炸（用户先看到白屏）；ArkTS 把这类错误提前到编译期拦截。

## 1.2 联合类型与类型收窄 ★ 今日核心

一个值「可能是几种类型之一」时，用 `|`：

```typescript
let id: number | string = 101
```

但 `id.toFixed(2)` 编译不过——`id` 可能是 string。**规则：先收窄，再使用**：

```typescript
function render(id: number | string | null): string {
  if (id === null) {
    return '无ID'               // ✅ 此分支里 id 一定是 null
  }
  if (typeof id === 'number') {
    return id.toFixed(2)        // ✅ 收窄成 number，才能调数字方法
  }
  return 'ID: ' + id            // ✅ 排除 null 和 number，剩下一定是 string
}
```

三种收窄手段：`typeof`（判基础类型）、`instanceof`（判类）、`in`（判属性是否存在）。

## 1.3 函数

```typescript
// 标准写法：参数标类型，返回值标类型
function add(a: number, b: number): number {
  return a + b
}

// 可选参数：调用时可以不传
function greet(name: string, title?: string): string {
  return title ? `${title}·${name}` : name     // ${} 是模板字符串
}

// 默认参数：不传就用默认值
function repeat(text: string, times: number = 2): string {
  return text.repeat(times)
}

// 箭头函数：ArkUI 事件回调全是这个形态（把函数当参数传）
const multiply = (a: number, b: number): number => a * b
```

> [!tip] 认脸训练
> 以后天天见的 `onClick={() => { ... }}` 就是箭头函数当参数传。

## 1.4 enum 与类型别名

```typescript
enum TaskStatus { TODO = 0, DOING = 1, DONE = 2 }   // 给一组常量起名字
type ID = number | string                            // 给类型起名字

let s: TaskStatus = TaskStatus.DONE
```

---

## 练习①：三个函数（20min）

文件：`Practice1.ets`，在模拟器运行后点「Run Practice1」按钮，Log 窗口搜 `Practice1` 核对输出。

| 题目 | 要求 | 考察点 |
|---|---|---|
| `formatPrice(n)` | `formatPrice(3.5)` → `"¥3.50"` | toFixed(2)、字符串拼接 |
| `firstOrNull<T>(arr)` | 空数组返回 `null`，否则返回首元素 | 泛型 |
| `describe(value)` | 联合类型 → 中文描述 | 类型收窄 |

**验收标准**：三题全对、零红色报错、零 `any`。

## 练习点评记录（2026-09-12）

> [!warning] 我的错题
> - `formatPrice` 写成了 `'￥' + n`：① 没用 `toFixed(2)`，输出 `¥3.5` 不是 `¥3.50`；② 全角 `￥` 应为半角 `¥`
> - `==` 应写成 `===`（严格相等），运算符两侧加空格
> - `firstOrNull` 里 `arr.length == 0 || arr[0] == null` 的后半段是死代码：前半段命中时数组必然非空
> - `describe` 的 `else return 'error'` 是死代码：三个 typeof 分支已穷尽所有可能（留着无害，但要知道）

> [!success] 真实编译案例
> 给首页加按钮时，`alignRules` 里把 `HorizontalAlign`（水平，对应 `middle` 槽位）和 `VerticalAlign`（垂直，对应 `center` 槽位）塞反了，编译直接报：
> `Type 'HorizontalAlign' is not assignable to type 'VerticalAlign'`
> ——联合类型 + 编译器提前拦截的活例子。

## 命令行编译备忘

```powershell
# DevEco 之外手动编译（注意 DEVECO_SDK_HOME 必须设置）
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p module=entry@default assembleHap --no-daemon
# 黄色警告 "No signingConfigs" 属正常（命令行构建不签名）
```

## 待办

- [ ] 修复 `formatPrice`（toFixed + 半角 ¥）
- [ ] 统一 `===` 风格，删死代码
- [ ] 模拟器运行核对 6 行 Log 输出
- [ ] 进入 Block 2：class / interface / 泛型
