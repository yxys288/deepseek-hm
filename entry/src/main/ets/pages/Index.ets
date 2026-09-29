// DeepSeek 鸿蒙端 · 原生外壳 + ArkWeb 聊天区。
//
// 架构（2026-09-10 第五轮重写）：
//   原生顶栏（侧栏开关/标题/新建/分享）+ 原生侧栏（官方会话列表，按需从网页 DOM 抽取）
//   + ArkWeb 只承载聊天区（保留网页登录态与云端历史）。
//
// 为什么这么改：侧边栏卡顿的根因是旧方案让网页渲染侧栏，并在侧栏开合动画期间
// 对抽屉子树做同步排版测量（见 utils/ShellScript.ets 顶部说明）。侧栏改由原生组件
// 渲染后，开合只是原生属性动画，网页侧完全不参与，卡顿从根上消失。

import { webview } from '@kit.ArkWeb';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
// 第十九轮：`pasteboard` 随 copyLink() 一起删除（顶栏按 iOS 去掉「分享会话链接」后，
// 全工程只剩它一个消费者）。
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera, cameraPicker } from '@kit.CameraKit';
// `BuildProfile` 由 hvigor 在**构建期生成**（`entry/build/<mode>/generated/profile/<target>/BuildProfile.ets`），
// 走的是模块名映射而不是相对路径。可用性已实证两条：① 本工程构建产物里该文件确实存在
// （`export const DEBUG = true`，debug 构建）；② 同一工作区的 dsh-mobile / zcode-mobile
// 两个工程都在用 `import BuildProfile from 'BuildProfile';`。
// 用途只有一个：给 ArkWeb 调试通道做构建态门控（见 aboutToAppear 的说明，audit B-9）。
import BuildProfile from 'BuildProfile';
import { DEEPSEEK_HOME, MOBILE_ADAPTER_JS } from '../utils/DeepSeekConfig';
import { SHELL_JS } from '../utils/ShellScript';
import { ChatSessionItem, SideRow, ShellMessage } from '../model/ShellTypes';
import { SidePane } from '../view/SidePane';
import { NAV_TITLE_SLOT_VP, TopBar, topBarTitleOptions } from '../view/TopBar';
// 设置页底部功能栏（第二十一轮最终档）：**官方 `Tabs` 底部 TabBar + 官方沉浸材质**——
// 这是官方文档（pitfalls 245 号）认可的四类生效位置里、本工程底部唯一可用的一条，
// 也是 aa-hm 的「路线 A」。为什么不能走工具条/自绘，记在该文件头。
import { SETTINGS_TABS, SettingsTabBar } from '../view/SettingsTabBar';
import {
  BTN_H_MD, CURVE_STD, FS_BODY, FS_CAPTION, FS_LABEL, FS_SPLASH, FS_TITLE, GAP_LG, GAP_MD,
  GAP_SM, GAP_XL, GAP_XS, HAIRLINE, MOTION_FAST, MOTION_NORMAL, MOTION_SPLASH, PRESS_OPACITY,
  OFFICIAL_MATERIAL,
  RADIUS_LG, RADIUS_MD, RADIUS_SM, ROW_H, SEP_INSET, SHADOW_DY_SM, SHADOW_R_SM,
  TABBAR_BOTTOM_GAP, TILE_H, TILE_ICON
} from '../common/ShellUi';

const WEB_DOMAIN: number = 0x0000;
const WEB_TAG: string = 'DeepSeekWeb';
const SHELL_TAG: string = 'DeepSeekShell';
// TOP_BAR_H / 图标按钮尺寸 / 字号 / 间距 / 动效 / 阴影等全部共享 UI 常量统一定义在
// common/ShellUi.ets（设计令牌表，见 specs/UI-DESIGN.md）。
// 顶栏的模糊半径（`TOP_BAR_BLUR`）与深色亮度补偿（`DARK_BRIGHTNESS`）原本是本文件的本地常量，
// 第十六轮搬进令牌表 —— 它必须与侧栏面板的 `PANEL_BLUR` 同值，否则顶栏与面板的糊化程度不一致，
// 两者交叠处（面板上沿贴着顶栏下沿）会出现一条"糊↔更糊"的横向分界。**一个语义一个值**。
// 这两个常量现在由 `view/TopBar.ets` 消费，本文件不再直接引用。
/**
 * 启动页**最长**覆盖时长（ms）。
 *
 * 由 2200ms 硬盖子改成"事件驱动 + 超时兜底"：旧实现无论网页多快就绪都要硬等 2.2s，
 * 首屏可交互时间被白白推后约 1s（audit §3 启动速度）。新语义是
 * 「首个 `sessions` 桥消息到达（说明官方外壳已抽得出会话列表） 或 本超时 二者取先」，
 * 至多再等 1200ms。超时是**兜底**：网页一直不回话时也不能把用户永远关在启动页里。
 */
const SPLASH_MAX_MS: number = 1200;
/**
 * 启动页**最短**展示时长（ms）。
 *
 * 不能一收到桥消息就摘罩：那会让逐字跳出的标语只播一半就"啪"地消失。
 * 800ms 是本工程标语节奏（6 字 × 130ms = 780ms）之上的最近一档，保证**最早的摘罩时刻
 * 整句已经打完**，用户看到的是一个完整动画而不是闪一下。
 *
 * ⚠️ 这个下限是相对**启动页出现的时刻**（`splashShownAt`）算的，**不是**相对"网页加载完"
 * （本轮修）：逐字动画从启动页出现那一刻就开始跑，旧实现从 onPageFinished 起算 ⇒ 启动页
 * 实际停留 = 网页加载耗时 + 800ms，网页越慢白等越久。语义不变式仍是"摘罩时整句已打完"。
 */
const SPLASH_MIN_MS: number = 800;
/**
 * 站点主题偏好的 localStorage 键（与网页侧同一份数据；值是
 * `{"value":"light","__version":"0"}` 这样的包裹结构，已用 CDP 在模拟器上实证）。
 *
 * 为什么读它而不是"看网页当前是深还是浅"：站点主题是**站内偏好**，而原生外壳的配色完全由
 * 资源系统按 app 的 colorMode 解析 —— 两条线默认一致（站点默认"跟随系统"），但用户一旦在
 * 站点里手动选深/浅就分叉，表现就是"内容深、顶栏浅灰、状态栏图标还是深色"。
 * 读**偏好**而不是**观感**是这里的硬性口径：观感会被我们自己的 setColorMode 改到
 * （prefers-color-scheme 跟着 app 走），读它就形成"改 colorMode → 观感变 → 再改"的自激环；
 * 而 localStorage 里这个值只有用户会改，我们怎么设都不影响它 ⇒ 天然收敛。
 */
const SITE_THEME_KEY: string = '__appKit_@deepseek/chat_themePreference';
/**
 * 站点主题偏好的轮询间隔（ms）。
 *
 * 为什么只能是"轮询"而不是"等事件"：用户在站点「系统设置」里改主题时，原生侧**收不到任何信号**
 * —— 不改路由（不发 route）、不改系统配置（不触发 onConfigurationUpdate）、没有桥消息，
 * 而站点是当场生效的。不轮询就只能等下次整页加载，那这条修复对"当场改主题"等于无效。
 * 2s 是"改完几乎立刻可见"与"IPC 负担"的折中：一次求值**只读一个 localStorage 键**，
 * 不碰 DOM、不触发重排；三重门控把它压到近乎为零（见 syncSiteTheme）：
 * ① App 在后台整轮跳过（读 EntryAbility 落的 appForeground）；
 * ② 页面未就绪 / 停在错误页时跳过；③ 值没变则不做任何下发。
 * 它**不是**"高频定时器"：真正的重活（官方 DOM 巡检）仍在网页侧的 5s ticker 里，这里只有一次取值。
 *
 * **Lead 于 r18 裁定：2s 值守可接受，依据是「事件不可得 + 三重门控」**（RULES 里禁止的"高频定时器"
 * 指的是 16×120ms / 30×500ms 这类毫秒级循环，本值不在其列）。**后续维护者请勿按"多余定时器"删除** ——
 * 删掉它不会报错，只会让"用户在站点里当场改主题"这条路径静默失效（外壳要等下次整页加载才跟随）。
 */
const SITE_THEME_POLL_MS: number = 2000;
/** "还没读到过站点偏好"的哨兵（与任何真实 colorMode 都不相等）。 */
const SITE_THEME_UNKNOWN: number = -999;
/**
 * 「这次配置变更是我自己 setColorMode 引起的」的**自证窗口**（ms）—— C3 回归闩。
 *
 * 为什么需要一个时间窗而不是一个纯粘滞标记：目标档位与应用当前档位相同时，
 * 系统**不会**发配置更新（回调不来、闩没人消费）⇒ 粘滞闩会永久泄漏，并把下一次
 * 真实的系统主题变更误吞掉。带上时刻之后，超窗到达的一律按外部变更走老路径。
 * 1500ms 的依据：setColorMode 引发的配置回调实测在**同一拍或几十毫秒内**到达（Lead 的
 * C3 取证里 t+1s 早已稳定）；而人手操作系统主题不可能在 1.5s 内完成 —— 两者不重叠。
 */
const SITE_THEME_SELF_WINDOW_MS: number = 1500;
/**
 * 单次主框架加载的**最长容忍时长**（ms），到点仍没结束就转成可恢复的错误页。
 *
 * 为什么必须有（本轮补）：启动页只在**首次**加载时布超时兜底（见 onPageFinished 的
 * `splashHeld` 分支），此后每一次整页加载（错误页重试、深浅色 refresh）都只挂
 * `loading=true`。若那次加载既没有 onPageEnd 也没有 onErrorReceive（弱网下超时、
 * 内核卡住、被系统掐掉连接）——启动页就会**永远盖在屏幕上**：用户既看不到内容，
 * 也没有任何重试入口，只能杀进程。15s 取的是 HTTP 客户端级超时档：正常首屏（含
 * 冷启动）实测在 2s 内结束，15s 只可能是真出问题；而且它**不是单向判决** ——
 * 页面若在超时后仍然加载成功，onPageFinished 会照旧清掉错误态、把内容放出来。
 */
const PAGE_LOAD_MAX_MS: number = 15000;
/**
 * 启动页标语（逐字跳出）。
 * 拆成单字数组而不是整串 substring：只有"一个字一个 Text"才能让**新出来的那个字**
 * 单独播 opacity/scale/translate（整串 substring 是一次性换文本，没有"跳出"的过程）。
 */
const SPLASH_SLOGAN: string[] = ['探', '索', '未', '至', '之', '境'];
/** 逐字间隔（ms）：200 → 130，6 字共 780ms，正好在 `SPLASH_MIN_MS` 之内打完（见上）。 */
const SPLASH_TYPE_MS: number = 130;
/**
 * 启动页鲸鱼图标的显示边长（vp）。
 * 它是**图形尺寸**不是间距，故不走 GAP_* 刻度：`startIcon` 是 1024 画布、鲸鱼本体只占
 * 692×516（上下有留白），要放大到 168vp 才能让鲸鱼本体约 113vp 宽（第十一轮实测定标）。
 */
const SPLASH_LOGO_SIZE: number = 168;
/** 启动页标语行的固定高度（vp）：scale/translate 不参与排版，给固定行高可保证下面没有多余位移。 */
const SPLASH_LINE_H: number = 30;
/**
 * 账号菜单里**允许被原生侧驱动**的项（白名单常量，与 `utils/ShellScript.ets` 逐字一致）。
 *
 * 口径变更史（第十六轮内改过两次，写在这里免得下一个人再翻）：
 *   · 最早原生菜单镜像官方三项（系统设置 / 帮助与反馈 / 退出登录），靠**文案匹配**去驱动
 *     隐藏抽屉里的官方菜单项，隔着一次 React 异步渲染，用户实测"点击后不生效"；
 *   · 于是第十六轮把菜单收成只剩「退出登录」，回调也一律按常量处理、**不按上游 label 分支**
 *     （上游文案漂移会让旧写法静默走进"找不到该项"的死路）；
 *   · 现在用户要求**恢复「系统设置」**，但**不收回到自由入参**：改成**两个字面量的白名单** ——
 *     只有集合内的值会被下发到桥侧，其余一律回落到「退出登录」的确认流程（桥侧还有第二道闸）。
 * 为什么要常量而不是散落字面量：字面量一旦在某处漂移（多一个空格、繁体字），匹配就会静默失败。
 */
const ACCOUNT_OPTION_SETTINGS: string = '系统设置';
const ACCOUNT_LOGOUT_LABEL: string = '退出登录';

/**
 * 把 `WebviewController.runJavaScript()` 的回传值归一成**裸字符串**。
 *
 * 为什么需要：ArkWeb 回传的是**表达式结果的 JSON 文本** —— 页面侧 `return 'ok'` 拿到的字符串
 * 是 `"ok"`（带一对双引号），`return {t:'x'}` 则是对象字面量文本。直接与 'ok' 之类的字面量做
 * 全等比较**永远为假**，表现为"页面侧明明成功、原生侧却判定失败"。
 * 本轮真机实测就是这样一路重试到 `account option not found` 的（桥侧日志 `row=yes` 铁证）。
 */
function toJsText(res: string): string {
  if (res === undefined || res === null) {
    return '';
  }
  let s: string = res;
  if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') {
    return s.substring(1, s.length - 1);
  }
  return s;
}
/**
 * 账号菜单项重试链的轮询间隔（ms）。
 * 原生对话框与官方菜单之间隔着一次 React 挂载（实测 100ms 量级），
 * 140ms 是"下一次查时它基本已经出来"与"总共不超过 1.2s"的折中：8 次 × 140ms ≈ 1.1s。
 */
const ACCOUNT_RETRY_MS: number = 140;
/** 首页「已是新对话」提示的停留时长（ms）。 */
const NEW_CHAT_TIP_MS: number = 1600;
/**
 * 避让区变化推送到网页侧的去抖间隔（ms）。
 * 输入法弹出/收起会连发数次 avoidAreaChange，逐次下发轻量通道也是浪费；
 * 100ms 在用户感知阈值（~150ms）之内，看不出延迟。
 */
const INSET_PUSH_DEBOUNCE_MS: number = 100;
/** 避让值"同值不推"的容差（vp）：小于它视作没变，避免系统框复报同一个值时白推一次。 */
const INSET_EPSILON: number = 0.5;

/**
 * 渲染进程退出原因 → 用户能看懂的一句话。
 * 枚举值核对自 SDK `component/web.d.ts` 的 `RenderExitReason`（不凭印象写）。
 */
function renderExitReasonText(reason: number): string {
  if (reason === 0) {
    return '进程异常终止';
  }
  if (reason === 1) {
    return '被系统回收';
  }
  if (reason === 2) {
    return '进程崩溃';
  }
  if (reason === 3) {
    return '内存不足';
  }
  return '未知原因';
}

/**
 * 主框架导航白名单的**判据归一化**。
 *
 * 早先是"原样字符串比较 origin"，于是 `https://Chat.DeepSeek.com/`（大写主机名）、
 * `https://chat.deepseek.com:443/`（显式默认端口）这两种**同一来源**的写法会被拦掉。
 * 改为按 **小写 scheme://host + 去掉默认端口** 比较（URL 解析已做过归一化，
 * 这里再兜一层大小写与默认端口）。
 */
function normalizedOriginOf(target: string): string {
  let schemeEnd: number = target.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  let start: number = schemeEnd + 3;
  let pathStart: number = target.indexOf('/', start);
  let origin: string = pathStart < 0 ? target : target.substring(0, pathStart);
  origin = origin.toLowerCase();
  if (origin.endsWith(':443')) {
    origin = origin.substring(0, origin.length - 4);
  } else if (origin.endsWith(':80')) {
    origin = origin.substring(0, origin.length - 3);
  }
  return origin;
}

/**
 * 主框架导航是否放行。
 *
 * 为什么必须做白名单：Web 组件承载的是**带登录态**的 chat.deepseek.com，
 * 主框架一旦被导航到站外，用户的会话内容与输入都在那个页面手里（同源策略之外的钓鱼面）。
 * `about:blank` / `data:` / `blob:` 放行：它们是官方前端自己用的空文档与本地 URL
 * （下载、附件预览），不带站外来源。
 */
function isAllowedNavTarget(target: string): boolean {
  if (target === 'about:blank' || target.startsWith('data:') || target.startsWith('blob:')) {
    return true;
  }
  let origin: string = normalizedOriginOf(target);
  return origin === 'https://chat.deepseek.com' ||
    origin === 'https://www.deepseek.com' ||
    origin === 'https://deepseek.com';
}

/**
 * 剥掉注入脚本的**整行注释**（保守版压缩）。
 *
 * 只处理"trim 之后以 // 开头"的行：这两个脚本里 99% 的注释都是整行的文档注释，
 * 而行尾注释与字符串内容一律不动 —— 后者是高风险区（模板字符串里可能有 `//`、
 * 正则里可能有 `\\`），误伤一个字符就会让整条注入链路静默失效。
 * 不合法/多行块注释一律保留：它们数量少，且剥离要处理跨行状态，性价比低。
 */
/**
 * 两份渲染行是否**逐字段相同**（`applySessions` 用它决定要不要换 `@State rows` 的引用）。
 *
 * 为什么要逐字段比而不是比长度：会话标题重命名、"当前会话"标记回填都是"长度不变、内容变了"，
 * 只看长度会把真变化当成没变（§3.0-138 的同族缺陷）。
 */
function rowsEqual(a: SideRow[], b: SideRow[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    let x: SideRow = a[i];
    let y: SideRow = b[i];
    if (x.kind !== y.kind || x.key !== y.key || x.text !== y.text ||
      x.id !== y.id || x.active !== y.active) {
      return false;
    }
  }
  return true;
}

function stripLineComments(js: string): string {
  if (js.indexOf('//') < 0) {
    return js;
  }
  let lines: string[] = js.split('\n');
  let out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    let line: string = lines[i];
    let trimmed: string = line.trim();
    if (trimmed.startsWith('//')) {
      continue;
    }
    out.push(line);
  }
  return out.join('\n');
}

// —— 「选择上传」原生面板（官方半模态 bindSheet）——
/**
 * 「面板收起」与「拉起系统选择器」之间的间隔（ms）。
 * 系统选择器（图库/相机/文件）是独立 UIExtension 窗口，会在拉起瞬间盖住整个应用 ——
 * 不隔这一段，用户看到的官方半模态收起动效会被系统窗口整段切掉（点下去像没反应，
 * 然后整屏突然换掉）。200ms ≈ 半模态收起动效的可见段。
 */
const PICK_LAUNCH_DELAY_MS: number = 200;
/** 沙箱上传副本的前缀（下次选择前按前缀清理上一次的副本）。 */
const UPLOAD_CACHE_PREFIX: string = 'dsh-upload-';
/**
 * 错误页图标的字号（vp）。
 * 图形尺寸而非间距 / 字号档位，故不走令牌刻度：56 是"给足视觉重量但不把下方文案挤到边缘"的实测取值。
 */
const ERROR_ICON_SIZE: number = 56;

/** javaScriptProxy 注入对象：网页侧 window.dshBridge.post(json)。 */
class ShellBridge {
  private handler: (json: string) => void = (json: string) => {};

  setHandler(next: (json: string) => void): void {
    this.handler = next;
  }

  /** 由网页 JS 调用（methodList 内声明），只做解析派发，绝不在这里做重活。 */
  post(json: string): void {
    if (typeof json === 'string' && json.length > 0) {
      this.handler(json);
    }
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ShellBridge = new ShellBridge();
  private action: string = '';
  private splashTimer: number = -1;
  private splashHeld: boolean = false;
  /**
   * 启动页的"事件驱动摘罩"状态（第十六轮）。
   * `splashArmed` = 首个 `sessions` 桥消息**还没被用来提前摘罩**（只消费一次）；
   * `splashShownAt` 用来把摘罩时刻夹在 `SPLASH_MIN_MS`~`SPLASH_MAX_MS` 之间
   * （见 finishSplash / requestSplashRelease）。
   *
   * ⚠️ **它记的是"启动页出现的时刻"（aboutToAppear），不是"网页加载完的时刻"**（本轮修）：
   * `SPLASH_MIN_MS`(800) 存在的唯一理由是"逐字标语（6 × 130 = 780ms）已经打完"，而逐字动画
   * 是从**启动页出现**那一刻开始跑的。旧实现把下限从 `onPageFinished` 起算 ⇒ 启动页实际停留
   * = 网页加载耗时 + 800ms，网页越慢、白等越久（一次 1s 的加载就白等约 1s）。改从"出现时刻"
   * 起算后，不变式仍是"摘罩时整句已经打完"，但**不再叠加网页加载耗时**。
   */
  private splashArmed: boolean = false;
  private splashShownAt: number = 0;
  /** 首页「已是新对话」提示的定时器。 */
  private newChatTipTimer: number = -1;
  /** 账号菜单项重试链的定时器（140ms 轮询）。 */
  private accountRetryTimer: number = -1;
  /** 「选上传来源 → 拉起系统选择器」之间的 200ms 间隔定时器。 */
  private pickerLaunchTimer: number = -1;
  /**
   * 「选择上传」面板的兜底看门狗。
   * 面板若因故没呈现（bindSheet 静默不呈现是本工程踩过的坑），pendingFileResult 会
   * 一直非空 —— 网页侧就永远停在"上传中"，用户以为卡死。到点仍无人处理就回空列表复位。
   */
  private pickerWatchdog: number = -1;
  /** 网页无法后退时，上一次提示“再按一次退出”的时间戳（ms） */
  private lastBackToastTs: number = 0;
  /**
   * 卡片/深链「新建对话」意图的兜底重试链定时器。
   * 正常由 `{t:'ready'}` 回执消费（见 onShellMessage）；网页侧若因官方改版等原因
   * 一直不回 ready，就按 800ms × 5 次补试，宁可晚一点也不能让卡片点了没反应。
   */
  private newChatRetryTimer: number = -1;
  /** 避让区推送去抖定时器 + 上一次真正推下去的避让值（同值不推）。 */
  private insetPushTimer: number = -1;
  private lastPushedTop: number = -1;
  private lastPushedBottom: number = -1;
  /**
   * 单次主框架加载的看门狗（见 PAGE_LOAD_MAX_MS）。
   * 与启动页的 `splashTimer` **不是**一回事：后者只在首次加载后布一次，管的是
   * "网页回不回 sessions"；本看门狗每次主框架加载都重布，管的是"这次加载到底结没结束"。
   */
  private pageLoadWatchdog: number = -1;
  /**
   * 本次文档是否已经下发过注入脚本（由 onPageFinished 置位、onPageBegin 复位）。
   *
   * 用途只有一个：**干掉每次加载都发生的那次重复注入**。网页侧的 `{t:'ready'}` 只可能由
   * SHELL_JS 自己发出，而 SHELL_JS 又只可能由 onPageFinished 那次注入装进页面 ——
   * 所以 ready 到达时"本页已注入"必然为真，原先无条件的 `injectShell()` 每次加载都
   * 把 83 KB（剥离注释后仍有数万字节）的脚本重走一遍 IPC + 解析。SHELL_JS 内部虽有
   * `G.alive` 守卫、重入只退化成一次 `rescan(true)`，但那次强制重扫同样发生在启动关键路径上。
   * 保留 false 分支：万一 onPageFinished 的注入被中断而 ready 仍然到达（页面没被换掉的
   * 极端时序），行为与改动前完全一致 —— 不会出现"该补注入却没补"。
   */
  private shellInjected: boolean = false;
  /**
   * 本次文档下发注入脚本的次数（诊断读数，onPageBegin 归零）。
   * 为什么要留一个计数器：本轮把"ready 回执无条件再注入一次"这条重复路径去掉了，
   * 而这件事**只在真机/模拟器的 hilog 上看得到**（网页侧的重入被 G.alive 守卫吞掉、
   * 不产生任何日志）。留一行计数，验收就能直接断言"每次加载恰好一次注入"，而不是靠推理。
   */
  private injectCount: number = 0;
  /**
   * 站点主题偏好的轮询定时器 + **上一次读到的**站点偏好。
   *
   * ⚠️ 它**不是**"防自激的闸"，只是"站点偏好是什么"的最近读数（`onColorModeChange` 用它判断
   * 页面到底依不依赖 `prefers-color-scheme`）。防自激的闸是"目标档位 vs 外壳当前生效档位"
   * 的比较（见 `syncSiteTheme`）—— 第十八轮曾拿本字段当闸，于是外壳一旦因**外部**原因
   * （系统切深浅色 / `--ps colorMode`）偏离站点偏好，就再也不会被拉回来（本轮修）。
   */
  private siteThemeTimer: number = -1;
  private lastSiteThemeMode: number = SITE_THEME_UNKNOWN;
  /**
   * 我们是否曾按**显式**站点偏好下过 colorMode 覆盖（本轮新增）。
   * 只在"读到站点偏好 = 跟随系统"时消费：没有覆盖过就一个字节都不下发（默认路径零副作用），
   * 覆盖过就必须释放（`setColorMode(NOT_SET)`），否则外壳会永远停在旧的显式档位上。
   */
  private siteThemeOverrode: boolean = false;
  /**
   * C3 回归闩：上一次由**本站点主题同步**下发的目标档位 + 下发时刻。
   * `onColorModeChange` 会**一次性消费**它（见该方法开头）：只要这次配置回调落在
   * SITE_THEME_SELF_WINDOW_MS 窗口内，就是**我们自己引出来的**，直接返回，
   * 不去探 `prefers-color-scheme`、更不整页重载。
   */
  private siteThemeAppliedMode: number = SITE_THEME_UNKNOWN;
  private siteThemeAppliedAt: number = 0;
  /**
   * 组件是否已销毁。
   * `runJavaScript()` 的 `.then` / `.catch` 是**不可取消**的（不是定时器，清不掉），
   * 页面销毁后它们仍可能执行到 —— 那时再去碰 controller（refresh/runJavaScript）或写
   * @State 都是"对已销毁组件动手"。所有异步续作入口都先读这个闩。
   */
  private disposed: boolean = false;
  /**
   * 本次主框架加载是否**已成功结束**（onPageFinished 置 true、onPageBegin/onRenderExited 置 false）。
   *
   * 为什么要与 `loading` 分开（本轮修）：`loading` 是**启动页**的状态，它在 onPageEnd 之后
   * 还要再撑 `SPLASH_MIN_MS`~`SPLASH_MAX_MS`（800~1200ms）才落下。而站点主题同步那条
   * "读不到就不读"的门控原先用的正是 `loading` ⇒ `onPageFinished` 里那次"立刻读一次"
   * **每次都被自己挡掉**，真正的首次读取要等到下一个轮询拍（`SITE_THEME_POLL_MS` 2000ms）。
   * 真机 hilog 实证：首帧 20.055 → `site theme light` 22.045，空窗整整 2s；而这 2s 内
   * "系统深色 + 站点偏好浅色"的用户看到的是**深色外壳 + 浅色网页**（白字压浅底）。
   * 改用"文档是否就绪"作判据后，首次读取就在 onPageEnd 那一拍，空窗消失。
   */
  private pageReady: boolean = false;

  @StorageLink('launchAction') @Watch('onLaunchActionChange') launchAction: string = '';
  @StorageProp('topHeightPx') @Watch('onInsetChange') topInset: number = 0;
  @StorageProp('bottomHeightPx') @Watch('onInsetChange') bottomInset: number = 0;
  // 输入法避让：侧栏面板下沿要抬到键盘之上（否则搜索时列表与底部计数被键盘盖住）
  @StorageProp('keyboardHeightPx') keyboardInset: number = 0;
  @StorageProp('currentColorMode') @Watch('onColorModeChange')
  currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  @State loading: boolean = true;
  @State errorMessage: string = '';
  @State sidebarOpen: boolean = false;
  @State rows: SideRow[] = [];
  @State sessionCount: number = 0;
  @State routeKind: string = 'home';
  /**
   * 设置页底部功能栏当前选中的页签下标（第二十一轮）。
   * 只在 `routeKind === 'settings'` 时有意义；点底栏即刻回写，进入设置页时归 0（见 onSettingsOpened）。
   *
   * ⚠️ 用 `@StorageLink` 而**不是** `@State`：底栏的 tab 项组件（`SettingsTabItemView`）在
   * `TabContent.tabBar()` 里，吃的是 `@Builder` —— 而 `@Builder` 的值参数不会因父级重跑而重建
   * （内部踩坑表 的 38 号），父级把 active 当参数传下去是**不会刷新选中态**的。
   * 走 AppStorage 同一个键，两端各自订阅，谁改都能刷新（aa-hm 的 `AaBottomTabItem` 同款做法）。
   */
  @StorageLink('settingsTabIndex') settingsTabIndex: number = 0;
  @State currentSessionId: string = '';
  @State pageTitle: string = '';
  /** 账号昵称 / 头像（网页侧从官方抽屉页脚抽取上报）。 */
  @State accountName: string = '';
  @State accountAvatar: string = '';
  /** 批量删除：进行中标志 + 进度，供侧栏显示。 */
  @State deleteBusy: boolean = false;
  @State deleteTotal: number = 0;
  @State deleteDone: number = 0;
  /** 待删队列（组件内部状态，不需要驱动 UI，故用普通成员）。 */
  private deleteQueue: string[] = [];
  private deleteRunning: boolean = false;
  /**
   * 当前轮删除的**一次性通行证**（native 侧秘密，见 rotateDeleteNonce）。
   * 空串 = 闩关闭；网页侧只认这个值，不再有"传 true 即可开闸"的开关。
   */
  private deleteNonce: string = '';
  /** 未能确认删除成功的条数（网页侧回报非 done），队列走完后一次性提示用户。 */
  private deleteFailed: number = 0;
  /** 单步看门狗：网页侧任一步没回报（桥异常/官方改版）时强制推进，否则流程会永久卡住。 */
  private deleteWatchdog: number = -1;

  /** 首页「已是新对话」气泡是否可见。 */
  @State newChatTip: boolean = false;

  // —— 「选择上传」面板状态 ——
  /**
   * 官方半模态面板的显示开关（bindSheet 的 isShow，用 $$ 双向绑定）。
   * 双向绑定是必需的：用户点遮罩/下拉关闭时由框架把这里写回 false，
   * @Watch 才能察觉"用户自己关掉了面板"，把这次文件选择按取消收尾。
   */
  @State @Watch('onPickerSheetChange') pickerSheetShown: boolean = false;
  /** 用户是否已在面板里做出选择（选来源 / 点取消）：决定面板关闭是"继续选"还是"取消"。 */
  private pickerDecided: boolean = false;
  /** 正在等待系统选择器返回：期间屏蔽重复点选（系统窗口盖住时用户仍可能连点）。 */
  private pickerBusy: boolean = false;
  /** 网页侧这次文件选择的回传句柄（onShowFileSelector 给的 result，选完/取消都要回）。 */
  private pendingFileResult: FileSelectorResult | null = null;
  /** 网页侧是否允许多选（`<input multiple>`）：决定选择器里最多能选几个。 */
  private pendingMultiSelect: boolean = false;

  aboutToAppear(): void {
    // ArkWeb DevTools 调试通道：**只在 debug 构建打开**（audit B-9）。
    //
    // 为什么要门控：`setWebDebuggingAccess(true)` 会在设备上建一个调试通道，而本工程承载的是
    // **带登录态的 chat.deepseek.com** —— 发布态常开等于把"读网页 DOM / 改样式 / 执行脚本"的
    // 能力交给任何能连上该通道的人（SDK 亦注明"不建议在正式发布版本开启"）。
    // release 构建里 `BuildProfile.DEBUG === false`，通道自动关闭；真机 CDP 定位能力不受影响。
    try {
      webview.WebviewController.setWebDebuggingAccess(BuildProfile.DEBUG);
    } catch (err) {
    }
    // 启动页（若此刻就该显示）的"出现时刻"：逐字动画与 `SPLASH_MIN_MS` 下限都以它为基准
    this.splashShownAt = Date.now();
    this.bridge.setHandler((json: string) => {
      this.onShellMessage(json);
    });
    if (this.launchAction === 'newChat') {
      this.action = 'newChat';
      this.launchAction = '';
    } else if (this.launchAction === 'openSidebar') {
      // 首启也要消费一次：@Watch 在初始化时不回调（本项目多处踩过同源缺陷）。
      this.launchAction = '';
      this.sidebarOpen = true;
    } else if (this.launchAction === 'closeSidebar') {
      this.launchAction = '';
      this.sidebarOpen = false;
    }
  }

  /**
   * 页面销毁：把所有延时任务与待回传句柄一并收掉。
   *
   * 为什么必须在这里做（本轮补齐）：早先只清了 splash 与提示两个定时器，漏掉的
   * 60ms 鲸鱼入场、删除看门狗、账号菜单重试链、选择器拉起延时、上传看门狗都会在
   * 销毁后继续触发 → 对已销毁组件写 @State（框架告警）或对已失效的 FileSelectorResult
   * 调 handleFileList（无谓异常）。**"销毁后仍写 @State"的根源就是漏登记定时器**，
   * 所以约定：本页任何 setTimeout/setInterval 都必须存句柄、在这里 clear。
   */
  aboutToDisappear(): void {
    // 先落闩再清句柄：异步续作（runJavaScript 的 then/catch）不是定时器、清不掉，
    // 它们醒来第一件事就是读这个闩。
    this.disposed = true;
    this.clearTimer(this.splashTimer);
    this.splashTimer = -1;
    this.splashArmed = false;
    // 启动页的逐字动画与鲸鱼入场两个定时器随 SplashOverlay 一起销毁（它自己的
    // aboutToDisappear 里收），本组件不再登记它们 —— 见 SplashOverlay 的说明。
    this.clearTimer(this.newChatTipTimer);
    this.newChatTipTimer = -1;
    this.clearTimer(this.accountRetryTimer);
    this.accountRetryTimer = -1;
    this.clearTimer(this.pickerLaunchTimer);
    this.pickerLaunchTimer = -1;
    this.clearTimer(this.pickerWatchdog);
    this.pickerWatchdog = -1;
    this.clearTimer(this.newChatRetryTimer);
    this.newChatRetryTimer = -1;
    this.clearTimer(this.insetPushTimer);
    this.insetPushTimer = -1;
    this.clearDeleteWatchdog();
    this.clearPageLoadWatchdog();
    this.stopSiteThemePoll();
    // 待回传的文件选择句柄：销毁时给网页侧一个空结果，别让页面永远停在"上传中"
    if (this.pendingFileResult !== null) {
      try {
        this.pendingFileResult.handleFileList([]);
      } catch (err) {
      }
      this.pendingFileResult = null;
    }
  }

  /** 统一的定时器清理（-1 与已触发过的句柄都安全）。 */
  private clearTimer(id: number): void {
    if (id !== -1) {
      clearTimeout(id);
    }
  }

  // —— 启动页动画 ——
  // 逐字跳出与鲸鱼入场的**动画状态**（chars / logoIn）和两个定时器已**下沉到 SplashOverlay**
  // （本轮）。理由只有一条但是硬的：这两个 @State 在启动期是 7 次/130ms 级的自增，
  // 而 ArkUI 里 @Entry 根组件任何一个 @State 变化都会把**整棵根 build()** 重跑一遍
  // （连带 Web 组件的全部属性表达式、SidePane 的 20 个参数、MainPane 的 19 个参数与
  // 它们的 @Prop 逐项比较）—— 而启动页是**全屏不透明**的覆盖层，背后那一整轮重建用户
  // 一眼都看不到。下沉后启动页自绘自刷新，根 build() 的依赖面少两个 @State。
  // **重放语义不变**：loading 由 false→true（错误页重试、整页 refresh）会让 build() 里的
  // if 分支重新挂载 SplashOverlay，它的 aboutToAppear 即从 0 重放（与改动前逐字等价）。

  /**
   * 布下启动页的**兜底超时**（首个整页加载结束时调用一次，见 onPageFinished）。
   * 到点无论网页有没有回话都摘罩 —— 网页侧如果因官方改版一直不回 `sessions`，
   * 用户也不能被永远关在启动页里。
   */
  private armSplashDeadline(): void {
    this.clearTimer(this.splashTimer);
    // 基准时刻是"启动页出现"那一刻（aboutToAppear 落的 splashShownAt），这里**不要**再覆盖成
    // "网页加载完"—— 那会把网页加载耗时白加进启动页的停留时间里（见 splashShownAt 的说明）。
    this.splashArmed = true;
    this.splashTimer = setTimeout(() => {
      this.splashTimer = -1;
      this.finishSplash();
    }, SPLASH_MAX_MS);
  }

  /**
   * 尝试**提前**摘罩（首个 `sessions` 桥消息到达时调用）。
   *
   * 为什么以 `sessions` 为信号：它由网页桥脚本在**官方侧栏 DOM 抽取成功**后上报 ——
   * 那一刻说明"官方外壳已经渲染出来、原生侧栏也有数据可渲染了"，启动页的使命（盖住
   * 官方的预热渲染）已经完成，没有任何理由再硬等下去。
   *
   * 但仍夹一个 `SPLASH_MIN_MS` 下限：立刻摘罩会让逐字跳出的标语只播一半就消失。
   * 只消费一次（`splashArmed`），避免后续每次列表刷新都把摘罩逻辑重跑一遍。
   */
  private requestSplashRelease(): void {
    if (!this.splashArmed) {
      return;
    }
    this.splashArmed = false;
    const left: number = SPLASH_MIN_MS - (Date.now() - this.splashShownAt);
    if (left <= 0) {
      this.finishSplash();
      return;
    }
    this.clearTimer(this.splashTimer);
    this.splashTimer = setTimeout(() => {
      this.splashTimer = -1;
      this.finishSplash();
    }, left);
  }

  /** 摘罩：停掉逐字动画、清掉超时句柄，并把 loading 落下（启动页与错误页都由它驱动）。 */
  private finishSplash(): void {
    this.splashArmed = false;
    this.clearTimer(this.splashTimer);
    this.splashTimer = -1;
    // 逐字动画不必在这里收：loading 落下 ⇒ build() 的 if 分支卸载 SplashOverlay ⇒
    // 它自己的 aboutToDisappear 收掉两个定时器（定时器与组件同生命周期）。
    // 这一行是**启动速度的可读读数**（验收直接看它，不必靠推理）：自启动页出现起的毫秒数。
    // 不变式：首次摘罩时它必须 ≥ SPLASH_MIN_MS(800)（否则标语会被切一半）。
    hilog.info(WEB_DOMAIN, SHELL_TAG, 'splash off after %{public}dms', Date.now() - this.splashShownAt);
    this.loading = false;
  }

  // —— 首页「已是新对话」提示 ——
  /**
   * 新建对话。首页本来就是"新对话"态，此时点右上角 + / 面板里的 ⊕ 不该真的去点官方的
   * 「新建对话」（那样会把已经在输入框里的草稿和已选的深度思考/智能搜索状态一起重置，
   * 用户却看不出发生了什么），改为在按钮旁边短暂提示一次。
   */
  private requestNewChat(): void {
    if (this.routeKind === 'home') {
      this.showNewChatTip();
      return;
    }
    this.doNewChat();
  }

  private showNewChatTip(): void {
    if (this.newChatTipTimer !== -1) {
      clearTimeout(this.newChatTipTimer);
      this.newChatTipTimer = -1;
    }
    this.newChatTip = true;
    this.newChatTipTimer = setTimeout(() => {
      this.newChatTipTimer = -1;
      this.newChatTip = false;
    }, NEW_CHAT_TIP_MS);
  }

  private onLaunchActionChange(): void {
    if (this.launchAction === 'newChat') {
      this.action = 'newChat';
      this.launchAction = '';
      // 页面已加载完毕时可以直接执行；仍在加载则**留着**这个意图，
      // 由 onPageFinished 布兜底重试、ready 回执真正消费（见 onShellMessage）。
      // 早先在"加载中"这一支什么都不做，而 onPageFinished 又在 api 存在之前就调
      // doNewChat —— 卡片点击因此在冷启动路径上必然丢失（本轮修）。
      if (!this.loading) {
        this.doNewChat();
        this.action = '';
      }
      return;
    }
    // 自动化冒烟入口（与 EntryAbility 的 --ps colorMode 同类的调试通道）：
    // 侧栏是原生组件，CDP 摸不到它的状态，合成 tap 又受"面板是否已展开"影响而不可复现。
    //   hdc shell "aa start -a EntryAbility -b com.example.deepseekhm --ps action openSidebar"
    //   ... --ps action closeSidebar
    if (this.launchAction === 'openSidebar') {
      this.launchAction = '';
      this.openSidebar();
    } else if (this.launchAction === 'closeSidebar') {
      this.launchAction = '';
      this.closeSidebar();
    }
  }

  // —— 网页侧上报消息 ——
  /**
   * 桥消息的**结构校验**（本轮补齐）。
   *
   * 为什么必须校验：`dshBridge.post` 是网页侧可任意调用的入口（调试会话里一句
   * `window.dshBridge.post('<垃圾>')` 就能打进来）。早先只 try/catch 了 JSON.parse，
   * 但 `msg.t` 是任意字符串、`msg.items` 可能是字符串/对象/含 null 项的数组 ——
   * 后面 `applySessions()` 会去读 `it.id.length`，遇到非字符串直接抛异常；
   * 那个异常发生在 javaScriptProxy 回调里，会把整条桥链路打断（后续真实消息全丢）。
   * 约定：**不合法就丢弃 + hilog**，绝不让异常冒到桥回调之外。
   */
  private isKnownShellKind(t: string): boolean {
    return t === 'sessions' || t === 'route' || t === 'ready' || t === 'log' ||
      t === 'account' || t === 'deleted';
  }

  /** 逐字段校验会话项：id/title/group 必须是 string（缺 title 的项在渲染层会被跳过）。 */
  private toSessionItems(raw: Object | undefined): ChatSessionItem[] {
    if (raw === undefined || !Array.isArray(raw)) {
      return [];
    }
    let out: ChatSessionItem[] = [];
    for (let i = 0; i < raw.length; i++) {
      let it: Object = raw[i] as Object;
      if (it === null || typeof it !== 'object') {
        continue;
      }
      let rec: Record<string, Object> = it as Record<string, Object>;
      let id: Object | undefined = rec['id'];
      let title: Object | undefined = rec['title'];
      let group: Object | undefined = rec['group'];
      if (typeof id !== 'string' || typeof title !== 'string') {
        continue;
      }
      // 网页侧消息体里还带着 `active`，但**原生侧不消费它**（"当前会话"一律由
      // `applySessions` 按 id === currentSessionId 回填）—— 故这里不再解析（本轮精简，
      // grep 证据：`ChatSessionItem.active` 在原生侧零读者）。多一个未解析的键对
      // JSON.parse 无任何影响。
      let item: ChatSessionItem = {
        id: id as string,
        title: title as string,
        group: typeof group === 'string' ? group as string : ''
      };
      out.push(item);
    }
    return out;
  }

  private onShellMessage(json: string): void {
    let msg: ShellMessage | null = null;
    try {
      msg = JSON.parse(json) as ShellMessage;
    } catch (err) {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'bridge message not json, dropped');
      return;
    }
    if (msg === null || typeof msg !== 'object') {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'bridge message not object, dropped');
      return;
    }
    let kind: string = msg.t !== undefined ? msg.t : '';
    if (!this.isKnownShellKind(kind)) {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'bridge message unknown t=%{public}s, dropped', kind);
      return;
    }
    if (kind === 'sessions') {
      // 设备侧硬证据（hilog）：原生确实收到了 N 条会话
      let items: ChatSessionItem[] = this.toSessionItems(msg.items);
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'sessions from web: %{public}d', items.length);
      this.applySessions(items);
      // 首个会话列表 = 官方外壳已渲染完成：启动页不必再硬等（见 requestSplashRelease）。
      // 这是把 SPLASH_HOLD_MS=2200 的硬盖子换成事件驱动的唯一信号源。
      this.requestSplashRelease();
    } else if (kind === 'route') {
      // 跨入设置页那一刻要查一次网页侧的真实选中页签（见下方 syncSettingsTabFromWeb 调用），
      // 故先把上一帧的 kind 留一份。
      let prevKind: string = this.routeKind;
      this.routeKind = typeof msg.kind === 'string' ? msg.kind : 'home';
      this.currentSessionId = typeof msg.id === 'string' ? msg.id : '';
      this.pageTitle = typeof msg.title === 'string' ? msg.title : '';
      // 第二十一轮：刚进入设置页 ⇒ 读回网页侧真实选中下标，对齐原生底部功能栏高亮。
      // 只在**跨入**这一刻查一次：route 消息在设置页开着期间会随巡检反复到达，
      // 每次都查等于白白下发一串 JS；而页签打开后不会自己变（用户点原生底栏那条路径
      // 由 onSettingsTabSelect 直接回写，无需往返）。
      if (this.routeKind === 'settings' && prevKind !== 'settings') {
        this.onSettingsOpened();
      }
      // 路由一变，列表里"哪一行是当前会话"就跟着变 —— 必须立刻回填（否则侧栏高亮与
      // "打开侧栏自动定位当前会话"会停在旧位置上）。详见 syncActiveRow 的说明。
      //
      // 诊断日志（第十六轮补）：route 分支原先**一行日志都没有**，而"回填有没有生效"
      // 恰恰只能从 native 侧看（网页侧的 active 不是权威值）。排查 B8「当前会话不高亮」
      // 时，靠的就是这两条：route 到达时手上有没有 id、手上那份 rows 有没有对应行。
      // 与 `sessions from web: N` 对称，长期保留（onConsole 之外的本工程唯一 native 日志面）。
      //
      // ⚠️ **会话 id 用 `%s` 而不是 `%{public}s`**：`@ohos.hilog.d.ts` 明确"未指定标识时
      // 默认 private（明文不打印）"。会话 UUID 是用户数据，**发布态不该落进系统日志** ——
      // 这与本轮 B-9 把 `setWebDebuggingAccess` 按 `BuildProfile.DEBUG` 门控是同一条口径。
      // 发布态会打 `<private>`（不影响 `rows=` / `active=` 这些计数读数，而定性 B8 靠的正是计数）；
      // 真机取证若要读 id，临时改回 `%{public}s` 即可。
      //
      // 读法提醒：`route filled` 是 `syncActiveRow()` **之后**的读数，而该函数在"标记本来就对"
      // 时会早退什么都不做 —— 所以**证据是这一对行的对比**（`active=0` → `active=1`），
      // 单看第二条只能证明"回填后不变量成立"，不能证明发生过回填。
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'route kind=%{public}s id=%s rows=%{public}d active=%{public}d',
        this.routeKind, this.currentSessionId.length > 0 ? this.currentSessionId : '(empty)',
        this.rows.length, this.activeRowCount());
      this.syncActiveRow();
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'route filled: active=%{public}d', this.activeRowCount());
    } else if (kind === 'ready') {
      // 桥脚本就绪。**正常情况下这里不需要再注入**（ready 只可能由刚注入的 SHELL_JS 发出，
      // 见 shellInjected 的说明）；只有"本页还没注入过"这一支才补一次，
      // 保留它覆盖"SPA 挂载晚于 onPageEnd"的旧场景，行为与改动前等价。
      if (!this.shellInjected) {
        this.injectShell();
      }
      // 卡片/深链带来的"新建对话"意图必须等这一刻才执行 —— 它在 onPageEnd 时排在
      // SHELL_JS 之前，window.__dshShellApi 还不存在，会被 && 静默吞掉（本轮修）。
      if (this.action === 'newChat') {
        this.action = '';
        this.doNewChat();
      }
      if (this.newChatRetryTimer !== -1) {
        this.clearTimer(this.newChatRetryTimer);
        this.newChatRetryTimer = -1;
      }
    } else if (kind === 'log') {
      // 契约里一直放行、实现里却**没有分支**的一类消息（ShellTypes.ShellMessage.m 的注释
      // 早就写着"原生侧会打成一条 hilog"）。不补的话，网页侧主动上报的诊断文本会被
      // isKnownShellKind 放行后**静默丢弃** —— 排查网页侧问题时看不到任何线索。
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'web log: %{public}s', typeof msg.m === 'string' ? msg.m : '');
    } else if (kind === 'account') {
      this.accountName = typeof msg.name === 'string' ? msg.name : '';
      this.accountAvatar = typeof msg.avatar === 'string' ? msg.avatar : '';
    } else if (kind === 'deleted') {
      // 网页侧每条删除完成/失败都回报一次；串行推进下一条
      this.onDeleteStep(typeof msg.id === 'string' ? msg.id : '',
        typeof msg.status === 'string' ? msg.status : '');
    }
  }

  // —— 批量删除编排 ——
  // 为什么由原生侧串行驱动而不是网页侧循环：官方每条删除都要走
  // 「⋯ 菜单 → 删除 → 确认弹窗」三次异步渲染，网页侧若一把梭循环会互相踩状态
  // （菜单还没出来就点确认）。这里做成"发一条 → 等 deleted 回报 → 发下一条"，
  // 进度也能实时反馈到侧栏。
  /**
   * 生成并下发一次性删除密钥（"开闸"）。
   *
   * 安全设计（本轮返工两次才收口）：
   *  ① 密钥由 native 生成，页面上**没有任何能自行开闸的入口**（旧实现的 armDelete(on)
   *     只要一句 `__dshShellApi.armDelete(true)` 就能自己开闸，闩形同虚设）；
   *  ② 密钥不是"直接 set 进页面状态"，而是先写一个一次性的 window 交接变量、
   *     紧接着同步区里让页面脚本读走并删除它（见 ShellScript.setDeleteToken）——
   *     两次求值之间页面脚本没有执行机会，`ARM_SECRET` 因此页面上读不到；
   *  ③ 每条删除用过的密钥立刻换掉（见 pumpDelete），队列走完落闩。
   * 这三条合起来，页面上唯一能删数据的路径就是 native 主动下发密钥的那一条。
   */
  private rotateDeleteNonce(): void {
    const a: string = Math.floor(Math.random() * 0xFFFFFF).toString(16);
    const b: string = Math.floor(Math.random() * 0xFFFFFF).toString(16);
    const c: string = Math.floor(Math.random() * 0xFFFFFF).toString(16);
    this.deleteNonce = (a + b + c + Date.now().toString(16)).slice(0, 32);
    const js: string = 'window.__dshArmSecret=' + JSON.stringify(this.deleteNonce) + ';' +
      'window.__dshShellApi && window.__dshShellApi.setDeleteToken(' +
      JSON.stringify(this.deleteNonce) + ')';
    this.runJs(js);
  }

  private startDelete(ids: string[]): void {
    // **重入闸**（第十六轮补，audit B-11）：上一批还在途时又开一批，会把 `deleteRunning`
    // 与单步看门狗清掉 —— 在途那一条的回报从此推进**新**队列，进度错乱、`deleteDone`
    // 超过 `deleteTotal`，严重时用户以为删了其实没删。
    // 为什么侧栏的按钮禁用挡不住：`deleteBusy` 只隐藏 SelectBar 上的删除按钮，
    // 而退出选择模式后「选择」图标又会露出来，用户完全可以在上一批在途时再点一次。
    // 闸放在这里（数据入口）才是可靠的：无论从哪条 UI 路径进来都拦得住。
    if (this.deleteBusy) {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'delete already running, ignore new batch');
      this.toast('正在删除，请稍候');
      return;
    }
    this.deleteQueue = ids.slice();
    this.deleteTotal = ids.length;
    this.deleteDone = 0;
    this.deleteFailed = 0;
    this.deleteBusy = true;
    this.deleteRunning = false;
    this.pumpDelete();
  }

  private pumpDelete(): void {
    if (this.deleteRunning) {
      return;
    }
    if (this.deleteQueue.length === 0) {
      this.deleteBusy = false;
      this.clearDeleteWatchdog();
      // 队列走完即落闩：删除接口回到"只有重新进选择模式才可用"的状态。
      // **这是全流程唯一的落闩点**（进入删除流程时闩必须一直开着，见
      // SidePane.exitSelecting 的说明）。
      this.deleteNonce = '';
      this.callApi('clearDeleteToken()');
      // 全删完再刷新一次列表与计数
      this.callApi('rescan()');
      // 网页侧回报的每一步状态都记账：非 done 说明"点了但没能确认删掉"（官方改版、
      // 残留菜单被兜底拦下、闩被拒等）。静默当作成功会让用户以为删了其实没删 —— 必须明说。
      if (this.deleteFailed > 0) {
        this.toast('有 ' + this.deleteFailed.toString() + ' 个对话未能删除，请重试');
      }
      return;
    }
    let id: string = this.deleteQueue[0];
    this.deleteQueue = this.deleteQueue.slice(1);
    this.deleteRunning = true;
    this.armDeleteWatchdog();
    // 先带旧通行证下发这一条，再把通行证换掉（两条 runJavaScript 按序执行：
    // 前一条在求值期就完成了 token 捕获与 deleteBusy 置位，后一条才改 token）。
    const token: string = this.deleteNonce;
    this.callApi('deleteSession(' + JSON.stringify(id) + ',' + JSON.stringify(token) + ')');
    this.rotateDeleteNonce();
  }

  private armDeleteWatchdog(): void {
    this.clearDeleteWatchdog();
    this.deleteWatchdog = setTimeout(() => {
      this.deleteWatchdog = -1;
      if (this.deleteRunning) {
        // 看门狗触发 = 这一步**没能确认删成功**（网页侧没回报），
        // 必须计入失败，否则用户只会看到进度条走完、列表却没变。
        hilog.warn(WEB_DOMAIN, SHELL_TAG, 'delete step timeout, advancing');
        this.deleteRunning = false;
        this.deleteDone = this.deleteDone + 1;
        this.deleteFailed = this.deleteFailed + 1;
        this.pumpDelete();
      }
    }, 8000);
  }

  private clearDeleteWatchdog(): void {
    if (this.deleteWatchdog !== -1) {
      clearTimeout(this.deleteWatchdog);
      this.deleteWatchdog = -1;
    }
  }

  private onDeleteStep(id: string, status: string): void {
    hilog.info(WEB_DOMAIN, SHELL_TAG, 'delete %{public}s -> %{public}s', id, status);
    this.clearDeleteWatchdog();
    this.deleteRunning = false;
    this.deleteDone = this.deleteDone + 1;
    // 非 done 一律计失败：locked / busy 也是失败（早先只认 done，被闩拒绝时
    // 静默计成功，用户以为删了 —— 这正是本轮 P0 缺陷"连失败提示都没有"的成因之一）。
    if (status !== 'done') {
      this.deleteFailed = this.deleteFailed + 1;
    }
    this.pumpDelete();
  }

  /** 会话列表拍平成「分组标题行 + 会话行」，避免嵌套 ForEach。 */
  private applySessions(items: ChatSessionItem[]): void {
    let rows: SideRow[] = [];
    let lastGroup: string = '';
    for (let i = 0; i < items.length; i++) {
      let it: ChatSessionItem = items[i];
      if (it.id.length === 0 || it.title.length === 0) {
        continue;
      }
      let group: string = it.group.length > 0 ? it.group : '会话';
      if (group !== lastGroup) {
        lastGroup = group;
        let groupRow: SideRow = {
          kind: 'group',
          // key 必须唯一：同名分组标题在同一份列表里可能再次出现（官方分组顺序是
          // 今天/昨天/7天内/更早，一旦某条会话抽不到分组就会回落成"会话"，
          // 其后又出现"更早"）—— 只按分组名做 key 会与前面那条撞键，
          // ForEach 的复用语义会作用在错误的行上。这里带上"当前已产出的行数"。
          key: 'g:' + group + ':' + rows.length.toString(),
          text: group,
          id: '',
          active: false
        };
        rows.push(groupRow);
      }
      let sessionRow: SideRow = {
        kind: 'session',
        key: 's:' + it.id,
        text: it.title,
        id: it.id,
        // **当前会话必须由原生侧回填**（第十六轮补，audit §2 P2「`active` 注释与实现不符」）。
        // 判据只有原生侧有：网页侧虽然也会算一个 `active`（ShellScript.collect() 按路由算），
        // 但消息体里那个字段原生侧**从来不读**（第十九轮已从 ChatSessionItem 删除），
        // 唯一真相来源就是这里按 id 全等回填。
        // 后端（SidePane）用 `row.active` 决定三件事：当前行的 accent 高亮、
        // `activeIndex()` 的"打开侧栏自动定位当前会话"、以及无障碍文案「当前会话 / 会话」。
        // 不回填的话这三件事**全部静默失效**（列表永远不高亮、定位永远落空），且没有任何报错。
        // 判据用 id 全等：两侧同源（都取自官方路由 `/a/chat/s/<uuid>`）。
        active: this.currentSessionId.length > 0 && it.id === this.currentSessionId
      };
      rows.push(sessionRow);
    }
    // 会话总数先落（它与 rows 不是一回事：rows 里还含分组标题行，见 SidePane 的 totalCount），
    // 非法项被跳过时 items.length 会变而 rows 不变，所以这一句必须在下面的早退之前。
    this.sessionCount = items.length;
    // **内容没变就不换引用**（本轮加）：@State 数组换引用会让 SidePane 的 @Watch 链
    // （invalidateFilter / syncActiveId / 定位）与 ForEach 的 O(n) diff 白跑一遍，而
    // `sessions` 是**每 5s 巡检一次**推回来的、官方 DOM 抽取结果绝大多数拍完全不变。
    // ⚠️ 只在**侧栏关着**时早退：面板开着时"行数据到达"还带着两条 UI 副作用 ——
    // 下拉刷新指示器复位（SidePane.onRowsChange 的 settleRefresh）与"打开侧栏自动定位当前会话"，
    // 那些必须照常收到信号（用户正看着它）。
    if (!this.sidebarOpen && rowsEqual(this.rows, rows)) {
      return;
    }
    this.rows = rows;
    // 诊断日志（与 route 分支对称）：`applySessions` 是 active 回填的**另一条路径**
    // （sessions 与 route 是两条独立到达的桥消息），两条路径都要能看见各自的读数。
    // `cur=` 同样用 `%s`（private）—— 会话 id 是用户数据，见 route 分支的说明。
    hilog.info(WEB_DOMAIN, SHELL_TAG, 'sessions applied: rows=%{public}d active=%{public}d cur=%s',
      rows.length, this.activeRowCount(), this.currentSessionId.length > 0 ? this.currentSessionId : '(empty)');
  }

  /** 当前行标记为"当前会话"的行数（诊断用：回填是否生效的唯一可见读数）。 */
  private activeRowCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.rows.length; i++) {
      let row: SideRow = this.rows[i];
      if (row.kind === 'session' && row.active) {
        n = n + 1;
      }
    }
    return n;
  }

  /**
   * 路由变化后把"当前会话"的回填标记重新打到行上。
   *
   * 为什么不能只在 `applySessions` 里做：`route` 与 `sessions` 是**两条独立到达的桥消息**
   * （会话列表按需重抽，路由变化是即时的），先到的那条拿不到另一条的信息。两处都调才能收敛。
   *
   * 只在标记真的变了才换数组：@State 数组必须换引用来触发刷新，但无变化时换引用是白刷一遍
   * 整份列表（§3.0-138 的同源纪律）。
   */
  private syncActiveRow(): void {
    let changed: boolean = false;
    for (let i = 0; i < this.rows.length; i++) {
      let row: SideRow = this.rows[i];
      let want: boolean = row.kind === 'session' && this.currentSessionId.length > 0 &&
        row.id === this.currentSessionId;
      if (row.active !== want) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return;
    }
    let next: SideRow[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      let row: SideRow = this.rows[i];
      let want: boolean = row.kind === 'session' && this.currentSessionId.length > 0 &&
        row.id === this.currentSessionId;
      next.push({
        kind: row.kind,
        key: row.key,
        text: row.text,
        id: row.id,
        active: want
      });
    }
    this.rows = next;
  }

  /**
   * 原生顶栏标题。
   * 首页刻意**不用**文档标题：官网首页 title 是 "DeepSeek - 探索未至之境" 这类 slogan，
   * 真机上会把顶栏塞满并被省略号截断，观感差；首页固定显示品牌名。
   * 对话页优先用侧栏里的会话标题（与官方侧栏文案逐字一致）；子页（登录/条款）保留文档标题。
   */
  private displayTitle(): string {
    if (this.routeKind === 'home') {
      return 'DeepSeek';
    }
    // 设置页（第二十一轮，用户要求「把系统设置那一行做成整页的标题栏」）：固定「系统设置」。
    // ⚠️ 不能落到下面的文档标题兜底 —— 官方设置浮层**不改 URL**，文档标题仍是**当前会话名**，
    //    那样顶栏会写成会话名、内容却是设置页（真机 m1 时代就记过这个现象）。
    if (this.routeKind === 'settings') {
      return '系统设置';
    }
    if (this.routeKind === 'chat') {
      for (let i = 0; i < this.rows.length; i++) {
        let row: SideRow = this.rows[i];
        if (row.kind === 'session' && row.id === this.currentSessionId && row.text.length > 0) {
          return row.text;
        }
      }
    }
    let docTitle: string = this.pageTitle.trim();
    if (docTitle.length > 0) {
      return docTitle;
    }
    return 'DeepSeek';
  }

  /**
   * 打开原生侧栏。
   * 搜索词的清空与「定位当前会话」都由 SidePane 自己管（它持有滚动器与局部状态），
   * 这里只负责展开面板并让网页侧重抽一次列表。
   */
  private openSidebar(): void {
    // 幂等：面板已经开着时不再重抽。顶栏的 ☰ 在面板展开时仍可点（见 MainPane 的层序），
    // 连点会累积 rescan 请求，没必要。
    if (this.sidebarOpen) {
      return;
    }
    this.sidebarOpen = true;
    this.refreshSessions();
  }

  /**
   * 顶栏 ☰：开 / 关切换。
   * 只开不关是"点不动"的经典来源 —— 面板展开后 ☰ 仍在屏幕右上角可点（面板只占 82% 宽），
   * 但点它没有反应，用户会以为顶栏坏了。带侧栏的官方 App 一律是 toggle 语义。
   */
  private toggleSidebar(): void {
    if (this.sidebarOpen) {
      this.closeSidebar();
    } else {
      this.openSidebar();
    }
  }

  // —— 网页装载 ——
  // 主框架导航白名单的判据（`normalizedOriginOf` / `isAllowedNavTarget`）已上移为**模块级纯函数**：
  // 第十六轮 `onLoadIntercept` 随 Web 一起下沉到了 `MainPane`，而这两个判据不依赖任何组件状态，
  // 放在模块级才能被两处共用、也才好单独推演（纯字符串函数，无副作用）。

  private configureAndLoad(): void {
    try {
      // 只走"带应用标识的移动端 UA"这一条路：桌面 UA 分支自建工程起就没人开过
      // （useDesktopUa 恒为 false），而它引用的 DESKTOP_UA 常量与两处 if 守卫
      // 让"注入"相关的代码读起来像有两种模式。P2-2 清理时一并删除。
      let currentUa: string = this.controller.getUserAgent();
      this.controller.setCustomUserAgent(currentUa + ' DeepSeekHm/1.0');
      this.controller.loadUrl(DEEPSEEK_HOME);
      this.loading = true;
      this.errorMessage = '';
      // 整页重载会把启动页重新亮出来：loading 由 false→true 会让 build() 的 if 分支
      // 重新挂载 SplashOverlay，逐字动画由它的 aboutToAppear 从 0 重放（语义与改动前等价）。
    } catch (err) {
      let error = err as BusinessError;
      this.errorMessage = 'Web 初始化失败：' + error.message;
      this.loading = false;
    }
  }

  /**
   * 注入两个脚本 + 三个避让量。
   *
   * 本轮两处改动（P1-7）：
   *  ① **合并为单次 runJavaScript**：早先是 setup → (adapter, shell) 三次下发。
   *     三次之间有真实的时序缝隙（各自都是跨进程异步求值），而 SHELL_JS 依赖
   *     adapter 建好的 window.__dshPerf 与 __dshShellOwnsChrome —— 合并后顺序由
   *     一个 JS 引擎保证（adapter 在前、shell 在后），既省两次 IPC 又消掉这类竞态。
   *     保留各自的 try/catch 语义：一个脚本抛错不能带倒另一个（合并后包一层）。
   *  ② **剥离整行注释再下发**：两个脚本里 `//` 注释占约 23% 体积，
   *     每次推送都是这几万字节走过 IPC + 引擎解析。只剥"整行注释"（trim 后以 // 开头），
   *     不碰行尾注释与字符串 —— 保守但足够（注释绝大多数是整行的文档注释）。
   */
  private injectShell(): void {
    try {
      let setup: string = 'window.__dshStatusBarPx=' + this.topInset.toString() + ';' +
        // 让位量 = 状态栏 + **框架标题栏在状态栏之下的高度**（NAV_TITLE_SLOT_VP=66vp）——
        // 与 `pushInsets()` 同源同值（两处各写一个 66 是本轮最容易留下的静默缺陷）。
        'window.__dshTopInsetPx=' + (this.topInset + NAV_TITLE_SLOT_VP).toString() + ';' +
        'window.__dshBottomInsetPx=' + this.bottomInset.toString() + ';';
      let js: string = setup +
        'try{' + stripLineComments(MOBILE_ADAPTER_JS) + '}catch(e){console.warn("[DSH] adapter err",e)}\n' +
        'try{' + stripLineComments(SHELL_JS) + '}catch(e){console.warn("[DSH] shell err",e)}';
      this.injectCount = this.injectCount + 1;
      hilog.info(WEB_DOMAIN, WEB_TAG, 'injectShell #%{public}d bytes=%{public}d',
        this.injectCount, js.length);
      this.controller.runJavaScript(js).catch((err: BusinessError) => {
        hilog.warn(WEB_DOMAIN, WEB_TAG, 'inject js failed: %{public}s', err.message);
      });
    } catch (err) {
    }
  }

  // —— 站点主题偏好 → 原生外壳配色 ——
  /**
   * 读一次站点主题偏好并据此下发 colorMode（**只读偏好、不读观感**，理由见 SITE_THEME_KEY）。
   *
   * 门控（每一项都对应一种"不该做"的场景）：
   *   ① disposed：页面已销毁，runJavaScript 的续作不可取消，不能再去碰 UIContext；
   *   ② **!pageReady** / 错误页：此刻页面还不是站点文档（或根本没有文档），读了也是白读。
   *      ⚠️ 这里**必须**用 pageReady 而不是 loading（本轮修，见 pageReady 的字段注释）：
   *      loading 是启动页的状态，它在 onPageEnd 之后还要再撑 800~1200ms，于是本方法的
   *      "立刻读一次"每次都被自己挡掉、首次读取要等下一个 2s 轮询拍 —— 真机 hilog 实证的
   *      2s 空窗就是这么来的；
   *   ③ App 在后台：把整轮 IPC 省掉 —— 主题在后台变不变对用户没有意义。
   *   ④ --ps colorMode 调试钩子：刻意让位（保证验证者能强制档位）。
   * 稳态下这个 2s 轮询的成本就是"一次取值 + 一次比较"。
   */
  private syncSiteTheme(): void {
    if (this.disposed || !this.pageReady || this.errorMessage.length > 0) {
      return;
    }
    // 后台不做无用 IPC。这一条同时让 EntryAbility 落的 appForeground **第一次有了原生消费者**
    // （此前只有一条注释说"页面侧据此停掉常驻定时器"，而原生侧根本没人读它）。
    if (AppStorage.get<boolean>('appForeground') === false) {
      return;
    }
    // --ps colorMode 调试钩子显式指定了档位：这一轮以它为准，站点同步让位。
    // 否则 Lead 的验证工具会被站点偏好直接覆盖掉，调试通道形同失效。
    if (AppStorage.get<boolean>('debugColorModeForced') === true) {
      return;
    }
    // 只读一个 localStorage 键；JSON.parse 失败/结构不符一律回 'system'，绝不抛到原生侧。
    let js: string = '(function(){try{' +
      'var v=(window.localStorage?window.localStorage.getItem(' +
      JSON.stringify(SITE_THEME_KEY) + '):null);' +
      'if(!v){return "system";}' +
      'var p=JSON.parse(v);' +
      'var t=(p&&typeof p.value==="string")?p.value:"";' +
      'if(t==="dark"||t==="light"){return t;}' +
      'return "system";' +
      '}catch(e){return "read-error";}})()';
    this.runJsFor(js, (raw: string) => {
      if (this.disposed || raw.length === 0 || raw === 'read-error') {
        // 读不到就**什么都不做**（保持现状），而不是强制回"跟随系统" ——
        // 后者会在页面正在导航的瞬间把用户刚选的主题打回去。
        // 边界说明（如实记录）：此时外壳保持**系统档位**。站点在偏好缺失/为 system 时也是
        // 跟随 prefers-color-scheme（ArkWeb 的 WebDarkMode.Auto 让它跟随 app colorMode），
        // 两者同源 ⇒ 不构成"外壳深、网页浅"的分歧；真机未观测到该分支的分歧态。
        return;
      }
      let mode: number = raw === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (raw === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.lastSiteThemeMode = mode;
      if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
        // 站点偏好 = 跟随系统（绝大多数用户的默认值）：外壳继续跟随系统，**一个字节都不下发**。
        // 只有我们**此前下过显式覆盖**时才需要把它释放掉，否则外壳会永远停在旧的显式档位上。
        if (this.siteThemeOverrode) {
          this.siteThemeOverrode = false;
          hilog.info(WEB_DOMAIN, SHELL_TAG, 'site theme system -> release colorMode override');
          this.applyColorMode(mode);
        }
        return;
      }
      // 站点偏好 = 显式深/浅 ⇒ **外壳必须与它一致**。
      // 判据用"外壳当前生效档位"（currentColorMode）而**不是**"上一次读到的偏好"（本轮修）：
      // 拿后者当闸时，外壳一旦因**外部**原因偏离站点偏好（用户在运行中把系统切成深色 /
      // 走 --ps colorMode），站点偏好本身没变 ⇒ 早退 ⇒ 外壳再也不会被拉回来，而网页仍是
      // 站点偏好那一档 ⇒ 稳定态的"顶栏/侧栏按深色上色、网页却是浅色"（白字压浅底，几乎不可读）。
      // 用 currentColorMode 比较同时也是**防自激的闸**：自己 setColorMode 引发的配置回调会让
      // 两者相等 ⇒ 下一次轮询必然早退，环转不起来（C3 闩只负责"这一次回调是不是我引起的"）。
      this.siteThemeOverrode = true;
      if (mode === this.currentColorMode) {
        return;
      }
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'site theme %{public}s -> colorMode %{public}d', raw, mode);
      this.applyColorMode(mode);
    });
  }

  /**
   * 把 colorMode 下发给应用级配置（资源系统据此切档 ⇒ 顶栏玻璃 / 面板 / 状态栏图标一起变）。
   *
   * 必须 try/catch：这是跨进程的应用级配置调用，且调用点里有一处在 runJavaScript 的
   * 异步续作里（不可取消）。失败只留日志，**绝不能把一次主题同步失败升级成崩溃/白屏**。
   *
   * 下发前先落 **C3 回归闩**（目标档位 + 时刻），让 onColorModeChange 能认出
   * "这次配置回调是自己引出来的"。落闩必须在 setColorMode **之前**：回调可能紧随其后到达。
   */
  private applyColorMode(mode: number): void {
    try {
      // 目标档位就是应用当前档位（且不是"跟随系统"）时：系统不会为此发配置更新，
      // 落闩就没人消费 ⇒ 会泄漏到下一次真实变更。此时调用本身也是空操作，直接不下发。
      if (mode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET &&
        this.currentColorMode === mode) {
        return;
      }
      let ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let app: common.ApplicationContext = ctx.getApplicationContext();
      this.siteThemeAppliedMode = mode;
      this.siteThemeAppliedAt = Date.now();
      app.setColorMode(mode);
      // **先落闩、后打日志**：只有 setColorMode 没抛才算落闩成功，日志顺序反了会误导。
      // 这一行是给设备验收用的**歧义消除器**：只有它出现、而下面 onColorModeChange 里
      // 那条 "caused by site theme" 没出现，就说明"配置回调压根没来"（目标档位与生效档位
      // 相同时系统不发配置更新）——**没来就也不会有探测/重载**，不是栅栏漏了。
      hilog.info(WEB_DOMAIN, SHELL_TAG,
        'site theme apply colorMode %{public}d, latch armed', mode);
    } catch (err) {
      // 下发失败就把闩撤掉，免得它悬在那里吃掉一次真实的系统主题变更
      this.siteThemeAppliedMode = SITE_THEME_UNKNOWN;
      let e = err as BusinessError;
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'applyColorMode(%{public}d) failed: %{public}s', mode, e.message);
    }
  }

  /** 启动主题同步：首屏立刻读一次（load 结束这一刻 localStorage 已可读），随后按 SITE_THEME_POLL_MS 值守。 */
  private startSiteThemePoll(): void {
    this.stopSiteThemePoll();
    this.syncSiteTheme();
    this.siteThemeTimer = setInterval(() => {
      this.syncSiteTheme();
    }, SITE_THEME_POLL_MS);
  }

  private stopSiteThemePoll(): void {
    if (this.siteThemeTimer !== -1) {
      clearInterval(this.siteThemeTimer);
      this.siteThemeTimer = -1;
    }
  }

  /**
   * 避让区变化：**优先走轻量通道**，只有通道不可用（脚本还没就绪/被整页刷新清掉）才整注入。
   *
   * 为什么值得单开一条通道：避让区在键盘反复弹出/收起、手势条显隐时会连续变化，
   * 而旧实现每次都把两个脚本（合并前约 2500 行源码）整份重跑一遍。轻量通道只推三个数值
   * 并重跑 ensureTopSpacer / applySafeArea，代价是前者的百分之几。
   * 去抖 100ms：输入法弹出会连发好几次 avoidAreaChange，逐次下发纯属浪费。
   * 同值不推（0.5vp 容差）：系统框复报同一个值时不做任何事。
   */
  private pushInsets(immediate: boolean): void {
    if (this.loading || this.errorMessage.length > 0) {
      return;
    }
    if (!immediate) {
      this.clearTimer(this.insetPushTimer);
      this.insetPushTimer = setTimeout(() => {
        this.insetPushTimer = -1;
        this.pushInsets(true);
      }, INSET_PUSH_DEBOUNCE_MS);
      return;
    }
    // ⚠️ 与 `injectShell()` 的 `__dshTopInsetPx` **必须同源**（同一个常量、同一个算式）：
    // 栏下缘跟着框架标题栏走，两处不同源会让"轻量通道推的值"与"整注入的值"打架。
    let top: number = this.topInset + NAV_TITLE_SLOT_VP;
    let bottom: number = this.bottomInset;
    if (Math.abs(top - this.lastPushedTop) < INSET_EPSILON &&
      Math.abs(bottom - this.lastPushedBottom) < INSET_EPSILON) {
      return;
    }
    // ⚠️ 通道名必须写 `window.__dshShellApi.setInsets` —— 网页侧**有三个名字但只有一份实现**，
    // 别把另外两个当成笔误，也别把这里改回去：
    //   · `window.__dshShellApi.setInsets` = **原生宿主的主用入口**（门面）。它有"通道在不在"
    //     的语义（不在就回 'no-channel'，宿主据此回退整注入），这就是本文件只用它的原因；
    //   · `window.__dshNativeShell.setInsets` = 同一实现的另一挂点，供页面内部复用；
    //   · `window.__dshSetInsets` = 第十八轮由 web 侧为**旧探针名**补的兼容别名。
    //     第十八轮之前本文件探的正是它 —— 而当时它并不存在（全工程零定义），
    // 于是轻量通道恒判"不存在"：避让值虽然写进了 window 全局，但 `ensureTopSpacer()` /
    // `reportRoute()` 这两处真正的几何修正**一次都没被调用过**（键盘弹出后占位高度不重算）。
    let js: string = 'window.__dshStatusBarPx=' + this.topInset.toString() + ';' +
      'window.__dshTopInsetPx=' + top.toString() + ';' +
      'window.__dshBottomInsetPx=' + bottom.toString() + ';' +
      '(function(){try{' +
      'if(!window.__dshShellApi||!window.__dshShellApi.setInsets){return "no-channel";}' +
      'return window.__dshShellApi.setInsets(' + top.toString() + ',' + bottom.toString() + ');' +
      '}catch(e){return "fail";}})()';
    this.lastPushedTop = top;
    this.lastPushedBottom = bottom;
    // out 已由 runJsFor 归一化（§3.0-153）：网页侧 `return 'no-channel'` 到了原生侧是
    // `"no-channel"`（带一对双引号），不归一时下面的全等比较**恒为假** —— 于是"通道不在就
    // 回退整注入"这条兜底从来没有生效过，页面被整页 refresh 清掉外壳后避让值再也推不下去，
    // 而且全程静默（既没注入也没日志）。与账号菜单那处是同一个坑，本轮一起收口。
    this.runJsFor(js, (out: string) => {
      if (out === 'no-channel' || out === 'fail') {
        // 通道不存在（脚本未就绪 / 被整页刷新清掉）→ 回退整注入，绝不能"以为推了其实没推"
        hilog.warn(WEB_DOMAIN, WEB_TAG, 'inset channel unavailable(%{public}s) -> full inject', out);
        this.lastPushedTop = -1;
        this.lastPushedBottom = -1;
        if (!this.disposed) {
          this.injectShell();
        }
      }
    });
  }

  /**
   * 下发一次 `window.__dshShellApi.xxx(...)` 调用（fire-and-forget）。
   *
   * 统一入口的理由：那句"通道存在性守卫"（`window.__dshShellApi &&`）在本文件里有 **10 处**，
   * 而它是有语义的 —— 页面被整页刷新后注入脚本会消失，此时调用必须是**静默无操作**而不是抛错。
   * 散写十遍的后果是：将来通道判据要加一层（例如再加一个版本位）就得改十处，漏一处就是一条
   * 静默断链（与 §3.0-153 同族的"静默失效"）。**需要消费返回值**的调用点不要用它，走 `runJsFor`
   * （那里自带 §3.0-153 的回传归一化）。
   */
  private callApi(expr: string): void {
    this.runJs('window.__dshShellApi && window.__dshShellApi.' + expr);
  }

  /**
   * 刚进入设置页时对齐原生底栏（第二十一轮）：**只归零，绝不派发点击**。
   *
   * ## 为什么归 0、而不是读回网页的选中态
   * 真机实测（2026-09-28）：网页弹层每次打开渲染的都是**第 1 项的内容**，
   * 而它自己的选中 hash 类会残留上次的值（实测「内容 = 通用设置、hash = 服务协议」，
   * 网页自身就不一致）。跟着那个残留态高亮 → 用户看到「高亮服务协议、内容却是通用设置」。
   * ⇒ 以**内容**为准：归 0。
   *
   * ## ⛔ 为什么**删掉了**原先那次 `setSettingsTab(0)` 派发（第二十一轮七改）
   * 用户反馈「系统设置里有些界面每次打开都会刷新一下，转个圈再显示」。
   * 那次「幂等派发」正是元凶：它是对官方页签的一次**真实点击序列**
   * （`pointerdown → mousedown → pointerup → mouseup → click`），官方 tab 组件收到后会
   * **重新挂载内容页**（需要拉数据的页签于是就转一次圈）。
   * 而它要达成的目的（「高亮 = 内容」）**已经由「网页每次打开都渲染第 1 项」这一点天然满足** ——
   * 派发是多余的一步，代价却是每次打开都触发一次重挂载。
   * ⇒ 只设本地高亮，不碰网页。
   *
   * ⚠️ 若将来实测「网页某次打开渲染的不是第 1 项」，**不要**恢复这里的派发 ——
   *    那会重新引入转圈。正确做法是让底栏跟着网页的实际内容走（读回真实下标再设高亮）。
   */
  private onSettingsOpened(): void {
    this.settingsTabIndex = 0;
  }

  /**
   * 点原生底部功能栏（第二十一轮）：先回写本地高亮，再驱动网页切页签。
   *
   * 顺序是有意的：先回写 ⇒ 高亮反馈立刻出现（不等网页往返）。网页那边是幂等派发
   * （重复点同一项只多一次事件），所以这里**不做**「已是当前项就跳过」—— 那条判据在原生侧
   * 拿不到权威值，判错就是静默不切换（详见 ShellScript.setSettingsTab 的注释）。
   */
  private onSettingsTabSelect(index: number): void {
    if (index < 0 || index >= SETTINGS_TABS.length) {
      return;
    }
    this.settingsTabIndex = index;
    this.callApi('setSettingsTab(' + index.toString() + ')');
  }

  /**
   * 顶栏返回键（第二十一轮）：**设置页时关设置浮层**，其余路由保持原语义 `history.back()`。
   *
   * 为什么设置页不能直接 back()：官方设置浮层**不改 URL**，`history.back()` 退的是**聊天页**，
   * 会把用户从设置页直接赶回会话（甚至退到上一个会话）。关闭只能走它自己的 ✕ 入口。
   */
  private onTopBarBack(): void {
    if (this.routeKind === 'settings') {
      this.callApi('closeSettings()');
      return;
    }
    this.callApi('back()');
  }

  private runJs(js: string): void {
    try {
      this.controller.runJavaScript(js).catch((err: BusinessError) => {
        hilog.warn(WEB_DOMAIN, SHELL_TAG, 'runJavaScript failed: %{public}s', err.message);
      });
    } catch (err) {
    }
  }

  /**
   * 下发 JS 并**消费返回值**（fire-and-forget 用上面的 runJs）。
   *
   * 为什么要有这个统一入口：避让通道、深浅色核对、账号菜单三处原本各写一份
   * "外层 try + runJavaScript + then + catch" —— 同一件事三份拷贝。更关键的是，
   * 三份里只要有一份忘了把回传值过 `toJsText()`，就会重演 §3.0-153 那个坑
   * （网页侧 return 'ok'，原生侧拿到的是 `"ok"`，全等比较恒假、**且完全静默**）。
   * 把归一化放进这个唯一入口，等于让"必须归一化"变成结构约束而不是纪律。
   *
   * @param onResult 已经归一化过的字符串（剥掉了 JSON 文本的外层引号）
   * @param onFail   额外失败处理（日志由本方法统一打；这里只放调用方特有的动作，
   *                 例如深浅色核对在探测失败时要整页重载）
   */
  private runJsFor(js: string, onResult: (out: string) => void, onFail?: () => void): void {
    try {
      this.controller.runJavaScript(js).then((res: string) => {
        onResult(toJsText(res));
      }).catch((err: BusinessError) => {
        hilog.warn(WEB_DOMAIN, SHELL_TAG, 'runJavaScript failed: %{public}s', err.message);
        if (onFail !== undefined) {
          onFail();
        }
      });
    } catch (err) {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'runJavaScript threw: %{public}s', (err as BusinessError).message);
      if (onFail !== undefined) {
        onFail();
      }
    }
  }

  /** 避让区变化（状态栏/导航条/输入法）：走轻量通道，通道不可用才整注入。 */
  private onInsetChange(): void {
    this.pushInsets(false);
  }

  /**
   * 主框架开始加载：进启动页、清错误态、复位注入标记，并**重布本次加载的看门狗**。
   *
   * 单独成方法（而不是写在 build() 的回调里）的理由：这三件事必须与 onPageFinished /
   * onLoadFailed / onRenderExited 成对维护，散在 build() 里最容易漏掉其中一处。
   */
  private onPageBegin(): void {
    this.loading = true;
    this.errorMessage = '';
    // 新文档 = 页面上的注入脚本随之消失，ready 时该补注入；注入计数也按文档归零
    this.shellInjected = false;
    this.injectCount = 0;
    // 新文档尚未就绪：站点主题同步这一轮必须让位（见 pageReady 的字段注释）
    this.pageReady = false;
    this.armPageLoadWatchdog();
  }

  private armPageLoadWatchdog(): void {
    this.clearPageLoadWatchdog();
    this.pageLoadWatchdog = setTimeout(() => {
      this.pageLoadWatchdog = -1;
      if (!this.loading || this.disposed) {
        return;
      }
      // 到点仍在加载 = 这次加载既没 onPageEnd 也没报错（弱网超时 / 内核卡住）。
      // 转成错误页而不是继续盖着启动页：错误页自带「重新加载」，把"只能杀进程"变成"一键可恢复"。
      hilog.warn(WEB_DOMAIN, WEB_TAG, 'page load watchdog fired after %{public}dms', PAGE_LOAD_MAX_MS);
      this.loading = false;
      this.errorMessage = '加载超时，请检查网络后重试';
    }, PAGE_LOAD_MAX_MS);
  }

  private clearPageLoadWatchdog(): void {
    this.clearTimer(this.pageLoadWatchdog);
    this.pageLoadWatchdog = -1;
  }

  /** 主框架加载失败（onErrorReceive / onHttpErrorReceive）：结束加载态并给出可见错误页。 */
  private onLoadFailed(message: string): void {
    this.clearPageLoadWatchdog();
    // 这次主框架加载没成：站点文档不在（错误页盖着），主题同步这一轮必须让位
    this.pageReady = false;
    this.loading = false;
    this.errorMessage = message;
  }

  /** 渲染进程退出：同样是"结束加载态 + 可见错误页"，且**必须**清掉加载看门狗。 */
  private onRenderExited(reason: string): void {
    this.clearPageLoadWatchdog();
    // 渲染进程没了：对页面跑 runJavaScript 已经无意义（也不该再跑）
    this.pageReady = false;
    this.loading = false;
    this.errorMessage = '页面渲染进程已退出（' + reason + '），请重新加载';
  }

  private onPageFinished(): void {
    this.clearPageLoadWatchdog();
    // 先清错误态：本次主框架加载已经成功（onPageEnd 到了），早先那一次失败提示必须撤销 ——
    // 否则"先失败后重试成功"会留下一个压在最上层的 ErrorPane（它盖住一切，用户以为一直失败）。
    this.errorMessage = '';
    this.injectShell();
    // 本页的注入已经下发：下面 ready 回执到达时不必再注入一次（见 shellInjected 的说明）
    this.shellInjected = true;
    // 站点主题偏好同步：load 结束这一刻 localStorage 已可读，先立刻读一次
    // （把"站点选了深色但外壳还浅着"的窗口压到最短），随后按 SITE_THEME_POLL_MS 值守
    // （用户当场改主题时原生侧没有事件可等，见 SITE_THEME_POLL_MS 的说明）。
    // ⚠️ 顺序是硬约束：**先置 pageReady 再 startSiteThemePoll** —— 否则这一次"立刻读一次"
    // 会被 syncSiteTheme 的 !pageReady 门控挡掉，首次读取又退回下一个 2s 轮询拍（本轮修）。
    this.pageReady = true;
    this.startSiteThemePoll();
    // 「新建对话」**不能在这里执行**：此刻 SHELL_JS 才刚排队下发（runJavaScript 异步），
    // window.__dshShellApi 还不存在，doNewChat() 里的 `api && api.newChat()` 会被静默吞掉
    // （真机表现：点桌面卡片冷启动进来仍是上一个会话）。改由 ready 回执消费，这里只布兜底。
    if (this.action === 'newChat') {
      this.armNewChatRetry(0);
    }
    this.clearTimer(this.splashTimer);
    this.splashTimer = -1;
    // 仅**首次挂载**布"事件驱动 + 超时兜底"的摘罩（第十六轮）：
    //   首个 `sessions` 桥消息到达 且 已展示满 SPLASH_MIN_MS  → 立刻摘罩（见 requestSplashRelease）
    //   或 SPLASH_MAX_MS 到点                                → 兜底摘罩（见 armSplashDeadline）
    // 后续整页刷新（深浅色 refresh 等）保持"load 结束即摘罩"的旧时序，不拖慢。
    if (!this.splashHeld) {
      this.splashHeld = true;
      this.armSplashDeadline();
    } else {
      this.finishSplash();
    }
  }

  /**
   * 「新建对话」兜底重试：ready 回执没来（或来晚了）时按 800ms 补试，最多 5 次。
   * 每次补试前都重新下发一次注入：注入是幂等的（SHELL_JS 有 alive 守卫），
   * 但能保证 api 一定在页面上 —— 这正是"点了卡片没反应"的根因所在。
   */
  private armNewChatRetry(attempt: number): void {
    this.clearTimer(this.newChatRetryTimer);
    this.newChatRetryTimer = setTimeout(() => {
      this.newChatRetryTimer = -1;
      if (this.action !== 'newChat') {
        return;
      }
      if (attempt >= 5) {
        // 给用户一个明确回声，不再"点了没反应"（这比静默失败好得多）
        hilog.warn(WEB_DOMAIN, SHELL_TAG, 'newChat intent unfulfilled after retries');
        this.action = '';
        this.toast('网页未就绪，请手动点右上角 + 新建对话');
        return;
      }
      this.injectShell();
      this.callApi('newChat()');
      this.armNewChatRetry(attempt + 1);
    }, 800);
  }

  // 系统深浅色切换：与网页媒体查询核对，不一致则刷新，一致则重注入
  private onColorModeChange(): void {
    // —— C3 回归闩：**必须最先消费，且要先于下面的 loading/错误页早退** ——
    //
    // 为什么需要它（Lead 实测的 C3 缺陷，C2 引入）：`syncSiteTheme` → `setColorMode` →
    // `onConfigurationUpdate` → 本方法 → 探 `prefers-color-scheme`。而 **ArkWeb 的
    // prefers-color-scheme 更新滞后于配置回调**，此刻探到的是**旧值** ⇒
    // `(mode === 'dark') !== expectedDark` 成立 ⇒ `reloadPage()` ⇒ **整页重载**。
    // 用户视角：在站点「系统设置」里点一下「深色」，弹层立刻消失、页面重载（取证：
    // performance.timeOrigin 变化 + injectShell 计数归零 + chromium page load start/finished）。
    // 而且站点显式选了深/浅时，页面是靠**它自己的 class** 上色的（r17 已实证
    // prefers-color-scheme 恒 false），本来就与它无关 —— 探测 + 重载纯属误伤。
    //
    // 为什么放在 loading 早退**之前**：setColorMode 若发生在加载期，回调会撞上上面的早退，
    // 闩就没人消费、会泄漏到下一次真实变更（粘滞闩的经典坑）。
    // 为什么不是"粘滞标记"而带时刻：目标档位与当前档位相同时系统不发配置更新，
    // 闩同样没人消费 —— 超窗即按外部变更处理（见 SITE_THEME_SELF_WINDOW_MS）。
    if (this.siteThemeAppliedMode !== SITE_THEME_UNKNOWN) {
      let applied: number = this.siteThemeAppliedMode;
      let selfCaused: boolean =
        Date.now() - this.siteThemeAppliedAt <= SITE_THEME_SELF_WINDOW_MS;
      this.siteThemeAppliedMode = SITE_THEME_UNKNOWN; // 一次性消费，无论是否自证
      if (selfCaused) {
        hilog.info(WEB_DOMAIN, SHELL_TAG,
          'colorMode %{public}d caused by site theme, skip probe/reload', applied);
        return;
      }
      // 超窗才到这里：闩已过期 ⇒ 这次是**外部**变更，按老路径探测/reload（不误吞）。
      // 留一行痕，免得"闩过期因而没生效"与"闩根本没落"在日志上无法区分。
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'site theme latch stale(%{public}dms), treat as external',
        Date.now() - this.siteThemeAppliedAt);
    }
    // —— 站点偏好是**显式**深/浅时：页面靠站点自己的 class 上色，与 prefers-color-scheme 无关 ——
    //
    // 这是第十八轮那条结论的**补完**。原文（本方法下方）已写明：「站点显式选了深/浅时，页面是靠
    // 它自己的 class 上色的（r17 已实证真机 prefers-color-scheme 恒 false），本来就与它无关 ——
    // 探测 + 重载纯属误伤」。但上一轮只堵住了"我自己 setColorMode 引出的回调"（C3 闩），
    // **外部**变更这条没堵：用户运行中把系统切成深色 → 本回调 → 探测（真机恒 'light'）→
    // 与 expectedDark 不等 → **整页 reloadPage()**（草稿、滚动位置、正在生成的回答一起没了），
    // 而重载并不能让页面换主题（站点根本不看这个媒体特性）。
    // 故这一支只做一件事：把外壳拉回站点偏好（syncSiteTheme 会按 currentColorMode 判据收敛），
    // **绝不重载**。这里也不再 injectShell()：显式偏好下页面主题根本没变，没有需要重跑的东西。
    // 站点偏好为 system / 尚未读到（UNKNOWN）时不走这一支 —— 那种情况下页面**确实**依赖
    // prefers-color-scheme，下面那套探测 + 重载的兜底照旧生效。
    if (this.lastSiteThemeMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ||
      this.lastSiteThemeMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      this.syncSiteTheme();
      return;
    }
    if (this.loading || this.errorMessage.length > 0) {
      return;
    }
    let expectedDark: boolean =
      this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    let js: string = `(function () {
      try {
        return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
      } catch (ignore) {
        return 'unknown';
      }
    })()`;
    // ⚠️ 回传值必须归一化（§3.0-153），已由 runJsFor 统一处理：不归一时 `mode` 是 `"dark"` /
    // `"unknown"` 这种**带引号的 JSON 文本**，下面两个全等比较**永远不成立** ——
    // 后果是 (false !== expectedDark) 在深色下恒为 true ⇒ **每次切深色都无条件整页 refresh()**
    // （用户看到的是"切主题时页面闪一下重载"），而"探测结果与网页一致就不必重载"的
    // 省流分支从来没有走到过。这是第十六轮修账号菜单时顺带查出来的同源缺陷。
    this.runJsFor(js, (mode: string) => {
      if (this.disposed) {
        return;
      }
      if (mode === 'unknown' || (mode === 'dark') !== expectedDark) {
        this.reloadPage();
        return;
      }
      this.injectShell();
      // 系统主题变了 → 顺带重读一次**站点偏好**（站点选"跟随系统"时它本该跟着系统走）。
      // 站点选定了深/浅时值没变，会被"同值不重设"挡掉 ⇒ 不会与本次 setColorMode 形成环。
      this.syncSiteTheme();
    }, () => {
      // 探测本身失败（页面正在导航 / 未就绪）也走整页重载 —— 与"探测不到"同义
      this.reloadPage();
    });
  }

  /**
   * 整页重载（深浅色核对不一致时的兜底）。
   *
   * 为什么不直接 `this.controller.refresh()`：`refresh()` 在控制器已随页面销毁时会抛，
   * 而这三处调用点里有**两处在 runJavaScript 的异步续作里**（不可取消），恰好是最容易
   * 落在"页面已经没了"之后的位置。抛出的异常落在一个没有 catch 的 then 里就是一条
   * 未处理的拒绝，且刷新动作本身也丢了 —— 包一层才能既有日志又不炸。
   */
  private reloadPage(): void {
    if (this.disposed) {
      return;
    }
    try {
      this.controller.refresh();
    } catch (err) {
      let e = err as BusinessError;
      hilog.warn(WEB_DOMAIN, WEB_TAG, 'refresh failed: %{public}s', e.message);
    }
  }

  // —— 原生 -> 网页 ——
  private sanitizeId(id: string): string {
    let out: string = '';
    for (let i = 0; i < id.length && i < 64; i++) {
      let c: string = id.charAt(i);
      let ok: boolean = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c === '_' || c === '-';
      if (ok) {
        out += c;
      }
    }
    return out;
  }

  /**
   * 收起原生侧栏。
   * 必须顺手清掉搜索框焦点：真机实测，搜索完直接点会话只关面板不清焦点，输入法键盘
   * 会一直悬在聊天区上；而且键盘会盖住侧栏底部，「打开侧栏自动定位当前会话」定位到
   * 列表末尾时结果正好被键盘挡掉。
   */
  private closeSidebar(): void {
    this.sidebarOpen = false;
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (err) {
    }
  }

  private openSession(id: string): void {
    let safe: string = this.sanitizeId(id);
    if (safe.length === 0) {
      return;
    }
    this.closeSidebar();
    this.callApi("openSession('" + safe + "')");
  }

  private doNewChat(): void {
    this.closeSidebar();
    this.callApi('newChat()');
  }

  private refreshSessions(): void {
    this.callApi('rescan()');
  }

  /**
   * 回网页侧点官方账号菜单里的**白名单项**（现状：`ACCOUNT_OPTION_SETTINGS` /
   * `ACCOUNT_LOGOUT_LABEL` 两项，见文件头两个常量的口径变更史）。
   *
   * 为什么按下发值分支而不是按上游 label 分支：驱动的是**隐藏抽屉里**的官方菜单项，
   * 隔着一次 React 异步渲染 + 纯文案匹配，上游文案一漂移就静默失败。故原生侧只认两个常量，
   * 入参已在 `onPickAccountOption` 收敛过。
   * `label` 会被原样下发给桥侧，而桥侧 `pickAccountOption` 对**同一个白名单**做二次校验，
   * 因此这里不必再判一次（入参已在 `onPickAccountOption` 收敛过）。
   *
   * **为什么要重试**：原生菜单（AlertDialog）与官方菜单（ds-dropdown-menu）之间隔着一次
   * 异步渲染 —— onOpenAccount 只是派发了一次 tap，React 挂载菜单要 100ms 量级。
   * 用户手快时官方菜单还没出来，早先的"查一次、查不到就算"会静默失败：
   * 面板关了、什么都没发生。现在按 `ACCOUNT_RETRY_MS`(140ms) 轮询最多 8 次（约 1.1s），
   * 成功或"重试窗口用尽"都给用户一个明确回声，不再无声失败。
   */
  private pickAccountOption(label: string, attempt: number): void {
    if (attempt > 8) {
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'account option not found: %{public}s', label);
      this.toast('官方菜单未响应，请重试');
      return;
    }
    let js: string = '(function () {\n' +
      '  try {\n' +
      '    var api = window.__dshShellApi;\n' +
      '    if (!api || !api.pickAccountOption) { return \'no-api\'; }\n' +
      '    return api.pickAccountOption(' + JSON.stringify(label) + ');\n' +
      '  } catch (e) { return \'fail\'; }\n' +
      '})()';
    // 回传值由 runJsFor 统一归一化：ArkWeb 把 JS 字符串结果以 **JSON 文本**回传 ——
    // 页面侧 return 'ok' 到了这边是 `"ok"`（带一对引号），拿它和 'ok' 做全等比较**永远不中**。
    // 真机实证（第十六轮第三批）：桥侧日志明明 `row=yes`（也就是返回了 ok），原生侧却一路
    // 重试到 `account option not found`，并在界面上弹"官方菜单未响应"。
    // 这也正是上一轮"点系统设置没反应"的最后一环 —— 当时只重试 'not-found'，
    // 带引号的 `"not-found"` 同样不匹配，于是**既不成功也不提示**（静默断链）。
    this.runJsFor(js, (out: string) => {
      if (this.disposed) {
        // 页面已销毁：再往下走只会重排一个永远不会触发的定时器，或对已销毁的
        // UIContext 弹 toast（这里处于不可取消的 runJavaScript 续作里，必须自己判）
        return;
      }
      hilog.info(WEB_DOMAIN, SHELL_TAG, 'account option res=%{public}s', out);
      if (out === 'ok') {
        hilog.info(WEB_DOMAIN, SHELL_TAG, 'account option done: %{public}s', label);
        return;
      }
      // 除 'ok' 之外**一律重试**（第十六轮补）：
      //   'not-found' 官方菜单还没渲染出来；'no-api' 桥脚本还没注入（整页刷新 / 尚未就绪）；
      //   'fail' 页面侧抛异常。这三者都不是"用户点错了"，而是"这一拍还没到位"。
      // 早先只重试 not-found，另外两种会**静默断链**：面板关了、屏幕上什么都没发生 ——
      // 正是用户报的"点击后不生效"的形态之一。现在它们同样进入重试链，
      // 重试窗口用尽时会给出可见 toast（见方法开头的 attempt > 8 分支）。
      this.clearTimer(this.accountRetryTimer);
      this.accountRetryTimer = setTimeout(() => {
        this.accountRetryTimer = -1;
        this.pickAccountOption(label, attempt + 1);
      }, ACCOUNT_RETRY_MS);
    });
  }

  /** 兜底：会话抽取失败时把官方外壳交还给用户，绝不让侧栏变成死路。 */
  private revealOfficialSidebar(): void {
    this.closeSidebar();
    this.callApi('reveal()');
  }

  // 原先这里有一个 copyLink()（把会话标题 + 官方链接写进系统剪贴板）。第十九轮**删除**：
  // 它唯一的调用者是顶栏右槽的「分享会话链接」，而用户已拍板按 iOS 移除该按钮
  // （iOS 首页与会话页顶栏都只有左右各 1 个按钮）—— 调用链断开后它就是死代码。
  // grep 证据（全工程）：`copyLink` 零命中；随之失去消费者的还有
  // `DEEPSEEK_SHARE_TEXT`（utils/DeepSeekConfig.ets 仍导出，属 W1 作用域，本文件不再 import）
  // 与 `pasteboard`（本文件 import 已收窄）。会话链接的复制入口今后只在网页端。

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
    }
  }

  // —— 「选择上传」接管（官方半模态 bindSheet + 三个系统选择器）——
  //
  // 为什么接管：网页里 `<input type=file>` 被点中时，ArkWeb 若没有实现
  // onShowFileSelector，会自己弹一个系统「选择上传」窗（图库 / 拍照或录像 / 文件 / 取消）。
  // 那个窗由系统绘制，**没有任何进场动效**：真机逐帧取证（280ms/帧的连拍）从点击到
  // 终态一帧不差地全是终态，抓不到任何中间几何。
  // 接管后改用 ArkUI 官方半模态组件 bindSheet 承载同样的三个选项：
  // 弹出/收起动效、遮罩渐显、下拉关闭、圆角与材质全部由系统组件负责（不自己画）。
  //
  // 三条链路各自拉起系统选择器（都不需要额外权限，属"安全控件/临时授权"类）：
  //   图库   → photoAccessHelper.PhotoViewPicker
  //   拍照或录像 → cameraPicker.pick（系统相机）
  //   文件   → picker.DocumentViewPicker
  // 选择器给出的 URI 是**跨应用临时授权**的（file://media/...、file://docs/...），
  // ArkWeb 渲染进程读不了，必须先落成应用沙箱副本再回传（见 stageUploadFile）。

  /** 打开半模态面板（由 onShowFileSelector 调用；multi 来自网页侧的 multiple 属性）。 */
  private openPickerSheet(result: FileSelectorResult, multi: boolean): void {
    // 极端情况：上一次选择还没回传就又被触发（网页侧重复触发/桥异常）——
    // 先给旧请求一个空结果，否则网页侧会永远等不到回调而卡住"上传中"。
    if (this.pendingFileResult !== null) {
      try {
        this.pendingFileResult.handleFileList([]);
      } catch (err) {
      }
    }
    this.pendingFileResult = result;
    this.pendingMultiSelect = multi;
    this.pickerBusy = false;
    this.pickerDecided = false;
    this.pickerSheetShown = true;
    this.armPickerWatchdog();
  }

  /**
   * 「选择上传」看门狗（本轮新增的兜底）。
   *
   * 为什么必须有：`pendingFileResult` 只在"选完 / 取消 / 用户关掉面板"三条路上被清空。
   * 若半模态因故没呈现（bindSheet 静默不呈现是本工程踩过的坑），用户既看不到面板、
   * 也无从取消 —— 这个句柄就一直挂着，网页侧表现为**永远"上传中"**，只能杀进程。
   * 8s 是"用户此刻还在犹豫"与"页面已经卡死"的分界：正常路径上 8s 内一定会发生
   * "选了来源"（pickerBusy=true）/ "点了取消"（pickerDecided=true）/ "面板被关掉"
   * 三者之一，此时看门狗自己让位（见下），不会打断任何真实交互。
   */
  private armPickerWatchdog(): void {
    this.clearTimer(this.pickerWatchdog);
    this.pickerWatchdog = setTimeout(() => {
      this.pickerWatchdog = -1;
      if (this.pendingFileResult === null) {
        return;
      }
      // 用户已动手（选了来源，正在等系统选择器）或已决定取消：不打断
      if (this.pickerDecided || this.pickerBusy) {
        return;
      }
      if (this.pickerSheetShown) {
        // 面板好好地在屏幕上：用户只是还没选，继续等（重排一次看门狗）
        this.armPickerWatchdog();
        return;
      }
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'picker sheet never shown, releasing file selector');
      this.pickerSheetShown = false;
      this.settleFilePick([]);
    }, 8000);
  }

  /**
   * 面板关闭回调（$$ 双向绑定：用户点遮罩/下拉/返回键关闭时框架会把状态写回 false）。
   * 只有"用户没在面板里做过选择"才算取消 —— 选了来源/点了取消时由对应分支自己收尾，
   * 否则会把"已选好文件"的那次选择误判成取消，网页侧收到的就是空列表。
   */
  private onPickerSheetChange(): void {
    if (this.pickerSheetShown || this.pickerDecided) {
      return;
    }
    this.settleFilePick([]);
  }

  /** 取消选择：回一个空文件列表（网页侧据此结束这次 input 事件）。 */
  private cancelFilePick(): void {
    this.pickerDecided = true;
    this.pickerSheetShown = false;
    this.settleFilePick([]);
  }

  /** 把结果回传网页侧并清空待回传状态。 */
  private settleFilePick(uris: string[]): void {
    const pending: FileSelectorResult | null = this.pendingFileResult;
    this.pendingFileResult = null;
    this.pickerBusy = false;
    this.clearTimer(this.pickerWatchdog);
    this.pickerWatchdog = -1;
    if (pending === null) {
      return;
    }
    try {
      pending.handleFileList(uris);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(WEB_DOMAIN, SHELL_TAG, 'handleFileList failed: %{public}s', e.message);
    }
  }

  /** 面板里选了一类来源：先收面板，再拉起对应的系统选择器。 */
  private chooseUploadSource(kind: string): void {
    if (this.pickerBusy) {
      return;
    }
    this.pickerBusy = true;
    this.pickerDecided = true;
    this.pickerSheetShown = false;
    this.clearTimer(this.pickerWatchdog);
    this.pickerWatchdog = -1;
    this.clearTimer(this.pickerLaunchTimer);
    this.pickerLaunchTimer = setTimeout(() => {
      this.pickerLaunchTimer = -1;
      this.runPicker(kind);
    }, PICK_LAUNCH_DELAY_MS);
  }

  private async runPicker(kind: string): Promise<void> {
    // `getUIContext()` 与 `getHostContext()` 都是**可抛/可空**的（§3.0-144）：
    // 面板到定时器之间隔着 200ms，页面理论上可能已经不在。取不到就按取消收尾，
    // 绝不能让网页侧永远停在"上传中"。
    let ctx: common.UIAbilityContext | undefined = undefined;
    try {
      ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (err) {
      ctx = undefined;
    }
    if (ctx === undefined) {
      this.toast('拿不到界面上下文，无法选择文件');
      this.settleFilePick([]);
      return;
    }
    // 上一次选择的沙箱副本此时已无用（网页早已读完并上传），先清掉避免 cache 越堆越大
    this.cleanUploadCache(ctx);
    const maxCount: number = this.pendingMultiSelect ? 8 : 1;
    let uris: string[] = [];
    try {
      if (kind === 'camera') {
        // PickerProfile 是 class，但运行期字段是**只读**的：`new PickerProfile()` 之后再
        // `profile.cameraPosition = ...` 会抛 "Cannot assign to read only property"
        // （真机实测，catch 里只看到这一句、相机根本没起来）。必须用对象字面量构造。
        const profile: cameraPicker.PickerProfile = {
          cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
        };
        const res: cameraPicker.PickerResult = await cameraPicker.pick(ctx,
          [cameraPicker.PickerMediaType.PHOTO, cameraPicker.PickerMediaType.VIDEO], profile);
        if (res !== undefined && res.resultUri !== undefined && res.resultUri.length > 0) {
          uris = [res.resultUri];
        }
      } else if (kind === 'photo') {
        const option: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
        // 只给图片：网页侧 accept 里没有任何视频类型，给视频等于让用户白选一次
        option.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        option.maxSelectNumber = maxCount;
        const res: photoAccessHelper.PhotoSelectResult =
          await new photoAccessHelper.PhotoViewPicker().select(option);
        uris = res.photoUris;
      } else {
        const option: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
        option.maxSelectNumber = maxCount;
        uris = await new picker.DocumentViewPicker(ctx).select(option);
      }
    } catch (err) {
      // 系统选择器里"用户取消"是正常 resolve（返回空列表），不会走到这里 ——
      // 能抛出来的都是真失败（能力缺失/参数非法），必须让用户看见，
      // 否则表现为"点了某一项什么都没发生"（相机 PickerProfile 只读那次就是这样被藏住的）。
      const e = err as BusinessError;
      hilog.warn(WEB_DOMAIN, SHELL_TAG, 'picker %{public}s: %{public}s', kind, e.message);
      this.toast('未能打开选择器：' + e.message);
      uris = [];
    }
    const local: string[] = [];
    for (let i = 0; i < uris.length; i++) {
      const staged: string = this.stageUploadFile(ctx, uris[i], i);
      if (staged.length > 0) {
        local.push(staged);
      }
    }
    if (uris.length > 0 && local.length === 0) {
      this.toast('文件复制失败，未能上传');
    }
    this.settleFilePick(local);
  }

  /**
   * 把选择器给的 URI 复制成应用沙箱副本，返回沙箱绝对路径。
   * 必须复制的原因：图库/相机给的是 `file://media/...`、文档给的是 `file://docs/...`，
   * 这些是"选择器结果临时授权"的跨应用 URI，只有本应用（拿到授权的进程）能读；
   * ArkWeb 的渲染进程按普通文件路径打开它们会失败 —— 表现就是"选完了却什么都没上传"。
   * 复制进 cacheDir 后路径落在应用沙箱内，渲染进程可直接读。
   */
  private stageUploadFile(ctx: common.UIAbilityContext, uri: string, idx: number): string {
    let src: fileIo.File | null = null;
    let dst: fileIo.File | null = null;
    try {
      const target: string = ctx.cacheDir + '/' + UPLOAD_CACHE_PREFIX +
        Date.now().toString() + '-' + idx.toString() + '-' + this.uploadFileName(uri, idx);
      src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      dst = fileIo.openSync(target,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const buf: ArrayBuffer = new ArrayBuffer(64 * 1024);
      let pos: number = 0;
      let read: number = 0;
      do {
        read = fileIo.readSync(src.fd, buf, { offset: pos });
        if (read > 0) {
          // 写侧不传 offset：由目标 fd 的当前位置顺序追加（与 PrismAgent 的导入链路同款写法）
          fileIo.writeSync(dst.fd, buf, { length: read });
          pos = pos + read;
        }
      } while (read > 0);
      return target;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(WEB_DOMAIN, SHELL_TAG, 'stage upload failed: %{public}s', e.message);
      return '';
    } finally {
      if (src !== null) {
        try {
          fileIo.closeSync(src);
        } catch (ignore) {
        }
      }
      if (dst !== null) {
        try {
          fileIo.closeSync(dst);
        } catch (ignore) {
        }
      }
    }
  }

  /** 从 URI 里取一个安全的文件名（保留扩展名：网页侧靠扩展名/MIME 判断文件类型）。 */
  private uploadFileName(uri: string, idx: number): string {
    let base: string = uri;
    const query: number = base.indexOf('?');
    if (query >= 0) {
      base = base.substring(0, query);
    }
    const slash: number = base.lastIndexOf('/');
    if (slash >= 0) {
      base = base.substring(slash + 1);
    }
    // 百分号编码与路径分隔符一律打平：既是防注入，也让文件名在网页侧可读
    base = base.replace(/[^A-Za-z0-9._-]/g, '_');
    if (base.length === 0 || base.indexOf('.') < 0) {
      base = 'upload-' + idx.toString() + '.bin';
    }
    if (base.length > 64) {
      base = base.substring(base.length - 64);
    }
    return base;
  }

  /** 清理上一次选择留下的沙箱副本（只动本应用 cacheDir 里带前缀的文件）。 */
  private cleanUploadCache(ctx: common.UIAbilityContext): void {
    try {
      const names: string[] = fileIo.listFileSync(ctx.cacheDir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].indexOf(UPLOAD_CACHE_PREFIX) === 0) {
          fileIo.unlinkSync(ctx.cacheDir + '/' + names[i]);
        }
      }
    } catch (err) {
    }
  }

  onBackPress(): boolean {
    // 半模态面板是模态：返回键先关它（官方组件会自己播收起动效，这里只负责收尾这次选择）
    if (this.pickerSheetShown) {
      this.cancelFilePick();
      return true;
    }
    if (this.sidebarOpen) {
      this.closeSidebar();
      return true;
    }
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (err) {
    }
    if (Date.now() - this.lastBackToastTs < 2000) {
      return false;
    }
    this.lastBackToastTs = Date.now();
    this.toast('再按一次返回退出');
    return true;
  }

  // —— 视图 ——
  //
  // 第十六轮把原来自绘在本组件上的 @Builder 拆成 **3 个独立 @Component（本文件末尾）**
  // 与 **1 个独立文件（view/TopBar.ets）**。依据只有一条，但很硬：
  // ArkUI 里 **@Entry 根组件上任何一个 @State 变化都会重跑整棵 build()**，而这里的 build()
  // 读到了 17 个状态 —— 启动页逐字跳出（130ms 一次）、侧栏删除进度 `deleteDone++`、
  // 会话列表刷新……每一次都要把 `SideBarContainer` 子树与 **Web 组件的全部属性表达式**
  // 重算一遍。把"只被某一块读到的状态"连它的视图一起下沉之后，重建面从"整页"收窄到"那一块"。
  //
  // 留在本组件里的：路由 / 会话 / 账号 / 删除 / 上传等**跨块共享**的状态与业务逻辑，
  // 以及根层的编排（SideBarContainer + bindSheet + 两个整屏浮层）。
  // 下沉出去的：
  //   · view/TopBar.ets      顶栏（只读 routeKind/title/topPad）
  //   · MainPane             Web + 点击接管层 + 错误页 + 顶栏（层序是强契约，故放同一个组件）
  //   · SplashOverlay        启动页（逐字动画的状态与定时器都在它自己内部，无参）
  //   · NewChatTipLayer      「已是新对话」轻提示（只读 newChatTip/topInset）
  //
  // **两个整屏浮层从 MainPane 里搬到了根 Stack**：轻提示原本就在这一层；启动页原本在
  // `SideBarContainer` 的**内容槽**里，而抽屉是覆盖在内容之上的 —— 抽屉一旦展开就会盖住
  // 启动页（冷启动带 `--ps action openSidebar`、或状态恢复时面板本来就是开的）。
  // 启动页本该盖住包括抽屉在内的整屏，故一并上移。

  build() {
    Stack() {
      SideBarContainer(SideBarContainerType.Overlay) {
        // 侧栏面板贴左、右侧两角圆角 + 投影，自身在 view/SidePane.ets 里完成
        // 状态栏/手势条/输入法三重避让（见该文件顶部说明）
        SidePane({
          panelOpen: this.sidebarOpen,
          sideRows: this.rows,
          totalCount: this.sessionCount,
          topPad: this.topInset,
          bottomPad: this.bottomInset,
          keyboardPad: this.keyboardInset,
          accountName: this.accountName,
          accountAvatar: this.accountAvatar,
          deleteBusy: this.deleteBusy,
          deleteDone: this.deleteDone,
          deleteTotal: this.deleteTotal,
          onOpenSession: (id: string) => { this.openSession(id); },
          onNewChat: () => { this.requestNewChat(); },
          onRefresh: () => { this.refreshSessions(); },
          onReveal: () => { this.revealOfficialSidebar(); },
          onClose: () => { this.closeSidebar(); },
          // 账号菜单：原生侧自己弹一份与官方同选项的菜单（官方那套入口在页面上被外壳接管了）。
          //
          // **不再有 `onOpenAccount`**（第十六轮第三批真机实测后删除）：老链路是"弹原生菜单前
          // 先在网页侧点一次官方账号入口，把隐藏抽屉里的官方菜单展开"，但实测**官方账号入口
          // 点一下打开的就是设置弹层本身**（不再是下拉菜单）—— 预点等于"设置页在原生弹窗背后
          // 被悄悄打开"，用户一取消就残留。现在改成**按需驱动**（用户真的选了某一项才回网页侧，
          // 见 `ShellScript.pickAccountOption`），这个"预开"回调随之成为零消费者，删掉。
          // 原生账号菜单被取消（点对话框外 / 返回键）时把官方菜单一并收起：
          // 官方菜单挂在隐藏抽屉里、且是 toggle 语义 —— 不收掉的话下次点"账号"
          // 会先把它关掉，表现为"点了没反应"。
          onCloseAccount: () => {
            this.callApi('closeAccountMenu()');
          },
          // 第十六轮第三批：菜单恢复为「系统设置」+「退出登录」两项（用户要求恢复设置入口）。
          // 参数 `label` 是跨文件契约（SidePane 的 onPickAccountOption 签名），但这里**按白名单
          // 收敛**：只有 `ACCOUNT_OPTION_SETTINGS` / `ACCOUNT_LOGOUT_LABEL` 会被下发，其余
          // （上游文案漂移、或页面被构造）一律回落到退出登录的确认流程 —— 桥侧 `pickAccountOption`
          // 还有第二道同样的闸门，两道都过不去就不可能有"点中官方菜单其它项"的路径。
          // 前面的 closeSidebar 仍然必需：两项都会在网页侧打开官方界面，
          // 原生侧栏不让开时会被面板盖住（真机实测只剩右半边可见）。
          onPickAccountOption: (label: string) => {
            this.closeSidebar();
            this.pickAccountOption(
              label === ACCOUNT_OPTION_SETTINGS ? ACCOUNT_OPTION_SETTINGS : ACCOUNT_LOGOUT_LABEL, 0);
          },
          onDeleteSessions: (ids: string[]) => { this.startDelete(ids); },
          // 删除安全闩（本轮重做）：网页侧的 deleteSession 必须带上由**本页面生成并保管**
          // 的一次性通行证才可用。旧实现把 armDelete(true) 也暴露在同一个页面对象上，
          // 调试脚本自己开闸即可删 —— 形同虚设（见 rotateDeleteNonce 注释）。
          onSelectModeChange: (on: boolean) => {
            if (on) {
              // 进入选择模式 = 用户在场：生成新通行证（用完即换，见 pumpDelete）
              this.rotateDeleteNonce();
            } else if (!this.deleteBusy) {
              // 落闩只在此处与 pumpDelete 收尾发生；删除队列进行中不落闩（时序见
              // SidePane.exitSelecting）
              this.deleteNonce = '';
              this.callApi('clearDeleteToken()');
            }
          }
        })
        // 主内容区。**直接内联而不是经 `@Builder` 转一层**：`@Builder` 的"值参数不重跑"
        // 语义（§3.0-38）会让这里多一个不必要的失效面，而 `@Prop` 的正常刷新路径最短最稳。
        MainPane({
          controller: this.controller,
          bridge: this.bridge,
          sidebarOpen: this.sidebarOpen,
          topPad: this.topInset,
          bottomPad: this.bottomInset,
          routeKind: this.routeKind,
          title: this.displayTitle(),
          errorMessage: this.errorMessage,
          onCloseSidebar: () => { this.closeSidebar(); },
          // 顶栏返回键：设置页时关设置浮层，其余路由仍走网页 history.back()（见 onTopBarBack）。
          onBack: () => { this.onTopBarBack(); },
          onToggleSidebar: () => { this.toggleSidebar(); },
          onNewChat: () => { this.requestNewChat(); },
          // 重试只需重新装载：loading / errorMessage / 逐字动画都由 configureAndLoad 自己置位，
          // 早先在这里提前写一遍是重复状态（两处各写一半，改一处忘一处就会出现"重试了但还盖着错误页"）
          onRetry: () => { this.configureAndLoad(); },
          onControllerAttached: () => { this.configureAndLoad(); },
          onPageBegin: () => { this.onPageBegin(); },
          onPageEnd: () => { this.onPageFinished(); },
          onRenderExited: (reason: string) => { this.onRenderExited(reason); },
          onLoadFailed: (message: string) => { this.onLoadFailed(message); },
          onBlockedNav: (origin: string) => { this.toast('已拦截站外跳转：' + origin); },
          onPickFile: (result: FileSelectorResult, multi: boolean) => {
            this.openPickerSheet(result, multi);
          },
          // 设置页底部功能栏点选（第二十一轮）→ 驱动网页切页签。
          onSelectSettingsTab: (index: number) => { this.onSettingsTabSelect(index); }
        })
      }
      .showSideBar(this.sidebarOpen)
      // 面板本身已有右边距，宽度略放宽让圆角与投影有呼吸空间。
      // 侧栏容器**必须显式关掉默认分隔线**：SDK 默认会给抽屉与内容之间画一条
      // DividerStyle（strokeWidth 1vp），它在浅色下就是紧贴面板右缘的一条竖向细线；
      // 面板自己已有圆角 + 投影做边界，再叠一条官方分隔线只会在右缘做成"两层面板"的观感。
      .divider({ strokeWidth: 0 })
      .sideBarWidth('82%')
      .minSideBarWidth(220)
      .maxSideBarWidth(352)
      .showControlButton(false)
      .autoHide(false)
      .onChange((value: boolean) => {
        this.sidebarOpen = value;
      })
      .width('100%')
      .height('100%')

      // 轻提示画在 SideBarContainer **之后**：面板展开时它也要看得见（面板里的 ⊕ 也会触发）
      NewChatTipLayer({
        visible: this.newChatTip,
        topPad: this.topInset
      })

      // 启动页画在**最上层**：它要盖住包括侧栏抽屉在内的整屏（见本节开头的说明）
      if (this.loading && this.errorMessage.length === 0) {
        // 逐字动画的状态与定时器都在 SplashOverlay 内部（见该组件的说明）——
        // 这里**不传任何参数**：一旦传参，父组件每次重建都要把参数表达式重算一遍。
        SplashOverlay()
      }

      // ★★ 设置页底部功能栏 = **根 `Stack` 的最后一个子节点（最顶层浮层）**（第二十一轮十一改）。
      //
      // 为什么回到浮层（用户拍板「改回浮层 + 让内容穿过」）：
      //   · 官方工具条那条路虽然**不被遮挡**，但它是**占位式**的 —— Web 视口被压短，
      //     设置页内容到不了屏幕底部 ⇒ 底栏背后永远是纯色 ⇒ 18vp 磨砂**没有内容可糊**，
      //     玻璃感无从谈起；而「内容从胶囊背后穿过」正是玻璃观感的前提；
      //   · 另外官方沉浸光感在工具条位置**本就不生效**（生效范围四类不含工具条，pitfalls 245 号），
      //     即走工具条并没有换来官方材质 —— 两条好处都没有。
      //
      // ⚠️ 被 ArkWeb 盖住的风险要**用真机验证**，不能只靠 Stack 顺序下结论：
      //    真到了「Web 图层翻上来」那一步，下一步是把底栏改成 `bindPopup` 承载
      //    （弹窗层在 Web 之上，且 `PopupCommonOptions` 属官方材质生效的第 ① 类）。
      // 层序：画在 `SplashOverlay` 之后 ⇒ 底栏在最顶层；两者不会同时在场
      //（底栏只在 `routeKind === 'settings'` 上树，那时 `loading` 必为 false）。
      if (this.routeKind === 'settings') {
        Column() {
          SettingsTabBar({
            bottomGap: Math.max(this.bottomInset, TABBAR_BOTTOM_GAP),
            onSelect: (index: number) => {
              this.onSettingsTabSelect(index);
            }
          })
        }
        .width('100%')
        .height('100%')
        // 胶囊贴屏幕底部、下方留「手势条避让」那一段（与 aa-hm 的几何同口径）。
        .justifyContent(FlexAlign.End)
        .padding({ bottom: Math.max(this.bottomInset, TABBAR_BOTTOM_GAP) })
        // ⚠️ 这一层是**整屏高**，必须 `HitTestMode.None`（自身不吃触摸、子节点照吃）：
        //    不写的话它会把整屏的真实触摸一口吃掉（同类事故见 EXPERIENCE 的顶栏丢包带）。
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    // 「选择上传」= 官方半模态组件：弹出/收起动效、遮罩、圆角、材质、下拉关闭全部由系统组件提供。
    // $$ 双向绑定：用户点遮罩/下拉/返回键关掉面板时，框架会把 pickerSheetShown 写回 false，
    // @Watch 据此把这次选择按"取消"收尾（见 onPickerSheetChange）。
    // 半模态**只挂在页面根节点这一个**上（§3.0-137 的硬性要求）。
    .bindSheet($$this.pickerSheetShown, this.PickerSheetContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: false,
      title: { title: '选择上传' }
    })
  }

  // 原先这里有一个 isDarkMode()，唯一用途是把 isDark 透传给顶栏的 brightness 三元
  // （isDark ? DARK_BRIGHTNESS : BLUR_BRIGHTNESS）。第十八轮已把 DARK_BRIGHTNESS 收敛成
  // BLUR_BRIGHTNESS 的**别名**（两者恒等；真机逐像素实测"模糊本身中性"），于是这条链路
  // 退化成"父组件传了、子组件读了、但两个分支同值" —— 传了也没有任何效果，本轮删除。
  // 判据：isDarkMode / isDark 在本文件已零引用（grep 证据见交付报告）。
  // currentColorMode 本身**保留**：它仍被 onColorModeChange 与 applyColorMode 消费，
  // @Watch 的触发与 build() 是否读它无关。

  /**
   * 「选择上传」面板的**一个宫格**（图标在上 + 文案在下）。
   *
   * 第十九轮由"三行列表"改成 iOS 式三宫格（依据：`tmp/r19-audit/ios-shots/crop-attach.png`
   * 一手素材 —— 三个等宽大圆角方块，圆角 16 / 高 76 / 图标 26）。三处口径写在这里：
   *
   * ① **仍然用官方 `Button`**（第十六轮的配方，§3.0-49）：自绘 `Column + onClick` 要自己承担
   *    热区、按压反馈、无障碍与焦点语义，官方组件全部自带。`buttonStyle: TEXTUAL` 去掉按钮自带的
   *    底色/内边距，让方块由我们自己上色。
   * ② **按压反馈走"底色变淡"**（`shell_item_active_bg`）而不是官方 `stateEffect` 的缩放：
   *    这是 iOS 的列表/宫格语义（specs/UI-DESIGN.md §3.1：UIKit 的 highlighted 是变底色），
   *    也让本面板与侧栏列表的按压观感一致；缩放会让方块在手指下"抖"一下。
   * ③ **`layoutWeight(1)` 三个等宽、Row 内横向排布 ⇒ 三块互不重叠** —— 这一点是硬约束：
   *    本工程在"重叠 + 铺满的兄弟容器吃掉整片点击"上踩过 P0（§3.0-159 / UI-DESIGN §7-9），
   *    横排等宽从形态上就不存在那条风险；真实触摸仍要各点一次（§3.0-81）。
   */
  @Builder
  PickerTile(icon: Resource, label: string, desc: string, kind: string) {
    Button({ type: ButtonType.Normal, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: GAP_XS }) {
        SymbolGlyph(icon)
          .fontSize(TILE_ICON)
          .fontColor([$r('app.color.text_primary')])
        Text(label)
          .fontSize(FS_BODY)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    // 三块等宽：父 Row 有确定宽度（width 100%），layoutWeight(1) 均分剩余空间
    .layoutWeight(1)
    .height(TILE_H)
    .backgroundColor($r('app.color.icon_btn_bg'))
    .borderRadius(RADIUS_LG)
    .stateStyles({
      normal: {
        .backgroundColor($r('app.color.icon_btn_bg'))
      },
      pressed: {
        .backgroundColor($r('app.color.shell_item_active_bg'))
      }
    })
    .animation({ duration: MOTION_FAST, curve: CURVE_STD })
    .accessibilityText(label)
    .accessibilityDescription(desc)
    .accessibilityLevel('yes')
    .onClick(() => {
      this.chooseUploadSource(kind);
    })
  }

  /**
   * 「选择上传」官方半模态面板的内容。
   *
   * 只提供内容，弹出/收起动效、遮罩渐显、圆角、材质、下拉关闭全部交给官方
   * bindSheet 组件（见 build() 上的 .bindSheet）—— 不自己画覆盖层、不自己写
   * animateTo：本项目的教训是"自绘看起来像官方"终归是仿的，系统组件的动效
   * 和交互语义（含无障碍、返回键、拖拽）才是官方的那一套。
   *
   * 保留为 `@Builder`（不抽 @Component）的理由：它只在半模态打开时才被构建，
   * 且必须读本组件的 `bottomInset` 做手势条避让；抽出去要为一个"偶尔打开一次的浮层"
   * 多传一份避让参数，收益为负。
   */
  @Builder
  PickerSheetContent() {
    Column() {
      // 三宫格（iOS 形态）：三块等宽、横向排布、互不重叠。
      // 文案按 iOS 对齐：图库→**相册**、拍照或录像→**拍照**（Lead 第十九轮定夺）。
      // ⚠️ 已知偏差（如实记录，不顺手改）：中间那块仍走 cameraPicker.pick([PHOTO, VIDEO])，
      //    即文案叫「拍照」但系统相机里仍可切到录像 —— 按"不改链路"口径保持现状。
      Row({ space: GAP_MD }) {
        this.PickerTile($r('sys.symbol.camera'), '拍照', '使用相机拍照后上传', 'camera')
        this.PickerTile($r('sys.symbol.picture'), '相册', '从相册选择图片上传', 'photo')
        this.PickerTile($r('sys.symbol.doc'), '文件', '从文件中选择文件上传', 'file')
      }
      .width('100%')
      .padding({ left: GAP_XL, right: GAP_XL, top: GAP_MD, bottom: GAP_MD })

      Divider()
        .color($r('app.color.line_color'))
        .strokeWidth(HAIRLINE)
        // 分隔线**不从面板边缘起画**：iOS 的 inset separator 语义（specs/UI-DESIGN.md §3.1）
        .margin({ left: SEP_INSET, right: SEP_INSET })

      Button('取消', { type: ButtonType.Normal, stateEffect: false, buttonStyle: ButtonStyleMode.TEXTUAL })
        .fontSize(FS_TITLE)
        .fontColor($r('app.color.accent'))
        .width('100%')
        .height(ROW_H)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .stateStyles({
          normal: {
            .backgroundColor(Color.Transparent)
          },
          pressed: {
            .backgroundColor($r('app.color.shell_item_active_bg'))
          }
        })
        .animation({ duration: MOTION_FAST, curve: CURVE_STD })
        .accessibilityText('取消')
        .accessibilityDescription('取消选择文件')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.cancelFilePick();
        })
    }
    .width('100%')
    // 手势条避让：内容抬到导航条之上（面板底色由官方组件铺到屏幕底）
    .padding({ bottom: this.bottomInset + GAP_SM })
  }
}

/**
 * 主内容区：Web 聊天区 + 点击接管层 + 错误页 + 顶栏。
 *
 * ## 为什么这四样必须放在**同一个**组件里
 * 它们的层序是**强契约**（Web → 接管层 → 错误页 → 顶栏），任何一层挪错都会造成
 * "按钮点不动"或"内容被盖住"这类只能靠逐像素实测才能发现的缺陷（本工程在接管层上踩过）。
 * 层序写在同一段 build() 里，后人改起来一眼能看全；拆到多个文件只会让它更难发现。
 *
 * ## 层序的两条硬约束（都是实测结论）
 *   ① **接管层必须画在顶栏之下**：面板只占 82% 宽，右上角的 ☰ / ⊕ 露在外面；接管层是整屏
 *      透明层，若排在顶栏之上就会把它们"点死"（真机表现：☰ 明明看得见却点不动）。
 *   ② **错误页必须画在顶栏之下**：错误页是 `height('100%')` 的实底容器，压住顶栏的话
 *      `☰` 也会失效（audit B-6）。故它的内容区用 `topPad + NAV_TITLE_SLOT_VP` 起画，
 *      顶栏照常可点、照常显示标题。
 */
@Component
struct MainPane {
  /** Web 控制器（由父组件持有，本组件只消费）。 */
  controller: webview.WebviewController = new webview.WebviewController();
  /** 网页 → 原生 的桥对象（javaScriptProxy 注入）。 */
  bridge: ShellBridge = new ShellBridge();
  /** 侧栏是否展开：决定要不要铺点击接管层。 */
  @Prop sidebarOpen: boolean = false;
  /** 状态栏高度（vp）。 */
  @Prop topPad: number = 0;
  /** 手势条（底部避让）高度（vp）—— 工具条内容要用它避开系统手势条，否则文字会被那条横杠划过。 */
  @Prop bottomPad: number = 0;
  /** 路由类别（决定顶栏按钮语义）。 */
  @Prop routeKind: string = 'home';
  /** 顶栏标题。 */
  @Prop title: string = 'DeepSeek';
  /** 错误文案：非空即显示错误页。 */
  @Prop errorMessage: string = '';

  /** 点面板外的接管层 → 关侧栏。 */
  onCloseSidebar: () => void = () => {};
  /** 子页返回。 */
  onBack: () => void = () => {};
  /** 侧栏开关。 */
  onToggleSidebar: () => void = () => {};
  /** 新建对话。 */
  onNewChat: () => void = () => {};
  /** 错误页「重新加载」。 */
  onRetry: () => void = () => {};
  /** 控制器就绪（首次装载入口）。 */
  onControllerAttached: () => void = () => {};
  /** 主框架开始加载。 */
  onPageBegin: () => void = () => {};
  /** 主框架加载结束（成功路径）。 */
  onPageEnd: () => void = () => {};
  /** 渲染进程退出（已翻译成人话的原因）。 */
  onRenderExited: (reason: string) => void = () => {};
  /** 主框架加载失败（错误文案）。 */
  onLoadFailed: (message: string) => void = () => {};
  /** 主框架导航被白名单拦下（给出被拦的 origin，用于可见反馈）。 */
  onBlockedNav: (origin: string) => void = () => {};
  /** 网页触发 `<input type=file>`：交给父组件弹官方半模态。 */
  onPickFile: (result: FileSelectorResult, multi: boolean) => void = () => {};
  /** 设置页底部功能栏点选（第二十一轮）：宿主据此驱动网页切页签。 */
  onSelectSettingsTab: (index: number) => void = () => {};


  build() {
    if (OFFICIAL_MATERIAL) {
      // ① 官方档：内容层放进 `Navigation`，顶栏作它的**标题栏**（barStyle: STACK ⇒ 标题栏叠在内容上）。
      //    ⚠️ 官方沉浸光感只在 Navigation/NavDestination 标题栏（或横向 Tabs 底部 TabBar）里生效，
      //       页面正文里挂是**静默无效**（§3.0-245）⇒ 顶栏必须"进栏"。
      //    **沉浸形态（用户 2026-09-25 真机拍板）**：栏本体的模糊由**框架标题栏自己**供给
      //    （`topBarTitleOptions()` 的 `backgroundEffect`）—— `.titleMode(Full)` 下框架栏占窗口顶
      //    0..112vp（**含状态栏那 46vp**），于是模糊从**屏幕最顶连续覆盖到 112vp**：
      //    既没有上缘接缝，也没有"状态栏带 / 标题栏带"的二次分界。
      //    ⛔ 不要改回"节点级 systemMaterial 挂自建 Row"：那会画出**有确定边界的圆角材质带**，
      //       下缘就是一条可见接缝（用户原话"标题栏和页面有明显分界线"；aa-hm R77 同型实测
      //       y=167 顶缘高光 255 / y=356 底缘高光 254，已被用户否决）。
      //    ⛔ 也**不要**再补自绘渐变过渡带（旧的 TOPBAR_FADE_H 装饰层）：它的存在理由
      //       （抹平磨砂方块下缘）已被官方模糊的边缘接替，留着会在自己边缘再产生第二条分界。
      //    几何（真机实测，见 view/TopBar.ets 文件头标定段）：框架 `TitleBar` = 0..332px
      //    （112vp），网页侧让位因此同步收到 **`topInset + NAV_TITLE_SLOT_VP`(45.71+66=111.71vp=332px)**
      //    （见本文件 :1151/:1317 与 ErrorPane / NewChatTipLayer），正文首行不再落进模糊区。
      Navigation() {
        Stack() {
          this.ContentLayers()
        }
        .width('100%')
        .height('100%')
        // Stack 默认 alignContent=Center，内容层会被摆到屏幕中间 —— 必须显式靠顶
        .alignContent(Alignment.Top)
      }
      // 标题栏 = 顶栏一行（材质/模糊档位全在 `topBarTitleOptions()` 里，一行可切）。
      // ⚠️ `.titleMode` 必须显式 **Full**：缺省是 Free（标题随滚动收起/改位）；
      //    Mini 的 56vp 从窗口顶 y=0 起算 ⇒ 状态栏之下只剩 29px、按钮压在时钟上（aa-hm 真机证伪）。
      .title(this.TopBarTitle(), topBarTitleOptions())
      // ⚠️ 底栏**不再**走官方 `Navigation` 工具条（第二十一轮十一改，用户拍板「改回浮层 + 让内容穿过」）。
      //
      // 工具条那条路的账在 `view/SettingsTabBar.ets` 的文件头记着：它**不被遮挡**，但它是**占位式**的 ——
      // Web 视口被它压短 ⇒ 设置页内容到不了屏幕底部 ⇒ 底栏背后永远是纯色 ⇒
      // 那层 18vp 磨砂**没有内容可糊**，玻璃感无从谈起（而用户要的正是「内容穿过」）。
      // 另外官方沉浸光感在工具条位置**本就不生效**（生效范围四类不含工具条，见 pitfalls 245 号）。
      // ⇒ 底栏回到根 `Stack` 的浮层（见 build() 末尾），Web 恢复铺满全屏、内容可从胶囊背后滚过。
      // 工具条全程隐藏。
      .hideToolBar(true)
      .mode(NavigationMode.Stack)
      .titleMode(NavigationTitleMode.Full)
      .width('100%')
      .height('100%')
      // 底色透明：让 Web 自己的 `bg_page` 透出来，避免深浅色切换时闪一层框架默认底色。
      .backgroundColor(Color.Transparent)
    } else {
      // ② 自绘回退档（`OFFICIAL_MATERIAL = false`）：与改前**逐字相同** —— 顶栏作为悬浮浮层
      //    画在 Stack 最上层，自绘 `backgroundEffect` 磨砂 + 渐变过渡带。
      Stack() {
        this.ContentLayers()

        // 悬浮顶栏：画在最上层，自身半透明 + backgroundEffect，因此网页内容滚到它下面
        // 时会被高斯糊化。为让它有东西可糊，Web 组件必须铺满整个窗口（含顶栏那一条），
        // 网页侧再用一条 topInset 高的占位把内容起点推回顶栏下沿 —— 不动 Web 的位置
        // 就永远糊不到内容（旧版 Column{TopBar;Web} 里顶栏下方是空的）。
        TopBar({
          routeKind: this.routeKind,
          title: this.title,
          topPad: this.topPad,
          official: false,
          onBack: this.onBack,
          onToggleSidebar: this.onToggleSidebar,
          onNewChat: this.onNewChat
        })
      }
      .width('100%')
      .height('100%')
      // Stack 默认 alignContent=Center，顶栏会被摆到屏幕中间 —— 必须显式靠顶
      .alignContent(Alignment.Top)
    }
  }

  /**
   * `Navigation.title(...)` 的**标题栏构造器**：栏内只有顶栏那一行（`view/TopBar.ets`，
   * `official: true` ⇒ 栏本体零自绘层、3 个按钮走官方沉浸光感）。
   *
   * 为什么用 `@Builder` 方法而不是全局构建函数：`.title()` 要一个 `CustomBuilder`，
   * 组件成员 `@Builder` 能直接读 `this.routeKind` / `this.title` 等状态 ⇒ 路由或标题一变，
   * 构造器随之重建（全局构建函数的**值参数**不随内容变化重建，§3.0-38）。
   */
  @Builder
  TopBarTitle() {
    TopBar({
      routeKind: this.routeKind,
      title: this.title,
      topPad: this.topPad,
      official: true,
      onBack: this.onBack,
      onToggleSidebar: this.onToggleSidebar,
      onNewChat: this.onNewChat
    })
  }

  /**
   * 内容层：Web + 点击接管层 + 错误页。**层序是强契约**（见本组件头部的说明）：
   * 接管层与错误页都必须画在顶栏**之下**，否则会把 ☰ / ⊕ "点死"。
   *
   * 抽成 `@Builder` 只为让"官方档（放进 Navigation）"与"自绘回退档（放进 Stack）"
   * **共用同一份内容层**，避免两份拷贝漂移；两条路径都留在树上（验收 ③）。
   */
  @Builder
  ContentLayers() {
    Stack() {
      Column() {
        Web({ src: '', controller: this.controller })
          // localStorage / sessionStorage：**必须开**，登录态与网页侧状态都在这里
          .domStorageAccess(true)
          // Web SQL Database：**关闭**（第十六轮，audit §3 内存项）。
          // 依据：网页侧没有任何 WebSQL 使用（该 API 早已从 Chromium 内核移除），
          // 登录态走 cookie + localStorage（见上一行的 domStorageAccess）。
          // 关掉可少一份数据库句柄与其页缓存。
          .databaseAccess(false)
          .javaScriptAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          // 捏合缩放保留：它是系统字体缩放之外的**用户级**可及性能力（audit 提出可关以省内存，
          // 但那属于产品决策，本轮不动，已列入"存疑项"回报）。
          .zoomAccess(true)
          .textZoomRatio(100)
          // 深浅色跟随系统：Auto 让网页的 prefers-color-scheme 与系统一致，
          // 不一致时由 onColorModeChange 触发 refresh 兜底。
          .darkMode(WebDarkMode.Auto)
          .javaScriptProxy({
            object: this.bridge,
            name: 'dshBridge',
            methodList: ['post'],
            controller: this.controller
          })
          .onControllerAttached(() => {
            this.onControllerAttached();
          })
          .onPageBegin((event) => {
            if (event) {
              this.onPageBegin();
            }
          })
          // 渲染进程异常退出（被杀/内存回收/崩溃）时的兜底。
          // 没有它的话：Web 组件留在最后一帧或直接白屏，`loading` 也仍是 false ——
          // Splash 不再显示、ErrorPane 也不出现，用户面对一块"死掉但看着像正常"的页面，
          // 连重试入口都没有。这里把错误态显式置出来（ErrorPane 自带「重新加载」按钮），
          // 把"不可恢复"变成"一键可恢复"。
          .onRenderExited((event) => {
            let reason: string = 'unknown';
            if (event) {
              reason = renderExitReasonText(event.renderExitReason);
            }
            hilog.error(WEB_DOMAIN, WEB_TAG, 'render process exited: %{public}s', reason);
            this.onRenderExited(reason);
          })
          .onPageEnd((event) => {
            if (event) {
              this.onPageEnd();
            }
          })
          .onConsole((event) => {
            if (event) {
              let text: string = event.message.getMessage();
              if (text.indexOf('[DSH') >= 0) {
                hilog.info(WEB_DOMAIN, WEB_TAG, '%{public}s', text);
              }
            }
            return false;
          })
          .onErrorReceive((event) => {
            // 只响应主框架错误：子资源失败会把已加载页面误盖成错误页
            if (event && event.request.isMainFrame()) {
              this.onLoadFailed('加载失败：' + event.error.getErrorInfo());
            }
          })
          .onHttpErrorReceive((event) => {
            if (event && event.request.isMainFrame()) {
              let code: number = event.response.getResponseCode();
              if (code >= 400) {
                this.onLoadFailed('HTTP ' + code.toString() + ' ' +
                  event.response.getReasonMessage());
              }
            }
          })
          .onLoadIntercept((event) => {
            if (event && event.data.isMainFrame() &&
              !isAllowedNavTarget(event.data.getRequestUrl())) {
              // 被拦时给用户可见反馈：早先只是静默 return true，
              // 用户点了一个站外链接会表现为"点了没反应"，像是应用坏了。
              let url: string = event.data.getRequestUrl();
              hilog.info(WEB_DOMAIN, WEB_TAG, 'blocked main frame nav: %{public}s', url);
              this.onBlockedNav(normalizedOriginOf(url));
              return true;
            }
            return false;
          })
          // 网页里点「附件」会触发 `<input type=file>`：实现本回调即接管，
          // ArkWeb 不再弹它那个"没有进场动效"的系统「选择上传」窗（返回 true = 应用自行处理）。
          .onShowFileSelector((event) => {
            let multi: boolean = false;
            try {
              multi = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode;
            } catch (err) {
            }
            this.onPickFile(event.result, multi);
            return true;
          })
          .width('100%')
          .height('100%')
          // 网页底色与原生外壳底色对齐（浅色纯白 / 深色 #1B1B1C），否则 Web 首帧、
          // 整页 refresh 的瞬间会从 bg_page 闪一下网页自己的底色。
          .backgroundColor($r('app.color.bg_page'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))

      // 点击接管层：只负责"点面板外关闭侧栏"，**不再压暗内容**，且必须画在顶栏**之下**。
      // 为什么把遮罩改成全透明（真机/模拟器逐像素实测，见 内部验证记录）：
      //   遮罩把内容区从 24 压到 13，而磨砂面板本色就是 24、原生顶栏本色也是 24 ——
      //   于是面板右边缘出现一条明显的竖向色差线，浅色下则是整片内容发暗，
      //   深色下面板相对邻区"发灰"。去掉压暗后三处同色，细线消失，
      //   深色也不再发灰；同时满足"无任何遮罩"的观感要求。
      if (this.sidebarOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onCloseSidebar();
          })
      }

      // 错误页：排在顶栏**之下**，让它只覆盖内容区（顶栏的 ☰ 仍可点，audit B-6）
      if (this.errorMessage.length > 0) {
        this.ErrorPane()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  /**
   * 错误页：图标 + 标题 + 文案 + 「重新加载」，做成一张卡片（iOS 的 alert-ish 版式）。
   *
   * 入场动效走官方 `.transition()` 而不是 `.animation()`：错误页是 `if` 分支里的节点，
   * **条件渲染没有可播的过渡**（挂载即终值，specs/UI-DESIGN.md §4 的硬性要求）；
   * `.transition(TransitionEffect.OPACITY)` 正是官方给"条件渲染节点出现/消失"的解法。
   */
  @Builder
  ErrorPane() {
    Column() {
      Column({ space: GAP_LG }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(ERROR_ICON_SIZE)
          .fontColor([$r('app.color.text_secondary')])
        Text('连接提示')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.errorMessage)
          .fontSize(FS_LABEL)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Button('重新加载')
          .type(ButtonType.Capsule)
          .height(BTN_H_MD)
          .fontSize(FS_TITLE)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .width('100%')
          // 主按钮的按压反馈同样走"变淡"（`PRESS_OPACITY`）：这是 iOS 的语义，
          // 也与顶栏图标按钮、侧栏列表行保持同一套按压观感。
          .stateStyles({
            normal: {
              .opacity(1)
            },
            pressed: {
              .opacity(PRESS_OPACITY)
            }
          })
          .animation({ duration: MOTION_FAST, curve: CURVE_STD })
          .accessibilityText('重新加载')
          .accessibilityDescription('重新加载网页')
          .accessibilityLevel('yes')
          .onClick(() => {
            this.onRetry();
          })
      }
      .width('100%')
      .padding(GAP_XL)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(RADIUS_MD)
      .shadow({
        radius: SHADOW_R_SM,
        color: $r('app.color.shell_panel_shadow'),
        offsetX: 0,
        offsetY: SHADOW_DY_SM
      })
    }
    .width('100%')
    .height('100%')
    // 顶栏照常显示与可点：错误页只覆盖内容区（audit B-6）
    // 错误页内容区起画于**框架标题栏下沿**：与网页侧让位同源（`topPad + NAV_TITLE_SLOT_VP`）。
    .padding({ top: this.topPad + NAV_TITLE_SLOT_VP, left: GAP_XL, right: GAP_XL })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_page'))
    .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
  }
}

/**
 * 启动页：蓝色鲸鱼 + 标语「探索未至之境」，标语随加载逐字跳出。
 *
 * 三处刻意的取舍（与第十一轮定稿一致，本轮只做令牌化 + 内存优化）：
 *   ① 只留鲸鱼与标语 —— 原来的 "DeepSeek" 标题、LoadingProgress 转圈、"正在打开 DeepSeek ..."
 *      三行字全部去掉（转圈本身也和"逐字跳出"的节奏打架）。
 *   ② 鲸鱼用 startIcon（**透明底**的官方鲸鱼，iconwork/make-starticon.js 生成），
 *      不再给它 borderRadius —— 它本来就不是一张方形卡片，加圆角是把透明区当卡片切。
 *   ③ 每个字一个 Text：只有独立组件才能让新出来的那个字单独播 opacity/scale/translate，
 *      整串 substring 只能"整体换文本"，没有跳出的过程。
 */
@Component
struct SplashOverlay {
  /**
   * 标语已逐字显示到第几个字（0..SPLASH_SLOGAN.length）。
   *
   * **状态与定时器都在本组件内部**（本轮从 Index 根组件下沉）：根组件上这两个状态在启动期
   * 是 7 次 / 130ms 级的自增，而 @Entry 根组件**任何一个 @State 变化都会重跑整棵根 build()**
   * —— 连带 Web 组件的全部属性表达式、SidePane 的 20 个参数、MainPane 的 19 个参数与它们的
   * @Prop 逐项比较。而启动页是**全屏不透明**的覆盖层，背后那一整轮重建用户一眼都看不到。
   * 下沉后逐字跳出只重建这一层。
   */
  @State chars: number = 0;
  /** 鲸鱼是否已入场（挂载后下一拍置 true，才有"从无到有"的变化可播）。 */
  @State logoIn: boolean = false;
  /** 逐字跳出 / 鲸鱼入场两个定时器的句柄（销毁时成对收掉）。 */
  private typeTimer: number = -1;
  private logoInTimer: number = -1;

  /**
   * 标语逐字跳出。
   * 用定时器而不是网页加载进度当驱动：官网首页常常命中缓存、onProgressChange 一帧就到 100，
   * 逐字效果会"一次性全亮"；定时器保证无论多快都有 6 次可见的跳字过程。
   * 每次**挂载**都从 0 重放 —— 错误页重试与整页 refresh 会让根组件的 `loading` 由 false→true，
   * 本组件随之重新挂载，与改动前"每次启动页出现都重放"的语义逐字一致。
   */
  aboutToAppear(): void {
    this.typeTimer = setInterval(() => {
      if (this.chars >= SPLASH_SLOGAN.length) {
        this.stopTyping();
        return;
      }
      this.chars = this.chars + 1;
    }, SPLASH_TYPE_MS);
    // 鲸鱼入场：挂载当拍就把终值写上去等于"没有变化可播"（本项目在扫掠光效上踩过同源坑），
    // 所以延后一拍再置位，让 opacity/scale 真的产生一次变化。
    // 句柄必须留住：页面可能在 60ms 内就被销毁（真机快速切换/返回），那时写 @State 会告警。
    this.logoInTimer = setTimeout(() => {
      this.logoInTimer = -1;
      this.logoIn = true;
    }, 60);
  }

  /**
   * 组件卸载（摘罩 / 页面销毁）：两个定时器一并收掉。
   * 与"本工程任何 setTimeout/setInterval 都必须存句柄、在销毁时 clear"的纪律同源
   * （漏登记的定时器会在销毁后写 @State —— §3.0-144 同族的静默缺陷）。
   * 定时器与组件同生命周期，比原先"句柄挂在根组件上、由根组件的 aboutToDisappear 收"更稳。
   */
  aboutToDisappear(): void {
    this.stopTyping();
  }

  private stopTyping(): void {
    if (this.typeTimer !== -1) {
      clearInterval(this.typeTimer);
      this.typeTimer = -1;
    }
    if (this.logoInTimer !== -1) {
      clearTimeout(this.logoInTimer);
      this.logoInTimer = -1;
    }
  }

  build() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(SPLASH_LOGO_SIZE)
        .height(SPLASH_LOGO_SIZE)
        .objectFit(ImageFit.Contain)
        // `autoResize(true)`：SDK 默认 false（`component/image.d.ts:1014`），即**按原图解码**。
        // `startIcon.png` 实测 1024×1024 / 33,440 B，RGBA 解码缓冲约 4 MB，而这里只显示 168vp
        // —— 开自动缩放后降到 0.1~0.5 MB（audit §3 内存 P0）。
        .autoResize(true)
        // 入场：轻微放大 + 淡入，避免"啪"地出现
        .opacity(this.logoIn ? 1 : 0)
        .scale({ x: this.logoIn ? 1 : 0.88, y: this.logoIn ? 1 : 0.88 })
        .animation({ duration: MOTION_SPLASH, curve: CURVE_STD })

      Row() {
        ForEach(SPLASH_SLOGAN, (ch: string, idx: number) => {
          Text(ch)
            .fontSize(FS_SPLASH)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .opacity(idx < this.chars ? 1 : 0)
            .scale({ x: idx < this.chars ? 1 : 0.4, y: idx < this.chars ? 1 : 0.4 })
            .translate({ y: idx < this.chars ? 0 : 9 })
            .animation({ duration: MOTION_NORMAL, curve: CURVE_STD })
        }, (ch: string, idx: number) => ch + idx.toString())
      }
      // 固定高度：scale/translate 不参与排版，给固定行高可保证下面没有多余位移
      .height(SPLASH_LINE_H)
      .margin({ top: GAP_MD })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_page'))
    // 收尾动效：启动页是 `if` 分支里的节点，**条件渲染没有可播的过渡**（挂载即终值，
    // specs/UI-DESIGN.md §4 的硬性要求）；`.transition()` 是官方给这类节点的解法。
    // 只动 opacity（不参与排版），摘罩时是"淡出"而不是"啪"地消失，与侧栏/错误页同一套语义。
    .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
  }
}

/**
 * 首页「已是新对话」轻提示。
 *
 * 画在**最外层 Stack**（而不是 MainPane 里）的原因：侧栏面板展开时，面板会盖住
 * MainPane 的一切；面板里的 ⊕ 也会触发这条提示，画在面板之上才看得见 ——
 * 而**官方 `bindPopup` 需要一个锚点节点**，本提示的锚点（顶栏的 + 按钮）在面板之下，
 * 弹层会被抽屉裁掉。故这里保留自绘气泡，但**走与错误页卡片同一套规格**
 * （`RADIUS_SM` 圆角 / `HAIRLINE` 描边 / `SHADOW_R_SM` 阴影 / `FS_CAPTION` 字号），
 * 不再是一份独立的视觉配方。
 *
 * 用常驻 + opacity/translate 而不是条件渲染：条件渲染没有可播的过渡（挂载即终值）。
 *
 * ⚠️ **只在外层 Column 上写 `hitTestBehavior(None)` 是不够的**（第十七轮真机实测，见 §3.0-159）：
 * `HitTestMode.None` 的语义是"**自身**不参与命中测试、子节点照常参与" —— 于是这个
 * **不可见**（opacity 0）的气泡一直是可命中的，实测在物理 [1030,290]-[1281,380] 上**吃掉了
 * 该区域的全部触摸**（设置弹层右上角的 ✕ 正好落在那里，表现为"要点好几下才关得掉"）。
 * 气泡是纯装饰（没有 onClick），故内层 Text 也必须显式 `None`；两处一起才是"这层不吃点击"。
 */
@Component
struct NewChatTipLayer {
  /** 是否可见。 */
  @Prop visible: boolean = false;
  /** 状态栏高度（vp）：气泡贴着顶栏下沿。 */
  @Prop topPad: number = 0;

  build() {
    Column() {
      Text('已是新对话')
        .fontSize(FS_CAPTION)
        .fontColor($r('app.color.text_primary'))
        .padding({ left: GAP_MD, right: GAP_MD, top: GAP_SM, bottom: GAP_SM })
        .backgroundColor($r('app.color.shell_item_active_bg'))
        .borderRadius(RADIUS_SM)
        .border({ width: HAIRLINE, color: $r('app.color.line_color') })
        .shadow({
          radius: SHADOW_R_SM,
          color: $r('app.color.shell_panel_shadow'),
          offsetX: 0,
          offsetY: SHADOW_DY_SM
        })
        .accessibilityText('已是新对话')
        .accessibilityDescription('当前已经在新的对话页面上')
        // 纯装饰气泡：必须**自身**也不吃点击，否则不可见时照样挡住右上角（见文件头说明）
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    // 顶栏右下角落：贴着 + 按钮的下沿
    // 轻提示落点同样读框架标题栏下沿（`topPad + NAV_TITLE_SLOT_VP`），与顶栏/错误页同源。
    .padding({ top: this.topPad + NAV_TITLE_SLOT_VP + GAP_SM, right: GAP_MD })
    .alignItems(HorizontalAlign.End)
    .justifyContent(FlexAlign.Start)
    .hitTestBehavior(HitTestMode.None)
    .opacity(this.visible ? 1 : 0)
    .translate({ y: this.visible ? 0 : -GAP_SM })
    .animation({ duration: MOTION_NORMAL, curve: CURVE_STD })
  }
}
