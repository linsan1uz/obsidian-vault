---
tags:
  - 鸿蒙
  - ArkTS
  - 学习笔记
course: 鸿蒙应用开发10天计划
day: 1
block: 2
date: 2026-09-12
---

# Day 1 · Block 2：class / interface / 泛型

> [!info] 本课目标
> 看懂鸿蒙 SDK 的所有 API 都是用这套东西写的。练习文件：`myapplication/entry/src/main/ets/pages/Practice2.ets`（迷你订单系统）

## 2.1 interface：能力的契约

接口描述「能做什么」，不描述「是什么」：

```typescript
interface IExportable {
  toSummary(): string                     // 方法签名：只声明，不实现
  readonly id: string                     // 实现者必须提供，且不可改
  label?: string                          // 可选属性
}
interface IStorable extends IExportable {  // 接口继承
  save(path: string): void
}
```

拿到 `IExportable` 类型的参数时只管调 `toSummary()`，不关心具体类——鸿蒙大量回调参数是接口类型。

## 2.2 class：具体的东西

```typescript
class Order implements IExportable {
  private amount: number                  // 类外不可访问
  readonly createdAt: Date = new Date()   // 必须在声明处或构造函数里初始化！
  status: OrderStatus = OrderStatus.CREATED

  constructor(id: string, amount: number) { /* this.id = id ... */ }

  pay(): void { this.status = OrderStatus.PAID }
  toSummary(): string { return `订单${this.id}，金额¥${this.amount.toFixed(2)}` }
}
```

要点：
- 属性访问**必须 `this.` 开头**（漏写 = 找不到变量，编译错）
- **所有属性必须在声明处或构造函数里初始化**（新手最常撞的编译错）
- `static` 属于类本身；`get/set` 像属性一样用、实际是方法
- `extends` 继承：构造函数第一行必须 `super(...)`；方法重写用 `super.xxx()` 调父类原实现

## 2.3 泛型：类型层面的参数

```typescript
class Box<T> {
  private items: T[] = []
  add(item: T): void { this.items.push(item) }
  getAll(): T[] { return this.items }
}
const orders = new Box<Order>()    // 放进去是什么，取出来就是什么

function printAll<T extends IExportable>(box: Box<T>): void {  // 泛型约束
  box.getAll().forEach(item => console.log('TAG', item.toSummary()))
}
```

对比「不限类型」的容器：泛型由编译器保证类型一致，不需要强转。

## 2.4 ArkTS 严格差异（高频踩坑区）

```typescript
const p: Point = { x: 1, y: 2 }       // ✅ 对象字面量必须标注类型
// const q = { x: 1, y: 2 }           // ❌ 无类型字面量
// p.z = 3                            // ❌ 不能动态增删属性
const prices: Record<string, number> = { 'apple': 5 }   // 动态键用 Record/Map
```

报错前缀 `arkts-no-...` 就是撞上了这类限制。原因：AOT 编译、无运行时反射开销。

## 2.5 装饰器认脸

`@Entry`（页面入口）、`@Component`（组件）、`@State`（状态变量，变了自动刷 UI）——编译期附加能力的标记，见到 `@Xxx` 不慌即可，Day 3 正式拆解。

---

## 练习点评记录（2026-09-12）

> [!warning] 我的错题
> 1. `readonly createdAt: Date =` 等号后空着就换行——赋值语句没写完，语法错误还污染了下一行解析
> 2. `pay()` 里写 `status = OrderStatus.PAID` 漏了 `this.`——类方法里访问自己的属性必须 `this.` 开头
> 3. `toSummary()` 里 `"..."` 双引号写 `$id` 不插值——**模板字符串必须用反引号** `` ` ` ``；且 `${¥amount}` 把符号写进了表达式里（应放外面）；`${createdAt}` 放错属性（应为 `this.status`）
> 4. 第一版 `toSummary` 忘了 `toFixed(2)`——和 Block 1 `formatPrice` 同一个知识点

> [!success] 验收结果
> 编译通过；` ORD001 → 状态1（已支付）、ORD002 → 状态0`，对象状态被方法修改的活证据。

## 待办

- [x] Order 类补全（private 属性、构造函数、pay、toSummary）
- [x] Box<T> 泛型容器
- [ ] 运行核对 Log 四行输出
