/*
 * Day 5 · 状态刷新机制实验场
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 玩法：每个按钮都标注了"能不能触发刷新"，逐个点击验证第 2 节的表格。
 * 挑战：自己加一个按钮直接改 todo.done（不替换整项），亲眼看界面不刷新——这就是最高频的坑。
 */

class UserProfile {
  name: string
  age: number

  constructor(name: string, age: number) {
    this.name = name
    this.age = age
  }
}

class TodoItem {
  id: number
  title: string
  done: boolean

  constructor(id: number, title: string, done: boolean) {
    this.id = id
    this.title = title
    this.done = done
  }
}

@Entry
@Component
struct StateLab {
  @State user: UserProfile = new UserProfile('张三', 18)
  @State tags: string[] = ['ArkTS', 'ArkUI']
  @State todos: TodoItem[] = [
    new TodoItem(1, '学完 Day 5', false),
    new TodoItem(2, '写作业', false)
  ]
  @State nextId: number = 3

  build() {
    Column({ space: 16 }) {

      // ===== 实验 1：对象——第一层属性 vs 整体替换 =====
      Text(`用户：${this.user.name}，${this.user.age}岁`)
        .fontSize(16)
      Row({ space: 8 }) {
        Button('改第一层属性 ✅')
          .onClick(() => {
            this.user.age = this.user.age + 1     // 第一层属性赋值 → 能被观察到
          })
        Button('整体替换 ✅')
          .onClick(() => {
            this.user = new UserProfile('李四', 20)
          })
      }
      .width('100%')

      // ===== 实验 2：数组——API 增删 vs 整体赋值 =====
      Text(`标签：${JSON.stringify(this.tags)}`)
        .fontSize(16)
      Row({ space: 8 }) {
        Button('push ✅')
          .onClick(() => {
            this.tags.push('HarmonyOS')           // 数组项增加 → 能被观察到
          })
        Button('整体赋值 ✅')
          .onClick(() => {
            this.tags = [...this.tags, 'Next']    // 变量赋值 → 永远有效
          })
      }
      .width('100%')

      // ===== 实验 3：if 条件渲染（分支切换 = 销毁重建） =====
      if (this.todos.length === 0) {
        Text('没有待办，躺平吧')
          .fontSize(14)
          .fontColor('#999999')
      } else {
        Text(`还有 ${this.todos.length} 件事没做`)
          .fontSize(14)
          .fontColor('#E53935')
      }

      // ===== 实验 4：ForEach 循环渲染（注意 splice 整项替换的写法） =====
      List({ space: 8 }) {
        ForEach(this.todos, (todo: TodoItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(todo.done ? '✔️' : '⬜')
                .fontSize(16)
              Text(todo.title)
                .fontSize(15)
                .layoutWeight(1)
                .decoration(todo.done
                  ? { type: TextDecorationType.LineThrough }
                  : { type: TextDecorationType.None })
              Button('完成')
                .fontSize(12)
                .height(28)
                .onClick(() => {
                  // todo.done = !todo.done 是"第二层"，观察不到！
                  // 解法：splice 整项替换（数组层操作，能被观察到）
                  this.todos.splice(this.todos.indexOf(todo), 1,
                    new TodoItem(todo.id, todo.title, !todo.done))
                })
              Button('删')
                .fontSize(12)
                .height(28)
                .backgroundColor('#E53935')
                .onClick(() => {
                  this.todos.splice(this.todos.indexOf(todo), 1)
                })
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#F7F8FA')
            .borderRadius(8)
            .alignItems(VerticalAlign.Center)
          }
        }, (todo: TodoItem) => todo.id.toString())   // 键：稳定唯一，绝不用 index
      }
      .width('100%')

      Button('+ 添加一条')
        .width('100%')
        .onClick(() => {
          this.todos.push(new TodoItem(this.nextId, `待办 ${this.nextId}`, false))
          this.nextId++
        })
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }
}
