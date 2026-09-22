/*
 * Day 7 手势实验场
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 实验剧本：
 *   1. 拖拽小球：棋盘里随便拖，拖不出边界（快照 + 钳制）；记录"起点+位移"的写法
 *   2. 长按色块：按住 400ms 变色，松手恢复
 *   3. 双指缩放：两指捏合 0.5~3 倍（还是快照模式）
 *   4. 单击/长按竞争：点一下是"单击"，按住是"长按"，长按松手【不会】误触单击
 */

import { promptAction } from '@kit.ArkTS'

@Entry
@Component
struct GestureLab {
  // --- 实验 1：拖拽小球 ---
  @State ballX: number = 0
  @State ballY: number = 0
  private startX: number = 0                    // 按下瞬间的快照（普通成员，不驱动 UI）
  private startY: number = 0
  private readonly boardSize: number = 300      // 棋盘边长
  private readonly ballSize: number = 56        // 球直径

  // --- 实验 2：长按 ---
  @State longPressed: boolean = false

  // --- 实验 3：双指缩放 ---
  @State boxScale: number = 1
  private baseScale: number = 1

  build() {
    Column({ space: 20 }) {

      // ===== 实验 1：Pan 拖拽（快照 + 边界钳制） =====
      Text('① 拖拽小球（边界钳制）')
        .fontSize(14)
        .fontColor('#999999')
        .width('100%')

      Stack({ alignContent: Alignment.TopStart }) {
        Circle({ width: this.ballSize, height: this.ballSize })
          .fill('#007DFF')
          .translate({ x: this.ballX, y: this.ballY })
          .gesture(
            PanGesture({ direction: Direction.All })
              .onActionStart(() => {
                this.startX = this.ballX        // 快照：按下时在哪
                this.startY = this.ballY
              })
              .onActionUpdate((e: PanGestureEvent) => {
                // 目标 = 起点 + 本次位移，再夹进棋盘范围
                const maxX = this.boardSize - this.ballSize
                this.ballX = Math.min(maxX, Math.max(0, this.startX + e.translationX))
                this.ballY = Math.min(maxX, Math.max(0, this.startY + e.translationY))
              })
          )
      }
      .width(this.boardSize)
      .height(this.boardSize)
      .backgroundColor('#F7F8FA')
      .border({ width: 1, color: '#E5E7EB' })
      .borderRadius(16)

      // ===== 实验 2：长按 =====
      Text('② 长按色块（按住 400ms）')
        .fontSize(14)
        .fontColor('#999999')
        .width('100%')

      Text(this.longPressed ? '按住了！松手恢复' : '长按我')
        .fontSize(16)
        .fontColor(Color.White)
        .width('100%')
        .height(56)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.longPressed ? '#E53935' : '#9AA4B2')
        .borderRadius(12)
        .gesture(
          LongPressGesture({ repeat: false, duration: 400 })
            .onAction(() => {
              this.longPressed = true
            })
            .onActionEnd(() => {
              this.longPressed = false
            })
        )

      // ===== 实验 3：双指缩放（快照 × 倍数） =====
      Text('③ 双指缩放（0.5~3 倍）')
        .fontSize(14)
        .fontColor('#999999')
        .width('100%')

      Text(`×${this.boxScale.toFixed(2)}`)
        .fontSize(20)
        .fontColor(Color.White)
        .width(140)
        .height(140)
        .textAlign(TextAlign.Center)
        .backgroundColor('#50B87A')
        .borderRadius(20)
        .scale({ x: this.boxScale, y: this.boxScale })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.baseScale = this.boxScale    // 快照：捏合瞬间的基准
            })
            .onActionUpdate((e: PinchGestureEvent) => {
              this.boxScale = Math.min(3, Math.max(0.5, this.baseScale * e.scale))
            })
        )

      // ===== 实验 4：单击 / 长按互斥共存 =====
      Text('④ 竞争：点一下 vs 按住（长按松手不误触单击）')
        .fontSize(14)
        .fontColor('#999999')
        .width('100%')

      Text('点我试试')
        .fontSize(18)
        .fontColor('#007DFF')
        .width('100%')
        .height(64)
        .textAlign(TextAlign.Center)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .gesture(
          GestureGroup(GestureMode.Exclusive,          // 互斥：抢椅子，先识别成功者独占
            TapGesture({ count: 1 })
              .onAction(() => {
                promptAction.showToast({ message: '单击 ✅' })
              }),
            LongPressGesture({ duration: 400 })
              .onAction(() => {
                promptAction.showToast({ message: '长按 ✅' })
              })
          )
        )
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }
}
