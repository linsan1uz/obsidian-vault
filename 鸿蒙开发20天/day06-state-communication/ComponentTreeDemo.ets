/*
 * Day 6 综合示例：四种父子通信通道同场对比
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 实验剧本（按顺序点，盯着界面和 Log 窗口）：
 *   1. LinkCounter 的 + ：它变，SummaryBar 的父总计同时变（双向同步）
 *   2. PropCounter 的 + ：只有它自己变，父总计不动（副本）
 *   3. 父组件 +1        ：LinkCounter 跟着变；PropCounter 的本地修改被覆盖（拷贝语义）
 *   4. 清零（回调）      ：父数据归零，两个 Counter 都归零
 *   5. 全程 Log 窗口有 PropCounter 的 @Watch 日志
 */

// ===== 子组件 1：普通成员——只读展示，父变会同步下来，本地改不刷新 UI =====
@Component
struct NavBar {
  title: string = ''

  build() {
    Row() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      Blank()
      Text('⚙️').fontSize(18)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
  }
}

// ===== 子组件 2：@Prop——值拷贝 + @Watch 副作用 =====
@Component
struct PropCounter {
  @Prop @Watch('onCountChange') count: number = 0

  onCountChange() {
    // @Watch：值一变立即回调，做"刷新 UI 之外"的事
    console.log(`[Watch] PropCounter 的 count 变成了 ${this.count}`)
  }

  build() {
    Row({ space: 12 }) {
      Text('@Prop 副本')
        .fontSize(13)
        .fontColor('#B8860B')
        .width(84)
      Button('-')
        .width(40)
        .height(40)
        .onClick(() => {
          this.count--          // 只改副本，父组件无感知
        })
      Text(`${this.count}`)
        .fontSize(16)
        .width(48)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(40)
        .height(40)
        .onClick(() => {
          this.count++
        })
      Blank()
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFF7E0')
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
  }
}

// ===== 子组件 3：@Link——双向同步，同一份数据 =====
@Component
struct LinkCounter {
  @Link count: number           // 不能本地初始化，必须由父组件用 $ 绑定

  build() {
    Row({ space: 12 }) {
      Text('@Link 同步')
        .fontSize(13)
        .fontColor('#007DFF')
        .width(84)
      Button('-')
        .width(40)
        .height(40)
        .onClick(() => {
          this.count--          // 直接改的就是父组件那份数据
        })
      Text(`${this.count}`)
        .fontSize(16)
        .width(48)
        .textAlign(TextAlign.Center)
      Button('+')
        .width(40)
        .height(40)
        .onClick(() => {
          this.count++
        })
      Blank()
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#E6F2FF')
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
  }
}

// ===== 子组件 4：回调函数——事件上行，父组件决策 =====
@Component
struct SummaryBar {
  total: number = 0
  onReset: () => void = () => {}

  build() {
    Row() {
      Text(`父总计：${this.total}`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
      Blank()
      Button('清零')
        .height(32)
        .backgroundColor('#E53935')
        .onClick(() => {
          this.onReset()        // 子组件只报告事件，怎么处理父组件说了算
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(12)
  }
}

// ===== 页面：组件树的根，数据的唯一主人 =====
@Entry
@Component
struct ComponentTreeDemo {
  @State total: number = 0

  build() {
    Column({ space: 12 }) {
      NavBar({ title: '父子通信实验室' })          // 通道①：普通成员
      LinkCounter({ count: $total })               // 通道②：@Link，注意 $
      PropCounter({ count: this.total })           // 通道③：@Prop，传值拷贝
      SummaryBar({                                 // 通道④：回调
        total: this.total,
        onReset: () => {
          this.total = 0
        }
      })

      Button('父组件 +1（观察两个 Counter 的差异）')
        .width('100%')
        .onClick(() => {
          this.total++
        })

      Text('实验提示：先给 PropCounter 本地 +3，再点上面的按钮，看它的本地修改被父值覆盖')
        .fontSize(12)
        .fontColor('#999999')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
