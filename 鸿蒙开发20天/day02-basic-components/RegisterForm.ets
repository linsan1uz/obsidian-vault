/*
 * Day 2 综合示例：注册表单
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 覆盖了：TextInput / Progress / Slider / Radio / Toggle / Checkbox / Button / Blank
 * 以及 @State 最小用法（事件里改数据，界面自动刷新）
 */

@Entry
@Component
struct RegisterForm {
  @State nickname: string = ''
  @State password: string = ''
  @State strength: number = 0
  @State age: number = 18
  @State gender: string = ''
  @State pushOn: boolean = false
  @State agree: boolean = false

  // 简单估算密码强度：长度打底，大写/数字/符号加分
  calcStrength(pwd: string): number {
    if (pwd.length === 0) {
      return 0
    }
    let score: number = Math.min(pwd.length * 10, 60)
    if (/[A-Z]/.test(pwd)) {
      score += 15
    }
    if (/[0-9]/.test(pwd)) {
      score += 15
    }
    if (/[^A-Za-z0-9]/.test(pwd)) {
      score += 10
    }
    return Math.min(score, 100)
  }

  build() {
    Column({ space: 16 }) {
      Text('创建账号')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      TextInput({ placeholder: '昵称' })
        .maxLength(12)
        .height(44)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .onChange((value: string) => {
          this.nickname = value
        })

      TextInput({ placeholder: '密码（至少8位）' })
        .type(InputType.Password)
        .height(44)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .onChange((value: string) => {
          this.password = value
          this.strength = this.calcStrength(value)
        })

      Progress({ value: this.strength, total: 100, type: ProgressType.Linear })
        .color(this.strength < 40 ? '#F44336' : this.strength < 70 ? '#FF9800' : '#4CAF50')
        .width('100%')

      Row({ space: 12 }) {
        Text('年龄').fontSize(15)
        Slider({ value: this.age, min: 1, max: 100, step: 1 })
          .selectedColor('#007DFF')
          .blockColor('#007DFF')
          .layoutWeight(1)
          .onChange((value: number) => {
            this.age = Math.round(value)
          })
        Text(`${this.age}岁`)
          .fontSize(15)
          .width(48)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('性别').fontSize(15)
        Radio({ value: 'male', group: 'gender' })
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.gender = '男'
            }
          })
        Text('男').fontSize(15)
        Radio({ value: 'female', group: 'gender' })
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.gender = '女'
            }
          })
        Text('女').fontSize(15)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('接收推送通知').fontSize(15)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.pushOn })
          .selectedColor('#007DFF')
          .onChange((isOn: boolean) => {
            this.pushOn = isOn
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Checkbox({ name: 'agreement' })
          .selectColor('#007DFF')
          .onChange((value: boolean) => {
            this.agree = value
          })
        Text('我已阅读并同意《用户协议》')
          .fontSize(14)
          .fontColor('#666666')
      }
      .width('100%')

      Button('注册')
        .width('100%')
        .height(44)
        .backgroundColor('#007DFF')
        .enabled(this.agree && this.nickname.length > 0)
        .onClick(() => {
          console.log(`注册信息：昵称=${this.nickname}，性别=${this.gender}，` +
            `年龄=${this.age}，推送=${this.pushOn}`)
        })
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }
}
