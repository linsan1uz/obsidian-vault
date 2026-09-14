/*
 * Day 3 综合示例：设置页（纯线性布局嵌套）
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 依赖：resources/base/media/avatar.png
 * 看点：
 *  1. 用户卡片：中间名字列 layoutWeight(1)，右侧 VIP 徽章自动贴行尾
 *  2. 每个设置项 Row 都用 alignItems(VerticalAlign.Center) 垂直居中
 *  3. Blank() 把"退出登录"推到页面底部
 */

@Entry
@Component
struct SettingsDemo {
  @State notifyOn: boolean = true
  @State darkOn: boolean = false

  build() {
    Column({ space: 12 }) {

      // ===== 用户信息卡片 =====
      Row({ space: 12 }) {
        Image($r('app.media.avatar'))
          .width(56)
          .height(56)
          .borderRadius(28)
          .objectFit(ImageFit.Cover)

        Column({ space: 4 }) {
          Text('张三')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
          Text('鸿蒙学习 · 第 3 天')
            .fontSize(13)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)   // Column 交叉轴（水平）左对齐
        .layoutWeight(1)                     // 吃掉头像和徽章之间的剩余宽度

        Text('VIP')
          .fontSize(12)
          .fontColor('#B8860B')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor('#FFF7E0')
          .borderRadius(8)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)      // Row 交叉轴（竖直）居中

      // ===== 设置项：消息通知 =====
      Row({ space: 12 }) {
        Text('🔔').fontSize(20)
        Column({ space: 2 }) {
          Text('消息通知').fontSize(16)
          Text('接收新消息和提醒').fontSize(12).fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.notifyOn })
          .selectedColor('#007DFF')
          .onChange((isOn: boolean) => {
            this.notifyOn = isOn
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)

      // ===== 设置项：深色模式 =====
      Row({ space: 12 }) {
        Text('🌙').fontSize(20)
        Column({ space: 2 }) {
          Text('深色模式').fontSize(16)
          Text('跟随系统设置').fontSize(12).fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.darkOn })
          .selectedColor('#007DFF')
          .onChange((isOn: boolean) => {
            this.darkOn = isOn
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)

      // ===== 设置项：隐私（右侧箭头，纯跳转样式） =====
      Row({ space: 12 }) {
        Text('🔒').fontSize(20)
        Text('隐私设置').fontSize(16).layoutWeight(1)
        Text('>').fontSize(16).fontColor('#CCCCCC')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(VerticalAlign.Center)

      Blank()   // 占满中间剩余高度，把退出按钮推到底部

      // ===== 退出登录 =====
      Button('退出登录')
        .width('100%')
        .height(44)
        .type(ButtonType.Normal)
        .backgroundColor(Color.White)
        .fontColor('#E53935')
        .borderRadius(16)
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
