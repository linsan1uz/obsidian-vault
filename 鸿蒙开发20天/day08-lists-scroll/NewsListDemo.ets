// Day 8 综合示例：资讯页头部
// = Swiper 轮播（课时1）+ Refresh 下拉刷新 / 上拉加载（课时2）+ LazyForEach 懒加载列表（课时3）
// 替换进工程的 Index.ets 直接运行

// ============================================================
// 数据源：IDataSource 合同实现（写在 struct 外面，仓库归仓库）
// ============================================================
class NewsSource implements IDataSource {
  private news: string[] = []
  private listeners: DataChangeListener[] = []     // 登记在册的"订货员"

  // —— 合同规定的 4 项义务 ——
  totalCount(): number {
    return this.news.length                        // 总共多少件货
  }
  getData(index: number): string {
    return this.news[index]                        // 给我第 index 件
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {    // 没登记过才登记
      this.listeners.push(listener)
    }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)                // 退订：删 1 个
    }
  }

  // —— 自定义进货方法：进完必须广播 ——
  reloadAll(data: string[]): void {                // 整批换新（下拉刷新）
    this.news = data
    for (const l of this.listeners) {
      l.onDataReloaded()                           // 广播：库存全刷新了
    }
  }
  addMore(data: string[]): void {                  // 追加（上拉加载）
    const start: number = this.news.length
    this.news = this.news.concat(data)
    for (const l of this.listeners) {
      l.onDataAdded(start, data.length)            // 广播：从 start 起新增 N 条
    }
  }
}

// ============================================================
// 页面
// ============================================================
@Entry
@Component
struct Index {
  // 轮播数据（课时1）
  @State banners: string[] = ['头条要闻', '科技数码', '财经热点']
  @State bannerColors: string[] = ['#FF6B6B', '#4ECDC4', '#45B7D1']

  // 仓库：普通成员即可，不需要 @State（驱动界面的是广播）
  private source: NewsSource = new NewsSource()

  // 界面状态（课时2 三道防线 + 刷新圈）
  @State isRefreshing: boolean = false
  @State isLoadingMore: boolean = false
  @State page: number = 0
  @State hasMore: boolean = true
  private counter: number = 0                     // 全局编号，保证 key 唯一（普通成员）

  aboutToAppear(): void {
    this.source.reloadAll(this.makeNews(10))       // 首屏 10 条 = 第一次进货
  }

  // 造一页数据（模拟服务器返回）
  makeNews(count: number): string[] {
    const arr: string[] = []
    for (let i = 0; i < count; i++) {
      this.counter++
      arr.push(`新闻 #${this.counter}`)
    }
    return arr
  }

  // ===== 下拉刷新：重置回第一页 =====
  refresh(): void {
    setTimeout(() => {                             // 模拟网络：1 秒后数据才回来
      this.counter = 0
      this.page = 0
      this.hasMore = true
      this.source.reloadAll(this.makeNews(10))     // 进货 + 广播（替换原来的整体赋值）
      this.isRefreshing = false                    // 收圈！！不写它圈永远在转
    }, 1000)
  }

  // ===== 上拉加载：三道防线 =====
  loadMore(): void {
    if (this.isLoadingMore || !this.hasMore) {     // 门卫：锁关着或没数据 → 回家
      return
    }
    this.isLoadingMore = true                      // 上锁
    setTimeout(() => {                             // 1 秒后"数据回来了"
      this.source.addMore(this.makeNews(10))       // 进货 + 广播（替换原来的 push）
      this.page++
      if (this.page >= 3) {
        this.hasMore = false                       // 模拟：3 页后到底
      }
      this.isLoadingMore = false                   // 解锁
    }, 1000)
  }

  build() {
    Column() {

      // ========== 上：Swiper 轮播（课时1） ==========
      Swiper() {
        ForEach(this.banners, (title: string, index: number) => {
          Column() {
            Text(title)
              .fontSize(24)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.bannerColors[index])
          .justifyContent(FlexAlign.Center)
        }, (title: string, index: number) => `${index}-${title}`)
      }
      .width('100%')
      .height(160)
      .autoPlay(true)
      .interval(2000)
      .loop(true)
      .indicator(                                   // 新版 DotIndicator 链式写法（旧对象写法已废弃）
        new DotIndicator()
          .color('#80FFFFFF')                       // 未选中：半透明白（#AARRGGBB 透明度在前）
          .selectedColor(Color.White)               // 选中：纯白
      )
      .onChange((index: number) => {
        console.log(`轮播翻到第 ${index + 1} 页`)
      })

      // ========== 下：Refresh 皮 包住 List 骨 ==========
      Refresh({ refreshing: $$this.isRefreshing }) {
        List() {
          // 懒循环：只创建看得见的条目
          LazyForEach(this.source, (item: string, index: number) => {
            ListItem() {
              Text(item)
                .width('100%')
                .height(64)
                .fontSize(16)
                .padding({ left: 16, right: 16 })
                .backgroundColor(index % 2 === 0 ? '#F5F5F5' : '#FFFFFF')
                .margin({ top: 1 })
            }
          }, (item: string, index: number) => `${index}-${item}`)

          // List 的孩子必须是 ListItem——if 里面也要包！
          if (this.isLoadingMore) {
            ListItem() {
              Text('⏳ 加载中…')
                .width('100%')
                .height(48)
                .textAlign(TextAlign.Center)
                .fontSize(14)
                .fontColor('#999999')
            }
          }
          if (!this.hasMore) {
            ListItem() {
              Text('— 已经到底啦 —')
                .width('100%')
                .height(48)
                .textAlign(TextAlign.Center)
                .fontSize(14)
                .fontColor('#999999')
            }
          }
        }
        .width('100%')
        .onReachEnd(() => {
          this.loadMore()                           // 挂钩子：滚到底 → 加载下一页
        })
      }
      .width('100%')
      .layoutWeight(1)
      .onRefreshing(() => {
        this.refresh()                              // 松手 → 刷新
      })
    }
    .width('100%')
    .height('100%')
  }
}
