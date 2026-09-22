# 鸿蒙应用开发 · 20 天学习计划

> **前置要求**：已学完 ArkTS 语言基础（基本类型、函数、类/接口、泛型、装饰器、async/await）✅
> **目标**：20 天后能独立设计、开发、调试一个完整鸿蒙 App，并了解打包上架流程
> **环境**：DevEco Studio（最新版）+ Previewer / 模拟器 / 真机（HarmonyOS NEXT，API 12+）

---

## 学习方式（先读这个）

1. **每天 = 一课**：读当日课程 → 跟着敲一遍示例 → 独立完成作业。
2. **作业交给我 review**：把代码贴给我，我帮你点评、指出坏味道、给优化版。
3. **卡住就问**：编译报错、预览器异常、概念不懂，直接把报错信息贴过来。
4. **节奏建议**：每天 1.5~2.5 小时，20% 读课、60% 动手写、20% 复盘。宁可少学点，别跳过动手。
5. **每周一个里程碑项目**，做完才算该周过关。
6. 课程文件都在本目录下：`dayXX-xxx/lesson.md`，示例代码在同目录 `.ets` 文件里。

---

## 四个阶段

| 阶段 | 天数 | 内容 | 里程碑 |
|------|------|------|--------|
| 一、ArkUI 基础 | Day 1–7 | 声明式UI思想、基础组件、布局体系、@State状态管理、事件手势 | 计算器 |
| 二、ArkUI 进阶 | Day 8–13 | 列表与性能、自定义组件、导航、弹窗、动画、资源与一多适配 | 资讯浏览页 |
| 三、应用核心能力 | Day 14–17 | Stage模型/UIAbility、网络请求、数据持久化、全局状态 | 联网+存储 Demo |
| 四、项目实战 | Day 18–20 | 综合项目：架构 → 实现 → 打磨 → 打包上架 | 完整 App |

---

## 每日课程表

### 阶段一 · ArkUI 基础（Day 1–7）
- [x] **Day 1** ArkUI 与声明式 UI · 工程结构 · 第一个页面（@Entry / @Component / build · Text / Image / Button）→ `day01-hello-arkui/`（作业暂缓，随时可补）
- [x] **Day 2** 常用基础组件：TextInput / Toggle / Slider / Progress / Radio / Checkbox · 通用属性体系 → `day02-basic-components/`（作业暂缓）
- [x] **Day 3** 线性布局 Column / Row：主轴交叉轴 · justifyContent / alignItems · space 间距 · layoutWeight 权重 · 嵌套实战 → `day03-linear-layout/`（作业暂缓）
- [x] **Day 4** 其余布局：Stack 层叠 · Grid 网格 · List 列表 · RelativeContainer 相对布局 · position 绝对定位 → `day04-more-layouts/`（作业暂缓）
- [x] **Day 5** 状态管理（上）：@State 深入 · UI 刷新机制 · if/else 条件渲染 · ForEach 循环渲染 → `day05-state-basics/`（作业暂缓）
- [x] **Day 6** 状态管理（下）：@Prop / @Link 父子通信 · @Watch 监听 · 自定义组件拆分 → `day06-state-communication/`（作业暂缓）
- [ ] **Day 7** 事件与手势：onClick / onChange / onScroll · Tap / Pan / LongPress 手势 · 🏁 里程碑：**计算器** → `day07-events-gestures/`

### 阶段二 · ArkUI 进阶（Day 8–13）
- [ ] **Day 8** 列表与滚动：Scroll / Swiper 轮播 / Refresh 下拉刷新 · LazyForEach 与 IDataSource · 列表性能要点
- [ ] **Day 9** 自定义组件进阶：@Builder / @BuilderParam · @Styles / @Extend · @Require · @Reusable · 泛型组件
- [ ] **Day 10** 页面导航：Navigation + NavPathStack 体系 · NavDestination 页面 · 参数传递 · Tabs 多页签框架
- [ ] **Day 11** 弹窗与菜单：AlertDialog · @CustomDialog 自定义弹窗 · bindMenu / bindPopup · promptAction（Toast）
- [ ] **Day 12** 动画：animateTo 显式动画 · animation 隐式动画 · transition 转场 · 关键帧与插值曲线
- [ ] **Day 13** 资源与适配：resources 规范（string / color / media）· 国际化 · 深色模式 · 断点+栅格"一多"适配 · 🏁 里程碑：**资讯浏览页**

### 阶段三 · 应用核心能力（Day 14–17）
- [ ] **Day 14** Stage 模型：应用/模块/Ability 概念 · UIAbility 生命周期 · module.json5 配置 · 权限申请
- [ ] **Day 15** 网络请求：@ohos.net.http · 封装统一请求层 · JSON 解析成模型类 · 加载态与错误处理 · Web 组件
- [ ] **Day 16** 数据持久化：Preferences 用户首选项 · RelationalStore（SQLite）· 文件 fs · 持久化选型
- [ ] **Day 17** 全局状态：AppStorage / PersistentStorage / Environment · @Observed / @ObjectLink · V2 状态管理（@Local / @Param / @Trace）与选型 · 🏁 里程碑：**联网+存储 Demo**

### 阶段四 · 项目实战（Day 18–20）
- [ ] **Day 18** 实战（上）：需求分析 · 分层架构（models / services / views）· 页面流与导航框架
- [ ] **Day 19** 实战（中）：接入真实网络数据 · 本地持久化 · 全局状态贯通
- [ ] **Day 20** 实战（下）：动效与体验打磨 · 适配检查 · 签名打包 HAP/App · 上架流程概览 · 🏁 **总结 + 进阶路线**

> 实战项目建议：**鸿蒙记账本**（启动页 + 记账表单 + 账单列表 + 月度统计 + 设置页），能覆盖全部知识点。想换个题材（如任务清单、笔记、天气）开课前告诉我即可。

---

## 课程文件存放与远程同步（Day 3 起生效）

- **课程主副本**：Obsidian 库 `D:\Documents\Obsidian Vault\鸿蒙开发20天\`（GitHub 远程：obsidian-vault，main 分支）
- **每日流程**：新课程文件直接写入该目录（`dayXX-xxx/dayXX-标题.md` + 同目录示例 `.ets`）→ 用 Obsidian MCP 的 `sync_github` 提交并推送；工作区 `harmonyos-20days\` 保留一份镜像和本进度索引
- **MCP 会话过期的恢复方法**：向 `http://127.0.0.1:27123/mcp` POST `initialize`（不带 mcp-session-id 头；Bearer token 见 ZCode 配置 `cli/config.json` 的 `mcp.servers.obsidian`，勿写入任何同步文件），从响应头取新 `mcp-session-id`，随后调用 `sync_github`

## 环境准备（Day 0，一次性，没装环境先做这个）

1. 注册华为开发者账号，从官网 developer.huawei.com 下载安装 **DevEco Studio**。
2. 新建工程：`File → New → Create Project → Application → Empty Ability`（Stage 模型，API 选默认最新）。
3. 三种运行方式，建议都配好：
   - **Previewer 预览器**：最常用，写 UI 靠它，秒级预览；
   - **模拟器**：Device Manager 里下载（Windows 需在 BIOS 开启虚拟化）；
   - **真机**：手机开启开发者模式 + USB 调试。
4. 安装/运行遇到问题把报错贴给我。

## 学习资料

- 官方文档（最权威）：developer.huawei.com/consumer/cn/doc/ →「HarmonyOS 应用开发指南 → UI 开发（ArkUI 声明式开发范式）」
- 官方 Codelabs 实战教程：developer.huawei.com/consumer/cn/codelabs/
- 学完后建议去考：**鸿蒙应用开发者基础认证**（免费，求职有用）

## 当前进度

- ✅ Day 1 概念课完成（作业暂缓，随时可补交）→ `day01-hello-arkui/day01-arkui与声明式ui-第一个页面.md`
- ✅ Day 2 课程完成（作业暂缓）→ `day02-basic-components/day02-常用基础组件-输入开关与进度.md`
- ✅ Day 3 课程完成（作业暂缓）→ `day03-linear-layout/day03-线性布局-column与row.md`
- ✅ Day 4 课程完成（作业暂缓）→ `day04-more-layouts/day04-其余布局-stack-grid-list与相对定位.md`
- ✅ Day 5 课程完成（作业暂缓）→ `day05-state-basics/day05-状态管理上-state刷新机制-if与ForEach.md`
- ✅ Day 6 课程完成（作业暂缓）→ `day06-state-communication/day06-状态管理下-父子通信与组件拆分.md`
- ➕ Day 6 另有 5.3flash 重写版（换"点单页"贯穿案例讲解，与初版对照阅读）→ `day06-state-communication/day06-状态管理下-父子通信与组件拆分-5.3flash.md` + `OrderDemo-5.3flash.ets`
- ➕ Day 6 另有 5.3 独立版（"音乐播放页"贯穿案例，自成一篇）→ `day06-state-communication/day06-状态管理下-父子通信与组件拆分-5.3.md` + `MusicPlayerDemo-5.3.ets`
- ✅ Day 7 课程已发布（事件与手势 + 计算器里程碑）→ `day07-events-gestures/day07-事件与手势.md` + `GestureLab.ets` + `Calculator.ets`
- ⬜ 等你交作业（Day 2~7 均可补）
