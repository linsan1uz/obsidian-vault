/*
 * Day 3 · 对齐实验场
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 玩法：只改 .justifyContent(...) 和 .alignItems(...) 里的枚举值，保存看色块怎么动。
 *   justifyContent: FlexAlign.Start / Center / End / SpaceBetween / SpaceAround / SpaceEvenly
 *   alignItems:     VerticalAlign.Top / Center / Bottom（Row 的交叉轴是竖直方向）
 * 进阶玩法：把 Row 换成 Column，再把两个枚举换成 FlexAlign / HorizontalAlign 体会方向变化。
 */

@Entry
@Component
struct AlignPlayground {
  build() {
    Column({ space: 16 }) {
      Text('justifyContent 实验：改下面那行枚举，看色块怎么动')
        .fontSize(14)
        .fontColor('#666666')

      Row({ space: 8 }) {
        Text('A')
          .fontSize(18)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(60)
          .height(60)
          .backgroundColor('#4A90D9')
          .borderRadius(8)
        Text('B')
          .fontSize(18)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(60)
          .height(60)
          .backgroundColor('#50B87A')
          .borderRadius(8)
        Text('C')
          .fontSize(18)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(60)
          .height(60)
          .backgroundColor('#F2A33C')
          .borderRadius(8)
      }
      .width('100%')
      .height(120)
      .padding(12)
      .backgroundColor('#F7F8FA')
      .borderRadius(12)
      .justifyContent(FlexAlign.SpaceBetween)   // ← 改这里
      .alignItems(VerticalAlign.Center)         // ← 和这里

      Text('再试试把上面的 Row 改成 Column，体会主轴方向的变化')
        .fontSize(13)
        .fontColor('#999999')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
