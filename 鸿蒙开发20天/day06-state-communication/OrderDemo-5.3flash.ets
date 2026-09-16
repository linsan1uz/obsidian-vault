/*
 * Day 6（5.3flash 重写版）综合示例：奶茶点单页
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 通道分布：
 *   DrinkRow   —— 普通成员（name/price，纯展示）+ @Link（count，直改父数据）
 *   Stepper    —— @Link 双向步进器 + @Watch 副作用日志
 *   OrderBar   —— 普通成员（total，派生值）+ 回调（onClear）
 * 实验剧本：
 *   1. 点任意 Stepper +/-：行内数字与底部合计同时变（@Link + 派生合计）
 *   2. 点"清空"：三个数量全归零（回调上行，父组件重置数据）
 *   3. 盯 Log 窗口：每次数量变化输出一行 [Watch] 日志
 */

// ===== 复用件：数量步进器（@Link 双向 + @Watch） =====
@Component
struct Stepper {
  @Link @Watch('onValueChanged') value: number

  onValueChanged() {
    // 刷新 UI 之外的副作用才需要 @Watch
    console.log(`[Watch] 数量变为 ${this.value}`)
  }

  build() {
    Row({ space: 8 }) {
      Button('-')
        .width(32)
        .height(32)
        .onClick(() => {
          if (this.value > 0) {
            this.value--
          }
        })
      Text(`${this.value}`)
        .fontSize(16)
        .width(32)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(32)
        .height(32)
        .onClick(() => {
          this.value++
        })
    }
  }
}

// ===== 商品行：普通成员（展示数据）+ @Link（联动数据） =====
@Component
struct DrinkRow {
  name: string = ''          // 不需要子组件修改 → 不加装饰器
  price: number = 0
  @Link count: number        // 加减就是在改父组件的账 → @Link

  build() {
    Row({ space: 12 }) {
      Text('🧋')
        .fontSize(24)
      Column({ space: 2 }) {
        Text(this.name)
          .fontSize(16)
        Text(`￥${this.price}`)
          .fontSize(13)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Stepper({ value: $count })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
  }
}

// ===== 底部小结：普通成员（派生值）+ 回调（事件上行） =====
@Component
struct OrderBar {
  total: number = 0
  onClear: () => void = () => {}

  build() {
    Row() {
      Text(`合计：￥${this.total}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Blank()
      Button('清空')
        .height(32)
        .backgroundColor('#E53935')
        .onClick(() => {
          this.onClear()          // 子组件只按门铃，父组件来开门
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

// ===== 页面：数据的唯一主人 =====
@Entry
@Component
struct OrderDemo {
  @State countLatte: number = 0
  @State countMocha: number = 0
  @State countTea: number = 0

  // 派生数据：能算出来的就不要存（build 里每次刷新自动重算）
  total(): number {
    return this.countLatte * 15 + this.countMocha * 18 + this.countTea * 12
  }

  build() {
    Column({ space: 12 }) {
      Text('今日点单')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      DrinkRow({ name: '拿铁', price: 15, count: $countLatte })
      DrinkRow({ name: '摩卡', price: 18, count: $countMocha })
      DrinkRow({ name: '红茶', price: 12, count: $countTea })

      Blank()

      OrderBar({
        total: this.total(),
        onClear: () => {
          this.countLatte = 0
          this.countMocha = 0
          this.countTea = 0
        }
      })
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
    .alignItems(HorizontalAlign.Start)
  }
}
