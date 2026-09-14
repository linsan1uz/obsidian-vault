/*
 * Day 1 综合示例：个人名片卡片
 *
 * 使用方法：
 * 1. 把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 2. 找一张图改名为 avatar.png 放进 entry/src/main/resources/base/media/
 * 3. 打开 Previewer 预览
 */

@Entry
@Component
struct ProfileCard {
  build() {
    Column({ space: 12 }) {
      Image($r('app.media.avatar'))
        .width(96)
        .height(96)
        .borderRadius(48)
        .objectFit(ImageFit.Cover)

      Text('张三')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#182431')

      Text('鸿蒙开发 · 第 1 天')
        .fontSize(14)
        .fontColor('#999999')

      Row({ space: 8 }) {
        Text('ArkTS')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
        Text('ArkUI')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
        Text('HarmonyOS')
          .fontSize(12)
          .fontColor('#007DFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#E6F2FF')
          .borderRadius(10)
      }

      Button('点个赞')
        .width(140)
        .height(36)
        .onClick(() => {
          console.log('点赞!')
        })
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)
  }
}
