/*
 * Day 7 里程碑：计算器（完整实现）
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 设计：
 *   - Grid 4列×5行（rowsTemplate 钉死，不可滚动——Day 4 规则）
 *   - CalcKeyButton 自定义组件复用 20 个按键（Day 6：子组件只喊事件，逻辑在页面）
 *   - ForEach 数据驱动生成按键（Day 5），键用 label（唯一）
 * 状态机（4 个 @State 就是一台四则运算机器）：
 *   display 屏幕内容 / acc 前操作数 / op 待执行运算符 / fresh 下一个数字是否重新开始
 * 验收清单：
 *   1. 7 + 8 = 15，接着 × 3 = 45（连续运算，fresh 旗的功劳）
 *   2. 5 ÷ 0 = 显示"错误"，按数字可继续用
 *   3. 3.14 连按 . 只进一个；± 切正负；% 除以 100
 *   4. 123 ⌫ 逐位删到 0；按 = 快速连点只算一次（防抖）
 */

// ===== 按键组件：只负责喊"我被按了"，不认识任何计算逻辑 =====
@Component
struct CalcKeyButton {
  label: string = ''
  kind: string = 'digit'                 // digit | fn | op | equals
  onPress: (label: string) => void = () => {}

  build() {
    Text(this.label)
      .fontSize(this.label.length > 1 ? 18 : 24)
      .fontColor(this.kind === 'digit' ? '#182431' :
        this.kind === 'equals' ? Color.White :
        this.kind === 'op' ? '#007DFF' : '#E53935')
      .width('100%')
      .height('100%')
      .textAlign(TextAlign.Center)
      .backgroundColor(this.kind === 'digit' ? '#FFFFFF' :
        this.kind === 'equals' ? '#007DFF' :
        this.kind === 'op' ? '#E6F2FF' : '#FDECEC')
      .borderRadius(16)
      .margin(4)
      .onClick(() => {
        this.onPress(this.label)         // 按门铃，页面来开门（Day 6 回调）
      })
  }
}

@Entry
@Component
struct Calculator {
  @State display: string = '0'           // 屏幕显示
  @State acc: number = 0                 // 前一个操作数
  @State op: string = ''                 // 待执行运算符：+ − × ÷（'' = 无）
  @State fresh: boolean = true           // 下一个数字是否重新开始输入
  private lastClick: number = 0          // 防抖时间戳（普通成员）

  // 20 个按键，拍平成一维数组，Grid 按 columnsTemplate 自动换行
  private readonly keys: string[] = [
    'AC', '⌫', '%', '÷',
    '7', '8', '9', '×',
    '4', '5', '6', '−',
    '1', '2', '3', '+',
    '±', '0', '.', '='
  ]

  kindOf(label: string): string {
    if (label === '=') {
      return 'equals'
    }
    if ('÷×−+'.includes(label)) {
      return 'op'
    }
    if ('AC⌫%±'.includes(label)) {
      return 'fn'
    }
    return 'digit'
  }

  // 浮点格式化：压掉 0.1+0.2=0.30000000000000004 的尾巴
  fmt(n: number): string {
    return parseFloat(n.toPrecision(12)).toString()
  }

  calc(a: number, b: number, o: string): number {
    switch (o) {
      case '+':
        return a + b
      case '−':
        return a - b
      case '×':
        return a * b
      case '÷':
        return b === 0 ? Number.NaN : a / b   // 除零 → NaN → 显示"错误"
      default:
        return b
    }
  }

  press(label: string): void {
    const isDigit: boolean = label >= '0' && label <= '9'

    // ---- 数字键 ----
    if (isDigit) {
      if (this.display === '错误') {           // 错误态：任何数字都从头开始
        this.display = label
        this.fresh = false
        return
      }
      if (this.fresh) {
        this.display = label                   // fresh 旗：开新数字，整体替换
        this.fresh = false
      } else if (this.display === '0') {
        this.display = label                   // 防前导 0
      } else if (this.display.length < 12) {
        this.display += label                  // 追加
      }
      return
    }

    // ---- 小数点 ----
    if (label === '.') {
      if (this.display === '错误') {
        this.display = '0.'
        this.fresh = false
        return
      }
      if (this.fresh) {
        this.display = '0.'                    // 运算符后直接按 . → 0.xxx
        this.fresh = false
      } else if (!this.display.includes('.')) {
        this.display += '.'
      }
      return
    }

    // ---- 运算符 ----
    if ('÷×−+'.includes(label)) {
      this.acc = this.display === '错误' ? 0 : parseFloat(this.display)
      this.op = label
      this.fresh = true                        // 下一个数字重新开始
      return
    }

    // ---- 等号 ----
    if (label === '=') {
      const now: number = Date.now()
      if (now - this.lastClick < 300) {        // 防抖：连点只算一次
        return
      }
      this.lastClick = now
      if (this.op === '') {
        return
      }
      const cur: number = parseFloat(this.display)
      const r: number = this.calc(this.acc, cur, this.op)
      if (Number.isNaN(r)) {
        this.display = '错误'                  // 除零
      } else {
        this.display = this.fmt(r)
      }
      this.acc = 0
      this.op = ''
      this.fresh = true
      return
    }

    // ---- 功能键 ----
    switch (label) {
      case 'AC':                               // 全部复位
        this.display = '0'
        this.acc = 0
        this.op = ''
        this.fresh = true
        break
      case '⌫':                                // 退一位
        if (this.display === '错误') {
          this.display = '0'
        } else if (this.fresh) {
          this.display = '0'                   // 刚按完运算符，无可删
        } else if (this.display.length > 1) {
          this.display = this.display.slice(0, -1)
        } else {
          this.display = '0'
        }
        this.fresh = false
        break
      case '±':                                // 正负切换
        if (this.display === '错误' || this.display === '0') {
          break
        }
        this.display = this.display.startsWith('-')
          ? this.display.slice(1)
          : '-' + this.display
        break
      case '%':                                // 百分比
        if (this.display !== '错误') {
          this.display = this.fmt(parseFloat(this.display) / 100)
        }
        this.fresh = false
        break
      default:
        break
    }
  }

  build() {
    Column({ space: 16 }) {

      // ===== 显示区：右对齐，超长自动缩号 =====
      Text(this.display)
        .fontSize(this.display.length > 9 ? 40 : 64)
        .fontWeight(FontWeight.Light)
        .width('100%')
        .height(100)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ right: 8 })
        .align(VerticalAlign.Bottom)

      // ===== 按键区：Grid 固定 4 列 5 行（钉死不可滚） =====
      Grid() {
        ForEach(this.keys, (label: string) => {
          GridItem() {
            CalcKeyButton({
              label: label,
              kind: this.kindOf(label),
              onPress: (l: string) => {
                this.press(l)
              }
            })
          }
        }, (label: string) => label)           // 键 = label，唯一稳定（Day 5 规则）
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr 1fr 1fr')
      .rowsGap(4)
      .width('100%')
      .layoutWeight(1)                         // 占满剩余高度
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
