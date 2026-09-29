// 原生顶栏（从 pages/Index.ets 抽出的独立组件）。
//
// ## 为什么抽出来（第十六轮）
//   1) **性能**：顶栏原先挂在 `@Entry` 根组件的 `build()` 里。ArkUI 的依赖登记规则是
//      "**只有 build() 真正读到过的状态才登记依赖**"（§3.0-134），而根 build() 读到的
//      状态有 17 个 —— 启动页逐字跳出（130ms 自增一次）、侧栏删除进度 `deleteDone++`、
//      会话列表刷新……任何一处变化都会把根的整个 build() 重跑一遍，连带把 Web 组件的
//      全部属性表达式重算一遍。抽成独立 `@Component` 后，只有这里真正读到的 `@Prop`
//      变化才会重建它，重建面从"整页"收窄到"这一条栏"。
//   2) **统一**：图标按钮的配方现在是 `common/ShellUi.ets` 的全局构建函数
//      `ShellIconButton`（第十六轮由 Lead 落地），本组件与 `view/SidePane.ets` 都引用它，
//      不再各自手写一份。**本文件不保留私有图标按钮副本**。
//
// ## 形态（对齐 iOS 导航栏，取值见 specs/UI-DESIGN.md §2）
//   高度 `TOP_BAR_H`(52) + 状态栏避让；左右内边距 `GAP_SM`；标题 `FS_TITLE`/Medium/单行省略；
//   底边线 `HAIRLINE`；背景是 `backgroundEffect` 悬浮玻璃（**不能用** `backgroundBlurStyle`，
//   那是"材质"会接管 backgroundColor 把网页内容整片盖掉 → §3.0-74）。
//   左侧按钮随路由换语义（home/chat = 侧栏开关，other = 返回），右侧**恒为 1 个「新建对话」**。
//   第十九轮（R19）：右侧的「分享会话链接」**已移除**（iOS 官方截图实证：首页与会话页顶栏右槽
//   都只有 1 个按钮，会话页右槽就是「新建对话」，见 tmp/r19-audit/ios-reference.md §1.1 与
//   §7 的 T1/T2 —— 用户已拍板按 iOS 走）。顶栏因此**任何路由下都只有左右各 1 个按钮**。
//   首页顶栏**不显示标题**（iOS 首页顶栏中间是空的，crop-topbar.png），标题槽仍占位以保证居中。
//
// ## 标题**严格居中**：单层 Row + 左右**等宽固定槽**（不要用铺满的覆盖层！）
//   iOS 导航栏的标题居中，且**不随两侧按钮数量变化而移动**。本工程右侧按钮数量随路由变
//   （home 1 个 / chat 2 个 / other 0 个），若用 `Row + layoutWeight` 让标题吃剩余空间、
//   而左右槽宽度不固定，标题中心就会跟着漂移 —— 切一次路由跳一次。
//   做法：三槽 Row —— 左槽 `SLOT_W` 固定 / 标题槽 `layoutWeight(1)` 居中 / 右槽 `SLOT_W` 固定。
//   左右槽等宽 ⇒ **剩余空间的中心 = 屏幕中心**，标题严格居中且恒定。
//
//   ⚠️ **这里踩过一次 P0 回归**，务必不要改回覆盖层写法：第一版用 `Stack` 三层（铺满的标题层
//   + 两个同样铺满的按钮组 `Row`），只给标题层加了 `None` ⇒ 最上层右按钮组把整条顶栏的点击
//   吃掉，**侧栏完全打不开**，而构建 0 error / 0 warning、`dumpLayout` 里 `clickable` 全是 true。
//   结论：**能用"不重叠的排布"解决，就不要用"覆盖层 + hitTest 特判"**（后者漏一个就整条栏失效）。
//   完整取证见 `specs/UI-DESIGN.md` §7 第 9 条、`内部踩坑表` §3.0-151、r16 REPORT 的 B0 项。

import {
  BLUR_BRIGHTNESS, BLUR_SATURATION, FADE_ANGLE_DOWN, FADE_STOP_CLEAR,
  CURVE_STD, FADE_STOP_GLASS, FS_TITLE, GAP_SM, GAP_XS, ICON_BTN, ICON_BTN_VISUAL, MENU_BAR_H,
  MENU_BAR_RADIUS, MENU_BAR_W_LONG, MENU_BAR_W_SHORT, MENU_GLYPH_H, MENU_GLYPH_W, MOTION_FAST,
  OFFICIAL_MATERIAL, officialImmersiveMaterial,
  ShellIconButton, ShellIconHotRegion, TOP_BAR_BLUR, TOP_BAR_H, TOPBAR_FADE_H
} from '../common/ShellUi';

// 菜单（汉堡）图标的几何（`MENU_BAR_W_*` / `MENU_GLYPH_*`）现在统一定义在
// `common/ShellUi.ets`（图形的边长与字号、间距是三条不同的刻度线，不能混用 ——
// 见该文件"图形边长"一节的说明）。本文件只负责把它画出来。

/**
 * 顶栏左右按钮槽的固定宽度（vp）。
 *
 * **必须"固定 + 左右相等"**：标题槽用 `layoutWeight(1)` 吃掉剩余空间，只有左右槽等宽时
 * 剩余空间的中心才等于屏幕中心 —— 标题因此严格居中，且不随路由漂移。
 *
 * **96 → 52（第十九轮，R19）**：旧值 `ICON_BTN*2 + GAP_SM`(96) 是按"右槽最多同时出现
 * 「新建对话」+「分享会话链接」两个按钮"定的；R19 按 iOS 移除分享后右槽**恒为 1 个按钮**，
 * 槽宽随之收敛为 `ICON_BTN(44) + GAP_SM(8) = 52`（仍留 8vp 安全垫，不做"零余量精确贴合"——
 * 零余量时任何尺寸微调都会**静默溢出被裁**，顶栏上不会有任何报错，正是 §3.0-141 的形态）。
 * 收益直接落在标题上：标题可用宽度 `376 − 52×2 − 16 ≈ **256vp**`（原 `376 − 96×2 − 16 ≈ 168vp`），
 * 与 iOS 实测标题槽 250~290pt 同档 —— iOS 三张会话页截图的长标题都不截断，而旧值约 10 个汉字就截断。
 *
 * ⚠️ **左右槽必须同时改**（两处都引用本常量），任何"只收窄一侧"的改法都会让标题中心偏离屏幕中心。
 */
const SLOT_W: number = ICON_BTN + GAP_SM;

/**
 * **第二十轮（R20）：顶栏改由官方 `Navigation` 标题栏承载** —— 栏本体与栏内 3 个按钮
 * 全部走官方「沉浸光感」（`uiMaterial.ImmersiveMaterial`），自绘 `backgroundEffect` 整组退场。
 * 依据：官方沉浸光感**只在 `Navigation`/`NavDestination` 标题栏（或横向 Tabs 底部 TabBar）
 * 里生效**，挂在页面正文里是**静默无效**（`内部踩坑表` §3.0-245）⇒ 想让材质生效，
 * 顶栏必须先"进栏"。
 *
 * ─────────────────────────────────────────────────────────────────────────
 * # 几何标定（**真机 dumpLayout 实测**；数值 + 命令 + 判据三件套）
 *
 * 设备：PLA-AL10 / API 26 / OpenHarmony-7.0.0.105，sn=**DEVICE_SN_REDACTED**，
 * 物理 1316×2832。**px/vp = 2.975**（判据：应用把 `__dshStatusBarPx=45.714` 推给网页，
 * 而状态栏窗口 = 136px ⇒ 136/45.714 = 2.975；同一比例下网页 `innerHeight = 952` CSS px
 * 对应 952×2.975 = 2832px = 整屏高）。命令：
 * ```
 *   hdc -t DEVICE_SN_REDACTED shell uitest dumpLayout -p /data/local/tmp/x.json
 *   hdc -t DEVICE_SN_REDACTED file recv /data/local/tmp/x.json "%TEMP%\dsh-r-material-t2\x.json"
 *   （转储解析与像素剖面脚本见 %TEMP%\dsh-r-material-t2\scripts\，不进工程目录）
 * ```
 *
 * ## ⚠️ 先记一条**读 dump 的坑**（本轮的第一次误判就是栽在这里）
 * `uitest dumpLayout` 把**节点顶边钳在状态栏下沿 137px**：节点若从屏幕 y=0 起，转储里
 * 报的是 `[.,137]`。判据（三条互相独立、都指向同一结论）：
 *   ① 本工程 `Web` 铺满整窗口，网页 `innerHeight` 实测 **952 CSS px = 2832px = 整屏高**
 *      ⇒ Web 的顶边必是 **y=0**，而转储报 `Web [0,137][1316,2832]`；
 *   ② `TopBar` 的 `Column` 源码高度 = `topPad + TOP_BAR_H + TOPBAR_FADE_H` = 45.714+52+16
 *      = **113.71vp = 338px**，转储报 `[0,137][1316,338]` ⇒ 底边 338 对得上、顶边被钳；
 *   ③ 窗口管理器 `hidumper -s WindowManagerService` 实测 `deepseekhm0 [0 0 1316 2832]`
 *      ⇒ 应用窗口全屏，页面根不在 137。
 * ⇒ **下面所有坐标一律换算成"屏幕绝对 px"后再比**，不要直接拿转储里的顶边当几何。
 *
 * ## 改前基线（T1 包 md5 = **156a128e8bfb7503e985621485bb0f91**，812821 B）
 *   · 状态栏 136px（45.71vp）；网页侧 spacer `__dshTopInsetPx = 97.714` CSS px = **291px**
 *     （与转储里网页首个容器的顶边 291 逐点吻合）；
 *   · 顶栏玻璃主体 `Row`：**0..291px**（`topPad`+52vp = 97.71vp）；
 *   · 渐变过渡带 `Blank`：**291..338px**（16vp = 47.6px）；
 *   · 三槽 Row 内按钮可见圆：**154..273px**（中心 214）；
 *   · ⇒ 原生绘制物覆盖 **0..338px**；其中"spacer 291 以下的正文"被渐变叠盖 **291..338 = 47px**。
 *
 * ## 框架标题栏几何（本轮实测 + aa-hm 同族真机同 API 互证）
 *   · `.titleMode(Full)` ⇒ 框架 `TitleBar` = 窗口顶起 **112vp**：转储 `[0,137][1316,332]`
 *     ⇒ 底边 **332px**（= 112vp×2.975 = 333 ✓）；⛔ `Mini`/`Free` 都不可用（Mini 从 y=0
 *     起算、状态栏之下只剩 29px，真机证伪；Free 标题随滚动收起）。
 *   · **构造器顶边被框架锚在 166px**（= 45.71vp 状态栏 + (66−45.71)/2 ≈ 55.8vp）：
 *     框架按"标准 46vp 行在 66vp 槽里居中"算出的余量，**与构造器自身高度无关**。
 *     实测：本构造器请求 66vp(196px) → 转储 `Column [0,166][1316,332]`（高 166px = 56vp，被钳）。
 *     ⇒ 构造器**可用高度 = 332 − 166 = 166px = 56vp**；请求 66 只会被钳成同一个 166px（两者实测同落点）。
 *   · ⇒ 三槽 Row（52vp=154px）贴顶落在 **166..320px**，按钮可见圆 **184..304px**（中心 244）。
 *     ⚠️ 这比改前**低 30px**：这是"进框架标题栏"的固有代价（aa-hm 9 个页面同款，其 46vp 行
 *     同样落在 166..302），**不是**参数写错 —— 只要用 Full，构造器顶边就压不回 137。
 *
 * ## 几何契约判据（沉浸形态，用户 2026-09-25 真机拍板）
 *   框架栏的 `backgroundEffect` 覆盖 **0..332px（= 0..112vp，含状态栏那 46vp）**，模糊从屏幕最顶连续铺下来。
 *   网页侧让位因此同步收到 **`topInset + NAV_TITLE_SLOT_VP` = 45.71 + 66 = 111.71vp = 332px**
 *   （`pages/Index.ets` 的 `injectShell()` 与 `pushInsets()` 两处同源，另 ErrorPane / NewChatTipLayer 同源）：
 *   · 网页**正文首行**起于 332px = 栏下沿 ⇒ **一点都不落进模糊区**（"正文不被多糊"的判据）；
 *   · 代价（如实记）：让位量从改前的 97.71vp(=291px) 增到 111.71vp(=332px)，**上方被原生覆盖的高度
 *     +14vp** —— 这是"内容不被糊"与"覆盖更少"二选一的取舍，本轮由用户按"沉浸、不要分界"拍板取前者。
 *   · `TOPBAR_FADE_GUARD`（utils/DeepSeekConfig.ets:100）**无需改动**：它算的是
 *     `setTopCss = 让位量 + 20` = 111.71 + 20 = **131.71 CSS px = 392px**，仍 **> 丢包带下界 332px**（实测见下）；
 *     面板/抽屉顶部也仍在栏下沿之下 ⇒ 设置面板的交互件不会被吃点击。该常量不在本任务 write scope，
 *     结论已同步给 lead。
 *
 * ## 命中测试丢包带（§3.0-159 的老坑，本轮复测）
 *   真机 CDP 探针（`%TEMP%\dsh-r-material-t2\scripts\band-probe.mjs`：在网页里挂 click 监听，
 *   再用 `uitest uiInput click 658 <y>` 逐点点击、读回 clientY）实测：
 *   · 改后：**y ≤ 332px 丢包，y ≥ 335px 稳定送达** —— 下界 = 框架 `TitleBar` 底边
 *     （转储 `TitleBar ht=HitTestMode.Default` 覆盖 0..332；我们自己的 Row 只到 320）；
 *   · 改前（装入 T1 冻结包 `dev-debug-20260925-143925.hap`，md5 156a128e… 实测）：同探针下
 *     **y ≤ 335px 丢包、y ≥ 340px 送达** —— 与 `DeepSeekConfig.ets` 注释里"物理 y≤336 丢包、
 *     y≥345 稳定"的历史记录同档。
 *   ⇒ **332 < 335：丢包带比改前还短 3px，没有回归**（原先担心的"框架栏多吃 41px"不成立：
 *     改前的自绘栏同样吃到 ~338px）。
 *
 * ▸ 本文件的实现取法（**默认档 = 沉浸形态**）：框架栏 `backgroundEffect` 供模糊（`topBarTitleOptions()`），
 *   构造器 = `Column{ Row(三槽) }`，高 `NAV_TITLE_SLOT_VP`、`justifyContent(FlexAlign.Start)`，
 *   **Row 上不挂任何材质**（零自绘层）；渐变过渡带**已删除**（它会在自己边缘产生第二条分界）。
 *   `NAV_TITLE_SLOT_VP` 在本文件同时承担两个语义：① 构造器请求高度（实测被框架钳到 56vp，
 *   两种取值落点相同）；② `pages/Index.ets` 网页侧让位的加数（此处**必须**是 66 = 112−46，
 *   否则正文首行会落进模糊区）。
 */
export const NAV_TITLE_SLOT_VP: number = 66;

/**
 * **栏本体 "谁在画底" 的总闸**（编译期常量，一行可切）：
 *
 * · `true`（**默认 = 沉浸形态，用户 2026-09-25 真机拍板**）：模糊由**框架标题栏自己**供给
 *   （`NavigationTitleOptions.backgroundEffect`）。`.titleMode(Full)` 下框架栏 = 窗口顶 0..112vp
 *   （**含状态栏那 46vp**）⇒ 模糊**从屏幕最顶连续覆盖**，没有上缘接缝、也没有"状态栏带 / 标题栏带"
 *   的二次分界 —— 这才是用户要的"沉浸式"。Row 上**不挂任何材质**。
 * · `false`（**A/B 对照档，已被用户否决**）：框架栏不挂模糊，材质改挂自建 `Row`
 *   （`CommonMethod.systemMaterial`）—— 即"有接缝"的那一版：节点级材质画出来是一个
 *   **有确定边界的圆角带**，下缘就是一条可见接缝（用户原话"标题栏和页面有明显分界线"；
 *   aa-hm R77 同型真机逐像素实测 y=167 顶缘高光 255 / y=356 底缘高光 254）。
 *   保留它只为 A/B 对照与一行回退。
 *
 * ⚠️ 两档**互斥**：见 `topBarTitleOptions()` 的 `if/return`（不是三元拼字段，避免同时挂两层）。
 * ⚠️ **曾用名 `TOPBAR_BAR_MATERIAL`**（R20 改名，语义与行为相反 —— 那个名字读起来像"栏本体挂材质"，
 *    恰好指 false 那一档；docs 独立核出、Lead 采纳）⇒ 只作追溯，**不要再改回去**。
 * ⚠️ 命名口径：本常量描述"**框架栏是否供模糊**"，而不是"Row 是否挂材质" —— 后者是它的副产物。
 */
const TOPBAR_FRAMEWORK_BLUR: boolean = true;

/**
 * `Navigation.title(构造器, 选项)` 的**选项**：栏本体的官方材质 / 框架模糊二选一。
 *
 * 为什么写成函数而不是就地写对象字面量：① 两形态**必须互斥**（同时挂 `systemMaterial` 与
 * `backgroundEffect` 就是两层叠加，测不出官方那层的贡献）；② 调用点 `pages/Index.ets` 只管
 * "用哪个选项"，不重复材质参数（口径同 `common/ShellUi.ets` 的 `officialImmersiveMaterial()`）。
 *
 * ⚠️ `backgroundColor` 必须**显式** `Color.Transparent`：不透明的标题栏底色会把材质/模糊整层盖住。
 */
export function topBarTitleOptions(): NavigationTitleOptions {
  if (TOPBAR_FRAMEWORK_BLUR) {
    // **默认档 = 沉浸形态（用户 2026-09-25 真机拍板）**：模糊由**框架标题栏自己**供给
    // （官方框架属性 `NavigationTitleOptions.backgroundEffect`，`navigation.d.ts:1744-1758` @since 19）。
    // `.titleMode(Full)` 下框架栏占**窗口顶 0..112vp**（含状态栏那 46vp）⇒ 这一层模糊是
    // **从屏幕最顶连续覆盖**的：没有上缘接缝，也没有"状态栏带 / 标题栏带"的二次分界 —— 这就是"沉浸"。
    // 依据（aa-hm R77 原文）：官方常驻 `backgroundEffect`「已经把正文滚到栏背后被糊化这件事做完了
    // ⇒ 沉浸一点没少」，且节点级材质那条**有确定边界的圆角带**在同型真机上被逐像素证伪
    // （y=167 顶缘高光 255 / y=356 底缘高光 254，用户原话"标题栏和时间栏有明显分界"）。
    return {
      barStyle: BarStyle.STACK,
      backgroundColor: Color.Transparent,
      // 同一档 blur 三参数 + 同一个半透明令牌（与改前自绘层逐字相同）⇒ 色调与糊度不变，只换"谁在画底"。
      backgroundEffect: {
        radius: TOP_BAR_BLUR,
        saturation: BLUR_SATURATION,
        brightness: BLUR_BRIGHTNESS,
        color: $r('app.color.shell_topbar_glass')
      }
    };
  }
  // **A/B 对照档（已被用户否决）**：框架栏什么都不画，材质改挂自建 Row
  // （`CommonMethod.systemMaterial`）—— 那正是"有接缝"的那一版，只保留作 A/B 对照/回退。
  return {
    barStyle: BarStyle.STACK,
    backgroundColor: Color.Transparent
  };
}

/**
 * 顶栏渐变过渡带：玻璃色（同 RGB、alpha 见令牌）→ `shell_topbar_fade`（同 RGB、alpha=0）
 * 的自上而下渐变，高 `TOPBAR_FADE_H`(16vp)、整宽、`HitTestMode.None`（纯装饰，不许吃点击 —— §3.0-159）。
 *
 * ## 现在**只有自绘回退档**用它（唯一调用点 = `DrawnBar()`，跟在玻璃主体下面，与改前逐字相同）
 *   · **官方档（默认）已删除这层过渡带**：它的存在理由（抹平磨砂方块的下缘接缝）已被框架标题栏
 *     自己的 `backgroundEffect` 边缘接替；留着它只会在它自己的边缘再产生**第二条分界**，
 *     正是用户 2026-09-25 反馈"标题栏和页面有明显分界线"要消灭的东西。
 *     `pages/Index.ets` 的官方分支里**没有**任何 `TopBarFadeBand()` 调用点（grep 可证）。
 *   · 也不许把它塞回 `.title(...)` 构造器：构造器可用高只有 56vp（框架锚点 166px → 底 332px），
 *     玻璃主体 52vp + 本带 16vp = 68vp 会被框架裁掉 12vp。
 */
@Builder
export function TopBarFadeBand() {
  Blank()
    .width('100%')
    .height(TOPBAR_FADE_H)
    // 终点色必须用 `shell_topbar_fade`（与玻璃色**同 RGB、alpha = 0**），**不能**用
    // `Color.Transparent` —— 后者是"透明黑"，插值过程会让过渡带整体发灰（浅色下尤其明显）。
    // ⚠️ **必须用 `Blank()` 而不是 `Column() {}`**：ArkTS 编译器对"空块容器 + 紧随其后的
    // 父级闭合 `}`"这种写法会解析失败（报 `arkts-no-any-unknown` / Rollup `Unexpected token`），
    // 而错误行号指向的是**父级修饰符**，很难一眼看出是它。`Blank()` 是无子节点的基础组件，
    // 没有这个坑，而且它本来就是"占位撑开"的语义 —— 正合适。
    .linearGradient({
      angle: FADE_ANGLE_DOWN,
      colors: [
        [$r('app.color.shell_topbar_glass'), FADE_STOP_GLASS],
        [$r('app.color.shell_topbar_fade'), FADE_STOP_CLEAR]
      ]
    })
    .hitTestBehavior(HitTestMode.None)
}

@Component
export struct TopBar {
  /**
   * 路由类别：`home` 首页 / `chat` 会话页 / `other` 子页（登录、条款等）/
   * `settings` 设置页浮层（R19 新增，由网页侧在浮层打开/关闭时上报）。
   * 取值来自桥消息 `route` 的 `kind` 字段（原样接收、无白名单），所以新增一类**不需要**改
   * `pages/Index.ets`；本组件是唯一按它分支渲染的地方。
   */
  @Prop routeKind: string = 'home';
  /**
   * 标题：会话标题 / 文档标题（由 `Index.displayTitle()` 决定）。
   * ⚠️ `home` 路由**不渲染**它（iOS 首页顶栏中间整条留空），但本参数**不能删** ——
   * 会话页与子页仍用它；首页那条取值只是被忽略。
   */
  @Prop title: string = 'DeepSeek';
  /** 状态栏高度（vp）。 */
  @Prop topPad: number = 0;
  // 这里原本有一个 `@Prop isDark`（透传给 `backgroundEffect.brightness` 的三元）。
  // **第十九轮删除**：两个亮度令牌（`BLUR_BRIGHTNESS` / `DARK_BRIGHTNESS`）真机实测同值
  // ⇒ 它**从未改变过任何绘制结果**；第十八轮把它留成"父组件在传、删了会留下无人消费的参数"，
  // 而 W3 已在 pages/Index.ets 侧删掉传参，于是它自己成了那个无人消费的参数。
  // 判据（grep 全工程）：`isDark` 在 .ets 里只剩注释命中。

  /** 子页返回。 */
  onBack: () => void = () => {};
  /** 侧栏开 / 关切换（`home`、`chat`）。必须 toggle 语义：只开不关会让用户以为顶栏坏了。 */
  onToggleSidebar: () => void = () => {};
  /** 新建对话。 */
  onNewChat: () => void = () => {};
  // 这里原本还有一个 `onShare`（分享会话链接）。**第十九轮删除**（连同右槽的分享按钮）：
  // 按 iOS 移除该按钮后它成了零消费者参数 —— 本工程明令消灭"看着像配置项、其实没人用"的假旋钮
  // （同 `MOTION_SLOW` / `PRESS_SCALE` / `SHADOW_DY_MD` 的处置）。调用点 pages/Index.ets 同步删除。

  /**
   * **官方档**（`OFFICIAL_MATERIAL` 且父组件传 `official: true`）：本实例是
   * `Navigation.title(...)` 的**标题栏构造器**，栏本体由框架标题栏的
   * `systemMaterial` / `backgroundEffect`（见 `topBarTitleOptions()`）画底 ——
   * 因此**本分支内不许有任何自绘层**：没有 `backgroundEffect(` / `.shadow(` /
   * `linearGradient(` / `backgroundColor(` / `.borderColor(` / `.borderWidth(`。
   * 依据：材质会**接管** `backgroundColor`/`borderColor`/`borderWidth`/`shadow`，
   * 官方不建议同用（SDK `@ohos.arkui.uiMaterial.d.ts:19-24`）；两层叠着也会把官方那层的
   * 贡献压到测不出来。**这是本轮 "官方分支零自绘层" 的落点，逐条对应验收 ③。**
   */
  @Prop official: boolean = false;

  build() {
    if (this.official && OFFICIAL_MATERIAL) {
      this.OfficialBar()
    } else {
      this.DrawnBar()
    }
  }

  /**
   * 官方档栏本体 = **框架标题栏构造器**。高度取整槽 `NAV_TITLE_SLOT_VP`、内容贴顶
   * （`FlexAlign.Start`）⇒ 三槽 Row 落在 137..291px，与改前逐点同位（推导见文件头标定段）。
   *
   * ⚠️ **必须保留 `.hitTestBehavior(HitTestMode.None)`**（验收 ⑤、§3.0-159 的历史 P0）：
   * 本容器是铺满型的（整条 66vp 宽 100%），ArkUI 里**容器整块参与命中测试** ⇒ 不吃点击的那段
   * （三槽 Row 之外、以及栏下沿那条）会把触摸吃在原生层、传不到下面的 Web。
   * `None` 的语义是"自身不吃、**子节点照吃**" ⇒ 三个按钮照常可点。
   */
  @Builder
  OfficialBar() {
    Column() {
      Row() {
        this.SlotLeft()
        this.SlotTitle()
        this.SlotRight()
      }
      // 左右内边距与改前同值（改前在带 padding 的 Row 上，这里拆成两层，值不变）。
      .width('100%')
      .height(TOP_BAR_H)
      .padding({ left: GAP_SM, right: GAP_SM })
      // ## 默认档这一行**不画任何东西**（零自绘层）：模糊由框架栏的 `backgroundEffect` 供给
      //    （`topBarTitleOptions()`）。栏内只有「三槽 + 三个按钮」，按钮各自挂官方沉浸光感。
      //    判据：默认档 grep 本文件应只见按钮上的 `.systemMaterial(`，见不到行级的。
      // `materialColor` 用带 alpha 的 `shell_topbar_glass`（= 改前那层自绘磨砂的同一个令牌，
      //    色调不变）；完全不透明的色会挡死材质滤镜（SDK `@ohos.arkui.uiMaterial.d.ts:325-327`）。
      // ⛔ 默认档**不挂**：节点级材质画出来是"有确定边界的圆角材质带"，下缘即可见接缝
      //    （用户 2026-09-25 原话"标题栏和页面有明显分界线"）⇒ 模糊改由框架栏供给。
      //    只在 A/B 对照档（`TOPBAR_FRAMEWORK_BLUR=false`，**已被用户真机否决**）才挂回来做对照。
      .systemMaterial(TOPBAR_FRAMEWORK_BLUR
        ? undefined
        : officialImmersiveMaterial($r('app.color.shell_topbar_glass')))
    }
    .width('100%')
    // ⚠️ 值 = **实测可用槽高 56vp**（166..332px）：框架把构造器顶边锚在 166px 且底边钳在
    //    332px（见文件头标定）。写 66（= 112−46 的理论槽高）会**被框架钳成同一个 166px**，
    //    实测两者落点完全一致 —— 这里取 56 是为了让常量与实测口径一致，不是改几何。
    .height(NAV_TITLE_SLOT_VP)
    .justifyContent(FlexAlign.Start)
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * **自绘档**（本轮之前的口径，回退路线）：`OFFICIAL_MATERIAL = false` 或
   * 调用点 `official: false` 时走这里，与改前**逐字相同** —— 悬浮浮层 + 自绘磨砂主体
   * （`backgroundEffect` 挂在内层 Row）+ 底部渐变过渡带 `TOPBAR_FADE_H`。
   */
  @Builder
  DrawnBar() {
    Column() {
      Row() {
        this.SlotLeft()
        this.SlotTitle()
        this.SlotRight()
      }
      .width('100%')
      .height(this.topPad + TOP_BAR_H)
      // ⚠️ padding **只能设一次**：ArkUI 里后设的 padding 会整体**覆盖**前面的，不是合并。
      // 所以"状态栏避让 + 左右内边距"必须写在同一个对象里（分开写会静默丢掉左右内边距）。
      .padding({ top: this.topPad, left: GAP_SM, right: GAP_SM })
      // 悬浮顶栏**主体**：磨砂玻璃（内容滚到它下面时被高斯糊化）。
      // 前提是 Web 组件铺满整个窗口且网页内容在顶部留出 topInset 占位（见 MainPane）。
      // 用 `backgroundEffect` 而非 `backdropBlur`：后者只有 radius / grayscale 两个旋钮，
      // 没法按深浅色分别调亮度；`backgroundEffect` 的 color 吃双值资源、brightness 可按主题补偿。
      // 更不能用 `backgroundBlurStyle`：那是"材质"，自带近不透明遮罩（§3.0-74）。
      //
      // ⚠️ **`backgroundEffect` 只加在这一层（主体），绝不能加到外层**：它是一层**均匀**的模糊，
      // 盖到哪儿哪儿就糊。第一版把它加在"主体 + 过渡带"的整块上，于是过渡带里的内容**也是糊的** ——
      // 用户看到的是"内容只是变淡了、并没有变清晰"，正是"模糊效果不对"的反馈。
      .backgroundEffect({
        radius: TOP_BAR_BLUR,
        saturation: BLUR_SATURATION,
        // 亮度**恒定**取 `BLUR_BRIGHTNESS`（中性值 1.0）：真机逐像素实测"模糊本身中性"——
        // 玻璃色 alpha 归零时模糊区与页面底色完全相等 ⇒ 色差 100% 来自玻璃色叠加，
        // 深浅色差异全部由 `shell_topbar_glass` 的双值资源承担，这里**不需要**按主题分档。
        // 不要恢复成"按深浅色三元"：那只会让后来者以为改亮度能调深浅色观感（实际同值、零效果）。
        brightness: BLUR_BRIGHTNESS,
        color: $r('app.color.shell_topbar_glass')
      })

      // 渐变过渡带：**只有颜色渐隐、没有任何模糊**（用户要求的"自下而上由清晰到模糊"）。
      // 它下面的内容是**清晰**的，只是被逐渐淡出的玻璃色覆盖 —— 于是从下往上看是
      // "清晰 → 半淡 → 磨砂"，而不是"整块都糊、只是浓淡不同"。
      // 参考效果：华为系统设置的沉浸顶栏（磨砂块 + 下方内容清晰）。
      // 定义（含"为什么必须 Blank()"与终点色为何不能用 Color.Transparent 的理由）
      // 已收口到全局构建函数 `TopBarFadeBand()` —— **本自绘回退档是它当前唯一的调用点**
      // （官方档已删除这层过渡带，理由见该函数注释）。
      TopBarFadeBand()
    }
    .width('100%')
    .height(TOP_BAR_H + this.topPad + TOPBAR_FADE_H)
    // —— 修：渐隐带里的点击被本容器整条吃掉（§3.0-159）——
    // 本容器高度含装饰性的 `TOPBAR_FADE_H`(16)，而 ArkUI **容器整块参与命中测试** ⇒ 带子里
    // "看着是空白"的 16vp 把触摸吃在原生层，传不到下面的 Web（真机实测丢包下界 = topInset+16）。
    // 上一轮只在网页侧绕，原生侧这条根留着。`HitTestMode.None` 的语义正是"自身不吃、子节点照吃"：
    // 根容器声明它，带子里的触摸穿透到 Web，顶栏主体里的三槽 `Row` 与按钮照常可点。
    // ⚠️ 必须重跑顶栏真实触摸回归（汉堡 / 新建对话 / 子页返回 / 顶栏下方带内点击穿透）。
    //   R19 移除了「分享会话链接」，所以"分享"点位不再有；但**新增了两个必测点**：
    //   ① 浅底圆是画在 44 按钮**内部**的 Stack 子节点，必须确认它没把按钮的点击吃掉
    //      （§3.0-159：容器整块参与命中测试，漏配 hitTestBehavior 会静默丢包）；
    //   ② 槽宽 96 → 52 后左右槽仍等宽，标题必须**严格居中**（会话页长标题逐字复核）。
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 左槽：**固定宽度**（见 SLOT_W 注释），内容贴左。
   *
   * `other` 路由下这里只放 1 个按钮、却仍占满整槽 —— 那 8vp 是**刻意留白**：
   * 左右槽等宽才能让标题槽的中心等于屏幕中心。**不要**为了"填满"把它改成自适应宽度，
   * 那会让标题随路由左右漂移（`specs/UI-DESIGN.md` §2「标题」一节写明了这个取舍）。
   *
   * `settings`（设置页浮层，**第二十一轮改**）：左槽放 **`<` 返回钮**（用户要求把 ✕ 换成 `<`）。
   * 为什么不是留白：设置页现在由**原生标题栏**整页承载（标题「系统设置」在标题槽居中），
   * 返回入口就归顶栏；网页那一行大标题（含它自己的 ✕）已由适配器隐藏，不存在两个关闭控件。
   * 按钮同样走 `ShellIconButton(..., official)` ⇒ 官方档下是官方沉浸光感。
   *
   * ⚠️ 拆成 @Builder 只做"把三槽从 build() 里提出来给两个分支共用"这一件事：
   * **不接收任何参数**（值参数会被 §3.0-38 钉成不随状态刷新），只读 `this.*`。
   */
  @Builder
  SlotLeft() {
    Row() {
      if (this.routeKind === 'other' || this.routeKind === 'settings') {
        // 子页返回 / 设置页关闭：与侧栏开关同样是"圆形浅底 + 图标"（iOS 顶栏两侧按钮形态一致）
        // `official` 透传 ⇒ 官方档走零自绘层的官方沉浸光感（验收 ②）。
        ShellIconButton($r('sys.symbol.chevron_left'),
          this.routeKind === 'settings' ? '关闭设置' : '返回', this.onBack, true, this.official)
      } else {
        this.MenuButton(this.onToggleSidebar)
      }
    }
    .width(SLOT_W)
    .height(TOP_BAR_H)
    .justifyContent(FlexAlign.Start)
  }

  /**
   * 标题槽：占满剩余空间并居中。**左右槽等宽 ⇒ 剩余空间的中心 = 屏幕中心**，
   * 因此标题严格居中，且 `home`/`chat`/`other`/`settings` 之间切换时一动不动
   * （槽宽是常量，与槽内到底有没有按钮无关）。长标题按 iOS 的做法单行省略（不是缺陷）。
   *
   * **首页不显示标题**（第十九轮）：iOS 首页顶栏中间整条留空（官方截图 crop-topbar.png 实证）。
   * 首页原本显示品牌名「DeepSeek」，而网页区正中已经有鲸鱼 logo + 问候语，重复且不是 iOS 形态。
   * **设置页（settings）由原生标题栏整页承载**（第二十一轮，用户要求）：
   * 标题「系统设置」显示在标题槽（严格居中），网页那一行大标题已由适配器隐藏 ⇒ 不再双重标题。
   * `displayTitle()` 在 settings 路由下固定返回「系统设置」，不走网页文档标题（那是会话名）。
   * 注意：`title` 这个 @Prop **不能删** —— 会话页/子页/设置页都在用它（只有 home 不渲染）。
   */
  @Builder
  SlotTitle() {
    Row() {
      if (this.routeKind !== 'home') {
        Text(this.title)
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .layoutWeight(1)
    .height(TOP_BAR_H)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 右槽：同样固定 `SLOT_W`（`ICON_BTN + GAP_SM`，放得下 1 个按钮并留 8vp 垫），内容贴右。
   *
   * `other`（登录/条款等子页）与 `settings`（设置页浮层）都**不渲染**「新建对话」：
   * 这两类页面上"新建对话"既不是当前语境的动作，iOS 的设置页顶栏也只有取消/完成。
   *
   * 首页本来就是"新对话"态：点它只给一次轻提示，不去动官方页面状态
   * （为什么：会重置输入框草稿与已选的深度思考/智能搜索，见 Index.requestNewChat）
   *
   * 图标 `plus` → `plus_circle`（第十九轮）：iOS 顶栏右槽是「**圆圈加号 ⊕**」
   * （crop-topbar.png 放大 4 倍逐像素核对：加号在圆**内**、圆左下有小尾巴即气泡嘴），
   * 而本工程原先是裸 `+`。SDK 实证（id_defined.json 的 symbol 段）：
   *   · `plus_circle` = 圆圈 + 内置加号 —— 与 iOS 造型最接近；
   *   · `message_badge_plus` = 气泡 + **右下角徽标**加号（加号在气泡外的小实心圆里），
   *     18vp 下徽标糊成一团，且与 iOS 的"加号在圆内"不同 ⇒ 不取；
   *   · `circle_and_plus`（W4 复核时建议并排看一眼）= 圆**右上角开口**、加号落在缺口处
   *     （加号在圆的轮廓**外**）⇒ 与 iOS"加号在圆内"不符，**不取**。已渲染并排比对
   *     （`tmp/r19-w2/symbols-menu.png` 第一格 vs 第二格）。
   * **无 SDK 符号同时具备"气泡尾巴 + 圆内加号"**（穷举了 85 个含 plus 的符号）⇒ 如实记录残差。
   */
  @Builder
  SlotRight() {
    Row() {
      if (this.routeKind !== 'other' && this.routeKind !== 'settings') {
        ShellIconButton($r('sys.symbol.plus_circle'), '新建对话', this.onNewChat, true, this.official)
      }
    }
    .width(SLOT_W)
    .height(TOP_BAR_H)
    .justifyContent(FlexAlign.End)
  }

  /**
   * 菜单图标本体：**两条**横杠、**上长下短、左端对齐**（第十九轮由三条改来）。
   * 自绘理由、旧定标为何被推翻、以及"SDK 里确实没有这个造型"的穷举核对，全在
   * `ShellUi.ets` 的菜单令牌段（改这里之前先读那段）。
   *
   * ⚠️ `MENU_BAR_W_MID` **仍在 `ShellUi.ets` 里导出**（RULES §1.5 不允许删已导出常量），
   * 但它**不参与绘制** —— 别看到它就以为图标是三条。
   */
  @Builder
  MenuGlyph() {
    Column({ space: GAP_XS }) {
      Row()
        .width(MENU_BAR_W_LONG)
        .height(MENU_BAR_H)
        .borderRadius(MENU_BAR_RADIUS)
        .backgroundColor($r('app.color.text_primary'))
      Row()
        .width(MENU_BAR_W_SHORT)
        .height(MENU_BAR_H)
        .borderRadius(MENU_BAR_RADIUS)
        .backgroundColor($r('app.color.text_primary'))
    }
    // **左对齐**（不是居中）：iOS 的两条杠左端齐平、只有右端长短不同。
    // 容器宽 = 长杠宽（`MENU_GLYPH_W`），所以"左对齐"的结果是长杠在圆内居中、短杠贴它的左端。
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(MENU_GLYPH_W)
    .height(MENU_GLYPH_H)
  }

  /**
   * 侧栏开关：与全局 `ShellIconButton` **同一套配方**（同尺寸 / 同按压 / 同无障碍），
   * 只把图标换成自绘的菜单横杠 —— 它不是图标按钮配方的副本，而是配方 + 自绘图标。
   * 无障碍文案是"打开侧栏"：它在面板展开时仍可点（面板只占 82% 宽），动作是 toggle，
   * 读屏要能听出"这是一个可切换的开关"。
   */
  @Builder
  MenuButton(action: () => void) {
    // 与 `ShellIconButton(…, official)` 的**两个分支一一对应**：官方档 / 自绘档（验收 ②）。
    // 两分支的**几何逐字相同**（`ICON_BTN_VISUAL` / `ShellIconHotRegion(true)` / 同一套无障碍三件套），
    // 只差"哪一层在画底" ⇒ A/B 的逐像素差值可归因。
    if (this.official && OFFICIAL_MATERIAL) {
      Button({ type: ButtonType.Circle, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.MenuGlyph()
      }
      .width(ICON_BTN_VISUAL)
      .height(ICON_BTN_VISUAL)
      // **零自绘层**：没有 `stateStyles` / `backgroundColor` / `.animation()` ——
      // 底部圆与按压反馈全部交给官方沉浸材质（`interactive: true` 供形变 + `lightEffect` 供光感）。
      // `materialColor` 用带 alpha 的 `icon_btn_material`：完全不透明的色会挡死材质滤镜
      // （SDK `@ohos.arkui.uiMaterial.d.ts:325-327`）。
      // ⚠️ `MenuGlyph()` 里那两处 `backgroundColor` 是**图标笔画本身**（两条横杠），不是"底"：
      //    SDK 的 4042 个 symbol 里没有"两条、上长下短、左端对齐"的造型（穷举实证见 ShellUi.ets
      //    的菜单令牌段）⇒ 只能自绘；除去它这个图标就不存在了，故它是**内容**而非自绘层。
      .systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))
      .responseRegion(ShellIconHotRegion(true))
      .accessibilityText('打开侧栏')
      .accessibilityDescription('打开侧栏')
      .accessibilityLevel('yes')
      .onClick(action)
    } else {
      Button({ type: ButtonType.Circle, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        this.MenuGlyph()
      }
      // 与 `ShellIconButton(…, raised=true)` **同一套配方**：可见圆 = Button 自己的尺寸与底色
      // （`ICON_BTN_VISUAL` + `icon_btn_bg`）、按下换 `icon_btn_bg_pressed` 并走 `MOTION_FAST` 过渡、
      // 热区由 `ShellIconHotRegion(true)` 补回 44。本按钮只是把图标换成自绘的菜单横杠，不是第二份配方。
      .width(ICON_BTN_VISUAL)
      .height(ICON_BTN_VISUAL)
      .stateStyles({
        normal: {
          .backgroundColor($r('app.color.icon_btn_bg'))
        },
        pressed: {
          .backgroundColor($r('app.color.icon_btn_bg_pressed'))
        }
      })
      // 必须写在 stateStyles 之后（`.animation()` 只作用于它前面已声明的属性）
      .animation({ duration: MOTION_FAST, curve: CURVE_STD })
      .responseRegion(ShellIconHotRegion(true))
      .accessibilityText('打开侧栏')
      .accessibilityDescription('打开侧栏')
      .accessibilityLevel('yes')
      .onClick(action)
    }
  }
}
