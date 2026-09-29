// 原生外壳的**共享设计令牌表**（design tokens）。
//
// ## 这个文件是什么
// 本工程全部原生 UI 的**唯一数值来源**：尺寸、间距、圆角、字号、动效时长、曲线、
// 阴影、按压态。两条铁律：
//   ① **新代码一律引用这里的常量**，不再写裸数字（`52`/`38`/`14.5` 这种散落的魔数，
//      改一处忘一处就会出现"两个按钮差 2vp"这类肉眼看得见、却说不清来源的问题）；
//   ② **同一语义只留一个值**。需要新语义时在此新增常量并写明依据，不要就地写字面量。
//
// ## 为什么做成令牌（第十六轮，2026-09-15）
// 第十五轮把原本散在两个页面里的魔数收进本文件（P2-1），但收的**只是"用到的那些值"**，
// 没有统一的设计标尺：于是同一个"卡片圆角"在一个文件里是 10、另一个是 12，
// 动效时长有的 200ms 有的 260ms 有的 420ms，纯随机。本轮按 **iOS 人机界面指南（HIG）**
// 建立一套刻度（见 `../../../../specs/UI-DESIGN.md`），所有页面只从刻度取值。
//
// ## 为什么参考 iOS 而不是别的
// 用户明确要求"尽可能参考 iOS 端设计 UI"。本工程的设备尺度恰好与 iOS 对齐：
// 目标机 1316×2832 / density 560 ⇒ **1vp = pt**（有效宽 376vp ≈ iPhone 12 mini 的 375pt），
// 所以 iOS 的 pt 数值可以**一对一**搬进 vp，不需要换算，也不会出现"照抄后大小不对"。
//
// ## 取值口径（每条常量都标注了依据，改之前先读它的注释）
//   · iOS HIG：导航栏 44、最小触控目标 44×44、列表行 44、inset grouped 卡片圆角 10、
//     标准间距 8/16/20、默认转场 0.25s、按压反馈走"底色变暗"而非缩放；
//   · 官方 ArkUI 默认：Button 高度档位、`Curve.FastOutSlowIn` 作为标准缓动；
//   · 本工程既有**实测值**：任何与本机实测相关的（顶栏接缝、面板模糊、玻璃色 alpha）
//     都注明"实测"，**不要凭审美改**——那些值是逐像素量出来的。

// ── 零、官方沉浸材质（Kit 依赖收口） ─────────────────────────────────
//
// 官方沉浸材质（沉浸光感）的**唯一**构造入口在本文件：`officialBarMaterial()` /
// `officialIconMaterial()`。`uiMaterial` 属于 `@kit.ArkUI`，Kit 依赖收口在此，
// 页面/组件只传一个**半透明**色令牌（与 aa-hm 的 ui/Components.ets 同一口径）。
//
// 这样做的两条理由：
//   ① 档位（THIN / ULTRA_THIN）与六个字段将来只改一处，不会「十余处各写一遍」而漏改；
//   ② 官方分支由一个编译期常量 `OFFICIAL_MATERIAL` 统管 —— 一旦真机上发现材质画出硬边，
//      把它置 false 即可整体退回自绘层（自绘回退分支**始终保留在树上**，见 ShellIconButton）。
//
// ⚠️ 生效范围（HarmonyOS 7 起，仅对 targetSdkVersion >= 26.0.0 生效，内部踩坑表 §3.0-245）：
//    **其他组件仅在 Navigation / NavDestination 标题栏、或横向 Tabs 且
//    barPosition = BarPosition.End 的底部 TabBar 中生效；在页面正文里设置沉浸光感不生效**
//    （不报错、不告警，静默无效）。⇒ 挂载点必须在标题栏内，这个前提由调用方负责。
import { uiMaterial } from '@kit.ArkUI';

// ── 一、尺寸：导航与控件 ───────────────────────────────────────────────

/**
 * 顶栏高度（vp，**不含**状态栏避让）。
 *
 * **这是接缝常量，不要单独改**：网页内容整体下移量 = `topInset + 本值`，原生顶栏高度
 * 也 = `本值 + topInset`，两侧必须同源，改一处不改另一处会在顶栏下沿露出网页底色。
 *
 * 取值 52 = iOS 导航栏 44pt + 8vp 呼吸：本工程顶栏右侧承载"新建 + 分享"两个图标按钮，
 * 且要与官方网页顶栏 60px 的视觉尺度对齐（第六轮真机实测），故比纯 iOS 的 44 高一档。
 */
export const TOP_BAR_H: number = 52;

/**
 * 纯图标圆形按钮的可点直径（vp）。
 *
 * 40 → 44：iOS HIG 的最小触控目标是 **44×44pt**，40 是华为 Design/ArkUI 的推荐下限，
 * 两者取更严的 44（本工程 1vp = pt，单位等价）。顶栏高 52 容得下 44 的按钮（上下各 4）。
 */
export const ICON_BTN: number = 44;

/**
 * 图标按钮**可见圆**的直径（vp）—— 与可点直径 `ICON_BTN`(44) 分开的两件事。
 *
 * 依据（R19 一手素材：iOS 官方 App Store 截图 `tmp/r19-audit/ios-shots/crop-topbar.png`
 * 与 `crop-topbar-chat.png`，首页与会话页**一致**）：iOS 顶栏的图标按钮是「**圆形浅底 + 图标居中**」，
 * 圆直径约 40pt，而 iOS HIG 的最小触控目标仍是 44pt ⇒ **可见圆比可点区小一档**。
 * 本工程此前是"裸图标、无底色"（真机基线 `tmp/r19-baseline/base-home.jpeg` / `base-chat.jpeg`），
 * 这是与 iOS 差距最直观的一处。
 *
 * 实现口径：圆画在 44 的按钮**内部**（Button 尺寸与命中面保持 `ICON_BTN` 不变），
 * 所以本值**只影响观感、不影响触控** —— 把这两件事分开正是 iOS 的做法。
 */
export const ICON_BTN_VISUAL: number = 40;

/**
 * 最小触控目标边长（vp）= iOS HIG 的 **44×44pt**。
 * 只做 `ICON_BTN` 的别名而不另写一个 44：两者一旦分开，下次只调其中一个就不同源了。
 * 用途：`BTN_H_SM`(32) 的文字按钮用 `.responseRegion()` 把**可点**高度补到本值
 * （看得见的胶囊仍是 32，手指的范围是 44 —— iOS 导航栏的「完成」就是这个做法）。
 */
export const HOT_MIN: number = ICON_BTN;

/** 紧凑文字按钮高度（vp）：面板里的「全选 / 完成」等胶囊文字按钮，不要用主按钮高度（会撑高整行）。 */
export const BTN_H_SM: number = 32;

/** 主按钮高度（vp）：错误页「重新加载」等独立 CTA。iOS 主按钮为 44~50，取 44 与触控下限对齐。 */
export const BTN_H_MD: number = 44;

/** 面板头部 / 账号行的行高（vp）：比列表行高一档，明确"这是容器级行"。 */
export const ROW_H: number = 52;

/**
 * 列表行的行高（vp）。
 *
 * 42 → 44：iOS 列表行标准是 44pt，正好也是最小触控目标。行高不足会让"点行开会话"
 * 这种高频操作的可点区域低于规范下限。
 */
export const LIST_ROW_H: number = 44;

/** 分组标题行的高度（vp）：比列表行矮，只做分隔语义（iOS 的分组标题是 13pt 小字 + 上下留白）。 */
export const GROUP_ROW_H: number = 30;

// —— 图形边长（**不是**间距刻度，也不能用 FS_* 顶替：字号套到图形上会把行撞高）——
// 上收的理由：它们此前散在 view/*.ets 顶部各自声明，而同类值分裂过（审计 U-11：
// 同一个空态转圈 18 与 26 两套并存）—— 一档值只能有一个声明点。

/** 搜索框高度（vp）：iOS 搜索字段比 44 的按钮矮一档（`specs/UI-DESIGN.md` §3.2）。 */
export const SEARCH_H: number = 36;
/** 行内小图标边长（vp）：搜索框放大镜、勾选圈。与正文同高即可，取 `FS_ICON`(21) 会把行撞高。 */
export const ICON_INLINE: number = 18;
/** 空态/加载态转圈直径（vp）：面板内**统一一档**（审计 U-11 指出旧实现 18 与 26 两套并存）。 */
export const SPINNER_SIZE: number = 24;
/** 账号头像直径（vp）：`specs/UI-DESIGN.md` §3.2 规定 28。 */
export const AVATAR_SIZE: number = 28;

// —— 上传半模态「三宫格」的两个边长（R19 新增）——
// 依据同一份一手素材（iOS 官方截图 crop-attach.png / ios-reference.md §4.1）：
// 三个等宽方块的**高约 76pt**，块内**图标在上（约 26pt）、文字在下**、水平居中。

/**
 * 三宫格动作方块的高度（vp）：**图标 + 文字两行**的方块。
 * 不能用现成的高度档：`ROW_H`(52) / `BTN_H_MD`(44) 都只装得下一行，硬套会把方块压成一条。
 */
export const TILE_H: number = 76;

/**
 * 三宫格方块内图标字号（vp）。
 * **不复用 `SPINNER_SIZE`(24)**：那个令牌的语义是"空态转圈"，套到宫格图标上正是审计 U-11
 * 吃过的那类亏（同一个数值被两个语义共用 ⇒ 改一处伤另一处）。`ICON_INLINE`(18) 又明显偏小。
 */
export const TILE_ICON: number = 26;

// 菜单（汉堡）图标自绘的横杠：**两条、上长下短、左端对齐**（第十九轮由"三条"改来）。
//
// **为什么改（旧定标被推翻的过程，别再来回翻）**：
//   · 旧值是第十六轮的三条 19/16/13（居中错落）——那是**没有任何 iOS 对照素材**时的自定值；
//   · R19 拿到 iOS 官方 App Store 截图原图（`tmp/r19-audit/ios-shots/crop-topbar.png` 与
//     `crop-topbar-chat.png`，首页与会话页一致），4 倍放大后**明确是两条**：上面一条长、
//     下面一条短、两条**左端对齐**（见 `tmp/r19-w2/ios-btn-left.png`）；
//   · **有第一手素材时证据优先**（Lead 定夺）⇒ 三条改两条、居中改左对齐。
//
// **自绘例外仍然成立**（R19 重新穷举 SDK 全部 4042 个 symbol 名并逐个渲染核对过造型）：
//   `line_2_horizontal` = 两条**等长**；`line_3_horizontal` = 三条等长；
//   `text_alignleft` = **四条**；`align_left` = 竖线 + 两条粗杠；`line_text_alignleft` = 竖线 + 四条
//   ⇒ **没有任何符号是"两条、上长下短、左对齐"**，做不出来，只能自绘（`specs/UI-DESIGN.md` §5）。
/** 两条横杠的宽度（长 / 短，绘制顺序即此）。 */
export const MENU_BAR_W_LONG: number = 19;
export const MENU_BAR_W_SHORT: number = 13;
/**
 * **已停用（第十九轮）**：三条形态里"中间那条"的宽度。
 * 保留导出名是因为 RULES §1.5 规定"已导出的常量名不得删除"；**但它已不再被绘制** ——
 * 不要因为它还在就以为菜单图标是三条（真实形态见本段开头）。
 */
export const MENU_BAR_W_MID: number = 16;
/** 每条横杠的粗细与圆角半径（vp）。 */
export const MENU_BAR_H: number = 2;
export const MENU_BAR_RADIUS: number = 1;
/**
 * 菜单图标的外框（vp，宽 × 高）。
 * 宽 **= `MENU_BAR_W_LONG`(19)**：容器与长杠同宽 ⇒ 长杠在圆内**居中**、短杠**左端与它对齐**，
 * 正是 iOS 的形态。旧值 24 是"三条居中"时的外框，两条左对齐后沿用会让整个图形偏左 2.5vp。
 */
export const MENU_GLYPH_W: number = MENU_BAR_W_LONG;
export const MENU_GLYPH_H: number = 18;

// ── 二、间距刻度（8 的倍数为主，iOS 标准间距 8/16/20）─────────────────
//
// 用刻度而不是随手写 6/10/14：间距不统一是"页面看着不和谐"最常见的来源，
// 而且比字号更隐蔽（人眼能感到乱，但说不出哪里乱）。

/** 极小间距（vp）：图标与紧邻文字的间隙、发丝线两侧。 */
export const GAP_XS: number = 4;
/** 小间距（vp）：同一行内元素之间（iOS 常用值）。 */
export const GAP_SM: number = 8;
/** 中间距（vp）：控件之间、卡片内边距。 */
export const GAP_MD: number = 12;
/** 大间距（vp）：区块之间（iOS 标准 16）。 */
export const GAP_LG: number = 16;
/** 特大间距（vp）：页面级留白（iOS 标准 20）。 */
export const GAP_XL: number = 20;

/**
 * 侧栏列表的左右内缩（vp，inset grouped 语义）。
 *
 * iOS 的 inset grouped 列表两侧各内缩 16pt；本工程侧栏面板只有约 308vp 宽
 * （82% × 376vp），照搬 16 会让行内容只剩 276vp，等比例收窄到 8vp。
 */
export const LIST_INSET: number = 8;

/**
 * 分隔线距行内容左边缘的内缩（vp）。
 *
 * iOS 的分隔线**不从屏幕边缘起画**，而是从文字起始处起画（inset separator），
 * 这是"列表看起来整不整齐"的关键细节：齐边的线会把图标列切成两半。
 */
export const SEP_INSET: number = 16;

// ── 三、圆角 ──────────────────────────────────────────────────────────
//
// 只留三档，且每档有明确用途。不要出现第四种（历史上出现过 10/12/14/22 四种并存）。

/** 小控件圆角（vp）：搜索框、会话行、提示气泡。= iOS inset grouped 卡片圆角 10pt。 */
export const RADIUS_SM: number = 10;
/** 中号容器圆角（vp）：卡片、分组卡、错误页卡片。iOS 中号容器常用 12pt。 */
export const RADIUS_MD: number = 12;
/**
 * 大圆角（vp）：上传半模态**三宫格**的动作方块。
 *
 * 依据（R19 一手素材：iOS 官方截图 `tmp/r19-audit/ios-shots/crop-attach.png`，
 * 见 `tmp/r19-audit/ios-reference.md` §4.1）：iOS 附件面板的方块圆角约 **16pt**。
 * 现有三档都够不着：`RADIUS_SM`(10) 是列表行/搜索框档、`RADIUS_MD`(12) 是卡片档、
 * `PANEL_RADIUS`(22) 是抽屉面板档（逐像素定标，不可挪用）⇒ 按"新语义就新增一档"的纪律加它，
 * **不要**就地写 16，也不要拿 22 硬套（那会让方块看起来像小面板）。
 */
export const RADIUS_LG: number = 16;
/** 面板右侧圆角半径（vp）。左侧贴屏边，故左两角保持直角。第十轮逐像素定标，勿单独改。 */
export const PANEL_RADIUS: number = 22;

// ── 四、动效 ──────────────────────────────────────────────────────────
//
// 时长分三档 + 一条标准曲线。判断用哪档的口径：
//   · 只反馈"我按到了"（按压、勾选、选中）→ FAST；
//   · 元素出现/消失/位移（淡入、气泡、列表项进出）→ NORMAL（= iOS 默认 0.25s）；
//   · 启动页这类"有编排节奏"的 → SPLASH（各段自行按节奏排布）。
//
// 这里原本还有一个 MOTION_SLOW(350)（"面板/整屏级转场"）。**已删除**：面板开合由官方
// SideBarContainer 自己的动画负责（UI-DESIGN §4 明文禁止在面板上再套 transform 动画），
// 于是它成了零消费者却看着像配置项的令牌 —— 正是本文件"宁可没有也不要假旋钮"的那条纪律。

/** 快（ms）：按压反馈、勾选、选中态切换。iOS 交互反馈约 0.15s。 */
export const MOTION_FAST: number = 150;
/** 标准（ms）：淡入淡出、元素进出、气泡显隐。= iOS 默认转场 0.25s。 */
export const MOTION_NORMAL: number = 250;
/** 启动页编排（ms）：鲸鱼入场的放大+淡入时长（第十一轮实测，配合逐字跳出的节奏）。 */
export const MOTION_SPLASH: number = 420;

/**
 * 标准缓动曲线。
 *
 * `Curve.FastOutSlowIn` 即"快出慢入"（≈ CSS ease-in-out / iOS 的标准缓动），
 * 是本工程动效的统一曲线。**不要用 `Curve.Linear`**：线性运动在 UI 里显得机械，
 * 是"动效廉价感"的主要来源。
 */
export const CURVE_STD: Curve = Curve.FastOutSlowIn;

/**
 * 按下的不透明度（iOS 语义的按压反馈用"变暗/变淡"，**不用缩放**）。
 *
 * 这里原本还有一个 PRESS_SCALE(0.98)（"卡片级按下的轻微缩放"）。**已删除**：全工程零消费者，
 * 而 iOS 的列表/卡片按压语义本来就是变底色（UI-DESIGN §3.1），缩放锚点还会让长标题行视觉跳动。
 * 留一个用不上的"缩放旋钮"只会让后来者以为改用它就统一了按压观感。
 */
export const PRESS_OPACITY: number = 0.6;

// ── 五、字号 ──────────────────────────────────────────────────────────
//
// 删掉 14.5/13.5/12.5 这类半像素档（第十五轮的既定结论）：半像素字号在不同字号缩放
// 档位下会四舍五入到不同结果，同一行文字出现两种视觉大小。

/** 正文/列表字号（vp）。 */
export const FS_BODY: number = 14;
/** 次要文案字号（vp）：面板里的搜索框、账号名、空态提示。 */
export const FS_LABEL: number = 13;
/** 小号文案字号（vp）：分组标题、轻提示。 */
export const FS_CAPTION: number = 12;
/** 页脚/计数文案字号（vp）。 */
export const FS_FOOTNOTE: number = 11;
/** 顶栏标题字号（vp）。 */
export const FS_TITLE: number = 16;
/** 面板品牌名字号（vp）。 */
export const FS_BRAND: number = 19;
/** 图标字号（vp，SymbolGlyph）：**裸图标**按钮（无浅底圆）用这一档。 */
export const FS_ICON: number = 21;
/**
 * 图标字号（vp，SymbolGlyph）：**带浅底圆**的图标按钮用这一档。
 * 依据同上（iOS 顶栏素材）：iOS 圆内图标约 18–20pt，与本工程 `ICON_BTN_VISUAL`(40) 的比例约 0.45。
 * 裸图标与圆内图标分两档而不是共用一个值：21 的字形放进 40 的圆里会顶到圆边（iOS 留白明显更大）。
 */
export const FS_ICON_BTN: number = 18;
/** 启动页标语字号（vp）。 */
export const FS_SPLASH: number = 20;

// ── 六、描边、阴影与模糊 ──────────────────────────────────────────────

/**
 * 发丝线宽度（vp）。
 *
 * 0.5vp 在 density 560 的机器上 = 1.75px，四舍五入后仍可见（本工程实测）。
 * 若换到低密度设备出现"线不见了"，优先改这里而不是每处就地写 1——保持同一语义一个值。
 */
export const HAIRLINE: number = 0.5;

/** 卡片阴影半径（vp）。 */
export const SHADOW_R_SM: number = 8;
/** 大卡片阴影半径（vp）。 */
export const SHADOW_R_MD: number = 16;
/** 卡片阴影的下偏移（vp）：iOS 阴影是"向下"的，偏移为 0 会显得像描边。 */
export const SHADOW_DY_SM: number = 2;
// 这里原本还有一个 SHADOW_DY_MD(4)（"大卡片阴影下偏移"）。**已删除**：零消费者 ——
// 唯一用大阴影半径的地方（侧栏面板）走的是"对称淡晕"（offsetX/offsetY 都是 0，真机逐像素定标，
// 横向或纵向偏移都会在圆角处露出硬边）。留着一个与真实用法相反的偏移量比没有更糟。

/**
 * 面板背景模糊半径（vp）。与圆角同尺度，避免模糊溢出边界采样到面板外的清晰内容。
 */
export const PANEL_BLUR: number = 24;

/**
 * 顶栏背景模糊半径（vp）。
 *
 * ⚠️ **本值经第十六轮真机第四批两次下调（24 → 12 → 6）**，均因用户反馈"模糊过重 /
 * 顶栏下内容不可见"，两条历史结论都要更新：
 *
 * 1) **为什么不能是 24**：`backgroundEffect` 的高斯模糊**会在组件边界外继续采样** ——
 *    真机实证（`内部验证记录`）：顶栏下沿**之外**约 10vp 处的
 *    正文行仍是重糊的（`b24-2.jpeg` 里顶栏下方第一行"金融集团，以及搜索…"上半部分糊成一团）。
 *    即模糊实际生效的高度 = 顶栏高度 + 外溢量，再叠上 `TOPBAR_FADE_H` 的渐隐带，
 *    顶栏下方近 40px 的内容全部看不清 —— 正是"顶栏下内容不可见"。**半径越大外溢越多**。
 *
 * 2) **为什么最终取 6 而不是 12**：12 已消除外溢（`back2.jpeg` 顶栏下沿第一行立即可读），
 *    但**穿过顶栏的内容本身仍被糊成一团**，与用户指定的对标物（华为系统设置沉浸顶栏）
 *    差距明显 —— 官方观感是"**字形轮廓仍清晰可辨**，只是被柔化 + 蒙了一层薄色"，
 *    而不是"糊成色块"。6vp 时穿过顶栏的内容仍是可辨认的糊影，才是对标物那一档。
 *    **判据是对标观感，不是"有没有外溢"** —— 别只盯着外溢量就以为调够了。
 *
 * 3) **不再要求与 `PANEL_BLUR` 同值**：旧注释担心"两者交叠处出现糊↔更糊的横向分界"，
 *    该担心**不成立** —— 侧栏面板在自己的层上做模糊、顶栏的模糊只作用于顶栏自身矩形，
 *    两者各自独立，不存在同一条接缝上两种糊度的问题。真机已复核：侧栏展开态顶栏下沿
 *    无新增分界（`real-device-r4/side.jpeg`）。
 */
export const TOP_BAR_BLUR: number = 6;

/**
 * 模糊层的**饱和度与亮度**（`backgroundEffect` 的两个强度旋钮）。
 * **顶栏与面板必须同值**：两者各自对背后内容做同一档高斯模糊，一处 1.0、另一处别的值
 * 就会出现"顶栏比面板更浓"。收敛前同一语义在工程里有三种写法（`1.0` / `DARK_BRIGHTNESS` /
 * `isDark ? 1.0 : 1.0`）。亮度取 1.0 的依据（真机逐像素）：玻璃色 alpha 设成 0 时模糊区与
 * 页面底色**完全相等** ⇒ 模糊本身中性，色差 100% 来自玻璃色叠加，深浅色差异全交给双值资源。
 */
export const BLUR_SATURATION: number = 1.0;
export const BLUR_BRIGHTNESS: number = 1.0;

/**
 * 深色模式下模糊层的亮度补偿。
 * ⚠️ 只作为 `BLUR_BRIGHTNESS` 的**别名**保留（RULES §1.5：已导出的常量名不得删除）。
 * **当前全工程零消费者**（R19 grep 证据：`.ets` 里只剩注释命中 —— 第十八轮收敛成别名后，
 * W3 已从 `pages/Index.ets` 撤掉传参，W2 也已从 `view/TopBar.ets` 删掉那个恒等的三元）。
 * 之所以不删：它是**已导出**的常量名，删除会打断"外部按名引用"的兼容面；
 * 之所以不要再引用：实测"模糊本身中性"，它没有独立数值 —— **新代码一律用 `BLUR_BRIGHTNESS`**。
 */
export const DARK_BRIGHTNESS: number = BLUR_BRIGHTNESS;

/**
 * 会话列表行的**官方转场**（`TransitionEffect` 工厂，SDK `TransitionEffect.asymmetric` @since 10）。
 *
 * ## 为什么新增（第二十一轮）
 * `ForEach` 列表数据变化（新开会话、删除、重命名触发 key 重建）时，旧实现是"新行挂载即终值、
 * 被删行瞬间消失"——观感生硬。官方 `TransitionEffect` 正是给"组件插入/删除"播过渡的官方机制
 * （SDK `CommonMethod.transition(value: TransitionOptions | TransitionEffect)`，`common.d.ts:18966`）。
 *
 * ## 参数口径
 * - **进场**（appear）：淡入 0→1 + 纵向下移 8vp（`TransitionEffect.move(TransitionEdge.Bottom)` 语义 =
 *   "从屏幕下缘方向滑入"，自带 translate+opacity，一条搞定）；
 * - **退场**（disappear）：只淡出不位移——被删的行如果还往下移，会与底下补位的那行"对穿"；
 * - 时长/曲线走 `MOTION_NORMAL` / `CURVE_STD`（与全工程动效同一档）；
 * - 列表行进出场频繁（搜索过滤、下拉刷新），`MOTION_NORMAL`(250ms) 既让用户感知到"行来了"，
 *   又不阻塞连续操作；过快（FAST 150ms）几乎不可见，过慢（SPLASH 420ms）在快速过滤时会叠成拖影。
 *
 * ⚠️ `asymmetric` 的形参顺序是 (appear, disappear)，**不要写反**；
 * ⚠️ `TransitionEffect.move` 的 `TransitionEdge.BOTTOM`（**枚举值全大写**，SDK `common.d.ts:5153`）
 *    指"从**屏幕底缘**方向滑入"（插页方向），不是"向下移动"；
 * ⚠️ 该转场只作用于**组件插入/删除**（ForEach key 变化触发的重建），不影响行内 stateStyles 按压、
 *    选中底色过渡（那两条仍走 `.animation()`，与 `.transition()` 互不干扰）。
 */
export function listItemTransition(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.move(TransitionEdge.BOTTOM)
      .animation({ duration: MOTION_NORMAL, curve: CURVE_STD }),
    TransitionEffect.opacity(0)
      .animation({ duration: MOTION_NORMAL, curve: CURVE_STD })
  );
}

// ── 六·五、官方沉浸材质（沉浸光感）────────────────────────────────────

/**
 * 官方沉浸材质的**总开关**（编译期常量）。
 *
 * `true`  ⇒ 顶栏与顶栏内按钮走官方材质分支（`.systemMaterial(...)`）；
 * `false` ⇒ 全部退回本轮之前的自绘口径（顶栏 `backgroundEffect` / 按钮底色 + stateStyles）。
 *
 * 为什么留这个常量（与 aa-hm 的 TOPBAR_OFFICIAL_MATERIAL 同一手法）：
 * aa-hm 在真机上测到节点级材质会画出一条**带硬边的圆角带**（R77：y=167 顶缘高光 255、
 * y=356 底缘高光 254，用户原话「标题栏和时间栏有明显分界」）。本工程同款风险必须可一行回退 ——
 * 回退时不需要理解材质接口。
 */
export const OFFICIAL_MATERIAL: boolean = true;

/**
 * **官方沉浸材质（沉浸光感）的唯一构造入口** —— 顶栏本体与栏内按钮共用同一档参数。
 *
 * ⚠️ 形参必须是**带透明度**的既有令牌：SDK 原文（`@ohos.arkui.uiMaterial.d.ts:325-327`）——
 *    The pure color must have a certain transparency value and cannot be completely opaque.
 *    Otherwise, the material filter effect will be completely blocked.
 *    ⇒ 不能传完全不透明的色（如 `icon_btn_bg` #F2F2F3），那样材质滤镜会被完全挡死。
 *
 * ## 为什么栏本体与按钮用**同一个函数**（而不是各写一份参数）
 * 同一栏内的按钮与栏本体必须同一档，否则会出现「按钮比栏更浓」的观感分界 ——
 * 本工程在模糊饱和度上踩过同款坑（见 `BLUR_SATURATION` 的注释）。差别只在传入的色令牌
 * （栏 = `shell_topbar_glass`，按钮 = `icon_btn_material`）。
 *
 * ## 六个字段的口径（全部写死，调用方不得各调一档）
 *   · `style: THIN` —— 强透明档，与 aa-hm 的 `officialBarMaterial()` 同档；
 *   · `colorInvert: false` —— 不做互补色自适配，深浅色差异仍由双值资源承担；
 *   · `applyShadow: true` —— 投影交给材质（调用点不再画自绘 `.shadow()`）；
 *   · `interactive: true` —— 按压形变反馈交给材质；
 *   · `lightEffect: { color: Color.White }` —— **沉浸光感**的交互反馈光；
 *     SDK 里 `LightEffectOptions` 只有 `color` 一个字段，没有第二个旋钮。
 *
 * ⚠️ 依据 SDK `@ohos.arkui.uiMaterial.d.ts:19-24`：材质会**接管** `backgroundColor` /
 *    `borderColor` / `borderWidth` / `shadow`，官方**不建议与它们同时使用** ⇒
 *    官方分支的调用点必须把这几层自绘样式**整组删掉**（本工程口径 = 零自绘层）。
 * ⚠️ 只在 `Navigation`/`NavDestination` 标题栏里挂载才生效（生效范围，见本文件 §零）。
 */
export function officialImmersiveMaterial(color: ResourceColor): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: color,
    colorInvert: false,
    applyShadow: true,
    interactive: true,
    lightEffect: { color: Color.White }
  });
}

// ── 七、面板（抽屉）专用 ──────────────────────────────────────────────

/**
 * 顶栏底部**渐变过渡带**的高度（vp）。
 *
 * 为什么需要它（第十六轮真机第三批，用户反馈"功能栏与内容之间有明显分界线"）：
 * 顶栏是磨砂玻璃，它下面就是清晰的内容 —— 这两者之间**必然是"糊↔清"的不连续**。
 * 旧做法是在顶栏底边画一条 0.5vp 发丝线把它"收边"，但真机上那**恰恰就是用户看到的那条
 * 明显分界线**（0.5vp 在高密度屏上是 1.5px 的深色线，比周围的模糊过渡醒目得多）。
 *
 * 正解是**让模糊自己渐隐**：在顶栏下方接一条同宽、高度为本值的过渡带，
 * 背景用"玻璃色 → 全透明"的纵向渐变，于是内容从下方滚上来时是**逐级变糊**的，
 * 而不是在某一条线上突然变糊 —— 即"**由下自上逐渐模糊**"。
 * 取 16vp（`GAP_LG` 刻度）：约等于一行正文的高度，足够长到看不出台阶、又不会吃掉太多可视内容。
 */
export const TOPBAR_FADE_H: number = 16;

/** 渐隐过渡带的渐变方向（`linearGradient` 的 `angle`）：180 = 自上而下。 */
export const FADE_ANGLE_DOWN: number = 180;
/** 过渡带**顶端**的端点位置：此处是玻璃色本体（与顶栏同色，接缝因此看不见）。 */
export const FADE_STOP_GLASS: number = 0.0;
/** 过渡带**底端**的端点位置：此处是 `shell_topbar_fade`（同 RGB、alpha=0）。 */
export const FADE_STOP_CLEAR: number = 1.0;

/** 面板与状态栏之间额外留的呼吸间距（vp）。**上边必须留 0**：上沿要与顶栏下沿严丝合缝。 */
export const EDGE_GAP: number = 0;

// 这里原本还有一个 `DRAWER_RIGHT_GAP = 6`（"面板右侧留缝，投影靠它才有落点"）。
// 第十六轮**删除**：它已经没有任何消费者 —— 面板是抽屉的全宽（82% 屏宽），
// 圆角与投影直接贴在自己的右缘，不存在"容器减掉一段"的实现。
// 一个零消费者、却看起来像配置项的令牌比没有更糟：后来者会以为改了它面板就会变，
// 而实际上改了毫无效果（同 §3.0-74 那类"以为在配 A、其实配的是 B"的静默失效）。
// 删除时同步订正了 `view/SidePane.ets` 里指向它的那段注释。

// ── 八、共享组件配方（全局构建函数）────────────────────────────────────
//
// 为什么把"配方"而不是"数值"也收进令牌：顶栏的图标按钮与侧栏的图标按钮原本各自
// 手写了一份**一模一样**的 15 行配方（圆 44 / TEXTUAL / 透明底 / 无障碍三件套），
// 两份代码只靠注释互相"约定同源"。改一处忘一处就会出现"两个按钮差 2vp"这类问题
// ——这正是本轮要消灭的"同类控件两套写法"。
//
// 用全局 `@Builder`（而非抽象成 `@Component`）：它不产生额外的组件节点与状态，
// 只做**纯属性配方**，正是这个场景需要的语义；官方文档明确"全局的自定义构建函数
// 可以被整个应用获取"。

/**
 * 纯图标圆形按钮（外壳统一配方）。
 *
 * @param icon   必须是 `$r('sys.symbol.*')` 矢量符号（符号名要查 SDK `id_defined.json` 实证）
 * @param label  无障碍名字：纯图标按钮没有文字，读屏用户听到的必须是**动作名**而不是"按钮"
 * @param action 点击回调
 * @param raised 是否画"圆形浅底"（iOS 顶栏形态）。**没有默认值**：默认值会让调用点看不出自己选了哪一档，
 *               而这两档的观感差别很大（裸图标 vs 浅底圆）。顶栏传 `true`，侧栏头部传 `false`
 *               （侧栏头部是三个相邻按钮、且**无 iOS 抽屉参考素材**，三个浅底圆贴在一起会连成一块，
 *                见 R19 W4 的 ios-reference.md §6「侧栏形态 C 级：未找到可靠来源」）。
 *
 * 三件套缺一不可：`accessibilityText` 是读屏取名字的正式属性；
 * `accessibilityDescription` 是本工程 `uitest dumpLayout` 里**唯一读得出来的字段**
 * （实测：dump 暴露 description、不暴露 text），少了它自动化无法断言"到底有没有名字"；
 * `accessibilityLevel('yes')` 保证能被读屏聚焦（默认 `auto` 时纯图标按钮有被跳过的风险）。
 */
/**
 * 图标按钮的热区（喂给 `.responseRegion()`）。
 *
 * 可见圆比可点区小一档时（`raised`：可见 `ICON_BTN_VISUAL`(40) / 可点 `ICON_BTN`(44)），
 * 把热区**四周各外扩 (ICON_BTN − ICON_BTN_VISUAL)/2 = 2vp**，补回 iOS HIG 的 44×44 最小触控目标；
 * `raised=false` 时按钮本身就是 44，热区与它重合（等价于不设）。
 *
 * 为什么写成带显式返回类型的函数、而不是就地写三元：`responseRegion` 的形参是
 * `Rectangle | Rectangle[]`（联合类型），ArkTS 对"联合类型上下文里的对象字面量"很挑；
 * 显式 `Rectangle` 返回类型能让两个字面量都有确定的目标类型。
 */
export function ShellIconHotRegion(raised: boolean): Rectangle {
  let d: number = (ICON_BTN - ICON_BTN_VISUAL) / 2;
  if (raised) {
    return { x: -d, y: -d, width: ICON_BTN, height: ICON_BTN };
  }
  return { x: 0, y: 0, width: ICON_BTN, height: ICON_BTN };
}

/**
 * 图标按钮（全工程唯一配方）—— 按第 5 个参数 `official` 分派到两个**互斥**分支。
 *
 * · `official = false`（缺省）：**自绘档** `ShellIconButtonDrawn` —— 可见圆 = Button 自身底色
 *   + 显式 `stateStyles` 按压。既有调用点（侧栏头部 3 处）走这一档，行为与改前逐字相同。
 * · `official = true`：**官方沉浸光感档** `ShellIconButtonOfficial` —— 由
 *   `.systemMaterial(officialImmersiveMaterial(...))` 负责画底与按压/光感反馈（零自绘层）。
 *
 * ⚠️ **official = true 只许挂在 `Navigation`/`NavDestination` 标题栏里**（生效范围，
 *    见本文件 §零 / 内部踩坑表 §3.0-245）。挂在页面正文里是**静默无效**，而且因为
 *    该档不画任何自绘层，会变成「看不见的透明空壳」—— 比不挂更糟。
 * ⚠️ 两个分支的**几何逐字相同**（`ICON_BTN_VISUAL` / `FS_ICON_BTN` / 热区 `ShellIconHotRegion`），
 *    这样「自绘 ↔ 官方」的 A/B 只差「哪一层在画底」，逐像素差值才可归因。
 */
@Builder
export function ShellIconButton(icon: Resource, label: string, action: () => void, raised: boolean,
  official: boolean = false) {
  if (official && OFFICIAL_MATERIAL) {
    ShellIconButtonOfficial(icon, label, action, raised)
  } else {
    ShellIconButtonDrawn(icon, label, action, raised)
  }
}

/**
 * 官方沉浸光感档：**零自绘层**。
 *
 * 为什么不写 `backgroundColor` / `stateStyles` / `.shadow(` / 渐变 / 边框：
 * SDK 原文（`@ohos.arkui.uiMaterial.d.ts:19-24`）——材质会**接管** `backgroundColor` /
 * `borderColor` / `borderWidth` / `shadow`，官方**不建议与它们同时使用**。
 * 按压反馈因此改由材质的 `interactive: true`（形变）+ `lightEffect`（光感）供给，
 * 而不是 `stateStyles` 里的换底色。
 * ⇒ 这也是为什么两个分支必须**互斥**（写成同一条链上的三元会同时留下自绘层）。
 */
@Builder
function ShellIconButtonOfficial(icon: Resource, label: string, action: () => void, raised: boolean) {
  Button({ type: ButtonType.Circle, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL }) {
    SymbolGlyph(icon)
      .fontSize(raised ? FS_ICON_BTN : FS_ICON)
      .fontColor([$r('app.color.text_primary')])
  }
  .width(raised ? ICON_BTN_VISUAL : ICON_BTN)
  .height(raised ? ICON_BTN_VISUAL : ICON_BTN)
  // `materialColor` 用带 alpha 的 `icon_btn_material`：完全不透明的色会挡死材质滤镜。
  .systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))
  .responseRegion(ShellIconHotRegion(raised))
  .accessibilityText(label)
  .accessibilityDescription(label)
  .accessibilityLevel('yes')
  .onClick(action)
}

/**
 * 自绘档（本轮之前的口径）—— 保留为**回退路线**：把 `OFFICIAL_MATERIAL` 置 false，
 * 或把调用点的 `official` 传成 false/省略，即回到这一档。
 */
@Builder
function ShellIconButtonDrawn(icon: Resource, label: string, action: () => void, raised: boolean) {
  Button({ type: ButtonType.Circle, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL }) {
    SymbolGlyph(icon)
      .fontSize(raised ? FS_ICON_BTN : FS_ICON)
      .fontColor([$r('app.color.text_primary')])
  }
  // 可见圆 = Button 自己的尺寸与底色（**不再用 Stack 套一个子节点**）：
  // 这样"按下变暗"能作用在圆本身上 —— iOS 的按压语义就是**整个圆变暗**（不是缩放、也不是只有图标变淡）。
  // 若把圆画成子节点，按钮的按压态就落不到它身上（子节点没有自己的 pressed 状态）。
  .width(raised ? ICON_BTN_VISUAL : ICON_BTN)
  .height(raised ? ICON_BTN_VISUAL : ICON_BTN)
  // `stateEffect: false` + 显式 `stateStyles` —— **不要顺手把它改回 true**。
  // 依据是 SDK 原文（`D:\DevEco Studio\sdk\default\openharmony\ets\component\button.d.ts:320-324`，
  // `stateEffect` 的 NOTE）：
  //   "When the pressed state effect is enabled and a custom pressed state style is configured,
  //    the resulting color displayed after pressing is a **composite blend** of the original
  //    background color and the newly defined pressed state color."
  // 即：开着 stateEffect 时，按下看到的是"原底色 ⊕ 按下色"的**混合**结果 —— 我们**拿不到**精确的
  // `icon_btn_bg_pressed`，深浅两态的观感也就不再可控。关掉它 + 显式 `stateStyles` 才是确定写法。
  // 非 raised（侧栏头部裸图标）的按下色复用列表行那套 `shell_item_active_bg`：**这是有意的统一** ——
  // 顶栏按钮有"可见圆 + 按下变底色"，侧栏头部的图标按钮保持同一套按压语义，才不出现
  // "同类控件两套反馈"（本工程一直在消灭的东西，同 §RULES "同类控件只留一套配方"）。
  .stateStyles({
    normal: {
      .backgroundColor(raised ? $r('app.color.icon_btn_bg') : Color.Transparent)
    },
    pressed: {
      .backgroundColor(raised ? $r('app.color.icon_btn_bg_pressed') : $r('app.color.shell_item_active_bg'))
    }
  })
  // **必须写在 stateStyles 之后**：`.animation()` 只作用于它前面已声明的属性。
  // 于是"按下变暗"是 150ms 过渡而不是硬切（`specs/UI-DESIGN.md` §4：只回答"我按到了吗"）。
  .animation({ duration: MOTION_FAST, curve: CURVE_STD })
  // 热区补到 44（可见圆仍是 40）——见 ShellIconHotRegion。
  .responseRegion(ShellIconHotRegion(raised))
  .accessibilityText(label)
  .accessibilityDescription(label)
  .accessibilityLevel('yes')
  .onClick(action)
}

// ── 九、设置页底部功能栏（第二十一轮，参考 aa-hm 的底部功能栏形态）─────────
//
// 用户需求（原话）：「参考 aa-hm 的底部功能栏，重新写设置页的功能栏」。
// 形态参考 aa-hm 的 ui/BottomNav.ets 的**自绘悬浮胶囊**：全圆角胶囊 +
// backgroundEffect 磨砂 + 同源渐变光层 + 亮边；四项「图标上、文字下」，选中项变色。
// aa-hm 那条路径有真机 Δ 判据（R63/F1：胶囊内 vs 带外 Δ+16.0），故这里按同一套结构复刻；
// 色值换成**本工程自己的令牌色系**（resources/*/element/color.json 的 shell_tabbar_*），
// 不照搬 aa-hm 的 glassNavSurface（那是它的色系）。
//
// ⚠️ 为什么不用官方 Tabs 底栏 + FloatingTabBarStyle.systemMaterial（aa-hm 的路线 A）：
//  ① 本工程的设置页**内容在网页里**（chat.deepseek.com 的系统设置弹层），页签语义由原生承载后
//     要反过来驱动网页切页签 —— 官方 Tabs 的 TabContent 是原生页面容器，挂不上网页内容；
//  ② aa-hm 自己的真机记录写着「官方材质在本机型本位置 Δ+0.0、barFloatingStyle 未生效」，
//     它最终交付的也正是**自绘胶囊**这条路径。
//  ⇒ 两工程结论一致：这里直接走自绘悬浮胶囊。

/** 底栏胶囊高度（vp）。取 54：与 aa-hm 的 BOTTOM_NAV_HEIGHT 同值（那条按参考图实测 163px/3 定）。 */
export const TABBAR_H: number = 54;

/** 底栏项图标边长（vp）。22 = aa-hm BOTTOM_NAV_ICON_SIZE；比正文图标大一档，底栏观感才不轻。 */
export const TABBAR_ICON: number = 22;

/** 底栏项文字字号（fp）。取 FS_FOOTNOTE(11)：caption 档是底栏通行做法（iOS tab bar 亦如此）。 */
export const TABBAR_LABEL_FS: number = FS_FOOTNOTE;

/** 胶囊左右留边（屏宽百分比）。12% ⇒ 本机 376vp 屏宽上胶囊约 286vp、四项每项约 71vp，
 *  放得下「通用设置」4 个汉字（TABBAR_LABEL_FS 11fp 约 44vp），且保持悬浮观感。 */
export const TABBAR_SIDE_MARGIN: string = '12%';

/** 胶囊离屏幕下缘的最小间隙（vp）。实际取 max(手势条避让, 本值)，由调用方算。 */
export const TABBAR_BOTTOM_GAP: number = GAP_MD;

/** 底栏专用磨砂半径（vp）。**与 TOP_BAR_BLUR(6)/PANEL_BLUR(24) 分开**：
 *  aa-hm 的教训是「共用的 6 对 54vp 的底栏太轻」⇒ 它单开 18。这里同值。 */
export const TABBAR_BLUR: number = 18;

/**
 * 渐变光层的**角度**（度）与**中间色标**。
 *
 * 色标 0.42 与 aa-hm 的 `GlassSpec.SHEEN_MID_STOP` 同值 ✓。
 *
 * ⚠️ **角度与 aa-hm 的 145 刻意不同，取 180（自上而下）** —— 这不是偷懒，是比例决定的：
 *    aa-hm 的底栏胶囊是**满屏宽**（835px / 438.7vp 屏 ≈ 190% 于我们的 286vp 胶囊宽度），
 *    在它那个宽高比下 145° 的光带仍斜着铺得开；而本工程胶囊是 **851×161px（宽:高 ≈ 5.3:1）**，
 *    145° 会让渐变几乎**纯水平**推进 ⇒ 竖直方向逐点同值。
 *    真机实测（2026-09-28）：145° 时胶囊内竖直扫描 y 2660~2780 **恒为 224**（零梯度），
 *    肉眼看就是一块平色 —— 这正是用户反馈「底栏没有光效」的直接原因。
 *    改 180°（自上而下）后同一扫描出现梯度：**229 → 226 → 224**（顶部被高光提亮、向下衰减）。
 * ⇒ 角度是**与元素宽高比耦合**的参数，照抄数值不等于照抄效果，换尺寸要重标。
 */
export const TABBAR_SHEEN_ANGLE: number = 180;
export const TABBAR_SHEEN_MID_STOP: number = 0.42;

/** 胶囊全圆角半径（vp）= 高/2（aa-hm 同款全圆角，参考图实测 r = 高/2）。 */
export const TABBAR_RADIUS: number = TABBAR_H / 2;

/**
 * 官方 `Tabs` 悬浮底栏的**栏宽**（vp）—— 走官方正规入口 `FloatingTabBarStyle.barWidth`
 * （SDK tabs.d.ts 的 FloatingTabBarWidth：smallBarWidth / mediumBarWidth / largeBarWidth，**不接受百分比**）。
 * 取 286 = 本机有效宽 376vp 的 76%（左右各留 12%，与 TABBAR_SIDE_MARGIN 同口径）。
 * ⚠️ 三个断点给**同一个值**：本工程是手机（md 断点）；大小断点先与手机一致，
 *    避免平板上出现「宽度突然跳成另一个数」（与 aa-hm 的做法一致）。
 */
export const TABBAR_WIDTH_VP: number = 286;

