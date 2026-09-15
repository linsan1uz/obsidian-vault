/*
 * Day 4 综合示例：布局全家福
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 依赖：resources/base/media/avatar.png
 * 看点：
 *  1. 顶部：Stack 头像 + 未读角标（alignContent + offset 微调）
 *  2. 中部：Grid 九宫格（rowsTemplate 钉死 → 不可滚动）
 *  3. 下部：List 消息列表（layoutWeight(1) 占剩余高度 → 内部滚动，消息里再嵌 Stack 角标）
 */

@Entry
@Component
struct LayoutShowcase {
  @State unread: number = 5

  build() {
    Column({ space: 16 }) {

      // ===== 顶部问候：Stack 角标 =====
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image($r('app.media.avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
          Text(`${this.unread}`)
            .fontSize(11)
            .fontColor(Color.White)
            .width(18)
            .height(18)
            .borderRadius(9)
            .backgroundColor('#F44336')
            .textAlign(TextAlign.Center)
            .offset({ x: 4, y: -4 })
        }

        Column({ space: 2 }) {
          Text('早上好，张三')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
          Text('今天也要加油学鸿蒙')
            .fontSize(12)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('🔔').fontSize(20)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ===== 九宫格入口：固定 2 行 4 列，不可滚动 =====
      Grid() {
        GridItem() {
          Column({ space: 6 }) {
            Text('📚').fontSize(26)
            Text('课程').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('📝').fontSize(26)
            Text('笔记').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('✅').fontSize(26)
            Text('打卡').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('📊').fontSize(26)
            Text('统计').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('👥').fontSize(26)
            Text('社区').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('⭐').fontSize(26)
            Text('收藏').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('⚙️').fontSize(26)
            Text('设置').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        GridItem() {
          Column({ space: 6 }) {
            Text('🧩').fontSize(26)
            Text('更多').fontSize(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')   // 4 等分列
      .rowsTemplate('1fr 1fr')              // 钉死 2 行 → 不可滚动
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
      .height(180)

      // ===== 消息列表：占剩余高度，内部滚动 =====
      List({ space: 12 }) {
        ListItem() {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              Text('张')
                .fontSize(18)
                .fontColor(Color.White)
                .width(44)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#4A90D9')
                .textAlign(TextAlign.Center)
              Text('2')
                .fontSize(10)
                .fontColor(Color.White)
                .width(16)
                .height(16)
                .borderRadius(8)
                .backgroundColor('#F44336')
                .textAlign(TextAlign.Center)
                .offset({ x: 3, y: -3 })
            }
            Column({ space: 4 }) {
              Text('张三').fontSize(16)
              Text('Day 4 的布局课更新了')
                .fontSize(13)
                .fontColor('#999999')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('09:12').fontSize(12).fontColor('#CCCCCC')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .alignItems(VerticalAlign.Center)
        }

        ListItem() {
          Row({ space: 12 }) {
            Text('李')
              .fontSize(18)
              .fontColor(Color.White)
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#50B87A')
              .textAlign(TextAlign.Center)
            Column({ space: 4 }) {
              Text('李四').fontSize(16)
              Text('作业记得交').fontSize(13).fontColor('#999999').maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('昨天').fontSize(12).fontColor('#CCCCCC')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .alignItems(VerticalAlign.Center)
        }

        ListItem() {
          Row({ space: 12 }) {
            Text('王')
              .fontSize(18)
              .fontColor(Color.White)
              .width(44)
              .height(44)
              .borderRadius(22)
              .backgroundColor('#F2A33C')
              .textAlign(TextAlign.Center)
            Column({ space: 4 }) {
              Text('王五').fontSize(16)
              Text('[图片]').fontSize(13).fontColor('#999999').maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('昨天').fontSize(12).fontColor('#CCCCCC')
          }
          .width('100%')
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .alignItems(VerticalAlign.Center)
        }
      }
      .layoutWeight(1)          // 吃掉页面剩余高度 → List 内部滚动
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
