/*
 * Day 6 综合示例（5.3 版）：音乐播放页
 *
 * 使用方法：把本文件内容替换到 entry/src/main/ets/pages/Index.ets
 * 组件树与通道：
 *   MusicPlayer  页面，全部 @State 的主人
 *   SongInfo     普通成员（title/artist）        —— 只是看看
 *   VolumePanel  @Link（volume）                 —— 一起改
 *   RatingStars  @Prop（rating 草稿）+ 回调确认   —— 自己改着玩
 *   ControlBar   普通成员（playing）+ 回调        —— 按门铃
 * 验证清单：
 *   1. 拖音量滑块：数字同步变（@Link），Log 每次输出持久化日志（@Watch）
 *   2. 点星级：星星先自己变（@Prop 副本）；点"提交评分"才交回页面
 *   3. 点播放/下一首：按钮由页面数据驱动，逻辑全在回调里
 *   4. 点"重置评分"：星级草稿被父值覆盖（拷贝语义）
 */

// ===== 歌曲信息：普通成员，只读展示 =====
@Component
struct SongInfo {
  title: string = ''
  artist: string = ''

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      Text(this.artist)
        .fontSize(14)
        .fontColor('#999999')
    }
  }
}

// ===== 音量面板：@Link 一起改 =====
@Component
struct VolumePanel {
  @Link volume: number            // 禁止本地初始化，必须由父组件 $ 绑定

  build() {
    Column({ space: 8 }) {
      Text(`音量 ${this.volume}%`)
        .fontSize(14)
        .fontColor('#666666')
      Slider({ value: this.volume, min: 0, max: 100 })
        .selectedColor('#007DFF')
        .blockColor('#007DFF')
        .onChange((v: number) => {
          this.volume = Math.round(v)    // 直接改父组件那份数据
        })
    }
    .width('100%')
  }
}

// ===== 评分星星：@Prop 草稿 + 回调提交 =====
@Component
struct RatingStars {
  @Prop rating: number = 0             // 本地草稿，可以给默认值
  onSubmit: (rating: number) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text('★'.repeat(this.rating))
          .fontSize(26)
          .fontColor('#FFB800')
        Text('☆'.repeat(5 - this.rating))
          .fontSize(26)
          .fontColor('#CCCCCC')
      }
      .onClick(() => {
        this.rating = this.rating >= 5 ? 0 : this.rating + 1   // 改副本，先自己刷新
      })

      Button('提交评分')
        .height(30)
        .fontSize(13)
        .backgroundColor('#666666')
        .onClick(() => {
          this.onSubmit(this.rating)     // 草稿通过回调交回父组件
        })
    }
  }
}

// ===== 播放控制：普通成员展示 + 回调按门铃 =====
@Component
struct ControlBar {
  playing: boolean = false
  onToggle: () => void = () => {}
  onNext: () => void = () => {}

  build() {
    Row({ space: 32 }) {
      Button(this.playing ? '⏸' : '▶')
        .width(56)
        .height(56)
        .fontSize(24)
        .backgroundColor('#007DFF')
        .onClick(() => this.onToggle())
      Button('⏭')
        .width(56)
        .height(56)
        .fontSize(24)
        .backgroundColor('#E5E7EB')
        .fontColor('#333333')
        .onClick(() => this.onNext())
    }
  }
}

// ===== 页面：数据的主人 =====
@Entry
@Component
struct MusicPlayer {
  @State isPlaying: boolean = false
  @State @Watch('onVolumeChanged') volume: number = 40
  @State submittedRating: number = 0

  onVolumeChanged() {
    // 副作用示例：真实项目里这里是 Preferences 存盘
    console.log(`[持久化] 音量=${this.volume}`)
  }

  playNext() {
    console.log('播放下一首')
    this.isPlaying = true
  }

  build() {
    Column({ space: 24 }) {
      Text('🎵 正在播放')
        .fontSize(13)
        .fontColor('#007DFF')

      SongInfo({ title: '晴天', artist: '周杰伦' })

      VolumePanel({ volume: $volume })          // @Link：注意 $

      RatingStars({
        rating: this.submittedRating,           // @Prop：草稿起点
        onSubmit: (rating: number) => {
          this.submittedRating = rating         // 回调：结果交回数据主人
          console.log(`评分已提交：${rating} 星`)
        }
      })

      Text(`已提交评分：${'★'.repeat(this.submittedRating) || '暂无'}`)
        .fontSize(13)
        .fontColor('#999999')

      Button('重置评分')
        .height(30)
        .fontSize(13)
        .backgroundColor('#F1F3F5')
        .fontColor('#666666')
        .onClick(() => {
          this.submittedRating = 0              // 父值一变，@Prop 草稿被覆盖
        })

      Blank()

      ControlBar({
        playing: this.isPlaying,
        onToggle: () => {
          this.isPlaying = !this.isPlaying      // 决策在页面
        },
        onNext: () => {
          this.playNext()
        }
      })
    }
    .padding(24)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
  }
}
