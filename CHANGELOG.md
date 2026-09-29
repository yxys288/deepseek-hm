# DeepSeek 鸿蒙端（deepseek-hm）· 变更史（第一轮 ~ 第十九轮）

> ⚠️ **开源发布说明**：本文件由工程内部文档整理而来。「内部验证记录」= 开发期的验证证据目录
> （整机截屏 / CDP 探针 / `dumpLayout` 读数，**未随本仓库发布**）；「内部踩坑表 `§3.0-N`」=
> 开发工作区的跨工程通用踩坑表编号（同样未随本仓库发布），编号保留以便与本项目内部记录对照。

> **现状**看 `PROJECT.md`；**踩坑细节与验证脚本手册**看 `EXPERIENCE.md`。
>
> **历史路径说明**：本文件与各 `内部验证记录\README.md` 的原始记录写于 2026-09-11 迁移之前，
> 当时的工程根目录就是现在的仓库根目录；
> 证据目录里的旧路径为保持历史原貌**保留原样**，本文件的命令与路径已更新为新路径。
>
> **已删除的验证残留**：迁移前工程内 `verify\`（headless 浏览器 profile `verify\.cdp-*`，约 15302 个文件、
> 共 2.6GB）、`preview\`、`entry\.preview`、`iconwork\.tmp1-4`、`Index.ets.disabled`、
> `.hvigor` / `.idea` / `entry\build`，以及 `内部验证记录` 下 **99 个 `blurtest*` 实验截图**
> （该目录保留 `build-*.log` 与 `p*.js` 探针、部分对照截屏）均**已于 2026-09-11 整理时删除**。
> 因此下文提到的 `verify/*.js` 排障脚本只存在于历史记录中，不在仓库内；现行脚本请用
> `内部验证记录\` 下的版本（见 `EXPERIENCE.md` §2）。
>
> 轮次口径：**第一轮** = 2026-09-05 上午首次真机冒烟；之后每轮对应一次「需求 → 改动 → 验证」。
> **第十二轮是整理轮**（2026-09-11：迁移与瘦身），没有独立的用户需求与验收读数，但占用一个轮号，
> 因此轮号从第一轮到**第十九轮**连续无断号（早期本文件把它记作「第十二轮之后」，已订正）。
> 各轮与旧版 `PROJECT.md` 的 §6~§15 一一对应（旧版现状文档已重写为现行 §1~§13）。

## 第一轮（2026-09-05 上午）：纯 ArkWeb 容器 + 沉浸光感首次真机冒烟

- 形态：`pages/WebPage` 单页 ArkWeb 容器——加载 `https://chat.deepseek.com/`，
  `setWindowLayoutFullScreen` + 透明系统栏 + 网页安全区避让，打开即聊天页（无原生首页）。
- 内容：深色模式跟随（`WebDarkMode.Auto` + `onConfigurationUpdate` 校验
  `prefers-color-scheme`，不一致 `refresh()`）、服务卡片（2x2/2x4/4x4）、
  错误页（`ImmersiveMaterial` 光感重试按钮）、返回键双击退出、下载推广入口隐藏。
- 方式：DevEco 构建 → 真机安装 → 目视 + 截屏留档。
- 证据：`真机整屏留档（截图未随仓库发布）`（真机整屏留档）；
  形态说明另见 `README-source.md`。

## 第二轮（2026-09-05）：侧栏进场动画闪烁根治 + 首页入口隐藏

**需求**：打开侧栏瞬间闪一下；首页右上角多余的「新建对话」与顶栏「下载应用」要清掉。

**怎么定位的**：命令行构建 → `hdc install -r` → ArkWeb DevTools（`hdc fport` + CDP
`Runtime.evaluate`）逐帧取证 + DOM 归因。

- 真机 PLB/PLA-AL10（Mate 70 系列）、OpenHarmony 7.0.0.105 / API 26、序列号 `DEVICE_SN_REDACTED`。
- 逐帧采样定位到三类跳变：底部 sheet 进场动画 0.2s 而几何修正走 200ms 防抖（动画播完才跳）；
  左侧抽屉 `.dc04ec1d` 的 `padding-top` 只在防抖链路里（t=64~365ms `padT=0` → t=765ms 跳变 52px）；
  关闭态 `width=0` 触发过 `width<120` 下限误拒。
- 修法：**CSS 首帧规则**（`injectStyle()` 内 `@media not all and (min-width:768px)` 下
  `.dc04ec1d { padding-top: 状态栏+6 !important; border-radius: 0 24px 24px 0 !important }`），
  零 JS 时序依赖；JS 快速路径降为类名改版兜底。
- 首页入口：官方 2026-09 改版后 `[aria-label]` 数量为 0 → 改**几何兜底**（顶部 ≤90px、
  右侧 110px 内、16..72px 方形、无文本、非推广、不在侧栏内，取最右）；
  官方框架会在 ~4ms 内恢复 inline style → 改 `data-dsh-home-hidden` / `data-dsh-promo`
  标记 + `!important` 样式表压制。
- 修复验证（真机 CDP）：冷态开侧栏 rAF 逐帧 `t=83→363ms`（left −261→0）全程
  `padT=51.71px`、圆角 `0/24px` 恒定、零跳变帧；⊕ 与「下载应用」胶囊均 `display:none`；
  会话页 `/a/chat/s/<id>` 的 ⊕ 与分享保留；发消息 → AI 回复（含深度思考）正常。
- 排障脚本沉淀（**已于 2026-09-11 随 `verify\` 一起删除**）：`flicker-probe.js`（rAF 逐帧）、
  `frame-truth.js`（inline/computed 同帧）、`mutation-trace.js`（突变流）、
  `regression-final.js`、`syntax-check.js`。
- 证据：截屏 `v-home.jpeg` / `v-side.jpeg` / `v-chat.jpeg`（原在已删除的 `verify\` 内）；
  第一轮留档 `真机整屏留档（截图未随仓库发布）`。

## 第三轮（2026-09-05）：原生化外壳升级 + 流畅性优化（模拟器冒烟）

**需求**：把外壳"原生化"——品牌 splash、错误页、返回键、卡片配色，并让适配器少做无用扫描。

- 方式：子 Agent 编码（外壳/卡片 + 脚本门控并行）→ 主 Agent 构建 → 模拟器
  `Pura 90 Pro`（emulator 7.0.0.105）冒烟 + CDP 断言；BUILD SUCCESSFUL 无告警。
- 改动：`pages/WebPage.ets` 颜色全资源化（删 `isDarkMode` 三元）、品牌 splash
  （startIcon 72vp + 应用名 + `LoadingProgress`，`loading` 期间全覆盖、结束**瞬时**移除）、
  错误页重排（SymbolGlyph + 分层文案 + 沉浸光感按钮 h40/f15）、返回键双击退出；
  `widget/pages/WidgetCard.ets` 硬编码色换 `$r`、'D' 字母色块换品牌图标；
  `utils/DeepSeekConfig.ets` 加 **2s 巡检门控**（`domMutationCount` / `lastPatrolCount=-1` /
  `patrolTicks`，页面静默时跳过全文档扫描，每 15 tick ≈30s 强制全查安全网）。
- 关键修复：**`onErrorReceive` 必须 `isMainFrame()` 过滤**——网络抖动期任一子资源失败
  （如 `ERR_INTERNET_DISCONNECTED`）会把已加载好的整页盖成错误页。
- 冒烟结果（全部通过，9 张截屏）：品牌 splash（深色 bg `#0B1220` 正确）、首页渲染
  （推广隐藏 2 处、⊕ 几何兜底隐藏、状态栏避让）、侧栏左抽屉（`padT=44.86px` 恒定、
  内侧 24px 圆角、零闪烁）、深色冷启动连续 3/3 稳定、深→浅热切换、断网错误页、
  返回键 Toast→2s 内二次退出、服务卡片（深浅色资源 + 品牌图标 + `onNewWant` 拉起新对话）。
- CDP 断言 `SMOKE-CDP: PASS`（`adapterActive` / `homeHidden=1` / `promo=2` / `drawer=left` /
  `viewport-fit=cover` / insets 注入 / `aria-label=0` 印证几何兜底是唯一有效路径）。
- 真机复核（15:59 构建，320,437 B，`install -r` 保留登录态）：浅色首页完整、侧栏左抽屉形态、
  深色像素采样全屏均匀 `rgb(27,27,27)`（**无模拟器上的黑屏+残带故障**）、返回键双击退出一致。
- 证据：`内部验证记录`（9 张截屏 + `cdp-smoke.mjs`；
  该目录**无 README.md**，口径见本节）。

## 第四轮（2026-09-07）：透底闪屏根治 + 侧栏开关悬浮圆框（模拟器）

**需求**：用户仍报"打开侧栏闪屏"——第三轮修的是几何跳变，这是第三种闪烁。

- 逐帧取证（t=118→460ms）真身：官方打开动画给抽屉**面板子元素**（`b8812f16 a2f3d50e`，
  不透明底色、h=765）挂 `opacity 0→1` 交叉淡入约 300ms，而**抽屉根元素背景透明** →
  滑动全程主页面内容（问候语/模式胶囊/输入框）从侧栏里透出来叠影
  （设备级截屏 `01-before-midslide-ghost.jpeg` 实锤：侧栏区混入 `rgb(33,33,33)`/`rgb(28,19,12)`）。
  旧几何采样只盯 rect/padT/圆角，看不见纯 opacity 变化。
- 修法（零 JS 时序依赖）：`syncDrawerBackdrop()` 把面板子元素的不透明底色与根 `padding-top`
  抄成根元素 CSS 自定义属性 `--dsh-drawer-bg` / `--dsh-drawer-padtop`，注入
  `[data-dsh-drawer][style*="--dsh-drawer-bg"]::before { top: var(--dsh-drawer-padtop);
  background: var(--dsh-drawer-bg); border-radius: inherit }`——根元素**首帧起**不透明。
  属性选择器 `[style*=...]` 保证只影响抄过色的根元素，不误伤同样带标记的内层列。
- 侧栏开关"透明悬浮圆框"：`markSidebarToggleButtons()` 按几何+结构打 `data-dsh-floatbtn`，
  注入 `::after`（`inset:-4px` → 用户反馈偏大后改 `-2px`，1px 环 + 半透明磨砂底 +
  `backdrop-filter: blur(10px) saturate(1.4)` + 柔影）；**关键层叠配方**：按钮 `z-index:0`
  自成层叠上下文、`::after z-index:-1` 沉到图标与官方 `.ds-button__background` 光效层之下，
  `:active::after { scale(0.9); opacity:.72 }`。
- 接线加固：`installPanelObserver()` 此前**定义了但从未调用**（`[BISECT]` 临时态遗留），
  已接到 `run()`；观察器实例挂 `window.__dshPanelObserver` / `__dshMainObserver` 跨注入复用。
- 铺底与"避让后顶部圆角"的两次返工（详见 `EXPERIENCE.md` §1.2）：border-box 铺底把圆角顶到屏幕顶、
  content-box 又把圆角吃掉 → **终版用 `::before` 独立伪元素铺底**。
- 冒烟 `SMOKE-2026-09-07: PASS`（`adapter` / `mainObs` / `panelObs` / drawer 标记 / 底色变量 /
  `padT=44.86` / 圆角 24 / `promo=2` / `homeHidden` 路由可逆 / `floatBtns>=1` / `viewport-fit` /
  零 JS 异常）；深浅切换实测 `rgb(27,27,28)↔rgb(249,250,251)` 自动重同步。
- 证据：`内部验证记录`（修复前后 mid-slide 截屏、圆框特写、
  会话路由、`frame-probe.mjs` + `smoke-assert.mjs`）。

## 第五轮（2026-09-10）：原生外壳重写 + 侧边栏卡顿根治（模拟器）

**需求**：①「用官方原生组件重写软件」②「解决侧边栏打开时卡顿」。
**方案**：**B 档 —— 原生 ArkUI 外壳 + ArkWeb 聊天区**（保留网页登录态与云端历史）。

- **卡顿根因（代码级定位，非猜测）**：不是网页动画慢，而是旧适配器在侧栏开合动画（约 0.3s）
  期间对抽屉子树做同步排版测量——`panelObserver → handlePanelMutation → fastCheckNode()`
  逐节点交替 `getComputedStyle()` + `getBoundingClientRect()`（layout thrashing），
  叠加 `scheduleFixedCleanup() → adjustFixedPanels()` 的 `querySelectorAll('body *')`
  全文档扫描。前三轮修的是「闪烁」（几何跳变 + 透底叠影），**卡顿是第三种症状**。
- 架构：`Index.ets(@Entry)` → `SideBarContainer(Overlay, sideBarWidth '80%')`
  ├ `SidePane`（DeepSeek 标题 + ⊕ + 分组会话 List + 计数/刷新）
  └ `MainPane(Stack)`[`Column[原生 TopBar, Web]` + Splash/ErrorPane + Scrim]。
  路由驱动顶栏形态：`home` (`/`) → ☰；`chat` (`/a/chat/s/*`) → ☰ + ⊕ + 分享；其它子页 → ← + 标题。
- 数据链路：网页 → 原生 `javaScriptProxy({object: bridge, name:'dshBridge', methodList:['post']})`
  上报 `sessions` / `route` / `ready`；原生 → 网页 `runJavaScript('window.__dshShellApi.openSession(id)')`
  （`openSession` / `newChat` / `back` / `rescan` / `reveal`）。
  抽取通道：已知类名（`._519be07` / `.dc04ec1d`）→ 几何兜底 → 锚点 `a[href*="/a/chat/s/"]`
  → **UUID 属性兜底 `extractByAttr`**；分组用 `TreeWalker` 顺序遍历归组（**零几何读取**）。
- **官方抽屉只作数据源**：`visibility:hidden`（**不能 `display:none`**，要保住 DOM 与布局），
  由桥脚本打 `data-dsh-hide-drawer`；官方侧栏永不真正打开。
- 流畅性改造 5 条：①**抽屉子树整体短路** `inNativeDrawer(el)` =
  一次 `window.__dshNativeDrawer.contains(el)`，在所有热路径前置返回；
  ②`__dshShellOwnsChrome` 门控让推广隐藏/几何兜底/圆框打标整块跳过；
  ③全文档选择器由 `body *` 收窄为 `div, aside, nav, section, header, footer, main`；
  ④下线 `markSideDrawers()`；⑤加轻量性能探针 `window.__dshPerf`
  （`fastNode` / `drawerSkip` / `fixedScan` / `homeScan`）+ `__deepseekHmPerfReset()`，
  把"卡顿有没有修掉"变成可回归断言的数字。
- 验证（模拟器 Pura 90 Pro / HarmonyOS 7.0.0.105，BUILD SUCCESSFUL 0 error / 0 warning）：
  CDP `shellAlive/apiReady/bridgePresent/adapterActive` 全 true、
  `bodyPadTop=90.86px` = 状态栏 38.86 + 顶栏 52、零 JS 异常。
  **卡顿量化（同构建内合成抽屉替身 A/B，约 130 节点）**：
  `fastNode 124 → 0`、`drawerSkip 0 → 129`；设备实测原生侧栏"开→关→再开"
  网页侧 `__dshPerf` 增量恒为 0（原生侧栏开合完全不触碰网页）。
- **未闭环（如实记录）**：模拟器登录态失效（停在 `/sign_in`），会话列表用"合成抽屉替身"
  覆盖同一条代码路径验证，**未在真实登录态下验证官方 DOM 锚点选择器** → 第六轮闭环。
- 证据：`内部验证记录`
  （7 张截屏 + 4 个脚本 + 性能读数 + 验证口径与未闭环项）。

## 第六轮（2026-09-10）：真机验证 + 三个真机缺陷修复 + UI 优化（真机）

**环境**：HUAWEI Mate 70 Pro+（PLA-AL10 / `DEVICE_SN_REDACTED`），HarmonyOS 7.0.0.105 / API 26，
1316×2832、`dpr=2.975`、CSS 视口 `443×855`；HAP 428,629 B。
**口径**：§第五轮的结论来自模拟器；本轮全部来自真机——下面是"只跑模拟器一定会漏掉"的那一类。

**闭环上一轮未闭环项**：真实账号下锚点通道 `a[href*="/a/chat/s/"]` 命中 **53 条真实会话**
（中文标题逐字正确），**UUID 兜底通道未启用**；分组 `今天` / `7 天内` / `30 天内` 全识别；
官方抽屉真身 `position:fixed`、关闭态 `left=-261 width=0 height=855`（**不能用宽度/left 判存在**）；
点原生侧栏会话 → 网页 `location.pathname` 切到 `/a/chat/s/<id>`、
`__dshNativeShell.taps` 递增 → 隐藏抽屉内 `visibility:hidden` 元素的事件派发链路在真机成立。

**真机发现并修复的三个缺陷（模拟器全部看不见）**：

1. **严重：官方顶栏从来没被隐藏过**（真机上原生顶栏下方多出一整排官方图标并压住内容）。
   两处判据各自早退叠加：`findSidebarToggle()` 只挡右侧、**负坐标直接放行** → 选中抽屉里
   `left=-198` 的按钮（文档顺序还排在顶栏之前）；`findTopBar()` 从它往上走撞不到
   `height<=130` 的容器 → 返回 `null`；即便找对，`findTopBar()` **在第一个匹配处早退**也错——
   官方横条是"外层占位容器 `DIV[_2be88ba] 443x60`（在流内）套内层 `the-header`"，
   只隐藏内层 → 外层 60px 占位仍在流内（实测隐藏内层后 scroller 恒为 `0,60 443x762`）。
   修法：开关判据加"排除抽屉子树 + 真正在屏内（`left>=0`、`right<=innerWidth+4`、`bottom>0`）"；
   `findTopBar(btn)` 改**取最外层匹配祖先**（走满 8 跳保留最后一个匹配）；宽度阈值放宽到 `0.8*innerWidth`。
   修后 `hiddenTopbarNodes=1`、`shellOwnsChrome=true`。
2. **`prewarm()` 被自己的修复打瞎**：顶栏 `display:none` 后几何判据必然失效 →
   修法 `markShell()` 把开关引用留在 `state.toggle`，`prewarm()` 优先复用。
3. **搜索后点会话键盘不收起**：面板关了但原生 `TextInput` 仍持焦点 →
   `closeSidebar()` 统一收口（`sidebarOpen=false` + `getUIContext().getFocusController().clearFocus()`），
   `openSession` / `doNewChat` / `revealOfficialSidebar` / 遮罩点击 / `onBackPress` 全走它。
   附带修 `SidePane` 底部行：`.height(36).padding({bottom: bottomInset})` → `.height(36 + bottomInset)`
   （ArkUI 的 padding 在 height **之内**，手势条高度会把文字压扁）。

**UI 优化**：首页顶栏标题固定 `DeepSeek`（官网 title 是 slogan，真机塞满顶栏）；
对话页标题优先取侧栏会话标题；顶栏底加 0.5vp 分隔线；原生侧栏搜索
（`TextInput` + `visibleRows()` 内存过滤 + `xmark_circle` 清空，实测 `ok` → 命中"回复ok"、
`python` → 10 条）；打开侧栏 `scrollToIndex(idx,false,ScrollAlign.CENTER)` 延时 220ms 定位当前会话；
每次打开清空筛选。

**性能 A/B（真机、真实触摸、同构建）**：`fastNode 636 → 0`、`fixedScan 1082 → 204`，零 JS 异常。
脚本 `shell-assert-real.mjs` 由第五轮脚本移植，**并修正了它自己带的同一个负坐标判据 bug**
（旧版返回抽屉内 `x=-181` 的点，`dispatchTouchEvent` 打在屏外 → A/B 两相皆 0 却判 PASS）。

**其余回归全通过**：启动无白带、`--ps colorMode dark|light` 双值资源、返回键只关侧栏、
`reveal()` 交还官方外壳（`hiddenTopbars=0`）并可再 `rescan(true)` 接管、
删 `entry\build` 后干净重建 33 tasks **0 error / 0 warning**。
**操作事故**：本轮开始时为规避签名不一致先跑了一次 `hdc uninstall`，**把真机登录态清掉**，
后续靠用户重新登录补齐（教训：覆盖安装一律 `install -r`）。

- 证据：`内部验证记录`
  （18 张截屏 + 10 个探针 + `perf-evidence.txt` 原始读数）；同日"第 7 次"真机复跑留档在
  `内部验证记录`（13 图 + `layout70x.json` + `perf-ab-round7.txt`，`SHELL-2026-09-10: PASS`，
  口径同第六轮）。

## 第七轮（2026-09-10）：侧栏重构 + 三重避让 + UI 圆角（模拟器）

**需求**：重构侧边栏，做好避让与 UI 圆角。用户已拔出真机，按目录规则回退模拟器
（`Pura 90 Pro`，`dpr 3.5` → 视口 376×719 CSS px）。

- **重构**：新增 `view/SidePane.ets`（`@Component export struct SidePane`），
  `pages/Index.ets` **811 → 668 行**；契约 = 数据与回调进、无副作用出
  （父→子 `panelOpen`/`sideRows`(@Prop+@Watch)、`totalCount`/`topPad`/`bottomPad`/`keyboardPad`；
  子→父 `onOpenSession`/`onNewChat`/`onRefresh`/`onReveal`）；
  **局部状态全部下沉**（搜索词、`Scroller`、"打开即定位"待办标记）。
  第二个收益是**纯 UI 可脱机验证**。
- **三重避让收敛到面板外层一次 padding**（上=状态栏，下=手势条 + **输入法**）：
  `avoidAreaChange` 增加 `window.AvoidAreaType.TYPE_KEYBOARD`（=3，SDK d.ts 实证）→
  `AppStorage['keyboardHeightPx']`，**只给原生侧栏消费**（聊天输入框在网页里，
  改全局 `KeyboardAvoidMode` 会让官方页面二次补偿）。
  实测焦点进搜索框后面板底部锚点 `y 2607 → 1508`（上收 1099px = 314 CSS px，正好一个键盘高）。
- **圆角**：面板贴左、右侧两角 22vp 圆角 + 右侧投影（双值资源 `shell_panel_shadow`）；
  容器 `sideBarWidth('82%')` / `maxSideBarWidth(352)`。
- **验证方法**：登录态失效时官方 DOM 没有会话抽屉、原生侧栏只渲染空态 → 纯视觉没法截屏。
  解法 = **临时预览页** `pages/SidePreview.ets`（假数据 3 组 × 6 条、第 14 条为当前会话、
  避让值取 `AppStorage` 真实上报），**验完三处临时改动全部还原**
  （`loadContent`、`main_pages.json`、`Index` 的 `--ps action openSidebar` 钩子）。
- **两个坑**：①`@Prop` 的 `@Watch` **初始化时不回调**——预览页把 `panelOpen` 初值写 `true` 时
  "清搜索词 + 定位当前会话"永不触发、看起来像功能坏了（夹具必须还原"关→开"时序）；
  ②`/sign_in` 顶栏是 ← 不是 ☰，且有路由守卫（`pushState` 到 `/` 会被弹回），
  模拟器上点不到侧栏入口 → 临时加 `--ps action openSidebar`。
- 结果：构建 0 error / 0 warning；注入脚本预检 `SHELL_JS 549 行 + MOBILE_ADAPTER_JS 1592 行` PASS；
  浅/深面板、定位高亮、输入法避让、真实 `SideBarContainer` 不裁圆角/投影、遮罩点击关闭 全部 ✅；
  `bodyPadTop=90.857`、`vh 719 = 809 − 90.86` 精确吻合。
- **未闭环**：模拟器最终截屏里网页区**纯黑**（同刻 CDP 证明页面完全正常）→ 属模拟器
  ArkWeb 表面合成故障，非本轮引入；**真机未复验本轮改动**（用户已拔机）。
- 证据：`内部验证记录`（13 张截屏）。

## 第八轮（2026-09-11）：磨砂玻璃落地 + 账号页脚/设置入口 + 批量删除 + 色差/深色修正（模拟器）

- **磨砂玻璃的能力验证与 API 选型（本轮最关键结论）**：四种写法逐个实测——
  `backgroundBlurStyle(Regular)` 近乎不透明地把网页盖住；`backgroundBlurStyle(Thin)` 能透出糊状块
  但自带灰调洗白内容；调 `backgroundColor` 的 alpha **完全无效**（`backgroundBlurStyle` 会接管背景填充）；
  **`backdropBlur(radius)` 正确**；最终改用 **`backgroundEffect({radius,saturation,brightness,color})`**
  （`color` 吃 `ResourceColor`、可直接喂双值资源）。像素相关性印证：面板背景亮度与网页内容的
  大半径平滑版相关（0.51 vs 原始 0.11）。
- **顶栏模糊的前提是"下面得有东西可糊"**：旧 `Column{TopBar; Web}` 里顶栏下方是空的 →
  Web **铺满整个窗口** + 顶栏**悬浮覆盖**，网页侧在滚动内容顶部插占位把内容起点推回顶栏下沿。
- 铺满带来的两个坑：①`Stack` 默认 `alignContent: Center`，顶栏被摆到屏幕正中间（必须显式 `Top`）；
  ②**重复补偿**——Web 铺到屏幕最顶后 ArkWeb 开始上报顶部安全区（45.71px），官方 CSS 据此给应用根
  加了同高 `padding-top`，此时自己再补一份就多落后 46px → **占位高度 = topInset − 应用根实际
  `padding-top`**；且占位不能塞进虚拟列表的 `padding-top`（那是虚拟化器自有变量），
  要在滚动容器内、内容容器**之前插兄弟占位**；**没有滚动容器的页面另走一路**（给应用根补 padding）。
- **输入坞下移**：实测距屏底 62px = 5px + **28px 官方免责声明行** + 33px `env(safe-area-inset-bottom)`；
  `.ds-virtual-list { margin-bottom: 12px }` 回收 21px + 免责声明行 padding 6+6 → 2+2 回收 8px
  （合规提示必须保留，只收内边距）→ **62 → 32px**。
- **账号页脚 + 设置入口**：抽屉底部账号行被 `visibility:hidden` 一起藏了 → **原生侧自己画一份**：
  头像 `img[src*="user-avatar"]` 上溯到 `tabindex=0` 的账号行，行内第一个"既不含 img 也不含 svg"
  的有文本子节点即昵称（实测 `爱莫能助`）；**不能按几何找**（关闭态宽度被压成 0）。
  整行点击弹原生 `AlertDialogParamWithOptions`（系统设置/帮助与反馈/退出登录），
  动作是先在网页侧点开官方菜单再按**文案精确匹配**点官方项。
- **会话批量删除（驱动官方 DOM）**：`⋯(_2090548) → 菜单「删除」→ 确认弹窗 ds-modal →
  按钮「删除该对话」(ds-button--error)`，每步给足官方渲染时间（550/800/1100ms），
  **必须由原生侧串行驱动**（发一条 → 等 `{t:'deleted'}` → 再发），另配 8s 单步看门狗。
  **本轮最隐蔽的 bug**：`findRowMoreButton` 早先"从会话锚点向上找行容器、再取容器里第一个按钮"，
  当 `closest('div')` 命中整个列表容器时返回的是**第一行**的按钮 → "删 A"实际删 B，
  而流程一路报成功（表象只是"数量对不上"）；正解 = 从**按钮侧** `closest('a')` 反查归属 +
  结果**存在性校验**（点下去后锚点必须真的消失）。
- **色差修正**（`内部验证记录`）：逐像素比三个值 → 面板 `24,24,26`、顶栏 ≈`24`、
  内容区 **`13,13,15`** = 本色 ×(1−0.45)（自己的 `shell_scrim` 压的）；**面板与顶栏本来同色**，
  遮罩才产生色差线。修法：①遮罩改 `Color.Transparent`（保留 `onClick` 关闭）；
  ②模糊 API 换 `backgroundEffect`（`backdropBlur` 只有 radius/grayscale，而 `grayscale` 是
  "色阶调整"、不是深浅色适配开关）；同时去掉侧栏右下角「刷新」。
  修正后 `x=900..1200` 恒为 `21,21,21`、浅色首页 `(255,255,255)`。
- 证据：`内部验证记录`（四写法对照截屏 + `p13/p15` 占位探针 +
  `p2a~p2i` 页脚/选择/确认/账号菜单/设置面板，批量删除实测锚点 **56 → 54**；构建日志 +
  47 个 `p*.js` 探针，**该目录无 README.md**）、
  `内部验证记录`
  （`r1-*.jpeg` 四张 + 逐像素剖面）；构建 0 error / 0 warning；注入预检 PASS。

## 第九轮（2026-09-11）：真机复核 + 官方抽屉遮罩「灰色蒙层」根因定位与修复（真机）

第八轮的 UI 此前**只在模拟器验过**，真机接回后逐项复核，抓到一个**从第五轮起就潜伏**的缺陷。

- **现象**：冷启动后首页整片发灰——原生顶栏 `235`，网页内容区**均匀 `153`**，文字最暗只到 `139`；
  CDP 单独截网页最亮也只有 `166.67` → 发灰发生在**网页内部**。
- **定位**：`document.elementFromPoint` 命中 `DIV._4cbcd96`：`position:fixed`、整屏 443×952、
  `rgba(0,0,0,.4)`、`z-index:1001`、**`pointer-events:auto`**、无子节点。它是**官方抽屉的遮罩，
  而且是抽屉本体的兄弟节点**——`markShell()` 只给抽屉本体打了标记，漏了兄弟遮罩。
  压掉它后网页最亮 `166.67 → 255`；算术吻合 `255 × 0.6 = 153`。
  两个后果：①整页压暗 40%；②它 `pointer-events:auto`，**真人手指全被它吃掉**
  （合成派发的事件不经过命中测试，所以自动化一路"通过"）。
- **为什么此前没发现**：①合成事件绕过命中测试；②**官方抽屉在本机视口（443×952）下默认就是打开态**
  （`cdp-reload-watch.mjs`：`performance.now()=518ms` 时抽屉已无 `collapsed`、宽 261、遮罩 visible，
  而此时会话链接数还是 0）；③反过来说明 `prewarm()` 那两次 tap 一直是空动作，
  只是被"会话列表 54 条抽到了"这个正常结果掩盖。
- **考古**：对第六轮真机截图重新做像素测量——`内部验证记录`
  面板 `27` / 内容 `12`（差 15 级），而 `21 × 0.6 = 12.6 ≈ 12` →
  "深色面板发灰 + 右缘竖向细线"在第六轮真机就存在；第八轮在模拟器上定位到的是同一根因，
  当时只修了原生侧那半，网页侧这半（官方抽屉自己的遮罩）本轮补齐。
- **修复**（`utils\ShellScript.ets`）：新增 CSS `[data-dsh-hide-scrim="1"]{visibility:hidden !important;
  pointer-events:none !important;}` + `markDrawerScrim(dr)` 扫**兄弟节点**打标
  （判据：兄弟 + `position:fixed` + 覆盖 ≥80% 宽 & ≥50% 高 + **深色半透明底**
  （`rgba` 且 alpha ∈ (0.05,0.95) 且 RGB 均值 < 140）+ 内部无可交互元素/文字；
  辅助函数 `scrimAlpha()` / `isBlankScrim()` **不用正则**，避免模板字面量反斜杠转义）；
  `markShell()` 一起接管、`reveal()` 一并摘标记；冷启动 `grabScrim` 每 120ms 重试（至多 16 次）
  抢首帧（否则固定那几次 rescan 落在 1000ms、冷启动会闪一层灰）；`diag().scrims` 供断言。
  原生侧：`onPickAccountOption` 先 `closeSidebar()` 再回网页侧点官方菜单项
  （不让开时官方设置弹层被原生面板盖住，只剩右半边）。
- **真机复核全通过**：首页最亮 `255` / 均值 `251.1`；**真实触摸可用**
  （`uinput -T -c 660 1476` → `activeElement BODY→TEXTAREA`、视口 `952→583`）；
  真机点发送 → 路由 `/a/chat/s/fad4d2a1-…`、会话 54→55；侧栏表头 `DeepSeek·选择·⊕`（**无「刷新」**）、
  22vp 圆角、面板 `[0,160]..[1047,2705]`；端到端批量删除 `links 55→54`、路由自动回 `/`、
  无残留弹窗、`taps 4→7`；深色页面底 `21,21,23` / 顶栏 `22,22,24` / 面板 `21,21,21`（差 ≤1 级）。
- `shell-assert-2026-09-11.mjs` → `SHELL-2026-09-11: PASS`：`fastNode 603→0`、
  `fixedScan 508→140`、`drawerSkip 0→1754`（与第六轮同量级，卡顿修复未回归），
  新增不变量 `scrimMarked=1` / `scrimHidden=true` / `scrimPE=none` / `hitIsScrim=false`。
  **触发方式必须改**：官方 ☰ 对合成事件完全不响应且抽屉本就打开 → 旧脚本两相都读到 0（假 PASS），
  新脚本改为**直接 add/remove 抽屉的 `collapsed` 类**。
- **遗留**：官方设置弹层打开时其网页 backdrop 只压暗网页内容，原生顶栏仍亮（架构固有取舍）。
- 证据：`内部验证记录`（11 张截屏 + 18 探针）。

## 第十轮（2026-09-11）：侧栏功能逻辑修复 + 磨砂玻璃定标 + 色差边界根治（真机 + 模拟器）

**需求**：①修复侧栏各种功能逻辑问题，尤其"弹窗后是否被覆盖"；②模糊效果加上；
③侧栏与页面存在色差、边界有明显分界线。证据目录
`内部验证记录`（8 张截屏 + `smoke-real.ps1`）。

- **色差分界线的真身（本轮最重要的结论）**：做**零 alpha 标定实验**——把 `shell_panel_glass`
  的 alpha 设成 0 后逐像素比对，**面板区与页面底色完全相等**（深色都是 `rgb(21,21,23)`、
  浅色都是 255）→ **`backgroundEffect` 的模糊本身是中性，一切色差 100% 来自玻璃色叠加**。
  旧值 `#C41B1B1C`（alpha≈77%）亮度比页面底色低：浅色 255 vs 250（5 级）、
  深色 21 vs **7**（14 级，肉眼可见的竖向界线）。关键洞察：**"更暗的颜色 + 高 alpha"配不出同色面板**，
  唯一解是 **tint 亮度贴近页面底色 + 低 alpha**：最终浅色 `#40F2F2F3`（面板 251–252，差 3–4 级）、
  深色 `#1728282A`（面板 23，差 **2 级**）；`DARK_BRIGHTNESS` / `TOP_BAR_DARK_BRIGHTNESS`
  **回归 1.0**（之前的 0.86 正是深色发灰的元凶）。
  逐像素剖面（真机深色 y=2200）：`x=1000..1040 → 23`、`x=1074..1200 → 21`，中间只有面板自身
  0.5vp 描边（18）与投影过渡，**无成片色差带**。
- **模糊半径 40 → 24**：40 时模糊会溢出面板边界去采样**面板外的清晰内容**，在右缘形成
  "糊 → 清"的不连续带；收到 24（与圆角同尺度）后糊化仍明显、边界收敛干净，
  再配 0.5vp 发丝描边 + 20vp 柔投影，右缘读作"有意的收边"。
- **侧栏功能逻辑逐条修复**：①**面板展开时顶栏整条点不动** —— `MainPane` 的 Stack 里透明接管层
  排在顶栏**之后**且是整屏容器 → 层序改为 **Web → 接管层 → 顶栏 → Splash/ErrorPane**；
  ②顶栏 ☰ 只开不关 → `toggleSidebar()`，并明确面板占 82% 宽时 ☰ 落在**面板之下**；
  ③面板没有关闭入口 → 面板头部新增 **×**（`sys.symbol.xmark`，先经 SDK `id_defined.json` 实证）；
  ④账号菜单 cancel 不收官方菜单（官方菜单是 toggle 语义）→ `cancel` → `onCloseAccount` →
  网页侧 `closeAccountMenu()`；⑤点账号菜单项偶发"什么也没发生" → 原生侧
  `pickAccountOption(label, attempt)` 140ms × 8 次重试 + 失败 Toast；
  ⑥`@Prop @Watch` 初始化不回调（**本工程第三次复发**）→ `aboutToAppear()` 补一次初始消费；
  ⑦空态就抢定位（`scrollToIndex` 打在不存在的索引上）→ `onRowsChange` 加"空态不定位"守卫，
  定位后 60ms 补滚一次（虚拟列表首帧会丢弃）；⑧关面板不清 `pendingLocate` → 关闭分支一并清标记 + 取消定时器。
- **真机回归 `smoke-real.ps1` 全绿**（坐标全部从 `dumpLayout` 现取，不用肉眼估）：
  `S1 面板已开 选择=1` / `S2 选择模式 全选=1 删除=1 完成=1` / `S3 已勾选 删除(1)` /
  `S4 删除确认框 对话框=1 确认框=1` / `S5 取消后 对话框=0` /
  `S6 账号菜单 对话框=1 账号项=2` / `S7 关闭菜单 对话框=0`；
  另：面板 × 关闭 ✅、遮罩点击关闭 ✅、深色面板 ✅、打开即定位 ✅（第 14 条"数学题解答"居中）。
- **新坑**：`hdc list targets` 同时列着模拟器与真机时命令会落到**另一台设备**上——
  本轮因此在模拟器上把"面板子控件整体点不动"误判成产品缺陷，换真机复核同一构建完全正常。
- 证据：`内部验证记录`（8 张截屏 + `smoke-real.ps1`；
  **该目录没有 README.md**，口径见本节与 `EXPERIENCE.md`）。

## 第十一轮（2026-09-11）：首页输入法"原地不动" + 图标统一 + 删除弹窗穿帮修复 + 启动动画（真机）

**需求原文**：①首页对话框在输入法弹出时保持不动；②菜单图标换成三条长短不一的横杠、
侧栏「选择」换成图标统一风格、首页点 + 时提示「已是新对话」；③修复删除对话时点删除按钮
会在侧栏窗口下方继续显示一次弹窗的 BUG；④打开动画只显示蓝色鲸鱼与「探索未至之境」，逐字跳出。
**环境**：真机 Mate70 Pro+（`DEVICE_SN_REDACTED`），1316×2832 / dpr 2.975 / 视口 443×952。

**① 首页输入框被输入法"顶上去"**
- 根因：ArkWeb 软键盘避让默认 `WebKeyboardAvoidMode.RESIZE_CONTENT`（SDK `component/web.d.ts`
  明确默认值），键盘弹出时**布局视口**一起收缩（`innerHeight 952 → 583`），官网首页
  「问候语 + 输入框」是**在可视高度里垂直居中**的 → 输入框 y 由 466 跳到 281。
- 修法（`pinHomeLayout()`）：首页把应用根 `.cb86951c` 的高度**钉在"键盘未弹出时的高度"**
  （取见过的最大 `innerHeight`，天然免注入屏幕参数）+ `html{overflow:hidden}`；
  实测 **ta y 281 → 465**、`scrollY` 恒 0。
- **二次修正（长草稿）**：块体居中 ⇒ 草稿变高时上下各长一半，12 行草稿把输入框底从 526 顶到 645、
  下半截沉到键盘（上沿 583）下 → 按"底边不越过键盘上沿"反推虚拟高度
  （居中位移 = 高度变化的一半 ⇒ 高度 −= 2×越界量）+ `document` 级 `input` 监听（80ms 防抖）重算；
  实测根高 952 → **767**、`ta.bottom` 645 → **553** < 583。
- **只在首页钉**：对话页输入坞是贴视口底的 sticky，钉高会让它沉下去——实测 `pinned=0`、
  dock 底 571 < 583 无回归。

**② 图标统一 + 「已是新对话」轻提示**
- 顶栏 ☰ 从 `sys.symbol.line_3_horizontal` 换成**自绘三条长短不一的横杠**（`MenuGlyph`：
  19/13/16 vp 宽、2 vp 高、圆角 1、间隔 4，居中于 38vp 圆按钮）；真机 dump 实测 57/39/48 px = 19/13/16 vp ✅。
- 面板头部「选择」文字按钮 → 同款圆形图标按钮（`sys.symbol.list_checkmark`，
  符号名先在 SDK `id_defined.json` 权威清单核对）；三按钮实测各 113px 同尺寸同色。
- 首页点 + → 按钮下沿右侧淡入「已是新对话」气泡，1.6s 自动消失
  （常驻 + `opacity`/`translate` 动画 + `hitTestBehavior(HitTestMode.None)` 永不吃点击），
  画在**最外层 Stack**（`SideBarContainer` 之后），面板展开时也看得见；
  且首页**不再去点官方「新建对话」**（那样会把草稿与深度思考/智能搜索开关一起重置）。

**③ 删除时"下方又冒一次弹窗随即消失"**
- 根因：官方确认弹窗是**文档级 portal**——`ds-modal-overlay`（`rgba(0,0,0,.36)`、`z-index 1025`）
  + `ds-modal-wrapper`（`z-index 1026`，含红色「删除该对话」），**不在隐藏抽屉里**，
  抽屉的 `visibility:hidden` 挡不住它；面板只占 82% 宽 → 右下方露出半张官方弹窗 + 整页压暗 36%。
- 修法：删除期间在 `<html>` 打 `data-dsh-delete-driving="1"`，注入样式把这两层
  `visibility:hidden`（**保留几何** —— `tap()` 派发的事件不经过命中测试，照旧能落到
  「删除该对话」上；`display:none` 会让 rect 全 0、事件坐标失真）。
  页面侧 80ms 采样、覆盖链路全程 2350ms 的 **31 个样本**里两层可见性恒为 `-/hidden` ✅。
- **顺带修掉一条真实风险（本轮验证时踩到）**：官方下拉菜单是 **portal**、DOM 不带归属信息，
  残留一个还开着的菜单时按文案点菜单项会命中**别人那一份** —— 本轮真机**真删错一条会话**。
  现在：①每步之前先要求"场上无菜单/无弹窗"，收不掉就**中止**（`stale-menu` / `stale-modal`）；
  ②`tap()` 在目标自身 `0×0` 时**退到最近有几何的祖先**取坐标；③删除链路回报非 `done` 时
  原生侧 toast「有 N 个对话未能删除，请重试」，不再静默当成功。

**④ 启动动画**：只留**蓝色鲸鱼**与「探索未至之境」（去掉 `DeepSeek` 标题、`LoadingProgress` 转圈、
「正在打开 DeepSeek ...」）；鲸鱼直接用 `startIcon`（`iconwork/make-starticon.js` 用官方 favicon SVG +
headless Edge 透明底截图生成的透明 PNG）→ **去掉 `borderRadius`**、显示 168vp；
标语拆成**单字数组**各播 `opacity`/`scale`/`translate`（260ms）200ms 一个字，
鲸鱼 420ms 淡入 + 0.88→1 放大；`start_window_background` 与 `bg_page` 对齐消除启动跳色。

**真机验证读数**：空草稿 + 键盘 `ta y=465`（与无键盘一致）；12 行草稿根高 952→767、
`ta.bottom 553` < 583；对话页 `pinned=0`、dock 底 571 < 583；删除链路 31 样本弹窗恒 hidden；
删除前后 id 差集**恰好只少目标**（53→52）；菜单图标三杠 57/39/48 px；面板头部三按钮同尺寸同色；
「已是新对话」~1.6s 自动消失（面板 ⊕ 亦可见）；启动动画 0.9s「探索未」→ 1.6s 全句（浅/深各一张）。

**补丁 A（同日）：输入框"长文本滑动出现两条滑块"**
- 两条来源完全不同：①官方**自绘**滚动条 = `div.ds-scroll-area__vertical-gutter >
  div.ds-scroll-area__vertical-bar`，色块画在其 `::after`（`rgb(229,229,229)`），
  输入框聚焦期间一直显示、跟手；②**引擎默认**的 overlay 滚动条（`textarea` 自身滚动溢出），
  平时淡出、一滑动就冒出来。用户原话"浅色长条一直保留，但滑动时深色长条会短暂出现"正是这两条的指纹。
- 修法（`markInputScrollbars()`）：给 **textarea 自己** + 同容器里"可滚动 + `pointer-events:none`"
  的镜像兄弟层打 `data-dsh-noscrollbar="1"`，注入
  `{scrollbar-width:none} / ::-webkit-scrollbar{display:none;width:0;height:0}`；
  ①是独立 DOM 元素、不受影响。**只扫 textarea 及其兄弟**，找不到就什么都不做（不误伤）。
- 读数：滑动中三列**深色像素 = 0**、浅色段 640–648px（`sb-B-scroll`）；静置 6s 只剩
  `LIGHT y924-1569(645px, avg=229)`（与官方 `::after` 的 229 一致，`sb-C-idle-clean`）；
  `diag().sbHidden = 2`；对照 `crop-nofix.png`（两条）vs `crop-withfix.png`（一条）。

**补丁 B（同日）：删除接口"安全闩"**
- 起因：本轮验证期间发生过一次**误删用户真实会话**（见 ③ 的残留菜单）。为杜绝"任何调试/自动化
  脚本顺手调一下 `__dshShellApi.deleteSession` 就把用户数据删掉"：网页侧 `state.deleteArmed`
  默认 false，`deleteSession` 首行 `if (state.deleteArmed !== true) return 'locked';`；
  原生侧**只有用户点了面板里的「选择」进入选择模式**才 `armDelete(true)`
  （`SidePane` 新增 `onSelectModeChange` 回调；退出选择模式 / 关闭面板 / 删除队列走完立即落闩）。
- 真机读数：未进选择模式直接调接口 → `{"armed":0,"ret":"locked"}`、会话数 50 → 50 无变化；
  进入选择模式 `deleteArmed=1`、退出后 `deleteArmed=0` ✅。

**遗留（如实记录）**：滚动条排查期间会话数由 51 变成 50（少了「现代城市水岸景观」），
**无法归因**；安全闩装好后复核显示直接调 `deleteSession` 返回 `locked` 且会话数不变，
此后列表稳定在 50 未再变化。另：本轮为取证创建了 3 条自建临时会话并于验证后逐条删除。

- 证据：`内部验证记录`
  （截屏 + 逐像素/逐帧读数 + `cdp.mjs` / `ui.ps1` / `analyze-sb.ps1` 等脚本）。

## 第十二轮（2026-09-11）：迁移与瘦身（整理轮，无独立需求与验收读数）

- 源码由 `.` 整体迁入 `.\`（源码树与文档同目录）；
  原工程根 `README.md` 改名保留为 `README-source.md`。
- 删除 2.6GB 验证残留（`verify\.cdp-*` 15302 文件、`iconwork\.tmp1-4`、`preview\`、`entry\.preview`、
  `Index.ets.disabled`、`.hvigor` / `.idea` / `entry\build`）。
- **新路径构建验证通过**：`scripts\build-hap.bat .` →
  BUILD SUCCESSFUL，签名 HAP `entry\build\default\outputs\default\entry-default-signed.hap`
  （552,799 B）。
- 文档重构为三层：`PROJECT.md`（现状）+ `CHANGELOG.md`（本文件）+ `EXPERIENCE.md`（经验与脚本手册）。

## 第十三轮（2026-09-11~12）：网页「选择上传」接管 —— 官方半模态 bindSheet + 三个系统选择器（真机）

**需求**：选择文件上传时弹出的那个窗口没有动效，要求"采用官方动效优化"；随后用户明确
"这不是官方原生组件吧" → 结论是**必须用官方组件**，不是自绘一个像官方的。

**定位（真机取证）**：点网页输入区回形针 → 弹出的是 **ArkWeb 自带**的系统「选择上传」窗
（图库 / 拍照或录像 / 文件 / 取消，居中卡片；`dumpLayout` 里没有它，进程表里出现
`com.huawei.hmos.photos:PickerUIExtensionAbility`）。**没有进场动效**：265ms/帧连拍 8 帧，
8 帧 MD5 完全一致 —— 从第一帧就是终态，抓不到任何中间几何。

**方案（含一次返工）**：
1. 首版自绘覆盖层（`animateTo` + `curves.springMotion`）——功能跑通、确实有动效，
   但被用户指出"不是官方原生组件" → **废弃**（自绘永远只是仿制，且有 §3.0-16 的
   `bindSheet` 静默不呈现风险在前，当初正是为躲它才自绘）。
2. 最终版：实现 `Web.onShowFileSelector` **接管**（返回 true 后 ArkWeb 不再弹它那个窗），
   用**官方半模态 `bindSheet`**承载同样三个选项：
   `height: SheetSize.FIT_CONTENT` + `dragBar:false` + `showClose:false` +
   `title:{title:'选择上传'}`；`$$this.pickerSheetShown` 双向绑定（用户点遮罩/下拉/返回键关面板时
   框架会写回状态，`@Watch` 据此把这次选择按"取消"收尾）。
   弹出/收起动效、遮罩、圆角、材质、下拉关闭**全部由系统组件负责**，应用只提供内容。
3. 三个来源各自拉起系统选择器（均无需额外权限）：图库 `PhotoViewPicker`、
   拍照或录像 `cameraPicker.pick([PHOTO,VIDEO])`、文件 `DocumentViewPicker`；
   多选上限按网页 `multiple`（本页 True → 8）。

**关键实现点**：
- **选择器 URI 必须落沙箱副本**再回传：图库/相机给的是 `file://media/...`、文档是 `file://docs/...`，
  都是"选择器结果临时授权"的跨应用 URI，ArkWeb 渲染进程按普通路径读不到（表现是"选完了
  什么都没上传"）。`stageUploadFile()` 开 fd 流式复制进 `cacheDir`（保留原文件名+扩展名），
  再把沙箱路径交给 `event.result.handleFileList([...])`；下次选择前按前缀 `dsh-upload-` 清理上次副本。
- **取消语义**：取消/返回键 → `handleFileList([])`。真机实测**不会清掉已挂的附件**
  （网页侧对空列表不做处理），与浏览器"取消文件对话框不改动 input"的语义一致。
- 拉起系统选择器前先等 200ms（`PICK_LAUNCH_DELAY_MS`）：系统选择器是独立 UIExtension 窗口，
  立刻拉起会把半模态的收起动效整段盖住。

**修掉的真 bug（cameraPicker）**：`new cameraPicker.PickerProfile()` 之后再
`profile.cameraPosition = …` 在运行期抛 `Cannot assign to read only property`（类字段只读），
相机根本起不来；而 catch 当时把它当"用户取消"静默吞掉 → 表现为"点『拍照或录像』毫无反应"。
修法：① 改**对象字面量**构造；② catch 不再静默（系统选择器"取消"是正常 resolve 返回空，
能抛的都是真失败）→ `toast('未能打开选择器：…')` + hilog。

**验收（真机 Mate 70 Pro+，交付件上复跑）**：
- 面板：`dumpLayout` 文本 `选择上传` 出现/消失判定开/关；深色 `n2-bindsheet-open.jpeg`、
  浅色 `fn-21-sheet-light.jpeg` 双主题正常。
- 动效：截图管线 265ms/帧抓不到 ~300ms 进场 → **相位扫描法**（点按后插不同 `sleep`，
  与静止帧逐行差分）：d=0/0.08/0.16/0.24/0.32s 的最大差 **47.2 → 34.5 → 25.9 → 9.3 → 3.9**
  单调收敛；`anim-sheet-compare.png` 肉眼可见动效中面板位置更低。
- 端到端：图库选中 1 张 → 沙箱副本生成 → 网页输入框出现附件缩略图（CDP `blob:` 预览）；
  文件链路拉起系统文件选择器；相机链路拉起系统相机（**实际拍摄未完成**：手机平放、后摄被挡，
  相机自身报"有遮挡"，非应用问题）。
- 取消/返回键：面板均正确关闭、进程未崩；**取消不吞已有附件**（两次 CDP 读数同一 blob）。
- 会话数全程 52 稳定（本轮无任何删除类操作）。
- 干净重建（删 `entry\build` + `.hvigor`）：34 tasks 全执行、**0 error / 0 warning**，
  签名 HAP 584,858 B，`install -r` 覆盖安装。

**遗留（如实记录）**：① 相机链路只验到"拉起"，未验"拍完回传"（环境限制，见上）；
② 系统文件选择器里"只点缩略图"不会选中（要进相册/分组再点圆圈），这是系统选择器自己的交互，
与本应用无关。

- 证据：`内部验证记录`
  （系统窗连拍 8 帧全同 + 相位扫描读数 + 端到端截图 + `dismiss-test.ps1` / `phase-analyze.ps1`）。

## 第十四轮（2026-09-14）：审查问题修复（P0 批 + P1 批）—— 批量删除失效 / 标题不刷新 / 安全闩返工 + 适配器单例与注入收敛（真机）

**起因**：`内部验证记录`（只读全量审查，模拟器）给出 P0×3 / P1×8 / P2 若干。
本轮按 P0 → P1 顺序施工，**全部在真机 HUAWEI Mate70 Pro+（`DEVICE_SN_REDACTED`）验证**。
证据：`内部验证记录`。

**P0-1 批量删除"一条都删不掉、且连失败提示都没有"**
- 症状：侧栏「选择」勾选 → 确认删除 → 列表原样不动、每条约 8 秒空转一格、**无任何提示**。
- 根因链：`confirmDelete` 的确认动作**先** `exitSelecting()`（内部 `onSelectModeChange(false)`
  → 下发 disarm）**再** `onDeleteSessions()` → 网页侧 `deleteSession` 首行判定 `locked` 直接返回
  **且不回报** → 原生侧看门狗只 `deleteDone++` 不计失败 → 全程静默。
- 修法：①**调换顺序**（先抛删除请求、再退选择模式），使父组件 `deleteBusy` 在退模式时已为 true，
  从而不提前落闩；②删除队列进行中一律不落闩，**唯一落闩点**是 `pumpDelete` 收尾；
  ③看门狗超时与网页侧非 `done` 回报（含 `locked`/`busy`）**一律计入失败并 toast**。
- **第一次没修对**：首版只挪了落闩点、给 `exitSelecting` 加了 `deleteBusy` 守卫，真机仍 100% 失败。
  用页面侧探针记录 `set/clear/del` 的调用序才看到 **`clear` 排在 `del` 之前** —— 是**顺序**问题，
  不是守卫条件问题。这条教训沉淀为 `§3.0-131`。
- 真机读数：`p0-e2e2.ps1` 会话数 57 → 56、**操作前后 id 差集恰为目标那一条**、无失败提示；
  hilog 出现 `delete <id> -> done`。

**P0-2 侧栏会话标题永不刷新**
- 根因：`SidePane` 的 `ForEach` key = `row.key + ':' + active + ':' + isSelected`，**漏了 `row.text`**，
  而 `SideRow` 是普通 interface（非 `@Observed`）→ "官方自动命名"这种只改标题的变化不会重建行。
- 修法：key 补 `row.text`（保留原粒度：只有变化的行 key 变，勾选仍只重建 1~2 行）；
  顺带把分组行 key 从 `i` 改为"已产出行数"（同名分组可能二次出现会撞键）。
- 真机读数：新会话网页侧自动命名成 `自动化验证会话确认` 后，原生顶栏与侧栏首行**同步显示同名**。

**P0-3 删除安全闩形同虚设（安全红线）—— 返工两次才收口**
- 根因：`armDelete(on)` 与 `deleteSession(id)` 挂在**同一个页面对象** `window.__dshShellApi` 上，
  任何脚本一句 `__dshShellApi.armDelete(true)` 就能自己开闸再删。
- 第一次修法（仍有洞）：密钥由 native 生成、随请求传参校验 —— 但 `setDeleteToken` 仍接受**任何**
  ≥8 字符的串，页面脚本自造一个再自己开闸照样能删。
- 最终修法：密钥经**一次性 `window.__dshArm` 交接**进脚本闭包（页面上无读取出口），
  `setDeleteToken` 只认"闭包密钥 + 传参相等"，并加 `deleteTokenAssigned` 标记
  （防"页面把密钥改成空串绕过匹配"）；**`armDelete` 从页面对象上删除**。
- 真机读数（`p0-latch2.ps1`，三个攻击面）：不带密钥 → `locked`；自造密钥 → `locked`；
  自造值/空串开闸 → `rejected`、随后两次删除 → `locked`；**会话数 56 → 56、id 差集 0**。
  `diag()` 只暴露 `deleteArmed` 布尔，**不暴露密钥本身**。

**P1-1 适配器重复注入叠加常驻定时器**
- 根因：适配器每次注入都新建整套闭包，而 `DOMContentLoaded` / `load` / `matchMedia` 监听与
  2s 巡检都注册在**顶层**，没有单例守卫 → 注入 N 次就有 N 份。
- 修法：顶层 `window.__deepseekHmAdapter.alive` 守卫（重复注入只跑一次 `run()`，并记 `boots`）；
  巡检 2s → 5s + `document.visibilityState` 门控 + `visibilitychange` 回前台补查；
  `patrolAll()` 抽出供两个分支共用。
- 真机读数：`boots = 2`（onPageEnd + ready 各一次，**只装 1 份**）；
  巡检采样序列 `[30105,5] [30506,6] [35504,7] [40503,8]` → 相邻间隔恒为 **5000ms**。

**P1-2 渲染进程崩溃零兜底**：补 `Web.onRenderExited`（`RenderExitReason` 成员值核对 SDK `web.d.ts`）
→ 置 `errorMessage`，由自带「重新加载」的 `ErrorPane` 承接，不再白屏/永久 Splash。
**未做真实崩溃注入**（无安全的单进程杀法），已在证据 README 如实标注。

**P1-3 模板字符串吃掉反斜杠**：`DeepSeekConfig.ets` 两处（`[\s]+` 被吃成 `[s]+`、
`rgba?\(…\)` 多一层捕获组）改双反斜杠；**预检脚本同步升级**：除 `node --check` 外新增
"按运行时语义还原 + 断言关键片段"与"单反斜杠 + 非法转义字符扫描"（沉淀为
`§3.0-130`）。预检当场又抓到我在注释里写反引号把模板字面量截断
（`§3.0-133`）。

**P1-4 上传无超时 / 卡片 newChat 意图丢失**
- 上传：新增「选择上传」8s 看门狗 —— 面板若因故没呈现，到点回空列表并复位，
  网页侧不再永挂"上传中"。
- newChat：`onPageFinished` 里原本**先注入脚本、再立刻 `doNewChat()`**，而脚本是异步求值 →
  `window.__dshShellApi` 尚不存在，被 `&&` 静默吞掉。改为由 `{t:'ready'}` 回执消费，
  另加 800ms×5 兜底重试 + 明确失败 toast。真机：先用 `openSession` 打开历史会话（路由 `/a/chat/s/…`），
  再 `aa start … --ps action newChat` 冷启动 → `route = /`、`title = DeepSeek - 探索未至之境`。

**P1-5 错误页与生命周期**：`aboutToDisappear` 补齐五个此前未登记的定时器
（60ms 鲸鱼入场 / 删除看门狗 / 账号菜单重试链 / 选择器拉起 200ms / 上传看门狗）并在销毁时
一并清掉、给待回传的文件选择句柄回空结果；`onPageFinished` 清 `errorMessage`；
`EntryAbility.onWindowStageDestroy` 里 `off('avoidAreaChange')` 并置空 `mainWindow`。

**P1-6 桥消息校验与删除链安全**：`t` 白名单 + `items` 逐项校验（`id`/`title`/`group` 必须 string），
非法丢弃并 hilog（早先 `applySessions` 读到非字符串会抛异常、打断整条桥链路）；
`confirmDeleteButton` 去掉 `foot || document` 兜底（拒绝全文档匹配，找不到 footer 直接 `no-confirm`）；
删除链路每步前校验路由未变，变了按 `aborted` 中止。

**P1-7 注入体积与 IPC 次数**：三次 `runJavaScript` 合并为一次（adapter 在前、各自 try/catch）；
下发前剥离整行注释；新增 `window.__dshSetInsets(t,b)` 轻量通道（避让变化不再整脚本重跑，
通道缺失回退整注入）；深浅色探测 `unknown`/异常分支降级为 `injectShell()`。
真机读数：`__dshShellApi.setInsets(109.71, 32.94)` → `ret='ok'`、`__dshTopInsetPx` 97.71 → 109.71、
`adapter.boots` 保持 2（**脚本未被重跑**）。

**P1-8 markSideDrawers 下线 + 避让写入去抖**：从 `scheduleFixedCleanup` 里删掉 `markSideDrawers()`
（`querySelectorAll('body *')` 全遍历，`run()` 里早已不调）；`avoidAreaChange` 加 100ms 去抖 +
同值不写（0.5vp 容差）；系统栏四色缓存上次值并改为读资源 `app.color.text_primary`。
真机复核侧栏圆角与投影正常（`p1-sidebar-final.jpeg`）。

**顺带（P2-2 两小项）**：会话签名由"拼长字符串整体比较"改为**逐条 `(id,title)` 元组比较**；
巡检强制全查由 `tick % 4`（12s）放宽到 `tick % 10`（30s）。导航白名单改归一化比较
（大小写 + 默认端口）且被拦时给可见 toast。

**构建**：P0 批 591,420 B / P1 批 622,360 B / P1+P2-2 收尾 629,320 B，
三次均 **BUILD SUCCESSFUL / 0 warning**（`内部踩坑表` §3.0-129 的 node 直调方式）。

**本轮证据**：`内部验证记录`
（端到端删除 + 安全闩三攻击面 + 巡检节奏/单例读数 + 注入脚本预检 + 真机截图与脚本）。
**未闭环项**（onRenderExited 未做真实崩溃注入、上传看门狗未构造到触发场景、注入体积未拆分 A/B、
平板双栏未开工）在该 README §3 逐条列明。


## 第十五轮（2026-09-14）：P2-1 官方组件替换与 UI 统一 + P2-2 收尾（真机）

**范围**：审查报告 P2-1（官方组件替换 / 尺寸字号收敛 / 无障碍 / 死资源）与 P2-2（内存与速度收尾）。

**官方组件替换**
- 账号行末尾的 `Text('⋯')` → `SymbolGlyph($r('sys.symbol.more'))`：字符的基线/字宽随字体走，
  与旁边的图标不在同一套视觉尺度上。符号名先在 SDK `id_defined.json` 里核对
  （`{'type':'symbol','name':'more','order':2305}` 存在；`ellipsis` 不存在 —— 别凭印象写）。
- 侧栏搜索框自绘 `Row{SymbolGlyph + TextInput + 16vp 清除图标}` → **官方 `Search` 组件**：
  原来自绘的清除按钮热区只有图标那么大（远低于 40vp 下限）、无障碍语义为零；
  官方组件的 `cancelButton` 自带 ≥40vp 热区与"有内容才出现"的行为。
  实现期踩到一个编译错并已修正：`searchIcon` 吃 `IconOptions | SymbolGlyphModifier`
  （`{size, color, src}`），**不是** `Resource`。

**尺寸/字号/圆角收敛**：新增 `entry/src/main/ets/common/ShellUi.ets` 作为唯一的 UI 尺寸常量表
（图标按钮 38 → **40vp**、行高/按钮高/圆角/字号各一档），`Index.ets` 与 `SidePane.ets` 同引一份；
删掉 `14.5 / 13.5 / 12.5` 半像素字号与 `14 / 12` 两套小圆角。

**无障碍**：所有纯图标按钮（顶栏 ☰/返回/+/分享、面板 选择/⊕/×）补 `accessibilityText`
+ `accessibilityDescription` + `accessibilityLevel('yes')`；会话行与账号行补行名与描述、
并按 `PickerRow` 同款配方补 `stateStyles{pressed}` 按压态。
**为什么要写两处名字**：`accessibilityText` 是读屏取名字的正式属性，但本工程
`uitest dumpLayout` **只暴露 `description`、不暴露 `text`** —— 第一版只写前者时，
dump 里 5 个图标按钮的 desc 全是空，自动化无从断言"到底有没有名字"。
真机 dump 断言 5/5 PASS（`内部验证记录`）。

**死资源与硬编码色**：删掉 4 个零引用资源（`shell_topbar_bg` / `shell_sidebar_bg` /
`shell_scrim` / `shell_select_bar_bg`，base+dark 共 8 条，各 19 → **16** 条：删 4 个 + 新增 `on_accent`
；2026-09-15 实测两份 `color.json` 各 16 条）；
新增双值资源 `on_accent`，把错误页按钮 / 删除按钮 / 头像占位上的 `Color.White` 改引用它；
`EntryAbility` 的系统栏内容色改为读 `app.color.text_primary`（与原生文字色同源）。

**P2-2 收尾**：`SidePane` 列表 `.cachedCount(6)`；`filteredRows()` 按 `queryText` 记忆化
（**只以本组件自己的 @State 为键、绝不对 @Prop 做缓存** —— ArkUI V1 的 @Prop 漏失效会出
"列表不更新"的隐蔽 bug，`onRowsChange` 里再显式清一次做双保险）；
`ShellScript.collect()` 的会话签名由"拼长字符串整体比较"改为逐条 `(id,title)` 元组比较、
巡检强制全查由 12s 放宽到 30s；删除 `useDesktopUa` + `DESKTOP_UA` 死分支。

**未做（如实记录）**：`ListItemGroup + List.sticky(StickyStyle.Header)` 吸顶分组头 ——
它要把一维 `SideRow[]` 重构成二维，一个分组内任一行变化都会重建整个 `ListItemGroup`，
与 P0-2 里明确要求保留的"勾选只重建 1~2 行"粒度**直接冲突**（不能为了吸顶把刚修好的
刷新粒度又打回去），故按用户"若判定不是问题就写明依据"的要求**故意不做**并记录理由。
平板双栏仍未实测，保持 `deviceTypes: phone + tablet`（不替用户在未实测时下"不支持平板"的决定）。

**构建与验证**：BUILD SUCCESSFUL / **0 warning**，HAP 628,094 B。
真机（Mate70 Pro+）复核：浅/深两色侧栏观感（`p2-1-sidebar.jpeg` / `p2-1-sidebar-dark.jpeg`）、
无障碍名 5/5、**P0 两条红线回归通过**（端到端删除 57→56 且 id 差集恰为目标；
安全闩三攻击面全被拒且 id 差集 0）。

- 证据：`内部验证记录` §2.9

## 第十六轮（2026-09-15）：UI 统一 + 官方原生组件 + 动效 / 残余 BUG / 内存与速度 / 文档缺漏

**最终产物**（B8 修复后再次冻结）：`entry\build\default\outputs\default\entry-default-signed.hap` =
**706,225 B / 2026-09-15 21:13:10 / md5 `9d1a625613911e7935decce5e18ec862`**，BUILD SUCCESSFUL / **0 warning**。
（B8 修复前的 `696,511 B / 19:31:48 / md5 fcf4310a1ecff91a3724ae1b4931734e` 已被取代，
`内部验证记录` 的读数即基于该前一版产物 —— 见 §7 B8 一节的说明。）

### 1. 用户五条诉求

1. **UI 统一 + 官方原生组件 + 动效**；2. **修残余 BUG**（含**侧栏账号菜单「系统设置」「帮助与反馈」入口直接去除**）；
3. **内存与速度优化**；4. **文档缺漏与错误**；5. **参考 iOS 设计**。

### 2. 设计令牌与 iOS 规范

`common\ShellUi.ets` 从"20 个尺寸常量"扩成**设计令牌表**（尺寸 / 间距 / 内缩 / 圆角 / 发丝线 / 阴影 /
动效 / 按压 / 模糊与亮度），成为全工程唯一数值来源；新增 `specs\UI-DESIGN.md`（§0 适用范围与前提、
§1 总原则、§2 导航栏、§3 侧栏 inset grouped、§4 动效、§5 官方组件清单、§6 无障碍、§7 禁止事项 9 条、
§8 验证要求、§9 相关文档）。

**为什么 iOS 的 pt 能一对一搬进 vp**：目标设备 1316×2832 / **density 560** ⇒ 1vp = 560/160 = 3.5px ⇒
有效宽度 1316/3.5 = **376vp ≈ iPhone 12 mini 的 375pt**。因此 `44pt` 最小可点区、`inset grouped` 内缩、
`FastOutSlowIn` 级缓动都可直接照搬，不需要换算系数。

### 3. UI 统一与动效

- **顶栏抽成 `view\TopBar.ets`**：标题居中**且不随按钮数漂移**（左槽/标题槽/右槽，左右槽等宽固定
  `SLOT_W = ICON_BTN*2 + GAP_SM = 96`）。
- **图标按钮配方统一**为全局 `@Builder ShellIconButton`（顶栏与侧栏不再各持一份实现）。
- **侧栏改 inset grouped**：行高 44 / 分隔线从内容起始内缩（`SEP_INSET` 16）/ 分组头（`GROUP_ROW_H` 30）/
  按压底色过渡。
- 面板头的 `⋯` 文本字符改 **`SymbolGlyph`**；**空态与转圈统一**；**4 处分支补 `TransitionEffect.OPACITY`**。

### 4. 逻辑 BUG

- **侧栏账号菜单「系统设置」「帮助与反馈」入口直接去除**，只留「退出登录」。**这是产品决策，不是缺陷回退**：
  两个入口在本容器里**点了不生效**（设置面板属官方网页侧弹层、原生菜单打不开；反馈须走官方网页渠道），
  属"点了没反应"的死入口，既误导用户又拉低观感。副作用：`EXPERIENCE.md` §5-1「网页 backdrop 不覆盖原生
  顶栏」的触发路径随之消失，该项优先级下降。
  > ⚠️ **本条在同轮内被用户推翻**：第三批按用户要求**恢复「系统设置」**，并把它**真的修好**（真因见 §9）。
  > **「帮助与反馈」维持移除**。**当前现状以 §9 与 `PROJECT.md` §4 为准**，本段保留以记录决策演变。
- **顺手修掉一个静默失效的真实缺陷**：网页侧上报的 `active` **恒为 `false`**，且原生侧**从未回填** ⇒
  侧栏「当前会话高亮」「打开侧栏自动定位」「读屏文案」**三处全部失效**（谁都没报错）。改为
  `applySessions()` 按 `id === currentSessionId` 回填 + 路由变化时 `syncActiveRow()` 重新对齐。
- `onRefresh` 从**死参数**（只有声明与传参、工程内根本没有 `Refresh` 组件）改为真的官方 `Refresh` 下拉刷新。
- `deleteBusy` 重入闸；错误页层序 + 入场动效；导航白名单拦截给**可见 toast**；
  `setWebDebuggingAccess` 按 **`BuildProfile.DEBUG` 门控**；桥消息**逐字段校验**。

### 5. 内存与速度

- **`Image.autoResize(true)`**：SDK 默认 `false` = 按原图解码，1024×1024 原图 4MB 级 → **0.1~0.5MB**。
- **`databaseAccess(false)`**：本工程不依赖网页 IndexedDB。
- **启动页**从"固定 2.2s"（`SPLASH_HOLD_MS = 2200`，已删除）改为**事件驱动**：
  首个 `sessions` 桥消息到达 ∧ 最短 800ms → 立刻摘罩；或 **1200ms 硬超时**兜底。
- `@Entry` 根的 **17 个 `@State` 拆成 `TopBar` / `MainPane` / `SplashOverlay` / `NewChatTipLayer` 四组件**
  （缩小刷新面）。
- `EntryAbility.onMemoryLevel` → **`trimMemoryByPressureLevel`**（审计 §3 指出"全工程无 `onMemoryLevel`"）。
- **`initializeWebEngine` + `prepareForPageLoad` 预热**（DNS 预解析 + TCP 预连接）。
- **卡片周期刷新关闭**（`form_config.json` `updateEnabled: false`，删 `scheduledUpdateTime` / `updateDuration`）。
- **`app_icon.png` 去重**（与 `entry/.../icon.png` md5 逐字节相同、零引用；回退可用 `git show HEAD:...` 精确还原）。
- **注入脚本**：`removeDownloadPromos` 的 **O(N²) 文本扫描改 `boundedText`**（合成树 A/B **3.8ms → 0.9ms**，
  **20 万例随机树等价性 0 不一致**）+ 外壳巡检 ticker **3s → 5s**（+ `visibilityState` 门控 + 路由脏标记，
  强制全查安全网墙钟仍 ~30s）。

### 6. P0 回归与修复：原生顶栏「侧栏完全打不开」（真实触摸抓到，构建期不可见）

- **现象**：第十六轮把顶栏从 `pages/Index.ets` 抽成 `view/TopBar.ets` 时，为满足"iOS 导航栏标题居中"改用了 `Stack` 三层布局（铺满的标题层 + 贴左按钮组 + 贴右按钮组）。改造后**侧栏完全打不开**：汉堡按钮 6 个点位真实触摸、连拍 5 帧、左缘右滑全部无反应；**同排的「新建对话」正常**；`uitest dumpLayout` 里按钮 `enabled/clickable` 均为 `true`（排除"被禁用"）。
- **根因**：`Stack` 的后添加者在上层 ⇒ 最上层的**右按钮组**成了整条顶栏的触摸目标。该 `Row` 只画了两个 44vp 图标按钮，但自身 `.width('100%')` 铺满整条顶栏 —— **ArkUI 里"铺满但没有 onClick 的容器"仍参与命中测试并阻断兄弟节点**，于是左侧汉堡的点击被整条吃掉。第一版只给铺满的**标题层**加了 `hitTestBehavior(HitTestMode.None)`，恰恰漏掉了真正致命的两个按钮层。补充语义：`HitTestMode.None` 只是"自身不参与命中，子节点仍参与"，因此它**只对"覆盖层里全是纯展示内容"这一种情形够用**。
- **修法**：改回**单层 `Row` 三槽、零重叠** —— 左槽 `.width(SLOT_W)` 贴左 / 标题槽 `.layoutWeight(1)` 居中 / 右槽 `.width(SLOT_W)` 贴右，`SLOT_W = ICON_BTN * 2 + GAP_SM`（= 96）。左右槽**等宽且固定** ⇒ 剩余空间的中心 = 屏幕中心 ⇒ **标题仍严格居中且不随右侧按钮数量（0/1/2）漂移**（原验收目标保住）。代价：标题槽可用宽度约 272vp → 约 168vp（≈ 10~11 个汉字 @ `FS_TITLE`），长标题更早省略 —— 与 iOS 一致。
- **判据固化**：`specs/UI-DESIGN.md` §7 新增第 9 条「**能用"不重叠的排布"解决，就不要用"覆盖层 + hitTest 特判"**」，并订正该文件把问题简化成"给那一层加个属性"的旧表述；`view/TopBar.ets` 文件头同步记录。
- **证据**：`内部验证记录` §2 B0 项（6 点位真实触摸 + 连拍 5 帧 + `dumpLayout`）；最终产物 `entry-default-signed.hap` **706,225 B / 21:13:10 / md5 `9d1a625613911e7935decce5e18ec862`**，BUILD SUCCESSFUL / 0 warning。
- **可复用教训**：**重写布局时必须先确认"命中测试面"与旧布局等价**。旧布局（单层 `Row`）天然不重叠、命中面就是按钮本身；新布局（`Stack` 重叠）引入了新的、铺满整屏的命中面，**必须对每一个可点元素重跑真实触摸回归**。构建期 `0 error / 0 warning` 对这类缺陷完全无感（§3.0-81 的又一实证）。

### 7. B8 修复：「当前会话不高亮」—— 数据层对、渲染层断链
- **现象**：侧栏里当前会话行**无任何高亮**（verifier 像素判据：当前行与相邻行文字均色 `RGB(58.3,61.8,71.1)` vs `(55.7,59.2,68.3)`，**无可测差异**）；而"打开侧栏自动定位当前会话"是**正常**的。
- **第一阶段误判**：先按 `dumpLayout` 的 `accessibilityDescription`（`row.active ? '当前会话' : '会话'`）判定为"**回填失败**"，被带偏一轮。
  真因是 **`uitest dumpLayout` 只遍历可见节点** —— 当时"当前会话"那一行**不在可见区，压根没被 dump 出来**，把"读不到"误读成了"没更新"。
  （初版曾据此写成"无障碍字段不随 `@State` 更新"，**该结论已被定标实验证伪并作废**：真实触摸勾选一行后，该行 `description` 由"未选"变"已选"。）
  已沉淀为 `§3.0-152` 的 §②③。
- **根因（native 日志实测，非推理）**：`Index` 侧回填链路**完全正确** —— `route filled: active=1`、`sessions applied: active=1`；`SidePane` 侧 `sideRows in: active=1`、`filter recomputed: active=1`；但行内读的是 `row.active`，而 **`row` 是 `@Builder` 的值参数，ArkUI 的值参数不因内容变化重新求值**（`§3.0-38`），`ForEach` 复用行组件时行内永远是首建那个 `row`（**视觉与无障碍一起**停在首建快照）。
- **修法**：把"当前会话 id"提升为 `SidePane` 的 **`@State activeId`**，行内改读 `this.isActive(row)` —— 与"勾选态移出 `ForEach` key"（本轮 B1 PASS 的实证）**同一条元素级依赖路径**；`ForEach` 的 key 同步去掉 `row.active`（`row.text` 保留，P0-2 不回退）。
- **顺带补的诊断能力**：`Index.route` / `applySessions` 与 `SidePane.onRowsChange` / `filteredRows` 各加一条 hilog（**`route` 分支原先一行日志都没有**，而"回填有没有生效"只能从 native 侧看），**只在状态真变化时打**，运行期成本可忽略。
- **证据**：`内部验证记录`（B8 复测节 + 像素判据）、截图 `tmp/r16-b8-check.jpeg`（当前行 accent 蓝字 + `shell_item_active_bg` 底衬）。
- ⚠️ **与 verifier 报告的差异（如实记录）**：`REPORT.md` §8.1 / §8.4① 写的是**第一阶段的"回填失败"结论**
  （§9-3 并把它推广成"行级 `description` 是第一判据"）。其中**"回填失败"已被本节修正**（回填正确、断链在渲染层）；
  而**"`description` 可作为状态判据"这一条本身是对的**，只是当时**目标行不在可见区**才读不到 ——
  完整口径见 `§3.0-152` §②③。verifier 的报告是**当时产物的诚实快照**，不回改。

> **已沉淀为通用坑**：本条教训与 `§3.0-61`（`HitTestMode.Block` 阻塞子节点）**不是一回事**，
> 已按 `AGENTS.md` §6.2「新坑先沉淀再引用」编号递增进 `内部踩坑表` §3.0-151`，
> 并同步进 `AGENTS.md` §4 高频摘要第 29 条。

### 7.1 真机复核与修复：侧栏右上/右下圆角的「阴影分界线」（真机 Mate70 Pro+）

- **用户反馈**：侧边栏窗口**右上角、右下角**"由于阴影导致和其他页面有明显分界线"。
- **真机定位**（截图裁切右上/右下角逐张对比）：面板 `.shadow({ offsetX: 6 })` 做**横向偏移投影**，
  而**阴影是按组件的边界矩形投影的** —— 面板在圆角处向内收，阴影的右缘/下缘**仍是直角**，
  于是圆角外侧露出一块"本该被裁掉"的直角阴影，其外缘与圆角弧线**不重合**，
  在浅色网页内容上表现为**一条竖直硬边**（圆角越大越明显）。
- **修法**：投影改**对称淡晕**（`offsetX: 0, offsetY: 0`，半径仍走令牌 `SHADOW_R_MD`(16)）；
  随之**零消费者的局部常量 `PANEL_SHADOW_DX` 删除**（同 `DRAWER_RIGHT_GAP` 的处置纪律：
  **零消费者常量不留**，只保留说明注释 `SidePane.ets:46`）。
- **证据**：真机裁切 `tmp/crop-tr-old.png` / `crop-tr-new.png`（右上）、
  `tmp/crop-br-old.png` / `crop-br-new.png`（右下）—— 旧版圆角外有**直角灰块**，
  新版沿圆角**连续扩散、台阶消失**。
- **真机同时复核的四项**：① 侧栏**可打开**（真实触摸）；② B1 勾选态（14×`未选` → 触摸后 13×`未选` + 1×`已选`）；
  ③ B2 账号菜单**只剩「退出登录」**（`tmp/r16-real-accountmenu.jpeg`）；
  ④ B8 当前会话**视觉高亮生效**（`tmp/crop-b8-real.png`：accent 蓝字 + 淡蓝底衬）。

> **B8 的第二条独立证据（真机，很重要）**：真机上**视觉高亮已生效**，但 `dumpLayout` 里那一行
> `description` **仍是 `会话`**（11 × `会话`、无 `当前会话`）；而同一条路径在**模拟器**上验到的是
> `{"当前会话":1, "会话":8}`。⇒ `accessibilityDescription` 的更新**还依赖"该行是否被重建"**
> （行复用时不更新、重建时才更新），因此它**不是稳定判据**。已补进 `§3.0-152` §③。

### 8. 文档缺漏与错误（逐条实测复核后订正）

审计报告 `内部验证记录` §4 的每一条都用 `ls` / `find` / `grep -c` **实测复核**后订正，
**报告本身已过期**（它写踩坑表 125 条 / `entry\src` 16 个 / README 5无7有，实测为 **150 / 18 / 6无9有**）。

- **踩坑表口径统一为当时的实测 153 条**（`grep -oE '^## 3\.0-[0-9]+' | sort -u | wc -l` = 153，1~153 连续无断号；
  **2026-09-24 已增至 253 条，本节数字是历史快照**），
  根 `README.md` 3 处、`docs\{workflow,toolchain,arkts-conventions}.md`、`README.md`、
  `PrismAgent\{CHANGELOG,PROJECT,EXPERIENCE}.md` 全部对齐；补充 **§3.0-130~153 的来源段落**；
  写明锚点现状（显式 `<a id>` 131 个，缺 113~129 / 145~150 共 23 条，靠自动锚点仍有效）。
- **新增通用坑 `§3.0-151`**（本轮 P0 的教训，见上一节）：
  "重叠布局里每个铺满的兄弟容器都参与命中测试、并阻断下层兄弟"，与 `§3.0-61` 互引说明两者区别；
  同步进 `AGENTS.md` §4 高频摘要第 29 条；补齐了踩坑表目录里 §3.0-145~153 的缺失条目。
- `PROJECT.md` §5 证据索引**五处数量与磁盘不符**全部重数；ghost 文件 `layout70x.json` **全工程 0 命中**
  （从未存在）已写勘误；`.` **已整体移除**（不再是"空壳目录待删除"）；
  **补齐缺失的「踩坑」与「下一步 / TODO」章节**（回写 `EXPERIENCE.md` §5 的 8 条残留）。
- `_template\`：补齐缺失的 **`EXPERIENCE.md`** 模板（§6.1 要求三份齐全）；
  `UIMaterial.state` 由大写 `ENABLE` **订正为小写 `"enable"`**（与 §3.0-2 一致，原写法会把新人带进静默失效坑）；
  删除"在 `E:\<工程名>` 建工程 + 知识镜像"与指向已不存在的"根 `AGENTS.md` §3.0"两处死引用。
- `AGENTS.md`：工程数 **6 → 7**；DeepSeekHm / DshMobile / PrismAgent 三行状态按实测订正
  （DshMobile 描述「自研悬浮玻璃胶囊底栏」→ 第 7 轮起改官方 `Tabs` 的 `tabBar`、第 17 轮移除原生工具栏；
  最近验证第 12 轮 → **第二十轮**）。
- **新发现并如实记录**：`.workbuddy\` 原写"已被 `.gitignore` 覆盖、不进版本库" → 实测**相反**
  （`git ls-files` 命中 `memory/2026-09-05.md`，`git check-ignore -v` 无输出）；
  `EXPERIENCE.md` §5-6 原写四个死资源"保留备查" → 实测**第十五轮已删除**。
- `README.md` 与根 `README.md`：deepseek-hm 状态落后两轮已订正（→ 第十五/十六轮、**15 个** `verify-*`）；
  证据清单补 `内部验证记录`（第十三轮）、`内部验证记录`、`内部验证记录`、
  `内部验证记录`；根 README 项目一览**补上缺失的 aa-hm 行**。

**证据**：`内部验证记录` ——
`REPORT.md`（**verifier 独立验证**：产物锚点、B0~B9 逐项判定、
§8 补测与结论更正、§9 方法论补充）、`baseline.md`（改造前基线读数 + 可追溯性核对）、
`platform\`（平台层证据包：`check-platform` / `check-sdk-symbols` / `check-widget-whitelist` /
`form-config-evidence` / `hap-inventory` / `platform-diff`）、`r16-integration-check.sh`（30 项集成复核）、
`r16-base-*.jpeg` 与 `r16-post-*.jpeg`（改造前后逐屏对照）。

> **读数口径提醒（产物锚点已迭代四次，务必对齐）**：
> `REPORT.md` 自身声明的是 **`704,918 B / md5 e5423a22…`**（其 §0 / §8 / §11 口径），
> 而它 §2 之前的部分章节记录的是更早的 **`696,511 B / md5 fcf4310a…`**；
> **本轮最终交付产物是 `706,225 B / md5 9d1a6256…`**（见本节开头，第三批冻结）。
> 各版差异只来自 B8 修复、诊断日志、面板投影、侧栏界线与顶栏渐变这几处改动，
> **不影响该报告对 B0~B7、B9 的判定**；verifier 的**真机复验节**落盘后以其声明的最新锚点为准。

### 9. 第三批：侧栏界线 / 顶栏渐变模糊 / 恢复系统设置并修好驱动链路（真机 Mate70 Pro+）

**本批是用户第三条要求的收口** —— 用户原话："**侧边栏窗口和其他页面还是有明显界线**"。
上一批只改了**阴影**（那是另一个问题）；本批**放大真机截图**才看清：**界线就是两条刻意的发丝线**。

#### 9.1 侧栏界线（用户第 3 条）

- **根因**：面板右缘 `.border({ width: { right: HAIRLINE } })`（竖线，**且只画右边** ⇒ 在两个圆角处
  突然开始/结束）+ 顶栏底边 `.border({ width: { bottom: HAIRLINE } })`（横线）。
- **修法**：**两条线都删掉**，边界改由"**磨砂玻璃色差 + 对称淡晕投影 + 渐隐过渡带**"表达
  （三者都是**渐变**的，不存在硬边）。随之删掉四条资源引用（`shell_panel_edge` 等，见 `PROJECT.md` §10）。
- **真机确认**：侧栏右缘、顶栏下沿**都没有硬边了**。

#### 9.2 顶栏"由下自上逐渐模糊"（用户第 2 条）

- 新增令牌 `TOPBAR_FADE_H`(**16vp**) + 顶栏整块 `linearGradient`（top→bottom：玻璃色保持到主体下沿，
  再在过渡带内**渐隐到全透明**），并**删掉原来那条底边发丝线**。
- 新增一对**同 RGB、alpha = 0** 的渐隐色资源 `shell_topbar_fade`（浅 `#00F2F2F3` / 深 `#0028282A`）——
  若用 `Color.Transparent`（**透明黑**），过渡带插值会**发灰**。
- **真机效果**：内容从下方滚上来时**逐级变糊**，不再在一条线上突然变糊。

#### 9.3 恢复「系统设置」并**真正修好**驱动链路（用户第 1 条，**反转上一批的决定**）

- **入口已恢复**：账号菜单 = 「**系统设置**」+「退出登录」；「帮助与反馈」**用户本轮未点名，维持移除**。
- **安全属性保留**：原生侧与桥侧各一道**同一份白名单**（`ACCOUNT_OPTION_SETTINGS` / `ACCOUNT_LOGOUT_LABEL`），
  **不收回成自由入参** —— 与上一批为 §3.0-93 立的规矩一致（`ShellScript.ets:1007` 明确写了两侧"必须逐字一致"）。
- **"点击不生效"被彻底修好**，根因是**三层叠加**（真机 + CDP 逐层实证）：
  1. **`runJavaScript` 回传的是 JSON 文本** —— 页面侧 `return 'ok'` 到原生侧是 `"ok"`（**带引号**），
     而原生做的是**精确全等比较** ⇒ 永不匹配。这是**最后一环**，也是上一批"点了没反应"的真凶
     （当时只重试 `not-found`，带引号的 `"not-found"` 同样不匹配 ⇒ **既不成功也不提示，静默断链**）。
     修法：新增 `toJsText()` 归一化。→ 已沉淀为 `§3.0-153`。
  2. **官方账号入口在隐藏抽屉里**（整条祖先链 `visibility:hidden`）—— 而**隐藏元素不接收点击**，
     `tap()` 派发的事件不会被 React 响应；且它**能被几何判据找到**（rect 非零），所以"只查坐标"查不出来。
     修法：新增 `tapInHidden()` —— 临时把祖先链改成 `visible + opacity: 0`（**可命中但用户看不见**），
     点完 400ms 后恢复。
  3. **链路是两步**：点账号入口 → 打开**下拉菜单**（下载手机应用 / 系统设置 / 帮助与反馈 / 退出登录）
     → **再点**「系统设置」才开设置弹层。老实现只有第二步，而第一步因为 (2) 从未成功 ⇒ 第二步永远 `not-found`。
- **真机日志终态**：`menu=0` →（点开菜单）→ `menu=1` → `res=ok` → `account option done: 系统设置`
  （**167ms 内完成，一次重试**）。
- **手机版布局**：真机截图确认设置页本来就是**手机版**（横滑 tab「通用设置 / 账号管理 / 数据管理」+
  卡片式主题选择 + 单列），**无需额外适配**。
- **顺带修掉一个同源既有缺陷**：`onColorModeChange` 的主题探测也用精确比较（`'dark'` / `'unknown'`）
  ⇒ **深色下 `(false !== true)` 恒真 ⇒ 每次切深色都无条件整页 `refresh()`**（用户看到"切主题时闪一下重载"），
  而"探测一致就不重载"的**省流分支从未走到过**。已加 `toJsText()`。

#### 9.4 验证与证据

- **构建**：BUILD SUCCESSFUL / **0 warning**；注入脚本预检 **CHECK-INJECTED-JS: PASS**；
  **集成复核 33 项 PASS / 0 FAIL**（脚本 `内部验证记录`。
  其第 4 项口径已同步更新：从"账号菜单只留退出登录"改为"**白名单 = 系统设置 + 退出登录、且不含帮助与反馈**"，
  脚本内还留了口径变更说明）。
- **证据**：`内部验证记录`（6 个文件：顶栏渐变、侧栏无界线、设置页）；
  `内部验证记录` 是上一批（阴影修复）。

### 10. 第四批：顶栏模糊对标官方（24 → 12 → 6，真机两次下调）

用户两句反馈驱动本批：先是"**顶栏下内容不可见，模糊效果过重**"，再是"**要达到像官方那种效果，
模糊还是过重了**"（对标物 = 用户指定的华为系统设置沉浸顶栏）。

#### 10.1 根因一：`backgroundEffect` 的模糊**在组件边界外继续采样**（24vp 时最刺眼）

- 真机实证 `real-device-r4/same24-3.jpeg`：顶栏下沿**之外**（正文的可见区内）第一行
  「技园的"中国储能大厦"，而"CTG"标志可能代表…」仍然是**糊的**，与顶栏内一样糊成一块。
- 即**模糊实际生效的高度 = 顶栏高度 + 外溢量**，再叠上 `TOPBAR_FADE_H`(16vp) 的渐隐带，
  顶栏下方近 40px 的内容全部看不清 —— 正是用户说的"顶栏下内容不可见"。
- **半径越大外溢越多**，所以"降半径"同时修两件事：外溢收窄 + 穿栏内容变清晰。

#### 10.2 根因二：12vp 虽已无外溢，但**穿栏内容仍糊成一块**，与官方观感不同档

- 第一次下调（24 → 12）后复采：顶栏下沿**第一行立即可读**（`back2.jpeg`），外溢问题解决。
- 但**穿过顶栏的内容本身**仍被糊成一团 —— 而官方（华为系统设置，`hw-top.png`）的观感是
  "**字形轮廓仍清晰可辨**，只是被柔化 + 蒙了一层薄色"，**不是糊成色块**。
- **教训（本批最重要的一条）**：判据必须是**对标观感**，不是"有没有外溢"；
  只盯着外溢量会**以为调够了**，实际离对标物还差一档。

#### 10.3 结论值：`TOP_BAR_BLUR = 6`

- 同位置 A/B（**同一滚动序列、画面逐像素对齐**）：`real-device-r4/same24-3.jpeg`（24vp）vs
  `b6-3.jpeg`（6vp）—— 顶栏区同一行字，前者**糊成灰块**、后者**逐字可读**，且与 `hw-top.png`
  的「星闪和蓝牙」同一档。
- 该值**一处可调**（`common/ShellUi.ets` 唯一常量）；若仍觉重，下一档 4；若觉过轻，回到 8/12。

#### 10.4 顺带解除一条**过期的历史约束**

- 旧注释要求 `TOP_BAR_BLUR` **必须与 `PANEL_BLUR`(24) 同值**，理由是"两者交叠处会出现
  糊↔更糊的横向分界"。**该约束不成立**：侧栏面板在自己的层上做模糊、顶栏的模糊只作用于顶栏
  自身矩形，两者**各自独立**，不存在同一条接缝上两种糊度的问题。
- 真机复核：侧栏展开态顶栏下沿无新增分界（`real-device-r4/side.jpeg`）。**两个常量就此解耦**。

#### 10.5 本次交付的产物锚点（**取代 §0 与 §9 的旧锚点**）

| 版本 | 大小 / 时间 | md5 | 对应反馈 |
| --- | --- | --- | --- |
| **本轮最终** | **706,264 B / 2026-09-15 21:40:52** | **`9c0eedccf5afad6fe014f2536494c131`** | 顶栏模糊 6vp |
| 上一批 | 706,263 B / 21:23:26 | `d555b9ebe731b169b70919bd1ccf1925` | 模糊 24 只在主体 |

- 构建：**BUILD SUCCESSFUL / 0 warning**；真机 Mate70 Pro+ 覆盖安装（`install -r`，保登录态）实测无崩溃。
- 证据：`内部验证记录`（11 个文件，含同位置 A/B、官方对标、侧栏接缝）。

#### 10.6 本轮工具侧教训（与产品无关，但会重复踩）

- **`hdc file recv` 的目标路径必须写成反斜杠的 Windows 绝对路径**（`C:\Users\...`）。
  写成 `C:/Users/...` 时 hdc **不报错**，而是把它当**相对路径**拼到当前工作目录下
  （`仓库根目录\C:/Users/...`），表现为"截图落进了工程目录" —— 上一轮那批误落截图即此因。
- **PowerShell + `System.Drawing` 在本机不可用**（`New-Object System.Drawing.Bitmap($p)` 返回 `null`，
  后续全 `InvokeMethodOnNull`）：**像素级取证别走它**，直接用真机截图目视 + 同位置 A/B 更可靠。


## 第十七轮（2026-09-16）：设置入口"左下角闪窗" + 系统设置弹层改手机版布局（真机）

**需求（用户原话两句）**：
> 1. 侧边栏点开系统设置后左下角会短暂闪过网页原生弹窗，看怎么隐藏掉
> 2. 系统设置仍用着网页版排布，每次切换窗口都会刷新，不美观，看怎么将布局改为适合手机的布局

两条都属于"**只看截图看不出来**"的类型：第 1 条只闪 0.3 秒，第 2 条的数字差在几十像素。
本轮全程用 **ArkWeb DevTools + CDP** 把数字量出来（零构建 A/B），再做**装机后的真实链路**复验。

### 1. 定位（真机实测，先有数再动手）

页面基线（装机版）：viewport **443×952 CSS px**、dpr 2.975、`__dshTopInsetPx = 97.714`。

| 现象 | 实测数据 |
| --- | --- |
| 左下角闪的那个"原生弹窗" | 官方账号下拉菜单 `.ds-dropdown-menu`，挂在 **body 级** `.ds-floating-position-wrapper.ds-theme` 下；rAF 采样：t=6020ms 出现 rect `[8,726,136,168]`（正是左下角）、opacity 0→**1**(t=6120)→0、t=6308 节点消失 ⇒ **可见约 290ms** |
| "网页版排布" | 弹层 `.ds-modal-content` = `[0,152.3,443,800]`：wrapper padding-top 103.7(**topInset+6**) + `.ds-modal` margin-top 48.6 ⇒ **顶部 152px 灰带**；页签行 `scrollW/clientW = 452/403`，4 个页签各 `min-width:108px` ⇒ **第 4 个（服务协议）360→468 越界被裁**；行 `395×60`、字号 14px |
| "每次切换窗口都刷新" | 页面侧实测：切 4 个页签时 sheet rect / scrollTop / nav.scrollLeft **全不变**、无页面重载 ⇒ 用户看到的是"内容整块瞬换 + 页签行被裁/横向滚动"的**观感**，不是真刷新（对症做法是把布局做成稳定、不裁切） |

### 2. 改动一：浮层视觉闩（`ShellScript.ets`，T1）

根因：驱动链路为了让**隐藏抽屉里**的账号入口可点击，把它整条祖先链临时改成 `visibility:visible; opacity:0`；
而官方下拉菜单是 React portal，**不在那条链里** ⇒ 整块露在左下角。
修法：`pickAccountOption('系统设置')` 在**派发点击之前** `armMenuVeil()`，给「含 `.ds-dropdown-menu` 的浮层 + 菜单本身」打
`data-dsh-menu-veil`，由常驻样式表压 `opacity:0 !important; transition:none !important`（**只能动 opacity**：visibility /
pointer-events / display 都会破坏合成事件命中）。打标挂在 `MutationObserver`（微任务、早于本帧绘制）⇒ 一帧都不露。
落闩三条路：菜单节点从 DOM 消失（主路径，实测 t≈736ms）/ 3s 硬超时 / 「退出登录」分支显式落闩。已沉淀为 `§3.0-154`。

### 3. 改动二：系统设置弹层 → 手机版设置页（`DeepSeekConfig.ets`，T2）

做法：按「`.ds-modal-content__title` 文本 === '系统设置'」定位 → 打 `data-dsh-settings-*` 属性 →
**CSS 全部写在属性选择器上**（官方类名是 CSS Module hash，跟着写会在官方下次发布时静默失效），并整块包在
`@media not all and (min-width: 768px)` 内；配色由 `syncSettingsColors()` 从官方弹层**实测色采样**写成内联 CSS 变量。

| 指标 | 改前 | 改后 |
| --- | --- | --- |
| 面板 rect | `[0,152.3,443,800]` | `[0,98,443,855]` |
| top 与 topInset 之差（顶部灰带） | **54.59px** | ≈0（top = topInset，多让 20px 见 §4） |
| `max-height` | 800px（官方截断） | none |
| 页签行 scrollW/clientW | **452/403**（第 4 个越界） | **411/411**（4 个页签 rect 全在行内） |
| 行高 / 字号 | 60px / **14px** | 60px / **16px** + 16px 圆角卡片 + 发丝线 |
| 主题三选一 | 三张 82px 描边大卡 | 分段控件 |
| 页签选中态 | 官方 hash 类 | `ensureSettingsAccent` **现场发现**选中 hash（"只出现在一项 + 该项背景不透明"），不写死 |

### 4. 补丁与根因修复（Lead，真机复验驱动）

T3 的真机复验暴露出一个**新引入**的瑕疵：面板 top 提到 97.7 后，标题行的 ✕ 中心（CSS 122）落在
**原生顶栏的触摸丢包带**里（逐点实测：物理 y ≤336 / CSS≈113 及以下全丢包，y ≥345 / CSS≈116 才送达）。
真因是原生顶栏容器实际高度为 `TOP_BAR_H + topPad + TOPBAR_FADE_H(16)`，**整块容器都参与命中测试**
（与 `§3.0-151` "铺满的兄弟容器照样吃点击"同源）。
修法：`setTopCss` 从 `topInset` 改成 `topInset + 20` —— 多让的这段**仍刷面板底色**，视觉上不重新出现灰带，
但交互元素整体落进可点区。

**但真机逐点复验把归因改掉了**（T4，`REPORT.md` §11）：同一 y 下 **x=1000/1290/1300 送达、x=1258 全丢**，
而顶栏丢包带是**全宽**的 ⇒ 吃点击的另有其人。`dumpLayout` 抓到元凶是**常驻的隐形气泡** ——
`NewChatTipLayer`（`Index.ets`）里那个"已是新对话"的 `Text`：外层 `Column` 虽写了 `HitTestMode.None`，
但 `None` **只豁免自身、子节点照常参与命中测试**，于是不可见的气泡在物理 `[1030,290]-[1281,380]` 上
一直吃触摸（✕ 正好落在那里）。A/B（运行时中和把面板顶还原到 97.71）：同一点 **0/5 送达 → 5/5 送达且 5/5 关窗**。

**因此本轮做了三处改动**（同一轮交付）：

| # | 文件 | 改动 | 性质 |
| --- | --- | --- | --- |
| 1 | `DeepSeekConfig.ets` | `TOPBAR_FADE_GUARD = 20`（面板顶 = topInset + 20） | 绕开顶栏渐变带（兜底） |
| 2 | `Index.ets` | `NewChatTipLayer` 内层 `Text` 补 `hitTestBehavior(HitTestMode.None)` | **根因**：隐形气泡不再吃点击 |
| 3 | `DeepSeekConfig.ets` | 新增 `installThemeClassObserver()`：定向观察 `body`/`html` 的 `class` 属性，一变就重打标 + 重采样 | **根因**：设置页切「深色」后配色即时跟上（原先靠 `matchMedia`，而真机 `prefers-color-scheme` 恒 `false`，只能等 5s 巡检、实测最长约 30s） |

复验见 `内部验证记录` §11（补丁）与 §12（根因修复）。

### 5. 验证（真机 Mate70 Pro+ `DEVICE_SN_REDACTED`，全部 `install -r` 保登录态）

- **构建**：增量 + **clean 全量**两次都 `BUILD SUCCESSFUL`、**0 warning / 0 error**；注入脚本预检 `CHECK-INJECTED-JS: PASS`。
- **T1 A/B（装机后真实链路）**：真实触摸 汉堡 → 账号行 → AlertDialog「系统设置」。
  A 相（闩生效）窗口期内菜单本体 opacity **54/54 样本全 0**；B 相（用更高特异性 !important 把闩中和）**55/56 样本为 1**
  ⇒ **A 相的 0 不是假 PASS**（探针灵敏度有非零相对照）。链路结束 `[data-dsh-menu-veil]` 计数 0，无残留。
- **T2 断言（装机后）**：panel `[0,98,443,855]`、`max-height:none`、页签 411/411 且 4 个全 inside、`bottom=952` 铺到底、行 60/16px；
  **4 个页签真实触摸逐一切换时 panel/tabs/bodyTop/scrollTop 全程不变**（无跳动）；
  浅/深色双组截图与配色实测（深色 root `rgb(21,21,23)`、卡片 `rgb(44,44,46)`）。
  ⚠️ 真机 `prefers-color-scheme: dark` 为 **false**（站点用自己的 `html.dark` 类）⇒ 深色是**色采样路径**生效的，
  `@media` 兜底在真机上不会命中。
- **≥768px 门控**：真机 viewport 固定 443，故用 CDP `Emulation.setDeviceMetricsOverride` 模拟 900×952 ⇒
  手机版规则全部失效、回落官方桌面排布（panel top 226 / maxHeight 920.269），还原后手机版完好。
- **补丁复验（T4，报告 §11）**：把面板顶让位**运行时中和**回修复前几何（`97.7143px`）后，
  ✕ 中心 (1258,363) 真实触摸 **0/5 送达 / 0 次关窗**；装机件几何下 ✕ 中心 **5/5 送达 / 5/5 关窗**。
  逐点扫描还**推翻了原归因**：同 y 下 x=1000/1290/1300 送达、x=1258 全丢 ⇒ 元凶是隐形气泡（见 §4）。
- **根因修复复验（T5，报告 §12）**：
  - **A（气泡）**：把几何中和回修复前位置后，同一点 **5/5 送达 + 5/5 关窗**（同一坐标 T4 是 0/5）；
    x 不对称消失（y=363 的四个 x 全部送达），只剩**全宽**的原生顶栏本体（y≤338）；
    气泡本身仍正常显示（触发后父层 opacity 0→1→0、像素均值 255→(204,208,220)→255），
    顶栏三区（汉堡/标题/+）真实触摸全部正常。
  - **B（主题换色）**：设置页里点「深色」→ 面板底色 **+27 ms** 翻转（还原 **+20 ms**；40ms 轮询分辨率即"下一帧"），
    对照修复前的"2s/8s 仍旧色、35s 才对"；页面侧 log 证实触发源是 **body 的 class**（html 的 class 全程未变）。
- **≥768px 门控**：真机 viewport 固定 443，故用 CDP `Emulation.setDeviceMetricsOverride` 模拟 900×952 ⇒
  手机版规则全部失效、回落官方桌面排布（panel top 226 / maxHeight 920.269），还原后手机版完好。
- **集成复核**：`内部验证记录` → **PASS=42 / FAIL=0**（T5 连续 3 次；Lead 收尾再跑 1 次）。
- **回归**：侧栏开合（61 个会话 + 4 分组 + 账号行）、账号菜单两项、首页输入框聚焦 + 输入法弹出且输入区原地不动、
  4 个页签真实触摸切换（几何四次完全一致）、✕ 多次关闭、深浅色切换并还原「跟随系统」。
- **产物**：`entry/build/default/outputs/default/entry-default-signed.hap`，**748,229 B**，
  clean 全量构建 **0 warning / 0 error**，md5 **`55f97df55cbad875e5db3a86b7223325`**（已 `install -r` 装到真机验证）。

### 6. 本轮通用教训（已沉淀）

| 教训 | 通用坑 |
| --- | --- |
| 隐藏**子树**管不住 React portal；兜底要给浮层本身打标，且只能动 `opacity` | `§3.0-154` |
| 「手机上还是网页版排布」先量 `scrollWidth > clientWidth`；排满一行还要防官方按压环 `inset:-2px` 与动态装饰层 | `§3.0-155` |
| 深色兜底的 `not ... and (prefers-color-scheme: dark)` 会**否定整条查询** ⇒ 浅色也被刷 | `§3.0-156` |
| ArkWeb DevTools 在应用**后台**时"连得上不回应"；先 `aa start` | `§3.0-157` |
| 注入脚本里"被拼进字符串的常量"声明晚于使用点 ⇒ 拼出 `[undefined="1"]`，规则静默失效 | `§3.0-158` |
| 装饰性渐隐带算进容器高度 ⇒ 替容器吃掉那一整条带的点击；`HitTestMode.None` 只豁免自身、**子节点照常参与命中测试**（隐形气泡同理） | `§3.0-159` |

### 7. 证据

`内部验证记录`：`REPORT.md`（真机全流程）、`integration-check.txt`、`build-clean.log`、`check-injected-js.txt`、
`t1-runA-veil-on.json` / `t1-runB-veil-neutralized.json`（T1 A/B 逐样本）、`t1-prefix-baseline-samples.json`（改前基线）、
`t2-assert-{light,dark}.json`、`t2-colors-dark.json`、`native-layout-*.json`（`dumpLayout`）、
`real-device/`（整屏 + 页面侧截图，含 `20-*` 补丁复验与 `21-*` 根因修复复验）、
`scripts/`（本轮探针与驱动脚本副本）；补丁/根因修复的复验数据在 `r17b-*` / `r17c-*` 前缀文件
（`r17c-tap-tipfix-old-position.tsv`、`r17c-theme-switch-dark.json`、`r17c-topbar.txt`、`r17c-integration-check.txt` 等）。

## 第十七轮 · 第二单（2026-09-17）：二轮反馈 —— 侧栏面板圆角裁切 + 设置页"滑动不出滑块"

**需求（用户原话）**：
> 1. 侧边栏点击设置产生的变黑层没有圆角优化，导致阴影超出圆角，不美观
> 2. 系统设置界面改为固定页面，做滑动动作时不要产生滑块

用户还补了两张截图 —— 本轮两条**都是靠截图才认出来的**（第一条原生层树里查不到任何暗色层，第二条我们自己复现不出来）。

### 1. 定位

| 现象 | 实测（真机） |
| --- | --- |
| ① "变黑层" | 用户截图（底部 360px 裁切）实测：账号行整条被 `#E8ECF7`（= `app.color.shell_item_active_bg`，即 `stateStyles.pressed` 底色）铺满，色带 y 2578..2733，**右缘恒为 1045/1046（只收窄 1px）**，而面板右下柔弧就落在 y≈2695..2733 ⇒ **矩形底色越过了圆角** |
| ② "滑块" | 用户截图实测：右侧 x=1248..1256 有一条灰 `#919294` 竖条、几乎整屏高；Lead 复现机制：设置页滚动区 `scrollHeight == clientHeight == 734` 但**真实内容高 733.997 / 内容盒 733.571 ⇒ 恒溢出 0.426px**，CDP 拖拽把它**真的滚走 0.336px**（`scrollTop = 0.336` 是这条缺陷的指纹） |

### 2. 改动（两处）

| # | 文件 | 改动 |
| --- | --- | --- |
| ① | `view/SidePane.ets` | 面板 Column 的 `.borderRadius(...)` 之后加 **`.clip(true)`** —— ArkUI 的 `borderRadius` 只作用于组件自身背景，子节点默认不被父圆角裁剪（SDK: not clipped by default），所以满宽子行的按压/选中底色会在圆角处露直角 |
| ② | `utils/DeepSeekConfig.ets` | 四件一起：`html[data-dsh-settings-open="1"]` 标记 + **隐藏滚动条**（`scrollbar-width:none` 与 `::-webkit-scrollbar{display:none}`，**必须覆盖 html/body 本身** —— 那条竖条是文档级的）+ 隐藏站点自绘 `ds-scroll-area__gutters` + **消亚像素溢出**（官方 `--stretch` 把内容撑到取整的 734px；改 `min-height:0`，另加 `pinSettingsBody()` 兜底）+ **钉页面**（`overscroll-behavior:contain` + `touch-action:pan-y` + 打开期间 `overflow:hidden`；刻意**不用** `touch-action:none`，否则内层滚动一起死） |

### 3. 验证（真机 Mate70 Pro+ `DEVICE_SN_REDACTED`，`install -r` 保登录态；md5 `9d91b297a9665193b55618ac65d3996a`）

- **构建**：clean 全量 `BUILD SUCCESSFUL`，**0 warning / 0 error**；注入脚本预检 `CHECK-INJECTED-JS: PASS`。
- **① 圆角裁切**：同一把尺（先量改前再量改后）—— 末段右缘收窄 **1px（改前 = LEAK）→ 80px（改后 = CLIPPED）**；
  另三项：投影与顶角**逐像素改前改后完全一致**（说明 `clip` 只裁子节点）、面板子树 70 节点右缘最大值 = 面板右缘（越界 0）、右上角 3× 放大正常。
- **② 竖滚动条**：拖动前 / 真实触摸拖动后 / 按住拖动**期间**三张整屏像素扫描**均无**竖条；
  `scrollTop 0`、`scrollDiff 0`、官方 gutter `display:none`、`html/body/滚动区` 的 `offsetWidth-clientWidth` 全 0、设置页"有占位差且可滚"容器 0；标记开则挂关则摘、`scrollbar-width` 复原。
  **两重正对照**（防"抓不到其实是看不见"）：还原改前条件后同一扫描器立刻在 **x=1247..1269** 抓到竖条（与用户报的 1248..1256 吻合）；合成 8px 竖条在 x=1250..1272 被抓到。
  **能滚但无滑块**的取舍没被掐死：真溢出（diff 452）下真实拖动 `scrollTop → 323.7`。
- **回归**：4 个页签逐个真实触摸切换（每个页签下机制量全 0）、✕ 真实触摸关闭后标记摘除 / 属性复原、
  设置页打开期间其它弹层遮罩仍在、侧栏开合（62 会话 + 4 分组 + 账号行）、深浅色切换并还原「跟随系统」。
- **集成复核**：`r17-integration-check.sh` **PASS=42 / FAIL=0**。
  顺带**更正上一单 §11.6-② 的定性**：那不是"瞬时抖动"，而是**确定性**的 —— 脚本第 3 段把 POSIX 路径直接交给
  Windows 版 node.exe，平时靠 Git Bash 自动转换；关掉转换（`MSYS_NO_PATHCONV=1`）必现 `ENOENT`。与产品无关，脚本未改。
- **产物**：`entry/build/default/outputs/default/entry-default-signed.hap`，750,965 B，md5 `9d91b297a9665193b55618ac65d3996a`。

### 4. 本轮通用教训（已沉淀）

| 教训 | 通用坑 |
| --- | --- |
| ArkUI 父容器写了 `borderRadius` **不会**裁子节点 —— 满宽子行底色会在父圆角处露直角，要 `.clip(true)`；判据是"逐行取底色最右 x"看收窄量 | `§3.0-160` |
| "内容放得下却出现滚动条"先查**亚像素溢出**（`min-height` 取整差 0.4px）；`scrollTop` 拖动后变成 0.3xx 是它的指纹 | `§3.0-161` |

### 5. 证据

`内部验证记录` 的 **§13**（第二轮反馈复核）+ `r17d-*`（14 个断言/对照原始输出）+ `real-device/22-*`（12 张，含
`22e-corner-side-by-side.png` 左右对照、`22i-control-old-conditions-bar.jpeg` 正对照能看到那条灰竖条）+
`scripts/r17d/`（55 个脚本，含判定器 `corner-assert.py`）。

---

## 第十八轮（2026-09-17）：顶栏丢包带原生根治 + 避让通道复活 + 站点主题跟随 + 外壳统一（模拟器）

**本轮任务书（Lead 派单，四条并行）**：修 bug + UI 美化统一 + 治「闪屏 / UI 不统一 / 点击失效」+ 精简代码 + 提速度 + 强稳定。
四人分工：W1 原生外壳（`common/ShellUi.ets` / `view/TopBar.ets` / `view/SidePane.ets` / 两份 `color.json`）、
W2 注入层（`utils/DeepSeekConfig.ets` / `utils/ShellScript.ets`）、W3 主页面（`pages/Index.ets` / `entryability/EntryAbility.ets` /
`model/ShellTypes.ets` / 卡片）、Lead 设备侧验收。**全部结论都经模拟器真实触摸验收**（见 §4）。

### 1. 定位：三条根因（都属「只看截图看不出来」的类型）

| 现象 | 定位读数 | 真因 |
| --- | --- | --- |
| 顶栏下方一条带里的点击**送不到网页** | 第十七轮真机逐点扫描：物理 y ≤ 336（CSS ≈ 113）全丢包、y ≥ 345 才送达 ⇒ 下界 = `topInset`(97.7) + **16** | 顶栏容器高度含装饰性的 `TOPBAR_FADE_H`(16)，而 ArkUI **容器整块参与命中测试** ⇒ 看着空白的带子照样吃触摸。第十七轮只在网页侧绕（内容下移 `topInset+20`），**原生这条根一直留着** |
| 键盘弹出后**几何不重算**（避让量写进了 window，占位却不跟） | 宿主探的通道名 `window.__dshSetInsets` **全工程零定义**（W2 本轮补上才存在）；且宿主对回传值的 `res === 'no-channel'` 判断撞上 §3.0-153「回传是带引号的 JSON 文本」⇒ **恒为假** | 两个独立缺陷叠在同一条链路上：**入口名不存在** + **判据永远不成立** ⇒ 轻量通道恒判「不存在」，`ensureTopSpacer()` / `applySafeArea()` 一次都没被调用过 |
| 站点里切主题，**原生外壳不跟** | 真机 `prefers-color-scheme` **恒 false**（站点用 `html.dark` 类，不用系统媒体特性） | 只挂 `matchMedia` 不足以跟随站点主题；改为读站点**偏好**（`localStorage` 键）+ 映射到 app `colorMode` |

### 2. 改动（按作用域）

#### 2.1 W1 原生外壳 —— 点击失效的**根因**修复 + 令牌统一 + 侧栏开合零跳变

| # | 文件 | 改动 | 依据 |
| --- | --- | --- | --- |
| ① | `view/TopBar.ets` | 顶栏**根容器**补 `.hitTestBehavior(HitTestMode.None)` | §3.0-159 修法 2。`None` 语义 = 自身不吃命中、**子节点照吃** ⇒ 渐隐带里的触摸穿透到 Web，顶栏主体的三槽 `Row` 与按钮照常可点 |
| ② | `view/SidePane.ets` | 定位时序重做：**打开当拍**就用已有行数据定位（去掉 900ms 兜底定时器），幂等判据从布尔 `pendingLocate` 换成**会话 id** `locatedKey` | 旧链路真正滚动发生在 rescan 数据到达之后（100~300ms，正落在 350ms 进场动画里）⇒ 列表先停顶部再「啪」地跳。改后第一帧即终态，数据再来时因「目标没变」直接跳过 |
| ③ | `view/SidePane.ets` | 两个 32vp 文字按钮（「完成 / 全选」与「删除」）补 `.responseRegion()` 把**可点**高度补到 44；面板头三个图标按钮改用与顶栏右槽同源的 `Row({ space: GAP_XS })`；SelectBar 内边距 12 → 16/8 | iOS HIG 最小触控 44×44；同类控件两套间距、两套内缩口径 |
| ④ | `common/ShellUi.ets` | 新增 17 个令牌（`HOT_MIN` / `SEARCH_H` / `ICON_INLINE` / `SPINNER_SIZE` / `AVATAR_SIZE` / `MENU_BAR_*` / `MENU_GLYPH_*` / `BLUR_SATURATION` / `BLUR_BRIGHTNESS` / `FADE_*`）；`DARK_BRIGHTNESS` 收敛为 `BLUR_BRIGHTNESS` 的**别名**（仍 1.0，导出名不删）；**删 3 个零消费者令牌** `MOTION_SLOW` / `PRESS_SCALE` / `SHADOW_DY_MD`（各留处置注释） | 本文件自己的纪律：「一个零消费者、却看起来像配置项的令牌比没有更糟」；实测「模糊本身中性、色差全来自玻璃色」⇒ 深色补偿在数值上不存在 |
| ⑤ | `view/SidePane.ets` | 删掉只做转发的 `@Builder PanelIcon`（转发层本身就是第二份配方） | 同类控件只留一套配方 |

#### 2.2 W2 注入层 —— 通道复活 + 死代码/体积收敛 + 设置页签

- **补上 `window.__dshSetInsets`**（此前宿主在探、页面上从未定义），并把 §3.0-153 的引号问题一起收口 ⇒ 轻量避让通道**第一次真的通**；
- 修 `tapInHidden` 的**原值恢复口径**：原值只在首次记录（挂元素 expando）+ 恢复定时器去抖 —— 旧实现每次把「当前值」当原值，140ms 重试链下第二次读到的就是自己写的 `opacity:0`，会把抽屉根**永久留在透明**上；
- 删除 7 个零引用死符号（`NEW_CHAT_JS` / `DIAG_MENU_JS` / `diagnoseSidebar` / `markSideDrawers` / `__deepseekHmDiagnose` / `__deepseekHmMarkSideDrawers` / `deepseekHmNewChatStart`，合计 **3,015 B**）；注入**下发体积 109,612 → 108,332 B**；
- 设置页 4 个页签改 `flex:1 1 0 + min-width:0`；重复的选中态声明抽成公共串 `ACCENT_DECL`、两条图标规则合并成一个选择器列表。

#### 2.3 W3 主页面 —— C2 站点主题跟随 + C3 不重载 + 稳定性

- **C2**：读站点**偏好**（`localStorage` 的 `__appKit_@deepseek/chat_themePreference`，只读偏好不读观感）+ 映射到 app `colorMode` + 同值不重设（防 `setColorMode` 与 `onColorModeChange` 自激）；
- **C3**：站点里切主题**不重载**（`performance.timeOrigin` 不变、设置弹层不消失、chromium `page load start` 0 行），每次切换只有一行 `colorMode N caused by site theme, skip probe/reload`；
- 注入去重（`shellInjected`）+ 页面加载看门狗（15s，未误伤）+ `runJsFor` 统一入口（把 §3.0-153 的归一化从「纪律」变成**结构约束**）+ `disposed` 闩（销毁后的异步续作不再写 `@State`）。

### 3. 关键机制：A/B 正对照（本轮最值钱的一步）

§3.0-159 那条修法**只有真实触摸能证伪**（`dumpLayout` 里一律 `clickable: true`、构建 0 warning）——
所以 Lead 在验收期**临时注释掉**顶栏根容器那一行，装包只跑 S6，拿到旧行为读数后**逐字节还原**：

| 相 | 条件 | S6 读数（渐隐带 321..370px，8 个真实触摸点） |
| --- | --- | --- |
| 对照组 | 注释掉 `.hitTestBehavior(HitTestMode.None)` | **`got=0`**（8 点全丢） |
| 实验组 | 该属性在场 | **`got=8`**（8 点全到） |

唯一变量就是根容器那一个属性 ⇒ **因果归属成立**，不是「本来就通」的假 PASS。
还原经 W1 独立复核：`view/TopBar.ets` md5 `49be49db2517086a2d6383e6342b991e`（与改动前冻结值逐字节一致）、
`grep -c hitTestBehavior(HitTestMode.None)` = 2。

### 4. 验收读数（模拟器 Pura 90 Pro，1316×2832 / dpr 3.5；`install -r` 保登录态）

```
== S1 冷启动只注入一次  :: count=1            == S2 避让通道无 unavailable
== S3 看门狗未误伤                           == S4 无崩溃
== S6 渐隐带 [321..370px] 8 点全部送达       :: got=8
== S7 汉堡真实触摸展开 / toggle 收起
== S8 点第 3 行进入会话                      :: /a/chat/s/6ae61cbc-…
== S9a 4 个页签均不溢出 :: [[通用设置,52,52],[账号管理,52,52],[数据管理,52,52],[服务协议,52,52]]
== S9c/S9d __dshSetInsets 已定义 / 返回 ok
== S10a 站点深色后原生顶栏转深               :: 242,243,245 -> 23,23,25
== S10b/c/e 切深 / 切浅 / 跟随系统均未重载且弹层仍在 :: docSame=true
== 结果 PASS=24 FAIL=1
```

**唯一的 FAIL（S10g）是测量假象，不是缺陷**：原判据是「按 `hilog -x` 全缓冲区 grep `caused by site theme` 应每切换一行」，
得 0 行；但 hilog 是**环形缓冲**，chromium 每秒刷几千行，等读时早被挤掉。改为「切完 2s 内立刻读」后
**每次切换恰好一行** `colorMode N caused by site theme, skip probe/reload` ⇒ C3 判据实际全绿。

避让通道三入口另做了运行时对照：`["ok","ok","ok"]`；**负对照**（只删掉 `__dshNativeShell.setInsets` 这一个属性）
门面返回 `no-channel` ⇒ 门面的「通道在不在」判据可达且正确。

### 5. 精简：**体积口径下降，源码行数上升**（如实记录，不包装成精简成功）

| 口径 | 读数 | 说明 |
| --- | --- | --- |
| 注入**下发体积** | 109,612 → **108,332 B** | 删死符号 3,015 B + 去重复 CSS 声明 |
| 零消费者令牌 | **−3** | `MOTION_SLOW` / `PRESS_SCALE` / `SHADOW_DY_MD` |
| `view/SidePane.ets` 行数 | 1201 → **1197** | 删转发层 + 定位机制收窄 |
| `view/TopBar.ets` 行数 | 236 → **236** | 常量上收（−14）与根因记录（+14）相抵 |
| `common/ShellUi.ets` 行数 | 288 → **344** | **+56，全部是新增令牌及其「依据」注释** |
| `pages/Index.ets` 行数 | 2265（轮初）→ **2633** | 净增来自 C2/C3 的状态机与生命周期收口 |

⇒ 本轮**没有**做到「总行数下降」。两条原因：①修 bug 的净增代码（主题同步、注入去重、加载看门狗、生命周期收口）；
②本工程既定的「每条常量 / 每处改动都写依据」注释风格 —— 删 3 个令牌要写 8 行处置记录，加 17 个令牌要写 40 余行依据。
**体积与死代码口径是真实下降的**（下发 −1,280 B、7 个死符号、3 个假旋钮），**行数口径不是**。

### 6. 本轮通用教训

| 教训 | 通用坑 |
| --- | --- |
| 顶栏**根容器**的命中面包含装饰性渐隐带 ⇒ 带子里点击传不到下层；`HitTestMode.None` 是正解（自身不吃、子节点照吃），**且必须做 A/B 正对照**才能证明 | `§3.0-159` |
| 「轻量通道恒判不存在」这类静默失效会**两处叠加**：入口名从未定义 + 回传值带引号导致 `===` 恒假 —— 修一处不够 | `§3.0-153` |
| **产物 mtime 不能当「是否同步」的判据** —— hvigor 从 cache 恢复未变文件会保留 mtime，「产物旧于源码」是假信号；改用**内容抽样** | `EXPERIENCE.md` §1.12 |
| 断言脚本自己也要做**变异测试**，且要在别人把它当 PASS 依据之前做 —— 否则假绿会被写进交付说明 | `EXPERIENCE.md` §1.12 |

### 6.5 真机复核（同日第二段，Mate70 Pro+ `DEVICE_SN_REDACTED`）

模拟器与真机**同一份产物**（`entry-default-signed.hap` 788,040 B，`install -r` 保登录态）：

| 项 | 模拟器（Pura 90 Pro，dpr 3.5） | 真机（Mate70 Pro+，dpr **2.975**） |
| --- | --- | --- |
| 集成验收 S0~S10（**同一套设备无关脚本**） | PASS=28 / FAIL=0 | **PASS=28 / FAIL=0** |
| §3.0-159 顶栏渐隐带 8 点真实触摸 | got=8 | got=8（物理 y 294..336） |
| 顶栏像素 浅→深 | 242,243,245 → 23,23,25 | 242,243,245 → 23,23,25 |
| 设置页签 4 项 | 均不溢出 | 均不溢出 |
| C3 切主题不重载 | `timeOrigin` 不变 / 弹层在屏 / `page load` 0 行 | 同左 |

**四处"换个平台就假失败"的差异（都已修进脚本）**：
1. **dpr 不同**（2.975 vs 3.5）⇒ CSS↔物理像素换算必须从 CDP 现读 `devicePixelRatio`；
   写死 3.5 会让丢包带探测带整体偏下约 18%，"看起来通过"其实是打在别处。
2. **原生 AlertDialog 的按钮在 `dumpLayout` 里是 `clickable=false` 的 Text 节点**（两平台一致）
   ⇒ 按文本找控件若只认 `clickable`，永远找不到「系统设置」，**整段设置链路静默跳过**。
3. **主题是持久化的**（站点偏好 + 应用 colorMode 都留存）⇒ 用例开头必须归零到已知状态，否则"点深色"无变化被记成 FAIL。
4. 真机 hilog 淘汰更快 ⇒ 日志计数必须**当场读**（§3.0-162）。

⇒ 沉淀：**"同一把尺"不能只在同一台设备上成立**。设备无关的验收脚本三条硬要求：
dpr 现算、控件按文本/描述定位而非坐标、状态先归零。证据 `内部验证记录`。

### 7. 证据

`内部验证记录` —— **先看 `REPORT.md`**（Lead 的验证报告：判据、读数、未覆盖项、证据索引）。

| 位置 | 内容 |
| --- | --- |
| `accept/r18v4b-result.txt` / `accept/emu-final2-result.txt` | 模拟器集成验收原始输出（设备无关脚本的收官轮 = PASS=28 / FAIL=0） |
| `ab-test/README.md` | A/B 正对照（got=0 ↔ got=8）+ H 组三入口探针 + S10g 判据订正 |
| `before-sweep/`、`after-sweep/` | 改前/改后全链路截图与 `dumpLayout` |
| `w1-review.md`、`w3-timers.md` | W1 对抗式复核（13 条 Finding）、W3 定时器清单表 |
| `scripts/` | 本轮全部脚本（验收 / 巡检 / CDP / 像素取样 / 构建 / 三份自检 / 跳变测量） |

注：本轮判据两次出现**假 FAIL**（`S10g`）—— 第一次是 hilog 环形缓冲淘汰早期行，第二次是采样窗（1.6s）短于站点主题的
2s 值守轮询。两次都定位为**测量问题而非产品缺陷**，原始读数与定性见 `REPORT.md` §三。

构建判据（本轮新增纪律）：`BUILD SUCCESSFUL` **且 `CompileArkTS` 与 `PackageHap` 都实际执行** —— 全 UP-TO-DATE 的「假绿」不算；0 ERROR / 0 WARN。

---

## 第十九轮（2026-09-18 ~ 09-19）：精简提速 + 残余 bug + 参考 iOS 彻底优化 UI（**真机**）

**用户原话**：① 优化 DeepSeek 手机端，彻底精简代码，提高运行速度；② 检查是否还存在影响体验的 bug；
③ 多去参考 iOS 端 DeepSeek，每个页面截图看，把鸿蒙手机端 UI 彻底优化。

**组织方式**：Agent Teams —— 1 Lead + **4 teammate**（写作用域互斥：注入层 / 原生 UI / 主页面 / 只读审计），
Lead 独占设备与构建。证据与逐项读数见 `内部验证记录`。

### 1. 交付锚点

| 项 | 值 |
| --- | --- |
| 设备 | **真机 Mate70 Pro+（PLA-AL10 / HarmonyOS 7.0.0.107）**，`DEVICE_SN_REDACTED`，1316×2832 / 实测 dpr 2.975 |
| 构建 | `BUILD SUCCESSFUL / 0 warning`（CompileArkTS + PackageHap + SignHap 均实际执行） |
| 产物 md5 | **`c29f0b0362822e10f777a9f1d745c534`**（808,419 B，`tmp/r19-verify/r19-final-signed.hap`） |
| 装机 | `hdc install -r`（保登录态） |

### 2. 改动（按写作用域）

**W1 注入层**（`utils/ShellScript.ets` / `utils/DeepSeekConfig.ets`）
- 精简：删 6 处零消费者死符号（旧密钥通道 `window.__dshArm`+`ARM_SECRET`、`SEP`/`SEP2`、`state.alive`、`state.sig`、`DEEPSEEK_SHARE_TEXT`）+ 2 处重复 CSS + 1 处重复 `installThemeListener()`；
- 提速：`inNativeDrawer()` 连判 2~3 次→1；同一节点 `getComputedStyle` 2→1；`getInsets()` 分配 2→1；`getBoundingClientRect` 3→≤2；几何判据后移；`img[src*=…]` 属性查询 2→1；
- **sessions 强制全量上报去重**（本轮最大单项）：发送条件改为 `changed || !sessionsSent` + 抽屉子树"未变"证明；**冷启动真机实测 4 次 → 2 次**（夹具：消息 9→2 条、全量抽取 9→3 次）；
- 设置浮层路由语义：新增 `kind:'settings'`（判据复用 r17 的 `data-dsh-settings-open`，零新增扫描；开/关两向都上报）。
- 体积（剥注释后渲染文本，权威口径）：SHELL_JS 43,157 → **43,914 字符**；适配器 65,175 → **65,317 字符**；合计 **+899 字符**（分阶段：纯精简+提速 −208 / 去重 +473 / 设置语义 +634）。

**W2 原生 UI**（对齐 iOS，素材为 **App Store 官方截图原图**）
- `SLOT_W` 96 → **52**（右槽恒 1 个按钮）⇒ 标题可用宽度 168 → **256vp**；
- **移除顶栏「分享会话链接」**（用户拍板；iOS 首页与会话页顶栏都只有左右各 1 个按钮）；
- **首页顶栏去标题**（iOS 首页无标题）；
- 顶栏按钮改**圆形浅底**（新键 `icon_btn_bg` / `icon_btn_bg_pressed`，深浅成对）+ 右槽符号 `plus` → **`plus_circle`**；
- 菜单图标**三条 → 两条左对齐**（穷举 4042 个 SDK 符号实证"没有两条上长下短的符号"，自绘例外成立）；
- 账号菜单 `AlertDialog` → 官方 **`showActionMenu`**（去掉技术口吻副标题）；账号行尾图标 `more` → `ellipsis_circle`；页脚行高 44 → 30；
- 新增路由类别 **`settings`**（左槽不渲染但占满 SLOT_W、右槽不渲染、标题走 `pageTitle`）；
- 新增令牌 `RADIUS_LG`/`TILE_H`/`TILE_ICON`/`ICON_BTN_VISUAL`/`FS_ICON_BTN`。

**W3 主页面**（`pages/Index.ets` / `entryability/EntryAbility.ets` / `model/ShellTypes.ets`）
- 精简：删 `isDark` 链路 4 处、`ChatSessionItem.active`、`launchWant`；10 处 `window.__dshShellApi && …` 前缀收敛成 1 个 `callApi()`；启动页 2 个 `@State` + 2 个定时器句柄下沉进 `SplashOverlay`（根 @State 17→15、句柄 12→10）；
- 提速：**启动期根组件重建 7 次 → 0 次**；**启动页最短展示基准修正（最多省 ~800ms）**，新增可读读数 `DeepSeekShell: splash off after Nms`（真机 801ms）；站点主题首读提前约 2s；`sessions` 每 5s 推回时"内容没变不换引用"；
- bug：**B1** 系统切深浅色后外壳与网页**永久**分歧（判据由"上次读到的偏好"改为 `currentColorMode`）；**B2** 首屏 2s 窗口期（`loading` 门控 → `pageReady`）；**B3** 运行中切系统深色会整页 `reloadPage()`（丢草稿/滚动/正在生成的回答）⇒ 站点偏好为显式深/浅时只收敛外壳、绝不重载；
- 上传半模态：`PickerRow` → `PickerTile`，三行列表 → **iOS 式三宫格**（拍照/相册/文件，官方 `Button` 配方、等宽不重叠、无障碍三件套齐全）；bindSheet 契约与三条选择器链路一行未动。

**W4 只读审计**（不改源码）
- iOS 参考素材：抓 App Store 商品页 HTML → 下载官方截图原图（1400px，10 张 + 4 张放大裁剪）→ 逐张看图；
- `REPORT.md`（41.2KB）：**P0×0 / P1×1 / P2×10**；六个历史高发面（注入脚本反引号与转义、深浅色 key、§3.0-153、定时器可清理、ForEach key、命中面）逐项 PASS 并有脚本证据；
- 红队复核两轮：未发现"看着对但其实错"；两次自我更正（预检模型用错、多行调用实参不能用单行 grep 判）。

### 3. 验证（真机，全部实测）

T0 构建 0 warning / T1 无注入异常 / T2 `splash off after 801ms` / **T3 冷启动 sessions 4→2** / T4 静止态 0 次 /
**T5 T13 主题无自激（22s 内 0 增长）** / T6 首页无标题+圆形浅底+⊕+两条横杠 / T7 长标题完整居中不截断 /
T8 侧栏 ⋯ 图标+页脚紧凑 / T9 账号菜单无技术副标题 / T10 三宫格 / **T11 三块真实触摸全部拉起对应选择器** /
**T12 设置页 `route kind=settings`** / **T13 站点切深色后外壳与网页同时变深、文字可读**。

### 4. 构建阻断与修复（Lead）

`pages/Index.ets` 的 ShellUi import 列表在 W3 整理时**误删了仍在使用的 `GAP_XS` / `FS_BODY`**
（`PickerTile` 用到），`CompileArkTS` 报 `COMPILE RESULT:FAIL{ERROR:3}`；Lead 补回后通过。
⇒ 教训：**静态体检的"无未使用 import"≠"可编译"**，还要查"无缺失 import"。

### 5. 本轮通用教训（已沉淀 内部踩坑表）

1. 注入脚本语法预检必须对**渲染后的文本**做 —— 原文模型下 `/[\\s]+/` 与 `/[\s]+/` **都 PASS**，抓不到转义被静默吃掉；
2. 改一个布尔参数的传参时，必须把该参数在**全部被调用者**里的分支逐个列出（`rescan(true)→(false)` 会顺带改掉 `markShell`/`reportRoute` 的 force 语义）；
3. "无未使用 import"≠"可编译"（见 §4）；
4. 跨写域接口变更（删 `onShare`）会产生"编译不过的中间态"，改完必须重跑完整构建；
5. "字符串不相等"不等于"业务判据翻转"——报缺陷要给后者（`boundedText` 81% 差异 vs `limit=40` 翻转 2.3%）；
6. 报数必须写口径（`String.length` 是 UTF-16 码元数，不是字节）；
7. 设备上跑的是哪个包必须用 md5/内容哈希对齐，不靠 mtime。

### 6. 证据

| 路径 | 内容 |
| --- | --- |
| `内部验证记录` | 本轮验收记录（逐项判据 + 截图索引 + 未闭环项） |
| `内部验证记录` / `W2-native-ui.md` / `W3-shell-core.md` | 三个写域的改动清单与依据 |
| `内部验证记录` + `w1-scripts\` | W1 的 7 个可复跑 node 脚本与读数 |
| `tmp/r19-verify/final\` | 真机验收截图（浅/深 × 各页面 + 三块选择器） |
| `tmp/r19-audit/REPORT.md` + `ios-reference.md` + `ios-shots\` | 审计报告 + iOS 官方截图素材与参考汇总 |

---

## 第二十轮（2026-09-25 ~ 09-26）：顶栏改官方 `Navigation` 标题栏 + 官方沉浸光感（**真机**）

**用户原话**：「**标题栏和页面有明显分界线，不好看，改为沉浸式**」；
叠加先前定下的口径「以后 UI 优化**默认使用官方材质**、**优先查询官方文档再决定怎样优化**」。

**组织方式**：Agent Teams —— 1 Lead + 4 teammate（T1 材质基础设施 / T2 顶栏改造 / T3 真机验证 / T5 文档），Lead 独占设备与构建。
**先查文档再动手**：本轮的技术判据来自《材质接入点清单》（[`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md)，逐条带本机 SDK 的「文件:行号」一手出处）。

### 1. 交付锚点

| 项 | 值 |
| --- | --- |
| 设备 | 真机 Mate70 Pro+（PLA-AL10 / API 26 / OpenHarmony-7.0.0.105），sn `DEVICE_SN_REDACTED`，1316×2832，**px/vp = 2.975** |
| 应用级开关 | `module.json5` 的 `ohos.arkui.UIMaterial.state`：`disable` → **`enable`**（值小写；**值写大写会被静默忽略**） |
| 改前基线包 | T1 冻结包 `dev-debug-20260925-143925.hap`，md5 **`156a128e8bfb7503e985621485bb0f91`**，812,821 B（顶栏仍是自绘 `backgroundEffect` 形态） |
| 构建 | `BUILD SUCCESSFUL in 18 s`，**0 ArkTS ERROR / 0 WARN**（T2 记录）；产物 `entry\build\default\outputs\default\entry-default-signed.hap` = **829,434 B / md5 `20d7b612d1c00a3763208a8da80e2e7c`**（2026-09-25 07:18:58）—— **该 md5 由 docs 独立对磁盘产物重算，与 T2 的记录逐字符一致** |
| 源码冻结 md5（**docs 独立重算**，不用任何人的转述值） | `view/TopBar.ets` `4752C26203A1BB0FD03E84664BBFA2BB`（37,662 B）/ `pages/Index.ets` `C26ECF69DE70C5738FBB82B617BFD591`（148,664 B）/ `common/ShellUi.ets` `1A6AEB3A0867793E18311B014DE4BDCF` / `module.json5` `7B2B28D25219AD0330382B6967C5BA18` |
| 「一行未动」的复核 | `view/SidePane.ets` md5 `4A80FD6B28DF79E4E7168D66792BC491`（mtime 仍是 2026-09-18）与 `utils/DeepSeekConfig.ets` `E9A4C0B59DBE6C298C01E8A3A464A9EE`（mtime 2026-09-18）**本轮未变** ⇒ 与「侧栏 / 注入层一行未动」的口径一致（docs 实测） |

### 2. 改动（按写作用域）

**T1 材质基础设施**（`module.json5` / `common/ShellUi.ets` / 两个 `color.json`）
- `UIMaterial.state` 由 `disable` 改 **`enable`**，并把「为什么改 + 生效范围 + 回退开关」写进 module.json5 注释；
- `common/ShellUi.ets` 新增：`import { uiMaterial } from '@kit.ArkUI'`（Kit 依赖收口）、`OFFICIAL_MATERIAL`（编译期回退开关）、
  `officialImmersiveMaterial(color)`（**唯一材质构造入口**：`style THIN` / `colorInvert false` / `applyShadow true` / `interactive true` / `lightEffect {color: Color.White}`）、
  以及 `ShellIconButton(icon, label, action, raised, official = false)` 的**两个互斥分支**（`ShellIconButtonOfficial` 零自绘层 / `ShellIconButtonDrawn` 与改前逐字相同）；
- 新增带 alpha 的按钮材质色令牌 `icon_btn_material`（浅 `#33F2F2F3` / 深 `#242A2A2C`）—— **完全不透明的色会挡死材质滤镜**。

**T2 顶栏改造**（`view/TopBar.ets` / `pages/Index.ets`）
- **承载结构**：`MainPane.build()` 改为 `Navigation() { Stack{ 内容层 } }` + `.title(this.TopBarTitle(), topBarTitleOptions())`
  + `.hideToolBar(true)` + `.mode(NavigationMode.Stack)` + `.titleMode(NavigationTitleMode.Full)` + `.backgroundColor(Color.Transparent)`；
  `TopBar` 成为**标题栏构造器**（`official: true`）。理由：官方沉浸光感**只在 `Navigation`/`NavDestination` 标题栏等位置生效**，正文里静默无效；
- **栏本体（交付口径）**：模糊由**框架标题栏**供给（`NavigationTitleOptions.backgroundEffect`，`radius/saturation/brightness` 与改前同值 + 同一个 `shell_topbar_glass` 令牌），
  自建 `Row` **零自绘层**；**自绘渐变过渡带删除**（官方模糊的边缘已接替它，留着会在自己边缘产生第二条分界）；
- **3 个按钮**：左槽「返回」/ 右槽「新建对话」传 `official: true`；菜单按钮（自绘 `MenuGlyph` 保留）也走官方分支 ⇒ `.systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))`；
- **几何契约**：网页侧让位量由 `topInset + TOP_BAR_H` 改为 **`topInset + NAV_TITLE_SLOT_VP`(66vp = 112−46)**，
  `injectShell()` / `pushInsets()` / `ErrorPane` / `NewChatTipLayer` **四处同源**；
- **A/B 对照档**：`TOPBAR_FRAMEWORK_BLUR = false` 时框架栏不画、材质挂自建 `Row`（即「有接缝」那一版，**已被用户否决**，只留作对照与一行回退）；
- **自绘回退档**：`OFFICIAL_MATERIAL = false` 时与 R19 **逐字相同**（悬浮 `TopBar` + 自绘 `backgroundEffect` + `TopBarFadeBand()`）。

### 3. 真机标定与实测（T2，命令 + 原始读数）

```text
hdc -t DEVICE_SN_REDACTED shell uitest dumpLayout -p /data/local/tmp/x.json
hdc -t DEVICE_SN_REDACTED file recv /data/local/tmp/x.json "%TEMP%\dsh-r-material-t2\x.json"   # 反斜杠 Windows 路径
hdc -t DEVICE_SN_REDACTED shell hidumper -s WindowManagerService    # 窗口 [0 0 1316 2832] ⇒ 应用全屏
```

| 项 | 改前（自绘悬浮档） | 改后（框架标题栏档） |
| --- | --- | --- |
| 状态栏 | 136px（45.71vp） | 同 |
| 网页让位量 | 97.714 CSS px = **291px** | 111.71vp = **332px**（+14vp） |
| 框架 `TitleBar` | — | `[0,137][1316,332]`（112vp，**含状态栏**） |
| 标题栏构造器 | 行高 `topPad + 52 = 97.71vp` | 顶边被框架锚在 **166px**，可用高 **166px = 56vp**（请求 66 或 56 落点相同） |
| 按钮可见圆 | 154..273px（中心 214） | 184..304px（中心 244，**低 30px** —— 进框架栏的固有代价） |
| 栏覆盖区是否吃网页点击 | T2 自述：改前 y ≤ 335 丢包 / y ≥ 340 送达 | **verify 实测（系统点击 + 网页内 click 探针）**：栏覆盖区 0..332 **整体不吃给网页**（probe=0，证据力**中**）；**y=350（栏下缘之下 18px）穿透成功**（probe=1，落点 CSS 221,117 = 物理 657,348，证据力**强**）；y330..400 **无任何原生可点节点**。⚠️ **「是否回归」不可断言** —— verify **未做同口径的改前对照**（设备已按要求装回默认包）⇒ T2 那条「332<335 无回归」**只作 T2 自述，不作为本轮结论**（见 `REPORT.md` §3-10、§7-1） |

**判据③（「模糊是否真的画在内容上」）—— 过程：原定臂被证伪为无效，换臂后通过**（全程见 `REPORT.md` §2.3 / §4）：

1. **原定臂无效（不许省略）**：「IMM vs OFF 顶栏中段 MAE」**不能**回答本问题 —— OFF 臂的 `DrawnBar` **同样带 `backgroundEffect`**，
   两臂中段本来就都模糊。实测（home，ROI x200:1100 / y137:332，排除按钮）：IMM vs OFF = **0.26**（light/dark 同）、IMM vs 改前基线 = **0.26**；
   而离群者是 SEAM 臂（light **2.25** / dark **10.22**）。任务早期测到的 0.02/2.68 亦属同族无效/跨页面态读数。
   同时 T2 的 `uitest uiInput swipe` 两次都没让网页滚动（CDP scroll 事件 = 0）⇒ 拿不到「内容滚到栏背后」的工况（verify 改**用 CDP 设 `scrollTop`** 解决）。
2. **换臂后的判据（已通过，证据力强）**：同一行网页正文（light y292:302）的横向梯度 `gradX`：OFF 臂 **8.523**（未模糊）vs IMM 臂 **0.374**（被糊）⇒ **22.8×**（dark 为 **23.8×**）；
   同帧对照区 y340:360 三臂 `gradX` **完全相等**（17.033/17.034/17.034）⇒ 内容与滚动位次一致，差异只能归因于栏。
   另有跨臂整体校验：IMM vs OFF 在**栏外** y340..1340 的 **MAE = 0.0022**（max 10、仅 15 个像素 >8）⇒ 两臂页面内容逐像素同一。
3. **主判据另有一条独立通路**：宽 ROI 逐行均值曲线的**最大一阶差分** —— 交付默认臂 IMM-dark **5.26 @ y=77（状态栏图标行）**，与改前基线 **5.25 同位置同量级**；
   被否决的 SEAM-dark 则是 **68.37 @ y=167** + 次峰 **52.00 @ y=322**（一条全宽硬边亮带）⇒ 「默认臂无新增分界」可断言。

**`TOPBAR_FADE_GUARD` 的处置（推断，未真机复核）**：`utils/DeepSeekConfig.ets:100` 的 `TOPBAR_FADE_GUARD`(=20) **判定无需改动**，
依据是算式 `setTopCss = 让位量 + 20 = 111.71 + 20 = 131.71 CSS px = 392px` **> 丢包带下界 332px**（T2 实测）。
⚠️ 但 T2 **没有**在真机上打开设置面板直接复核「面板内的交互件不被吃点击」⇒ 这条是**算式推断**，**不是实测**。

⚠️ **读 dump 的坑（本轮第一次误判的原因）**：`dumpLayout` 把节点**顶边钳在状态栏下沿 137px** ——
`Web` 铺满整屏（`innerHeight`=2832=整屏）却报顶边 137。三判据（网页自证 / 源码高度拼底边 / WMS 窗口全屏）已沉淀为
`§3.0-254`。

### 3.5 T3 真机独立验证结论摘引（**原文见 `内部验证记录`；证据力照抄，不升格**）

验证人 = **verify（独立于执行人 topbar）**；三臂 = **IMM**（交付默认：`TOPBAR_FRAMEWORK_BLUR=true` + `OFFICIAL_MATERIAL=true`）/
**SEAM**（有接缝臂 = `TOPBAR_FRAMEWORK_BLUR=false`，用户已否决）/ **OFF**（回退臂 = `OFFICIAL_MATERIAL=false`）；
三臂为**干净单变量 A/B**（HAP 解包 14/16 条目逐字节相同；源码侧 IMM vs SEAM 只差 `TopBar.ets` 一个文件、IMM vs OFF 只差 `ShellUi.ets` 一个文件）。

| 结论（verify 原文口径） | 证据力 |
| --- | --- |
| 应用级开关生效：构建产物 module.json 里 `UIMaterial.state` = `"enable"`（改前包 = `"disable"`） | **可断言（强）** |
| **交付默认臂无新增分界**：IMM-dark 逐行均值最大一阶差分 **5.26 @ y=77**（状态栏图标行），与改前基线 **5.25 同位置同量级**；y=332（栏下缘）处仅 2 级 | **可断言（强）** |
| **被否决的 SEAM 臂复现用户描述**：SEAM-dark 最大一阶差分 **68.37 @ y=167**、次峰 **52.00 @ y=322**，residual 带 49 行覆盖 y150..331 = 一条全宽硬边亮带 | **可断言（强）** |
| **框架栏模糊真的糊住正文**：同一行正文 gradX OFF **8.523** / IMM **0.374** = **22.8×**（dark **23.8×**），同帧对照区三臂 gradX 完全相等；栏外 MAE **0.0022**（max 10 / 15 px >8） | **可断言（强）** |
| 几何：`window.__dshTopInsetPx` = **111.714287**（×dpr = **332px**），转储网页首个容器顶边 **333px**（改前 **291px**） | **可断言（强）** |
| 交互回归：侧栏钮真实点击 + 效果回读（节点 **97→170**）；「新建对话」整屏 MAE **16.84** / 15.06% 像素变化 | **中-强** |
| 栏下沿触摸穿透：y=350（栏下缘之下 18px）系统点击被网页收到（probe=1）；y330..400 无原生可点节点 | **可断言（强）** |
| 崩溃：hilog **无本应用** jscrash/CppCrash/FaultLogger 命中（命中项全是 `com.huawei.hmos.aidataservice` 系统噪声） | **可断言（中）**（环形缓冲只覆盖本轮窗口） |
| 用户第二次反馈「又出现很明显的分界线了」的归属 | **可断言（时间线）**：对照臂在机窗口 = **15:25:56.831 → 15:30:32.705**，反馈落在该窗口内 ⇒ 他看到的是 **SEAM 臂**，不是交付包 |

**方法论修正（三条，verify 直接改写判据）**：① 固定阈值单列剖面（`--jump 12`）对本问题**不敏感**（四臂全 0 hit，而 SEAM-dark 实有 68 级硬边）⇒ 改**宽 ROI 逐行均值 + 最大一阶差分 + residual 带**；
② 噪声底要分「同页面态」（会话页同滚动位次：**0.26 / max 3~4**）与「跨冷启动」（站点问候语不同：**2.68 / max 5**）—— 早期那个 2.68 其实含页面态变化；
③ 按钮区不能作跨包 MAE 的 ROI（图标抗锯齿抖动可把 max 拉到 249），所有 MAE 均排除按钮区。

### 4. 判据与代价（**用户拍板覆盖了原硬约束，如实记录**）

- 原派活硬约束 = 「网页可读区上方被原生覆盖的高度**不得超过改前**」；
- 实际落地 = 让位量 **97.71vp → 111.71vp（+14vp）**，依据是用户真机反馈「有分界线，改成沉浸式」⇒
  **因果链**：用户反馈 → 形态取舍（框架栏连续模糊、正文首行不落进模糊区）→ 代价 +14vp；
- **原硬约束的记录保留**（标明被本轮覆盖及原因），不静默删除。

### 5. 文档与依据

| 产物 | 内容 |
| --- | --- |
| [`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md) | 材质接入点清单：14 个接入点逐点裁决 + SDK「文件:行号」一手出处（含「保留自绘」的逐条理由） |
| [`specs/UI-DESIGN.md`](specs/UI-DESIGN.md) §2.1 | 顶栏两档材质口径 + 几何契约 + 回退开关 |
| [`EXPERIENCE.md`](EXPERIENCE.md) §9 | 本工程专属经验（开关名语义反转、框架栏迁移的标定方法、材质像素判据的噪声底方法论） |
| `内部踩坑表` | 本轮新沉淀 3 条通用坑：`§3.0-254`（dumpLayout 顶边钳制）/ `§3.0-255`（标题栏可用高与让位量）/ `§3.0-256`（`enable` 不是空闸门） |

### 6. 证据

| 路径 | 内容 |
| --- | --- |
| `内部验证记录` | T6：设备快照 / 6 个取证脚本用法与实测输出 / **改前基线**（顶栏覆盖 0..338px、剖面相邻跳变 ≤2、同构建噪声底） / 未就绪项 |
| `内部验证记录` | 动手前整机截屏（浅/深）+ `dumpLayout` 原始 JSON + 剖面向量 JSON + 噪声底对照裁切 |
| `内部验证记录` | `shot.mjs` / `dump.mjs` / `roi-mae.mjs` / `tap.mjs` / `src-md5.mjs` / `lib.mjs`（可复跑） |
| `内部验证记录` | **T3 的正式真机判据（已产出，340 行）**：三臂定义与包冻结（含逐条目/逐文件核验）、判据逐条命令与原始输出、证据力分级（§3）、方法论修正（§4）、装机时间线（§5）、复跑命令（§6）、未验证项（§7）、SDK 口径核验（§8） |
| `内部验证记录` | 三臂原始证据：`{IMM,SEAM,OFF}/` 截图 + `dumpLayout` JSON、`*-hap-meta.json`、`*-src-md5.json`、`hapdiff-*.json`、`mae-*.json` |
| `内部验证记录` | **人眼裁定材料**：默认 vs 对照（plain + enhanced）、三臂 session 2×、4×/8× 定证 zoom |

### 7. 未闭环（勿当成已闭环）

1. ~~材质在真机上是否真的画出像素 / 是否出现硬边~~ —— **已由 T3 验证**：「模糊真的糊在正文上」= 同一行 gradX **22.8×**（强）；「交付默认臂无新增分界」= 逐行曲线 5.26 vs 改前 5.25（强）。**例外**：`lightEffect` 顶缘亮线与按钮材质洗白两条风险（反例 `§3.0-13` / `§3.0-58`）**仍未单独排除**；
2. **顶栏覆盖区（0..332px）内的网页元素是否可点**：verify 实测该区整体不吃给网页（probe=0，证据力**中**），**但未做同口径改前对照** ⇒ **不可断言是否为回归**（`REPORT.md` §7-1）；
3. **`other` 路由（子页/设置浮层）的返回键**：本轮未能稳定进入 `other` 路由 ⇒ **未验证**（`REPORT.md` §7-2）；
4. **观感裁定**：数值只证明「默认臂无新增分界、对照臂复现用户描述」；「是否好看 / 是否达成用户要的沉浸」**需用户本人看图裁定**（材料：`compare/DARK-TOP-IMM-default-vs-SEAM-rejected-{plain,enhanced}.png` 与 `LIGHT-…`），`REPORT.md` §3-11 明确列为**不可断言**；
5. **改后与改前「观感等价」不可断言**：只有中段 ROI 数值等价（MAE 0.26），没有用户观感样本；
6. 上传半模态（`bindSheet`）在 `enable` 档下默认带材质 ⇒ 宫格观感变化**真机未验证**（`§3.0-256`）；`TOPBAR_FADE_GUARD` 的「无需改动」仍是**算式推断**；
7. 崩溃扫描证据力受 **hilog 环形缓冲**限制（只覆盖本轮时间窗）；模拟器未参与（本轮全部结论仅基于真机）；
8. **`TOPBAR_BAR_MATERIAL` 旧名语义反转** ⇒ R20 改名 `TOPBAR_FRAMEWORK_BLUR`（教训保留在 [`EXPERIENCE.md`](EXPERIENCE.md) §9.2 第 1 条）。

## 第二十一轮（2026-09-28）：UI 官方组件/特效 + 逻辑适配 + 设置页适配收敛（**真机**）

**组织方式**：Team Lead 起两个 teammate 分工改源码（ui-optimizer 负责 UI 官方组件/特效、logic-optimizer 负责逻辑/适配/冗余清理），Lead 统一集成构建 + 真机验收 + 设置页适配修复。证据与逐条读数见 `内部验证记录`。

### UI 官方组件/特效（teammate ui-optimizer）

- `common/ShellUi.ets` 新增 `listItemTransition()`（`TransitionEffect.asymmetric`，进场 `move(TransitionEdge.BOTTOM)`+淡入 / 退场纯淡出）；`view/SidePane.ets` 的 `ListItem` 挂 `.transition(...)`、`Search` 加 `.searchButton("搜索")` + `.onSubmit()`（官方搜索提交键，iOS SearchBar 同形态）。`specs/UI-DESIGN.md` §4/§5/§9、`EXPERIENCE.md` §42 同步。

### 逻辑适配（teammate logic-optimizer）

- `utils/DeepSeekConfig.ets` `boundedText()` 空白判据补齐为 JS `\s` 全集 + U+200B（新增 `isFoldWs(ch)`），修掉 §13.B.0 登记的 P2-9（与 trim 不等价、推广行长度门临界漏判）；30 万例随机对照 0 差异，注入体积 +323 B。Index 层序 / Splash / 侧栏开合 / 键盘避让 / 注入脚本治理核对通过未改。

### 设置页适配收敛（Lead，响应用户「设置页还没完全适配」）

- **根因 1（双重标题）**：`view/TopBar.ets` `SlotTitle()` 只对 `home` 不渲染标题，`settings` 路由仍渲染 → 与网页设置面板自身的大标题「系统设置」叠成双重标题。改为 `settings` 同样不渲染（与 home 一样中间留空、只留磨砂底）。
- **根因 2（标题行空白带）**：`utils/DeepSeekConfig.ets` `TOPBAR_FADE_GUARD=20` 是 R17 自绘顶栏「渐变过渡带防丢包加数」，R20 官方档已失效 —— `__dshTopInsetPx` 实测=body padding-top=完整顶栏让位（111.714 CSS px），多加 20px 让设置面板标题行低于顶栏下沿、露一块面板底色。R18 已 `hitTestBehavior(None)` 根治丢包带（✕ 中心实测在可点区），故置 0。
- **效果**：设置面板标题行紧贴磨砂顶栏下沿、与网页正文让位同源无缝、单一标题。真机修复前后对照见证据目录 `r21-settings-{before,after}.jpeg`。

### 设置页底部功能栏（R21 同日用户二次需求）

- **标题**：「系统设置」`flex:1 + text-align:center` 居中、✕ 退出键 `order:-1` 移到左上角。
- **四页签移到底部做底部功能栏**（参考 `aa-hm` 底部功能栏形态）：`body` `order:1` 在上、`tabs` 容器 `order:2` 压底 + 顶部发丝分隔线 + 底部留手势条；页签项从顶部横排胶囊改**竖排**（`flex-direction:column`，图标上 / 文字下，高 54px ≥ 44 可点）；选中态改 aa-hm 式「变色 + 加粗」**不画卡片底**（原 ACCENT_DECL 卡片底会污染竖排透明项），静态规则与 `ensureSettingsAccent()` 动态采样两处同步。
- **真机验证**：标题居中 + ✕ 左上 ✅、四页签底部功能栏 ✅、点「账号管理」内容切换 + 选中态跟随 ✅（证据 `r21-settings-{bottomtab,accttab}.jpeg`）。release 正式版 549,012 B / md5 `789ea5a86192780fe9e43cd1c947025a` 已装真机。

### 构建与产物

- debug 827,963 B / md5 `a57ed3f72248c6a998a1fc0df111a3ee`；**release 正式版 551,555 B / md5 `cfe45ebb337d853765cab84542aceae0`**（`check-hap-dist.mjs` 门禁 PASS：app.debug=false / 无 sourceMaps / 可分发）。
- 两次均 `BUILD SUCCESSFUL / 0 error / 0 warning`，CompileArkTS 实跑。
- **正式版已 `hdc install -r` 装真机**（保留登录态），整机截图 `r21-release-installed.jpeg` 正常。

### 真机验收（Mate 70 Pro+ `DEVICE_SN_REDACTED`）

冷启动首页 / 侧栏打开（searchButton + 列表转场）/ 真实触摸进聊天页 / 选择模式 / 删除安全闩（`locked` 未退）/ 注入脚本健康（`drawerSkip=7021`）/ **设置页修复前后对照 + ✕ 关闭** 全部通过，无闪屏/遮盖/白屏。

### 未闭环

1. Splash 二次加载重放（错误页重试/深浅色 refresh 时 SplashOverlay 重挂载闪一帧）—— 需真机裁定三条路径，本轮未动；
2. `Index.onBackPress()` 在 settings 浮层下行为 —— 留到下一单；
3. bundleName 用保留域名 `example`（内部构建可接受，非上架）；
4. 深色「跟随系统」边界分支 —— R19/R20 已知架构事实。
### 设置页底部功能栏**重写为原生组件**（R21 同日用户三次需求）

用户原话：「参考 aa-hm 的底部功能栏，**重新写**设置页的功能栏」。
上一版（同日二次需求）是把**网页页签**用 CSS 挪到屏幕底部 —— 形态对但本质仍是网页元素伪装；
本次按 aa-hm 的做法改成**原生 ArkUI 组件**承载。

**改动（5 个文件）**

| 文件 | 改动 |
| --- | --- |
| `view/SettingsTabBar.ets`（**新增**） | 原生自绘悬浮胶囊。逐个复刻 aa-hm `AaBottomNav` 的四要素：全圆角（半径 = 高/2）+ `backgroundEffect` 磨砂 + 同源渐变光层（终点同 RGB、alpha=0）+ 亮边；四项「图标上、文字下」，选中项走 `accent`。图标 `gearshape`/`person`/`externaldrive`/`doc_text` 全部经 SDK `id_defined.json`（4042 条符号）实证 |
| `common/ShellUi.ets` | 新增 §9 底栏令牌 `TABBAR_*`（高 54 / 图标 22 / 文字 11fp / 留边 12% / 磨砂 18 / 光层角度 145 与色标 0.42 / 全圆角） |
| `resources/{base,dark}/element/color.json` | 新增 4 个底栏色（深浅逐键成对）：`shell_tabbar_glass` / `_rim` / `_sheen` / `_sheen_clear` |
| `pages/Index.ets` | 根 `Stack` 挂载（仅 `routeKind === 'settings'` 时上树，层序在 `SideBarContainer` 之后、`Splash` 之前）+ `onSettingsTabSelect` / `onSettingsOpened` |
| `utils/DeepSeekConfig.ets` | 网页那一行页签改 **`opacity: 0`** 让位（保留布局与真实 rect 供派发） |
| `utils/ShellScript.ets` | 新增 `setSettingsTab(i)` / `settingsTab()` 桥；切页签复用既有 `tap()` 派发序列 |

**为什么不用官方 `Tabs` 底栏 + `FloatingTabBarStyle.systemMaterial`（aa-hm 的路线 A）**：
① 本工程设置页的**内容在网页里**，`TabContent` 是原生页面容器、挂不上网页内容；
② aa-hm 自己的真机记录就写着「官方材质在本机型本位置 Δ+0.0、`barFloatingStyle` 未生效」，
它最终交付的也正是自绘胶囊这条路径（`BottomNav.ets` 文件头那张三臂表）。⇒ 两工程结论一致。

**两条关键结论（都是真机实测，不是推断）**

1. **隐藏网页页签只能用 `opacity: 0`**。`display: none` 会让 rect 全 0（`tap()` 会退到祖先、点错元素）；
   `visibility` / `pointer-events` 会破坏合成事件命中 —— 而这条链路**全靠 `dispatchEvent`**。
   R17 在「设置入口闪窗」那条链路上已经得到同一结论，本轮在原生底栏 → 网页切页签这条链路上**再次验证**。
2. **初始高亮不能读网页残留的选中态**。真机读数（2026-09-28）：网页弹层每次打开渲染的都是**第 1 项的内容**，
   而它自己的选中 hash 类会**残留上次的值** —— 实测「内容 = 通用设置、hash = 服务协议」，网页自身就不一致。
   第一版底栏跟着那个残留态高亮，用户看到的是「高亮服务协议、内容却是通用设置」（截图 `r21-nativebar-reopen.jpeg`）。
   ⇒ 改为**以内容为准**：进入设置页时归 0 并**幂等派发**一次点击；React 对同一页签重复点击不重渲染，
   于是「高亮 = 内容」这条不变量成立，且不依赖网页侧那个会漂移的残留态。

**真机验证（Mate 70 Pro+ `DEVICE_SN_REDACTED`）**

| 项 | 结果 | 证据 |
| --- | --- | --- |
| 原生悬浮胶囊渲染（浅色） | ✅ 全圆角白色胶囊、四项图标上文字下、选中蓝 | `r21-nativebar.jpeg` |
| 点「账号管理」 | ✅ 内容切账号页 + 高亮跟随 | `r21-nativebar-acct.jpeg` |
| 点「数据管理」 | ✅ 内容切数据页 + 高亮跟随 | `r21-nativebar-data.jpeg` |
| 点「服务协议」 | ✅ 内容切协议页 + 高亮跟随（四项索引无错位） | `r21-nativebar-agree.jpeg` |
| 关闭设置页 | ✅ 底栏随之消失、回首页 | `r21-nativebar-closed.jpeg` |
| 重开设置页 | ✅ 高亮与内容一致（都是通用设置） | `r21-nativebar-align.jpeg` |
| 深色（站点内切主题） | ✅ 底栏随站点主题切到深色档、与内容和谐 | `r21-nativebar-dark.jpeg` |

**构建与产物**：clean 全量 `0 error / 0 warning`；release **569,324 B / md5 `2e912f828b1f94a93642c837d0327f4e`**（`check-hap-dist.mjs` 门禁 PASS），已 `hdc install -r` 装真机。

### 设置页标题栏整页化 + 底栏改官方框架层承载（R21 同日四、五改）

用户原话：「将系统设置那一行做成整页的标题栏，将 ✕ 换成 `<`，标题栏和底部功能栏都要用官方组件，
实现模糊效果和沉浸光感，参考 aa-hm 的实现方式」→ 随后「底栏晃动时还是会被遮挡，将其置于最顶层」。

**改动（4 个文件）**

| 文件 | 改动 |
| --- | --- |
| `view/TopBar.ets` | `SlotLeft`：settings 路由渲染 `<` 返回钮（`ShellIconButton(..., official)` ⇒ 官方沉浸光感）；`SlotTitle`：settings 恢复标题（不再与网页标题重复） |
| `pages/Index.ets` | `displayTitle()` settings 固定「系统设置」；新增 `onTopBarBack()`（设置页走桥关闭、其余仍 `history.back()`）；`MainPane` 新增 `SettingsToolbar()` @Builder + `@StorageLink('settingsTabIndex')` + `bottomPad`；`Navigation` 挂 `.toolbarConfiguration(...)` + `.hideToolBar(routeKind !== 'settings')` |
| `view/SettingsTabBar.ets` | 从「组件」精简为「数据 + 图标 + 官方工具条选项」；`settingsToolbarOptions()` 只留透明底（表面交给胶囊） |
| `utils/DeepSeekConfig.ets` | 网页那一行（大标题 + ✕）让位：`header-wrapper` 高度归 0、标题不画、**✕ 保留几何**（fixed 到屏幕底部 + `opacity:0`）供桥派发；网页页签行改 `position: fixed`（toolbar 已占位，不再双重留白） |
| `utils/ShellScript.ets` | 新增 `closeSettings()` 桥（原生 `<` → 派发点击给官方 ✕；**不能用 `history.back()`**，设置浮层不改 URL） |

**三次承载演进（每次都是真机实测推动的，写清楚免得翻烧饼）**

| # | 承载 | 结果 |
| --- | --- | --- |
| ① | 自绘悬浮胶囊（Stack 浮层） | 观感可辨，但**晃动时被遮挡**、图标被裁 |
| ② | 官方 `Tabs` 悬浮底栏（`barFloatingStyle.systemMaterial`） | 真机实测**胶囊上半被裁**（Tabs 高度装不下 `barBottomMargin`）；补高度后仍**被遮挡** |
| ③ | **官方 `Navigation` 工具条（本版，交付档）** | ✅ 完整、稳定、不被遮挡 |

**关键结论（③ 为什么是正解）**：`ArkWeb` 是**独立合成图层**的内容，而 ①② 都是 `Stack` 里的**普通原生浮层** ——
两者重叠时的图层关系在页面滚动 / 内容切换这些时刻**不稳定**，纯 Stack 顺序（哪怕放最顶层）管不到。
而 `Navigation` 工具条属**框架层**，与本工程顶栏（同一 `Navigation` 的标题栏）同级 —— 顶栏从 R20 起从未被 Web 遮挡过，是同一机制的旁证。

**两条配套的实测细节**

1. **工具条自身不避让手势条**：真机实测底栏文字（y 2780~2818）与系统手势条（y 约 2734~2832）**叠在一起**。
   修法：`SettingsToolbar()` 的高度与内边距都算上 `bottomPad`（= 系统下发的底部避让），框架据此撑高工具条。
2. **工具条整条铺底色会与栏内胶囊叠成两层**（胶囊圆角在带上几乎看不出来）⇒ 工具条设 `Color.Transparent`，
   可见表面交给栏内的悬浮胶囊（`backgroundEffect` 官方口径，与顶栏自绘回退档同一套四参数）。

**真机验证（Mate 70 Pro+ `DEVICE_SN_REDACTED`）**

| 项 | 结果 | 证据 |
| --- | --- | --- |
| 原生标题栏：`<` + 居中「系统设置」 | ✅（按钮 `[23,184][142,304]`，accessibilityText=关闭设置） | `r21-toolbar-capsule.jpeg` |
| 底栏胶囊：四项等分、无裁切 | ✅（dump：x 中心 165/493/822/1150，等距 328） | 同上 |
| 点「数据管理」切内容 | ✅ 内容切换 + 高亮跟随 | `r21-toolbar-capsule-data.jpeg` |
| 点 `<` 关闭设置页 | ✅ 回首页、底栏消失 | `r21-toolbar-closed2.jpeg` |
| 滚动时底栏稳定 | ✅ 无裁切、不被遮挡 | `r21-toolbar-scroll.jpeg` |
| 手势条避让 | ✅ 手势条独立在胶囊下方 | `r21-toolbar-capsule.jpeg` |

**产物**：clean 全量 `0 error / 0 warning`；release **568,004 B / md5 `e305d733276fa6c0f1a68874ab545e0f`**（门禁 PASS），已装真机。

**过程教训（已沉淀）**：本轮两次因「注释里写了反引号」而**截断 `MOBILE_ADAPTER_JS` 模板字面量**（`§1.8-67` 的坑），
两次都是注入脚本预检（`check-injected-js.mjs`）先拦下的 —— 该预检是**装机前的必要闸门**，不是可选项。

### 底栏沉浸与「页面底部颜色统一」（R21 同日六改）

用户原话：「底栏没有沉浸，页面底部颜色要统一」（附底栏裁切截图，可见胶囊外一圈与最底部有一条**白色带**）。

**两个问题的根因（都是量出来的）**

1. **底部颜色断层**：工具条是**占位式**的（Web 视口被它压短），而我把工具条设成了透明 ⇒
   它下面露出原生 `Stack` 的 `bg_page`（浅色下**纯白 255**），而设置页底色是浅灰 **241** ⇒
   胶囊一圈与最底部那条明显更白（用户截图那一圈）。
2. **胶囊没有沉浸感**：玻璃色 `#E6FFFFFF`（90% 白）太实 ⇒ 看起来是一块白饼，不是玻璃。

**修法与两条实测细节**

- **`NavigationToolbarOptions.backgroundColor` 在 CustomBuilder 模式下不生效**（真机实测：设了它，
  工具条那条仍旧是 255 纯白）⇒ 底色改为**在 builder 的根容器上自己铺**
  （新增双值资源 `shell_settings_page`，与网页设置面板的 `--dsh-set-page` 对齐：浅 `#F1F3F5` / 深 `#151517`）。
- 玻璃色 alpha 由 90% 降到 **70%**（`#B3FFFFFF` / `#B3202023`）⇒ 半透明磨砂 + 18vp 模糊 + 发丝亮边。
- **`systemMaterial`（官方沉浸材质）在本位置实测无效**：挂上它之后胶囊像素差只剩 **Δ+1.8**
  （与底色几乎同色、胶囊等于消失），与 aa-hm「官方材质在本机型底部位置 Δ+0.0」的记录一致 ⇒
  表面改回官方 `backgroundEffect`（与顶栏自绘回退档同一套四参数）。

**真机读数（浅色，用户报的就是浅色）**

| 采样点 | RGB | 结论 |
| --- | --- | --- |
| 设置页空白底（y=1600） | 242, 243, 245 | 基准 |
| 胶囊带外左 / 右（y=2720） | 242, 243, 245 | **与页面底色完全一致** |
| 最底部（手势条上方） | 242, 243, 245 | **不再有白色断层** |
| 胶囊内（y=2650 / 2720） | 251, 251, 251 | Δ**+9**（可见的玻璃面） |

证据：`内部验证记录`（浅色终态）、`r21-immersive-light*.jpeg`（过程档）。

**残留（如实记录）**：工具条是**占位式**的 ⇒ 页面内容不会从底栏背后穿过，
所以那层 18vp 模糊在**纯色背景上没有可糊的内容**，观感上主要表现为「半透明白 + 亮边」。
这是位置决定的（浮层能从背后穿过，但浮层会被 ArkWeb 的独立图层遮挡 —— 见上一节），不是参数没生效。

### 底栏补回渐变光层 + 消除设置页打开时的「转圈」（R21 同日七改）

用户原话：「1.底栏没有光效 2.系统设置中，有些界面每次打开都会刷新一下，即转个圈再显示，看怎么优化掉」。

**① 底栏光效：补回被弄丢的「同源渐变光层」**

根因是**我自己改承载时丢的**：aa-hm 悬浮胶囊的四要素是「全圆角 + 磨砂 + **同源渐变光层** + 亮边」，
我把承载从自绘换成官方工具条时只保留了后两条 —— 令牌 `TABBAR_SHEEN_ANGLE` / `TABBAR_SHEEN_MID_STOP`
以及色 `shell_tabbar_sheen` / `_sheen_clear` 一直是**零消费者**（本轮才被发现）。

补法：胶囊上挂 `linearGradient`（角度 145°、色标 0.42，终点是同 RGB、alpha=0 的 clear 色 ——
不能用 `Color.Transparent`，那是透明黑、会让渐变插值发灰）。

真机读数（浅色）：胶囊上缘 **252** → 中部 **252** → 下缘 **240**（趋向底色 242），
即**上亮下暗的一段渐变**；胶囊与底色差 **Δ+10**。证据 `内部验证记录`。

**② 设置页「每次打开转个圈」：元凶是我自己那次多余的点击派发**

为对齐高亮，`onSettingsOpened()` 原先会**幂等派发一次** `setSettingsTab(0)`。
但那是给官方页签的一整套**真实点击序列**（`pointerdown → mousedown → pointerup → mouseup → click`），
官方 tab 收到后会**重新挂载内容页** —— 需要拉数据的页签于是每次打开都转一次圈。

而它想达成的「高亮 = 内容」**本来就由「网页每次打开都渲染第 1 项」这一点天然满足** ——
派发是纯粹多余的一步。⇒ 删除，只设本地高亮。

**硬证据（MutationObserver，真机 CDP）**：

| 动作 | DOM 变动 |
| --- | --- |
| **打开设置页** | `added:0, removed:0, runs:0` —— **零变动，不重挂载** |
| 点页签切内容（对照组，证明观察器有效） | `added:5, removed:4, runs:2` |

对照组保证了「零变动」不是观察器失效造成的假读数。

**产物**：clean 全量 `0 error / 0 warning`；release **567,471 B / md5 `6520d77a28587dad0a12ef1d166968dd`**（门禁 PASS），已装真机。

### 底栏光效补全 + **设置页「转圈」真正根因与修法**（R21 同日八改）

上一轮我把「打开设置页转圈」归因于自己那次多余的点击派发，实测后**该归因不完整**（见下）。用户回「都没解决」。
本轮改用**抓请求**的方式重查，拿到了确切根因。

**① 转圈：官方每次打开设置页都要重新拉三个接口（实测抓到）**

用 hook（覆盖 `XMLHttpRequest.prototype.open/send`）在真机上抓打开设置页期间的请求：

```
/api/v0/users/settings        （用户设置：主题 / 语言）
/api/v0/chat/tts/voices       （朗读音色列表）
/api/v0/users/get_birthday    （未成年人模式的生日）
```

三个都是 **XHR GET**，**每次打开设置页都会各发一次**。官方弹层每次打开都是重新挂载的
（MutationObserver 抓到 `ds-modal-overlay ds-fade-in-enter` / `ds-modal ds-fade-in-zoom-in-enter`），
所以这三次网络往返就是用户看到的「转个圈再显示」。这是**官方组件的生命周期**，注入层改不动；
能改的是「让它这一次不必走网络」。

**修法：白名单 + 短 TTL 的内存缓存**（`utils/ShellScript.ets` 的 `installRequestCache()`）

- 只认这三个 URL 且只认 GET；其余接口**完全不介入**（行为与改动前逐字一致）；
- 命中缓存时**伪造 XHR 响应**（按 `responseType` 给 `response` / `responseText`，
  并触发 `onreadystatechange` / `onload` / `load` / `loadend`），**不发起真实请求**；
- TTL 90 秒；
- **安全阀**：只有点「设置项本体」（`data-dsh-settings-row/seg/group`）才清缓存 ⇒
  用户改完主题/语言，下次打开必然是新鲜数据。

**真机读数（硬证据）**

| 动作 | `reqCache()` |
| --- | --- |
| 第 1 次打开设置页 | `{keys:[3 个], hits:0, miss:3}` —— 填充 |
| **第 2 次打开设置页** | **`{keys:[3 个], hits:3, miss:3}`** —— **三个请求全命中，没走网络** |
| 真实点「深色」（改设置） | `{keys:[]}` —— 缓存被清（安全阀生效） |

⚠️ **安全阀的第一版写错了，实测自己把缓存废掉**：原判据是「设置面板内任何点击都清」，
而关闭设置页要点面板头部的 ✕（也在面板内）⇒ 每次关闭都清一次 ⇒ 下次必然 miss。
实测读数：关闭后 `keys=[]`、第二次打开 `miss` 从 3 涨到 6、`hits` 恒为 0。
⇒ 判据收紧到设置项本体（页签、关闭钮都不清）。

**② 底栏光效：补投影 + 加深高光**

上一轮补的渐变光层幅度偏小（浅色下 252 vs 底色 242），观感上仍像一块平色。本轮再加两件：

- **对称投影**（`SHADOW_R_MD` + `shell_panel_shadow`，`offsetX/offsetY` 都为 0）：
  让胶囊「浮」起来。⚠️ 必须对称——偏移投影按**边界矩形**投影、不跟圆角走，会在圆角外露直角硬边
  （第十六轮在侧栏面板上踩过）；
- 深色高光 `shell_tabbar_sheen` 由 8% 提到 14%（`#24FFFFFF`）。

**产物**：clean 全量 `0 error / 0 warning`；release **576,406 B / md5 `ea5bf69fc365f4473e9189db2c9d7cb2`**（门禁 PASS），已装真机。

### 底栏光效：**先查官方文档**定路径 + 独立高光层（R21 同日十改）

用户指示：「仔细查阅官方文档，不要费功夫写一些没用的代码」。本轮先查证再动手。

**① 文档查证（结论：官方沉浸光感在本工程底栏位置不可达）**

依据 `内部踩坑表` §3.0-245` 引的官方原文要点（HarmonyOS 7 起，仅对 `targetSdkVersion >= 26`）：
沉浸光感只有**四类位置**生效 ——
① 弹窗类组件/接口 ② `Slider`/`Toggle`/`Select` ③ **`Navigation`/`NavDestination` 标题栏**
④ **横向 `Tabs` 且 `barPosition = BarPosition.End` 的底部 TabBar**；
**「在其他区域中设置沉浸光感效果不生效」**（不报错、不告警）。

对照本工程：

| 位置 | 是否在生效范围 | 能不能用 |
| --- | --- | --- |
| `Navigation` **工具条**（底栏现位置） | ❌ 工具条 ≠ 标题栏 | 官方材质**静默无效** —— 先前实测「挂 `systemMaterial` 后胶囊 Δ+1.8」正合此条，不是实现错 |
| `Navigation` **标题栏** | ✅ | 已被**顶栏**占用（R20） |
| ④ 横向 `Tabs` 底部 TabBar | ✅ | **本工程不可行**：要 4 个 bar 项就得有 4 个 `TabContent`，而我们的内容是 **Web**（一个页面）。把 Web 放进其中一个 ⇒ 切 tab 时 Web 被卸载重挂；把 4 个都放 ⇒ Web 挂 4 份 |

文档同条给的出路只有两条：**把组件挪进允许的区域**，或**放弃官方效果走自绘**（自绘自行承担「像不像」）。
本工程只能走后者 —— 即 aa-hm 的「路线 B：自绘胶囊」。

⚠️ 同条还有一条本轮才注意到的约束：材质**不要与 `backgroundColor` / `borderColor` / `borderWidth` / `shadow` 同时使用**
（材质生效时会把它们接管/覆盖）。先前给胶囊挂材质时**同时还画着发丝亮边**，属两套语义打架 —— 记此备查。

**② 真正让「光效」消失的原因：渐变与 `backgroundEffect` 挂在同一节点时几乎不出效果**

照搬 aa-hm 的三层渐变后仍「没有光效」，于是量了一次竖直剖面：

| 版本 | 胶囊内竖直梯度 | 胶囊 vs 底色 |
| --- | --- | --- |
| 渐变 + `backgroundEffect` **同节点**（照搬 aa-hm 的写法） | **2 级**（223 → 225，且方向反） | Δ-6 |
| **独立高光层**（Stack 里的装饰层） | **5 级**（229 → 226 → 224，顶部亮向下衰减） | **Δ-16** |

⇒ 修法：把光层从胶囊节点里**拿出来，做成 `Stack` 内的独立装饰层**（`HitTestMode.None`，避免吃掉四项点击）。
这与 aa-hm 在 `ui/GlassIcon.ets` 里处理光弧的方式一致（它也把光层做成独立层，不靠同节点叠）。

**③ 顺带修掉的两处（都是「照抄数值 ≠ 照抄效果」）**

- **纱的厚度**：我先前照抄 aa-hm `color.json` 里的 `#06000000`（2.4% 黑）⇒ 胶囊与底色只差 **6 级**，
  看起来就是一块平色。而 aa-hm `Design.ets` 的 `glassNavSurface()` 注释里写的定点依据是 **7.8% 黑 ⇒ Δ≈−19.7**
  （R63/F1 那次修复的读数）⇒ 改按**依据档**取 `#14000000`，实测 Δ**-16** ✓；
- **角度与元素宽高比耦合**：aa-hm 的 `SHEEN_ANGLE = 145` 是给它满屏宽胶囊的；
  本工程胶囊是 851×161px（约 5.3:1），145° 会把渐变推成近似水平 ⇒ 竖向零梯度。改 **0°（自上而下）**。
- 同时**撤掉我自创的 `.shadow()`**：aa-hm 的胶囊没有投影，它的立体感来自「亮环 + 光带 + 磨砂」三件。

**真机读数（浅色终态）**：胶囊内 229 → 226 → 224；带外 242；最底部 242（与页面底色一致）。
证据：`内部验证记录`。

**能力边界（如实记，不再反复试参数）**：工具条是**占位式**的，页面内容不从底栏背后穿过 ⇒
18vp 那层磨砂**没有可糊的内容**，所以拿不到「玻璃折射背后内容」那种效果；
本工程底栏的光效上限 = 「纱 + 光带 + 亮环」这套自绘配方。

**产物**：clean 全量 `0 error / 0 warning`；release **575,709 B / md5 `30cb1eae7ab01f9bd3c707b9873b381a`**（门禁 PASS），已装真机。

### 底栏定档：**官方 `Tabs` 底部 TabBar + 官方沉浸材质**（R21 同日十二改，按用户指示重查文档后落地）

用户拍板：「把底栏改回浮层 + 让内容穿过」+「参考 aa-hm」+「仔细查阅官方文档，不要费功夫写一些没用的代码」。

**文档查证（`pitfalls` §3.0-245 引官方原文）**：沉浸光感只有四类位置生效，其中底部唯一可用的是
**④横向 `Tabs` 且 `barPosition = BarPosition.End` 的底部 TabBar** —— 即 aa-hm 的「路线 A」。
本工程此前两次没走通的原因**都在实现层**、不在路径本身：

1. **胶囊被裁**：`Tabs` 的高度只给了 `barHeight`，而 `barBottomMargin` 那段也在 bar 带内
   ⇒ 高度必须是**胶囊高 + 离底间隙**（本轮已修，真机确认完整）；
2. **点击不生效**：`Tabs` 的 `index` 是**受控属性**（aa-hm 坑 101），且 `onChange` → 桥 → 网页的链路
   需要网页页签行的 `rect` 有效 —— 上一版把页签行改成 `position:fixed`（脱离文档流）后派发**静默失效**
   （直调桥 `r:"ok"` 但内容不切，CDP 量 rect 才发现）⇒ 改回**文档流占位**（本轮已修，真机确认切换成功）。

**最终实现（`view/SettingsTabBar.ets` 重写）**：

- `Tabs({ barPosition: BarPosition.End })` + 4 个**空** `TabContent`（内容是下层的 Web，不能放东西）；
- `.barHeight(TABBAR_H, true)` + `.barOverlap(true)`（`barFloatingStyle` 生效的前置条件）+
  `.barFloatingStyle({ barWidth, barBottomMargin, systemMaterial })` —— **官方沉浸材质含 `lightEffect` 光效**；
- `.height(TABBAR_H + bottomGap)`；`TabContent` 内用「带属性的 `Column()`」（`Blank` 只能嵌 Row/Column/Flex）；
- 组件由宿主放在**根 `Stack` 最顶层**（外层 `HitTestMode.None`），下层是铺满全屏的 Web ⇒
  **内容从 bar 背后穿过**；
- **按文档要求，材质不与 `backgroundColor`/`borderColor`/`borderWidth`/`shadow` 同用** ⇒ 组件零自绘层。

**网页侧配套**：页签行改回**文档流占位**（`order:2` + `padding-bottom:30px`）——
`position:fixed` 版会静默失效（见上）；占位让页签行 rect 落在胶囊区域（真实触摸被胶囊拦截、派发链路有效）。

**真机验证**：

| 项 | 结果 | 证据 |
| --- | --- | --- |
| 官方材质表面（浅色） | 胶囊内 231.8（Δ-10），带**上暗下亮的官方折射渐变**（231.8→240.9） | `r21-official-tabs.jpeg` |
| 点「数据管理」切换 | ✅ 内容切换 + 高亮跟随 | `r21-final-data.jpeg` |
| 底栏完整不裁 | ✅（dump：bar 项 `[0,2702][321,2832]` 等四项等分） | 同上 |

**产物**：clean 全量 `0 error / 0 warning`；release 见下方门禁记录；已装真机。
