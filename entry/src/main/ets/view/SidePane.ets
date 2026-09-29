// 原生侧栏面板（从 pages/Index.ets 抽出的独立组件）。
//
// 为什么抽出来：
//   1) Index.ets 已 800+ 行，顶栏/侧栏/遮罩/错误页混在一起；侧栏是唯一有局部状态
//      （搜索词、滚动定位、选择模式）的一块，独立后父子契约清晰：**数据与回调进、无副作用出**。
//   2) 抽成组件后可以单独用假数据渲染（临时预览页），纯 UI 的圆角/避让/模糊能在没有登录态
//      的设备上直接截屏验证，不必依赖官方 DOM 抽取成功。
//
// 形态（对齐官方抽屉的剪影）：
//   面板**贴左**、**上避让状态栏**、**下避让手势条与输入法**，右侧两角圆角 + 投影，
//   背景为高斯模糊（磨砂玻璃）。
//   避让在面板**外层容器**用一次 padding 完成，面板内部不再各自补 inset
//   （旧实现在 header 上挂 margin-top、在 footer 上算 height+padding，两处各改一次、
//   且 footer 那次因为 ArkUI 的 padding 在 height 之内而把文字压扁）。
//
// 形态与口径的**规范**在 `specs/UI-DESIGN.md` §3（inset grouped 列表 / 面板结构 / 按压态），
// 这里只记两条实现纪律：① **全部外观值引用 `common/ShellUi.ets` 的令牌**，本文件不再声明任何
// 尺寸/字号/间距/圆角/时长/颜色（本轮把最后 4 个也上收了）；② 本文件只声明**行为时序**常量。

import { SideRow } from '../model/ShellTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';
// 账号菜单走官方「动作菜单」（手机上就是 iOS 式底部弹出条）：
// `promptAction` 从 `@kit.ArkUI` 静态导入是安全的（ArkUI 是系统 Kit；
// 需要 dynamic import 的是 `@hms.*` / HSP 型 Kit，见 §3.0-30）。
import { promptAction } from '@kit.ArkUI';
import {
  AVATAR_SIZE, BLUR_BRIGHTNESS, BLUR_SATURATION, BTN_H_MD, BTN_H_SM, CURVE_STD, EDGE_GAP,
  FS_BODY, FS_BRAND, FS_CAPTION, FS_FOOTNOTE, FS_ICON, FS_LABEL, FS_TITLE, GAP_LG, GAP_MD,
  GAP_SM, GAP_XS, GROUP_ROW_H, HAIRLINE, HOT_MIN, ICON_INLINE, LIST_INSET, LIST_ROW_H,
  MOTION_FAST, MOTION_NORMAL, PANEL_BLUR, PANEL_RADIUS, RADIUS_SM, ROW_H, SEARCH_H, SEP_INSET,
  SHADOW_R_MD, SPINNER_SIZE, ShellIconButton, listItemTransition
} from '../common/ShellUi';

// 面板用到的**全部**外观值都在 common/ShellUi.ets（尺寸 / 图形边长 / 间距刻度 / 圆角 / 字号 /
// 动效时长与曲线 / 模糊 / 阴影 / 最小热区）—— 本文件不再声明任何外观数值，只声明行为时序。
// 为什么连"搜索框 36""头像 28"这种只有一个消费者的值也要上收：同类值在本工程的历史上
// 已经分裂过（审计 U-11：同一个空态转圈 18 与 26 两套；U-5：文字按钮 30 与 32 两套），
// 一个值只能有一个声明点，否则下一次"只改一处"就是缺陷。

/**
 * 定位滚动的补发延时（ms）：虚拟列表首帧可能还没测量完 Item，这一帧的 scrollToIndex 会被丢弃。
 * ⚠️ 这不是"用来补几何量的防抖"：几何量在**面板进场前**就已经算好并滚到位（见 locateIfNeeded），
 * 这里补发的**永远是同一个目标下标**，只处理"这一帧没生效"，不会产生跳变。
 */
const LOCATE_RETRY_MS: number = 60;
/**
 * 下拉刷新指示器的最长停留（ms）。
 * 网页侧的 `rescan()` 没有"完成回执"（它只派发一次抽取，结果由 3s 巡检推回来），
 * 所以指示器不能等一个并不存在的回调：**行数据到达**或**本超时**二者取先复位。
 */
const REFRESH_SETTLE_MS: number = 1500;

/**
 * 把 id 数组摊成 Set（O(1) 查表用）。
 * 写成模块级函数而不是 `new Set(ids)`：ArkTS 下显式循环最稳，且语义一目了然。
 */
function toIdSet(ids: string[]): Set<string> {
  let out: Set<string> = new Set<string>();
  for (let i = 0; i < ids.length; i++) {
    out.add(ids[i]);
  }
  return out;
}

@Component
export struct SidePane {
  /** 侧栏是否展开。父侧变化时清空搜索词、退出选择模式并重新定位当前会话。 */
  @Prop @Watch('onPanelOpenChange') panelOpen: boolean = false;
  /** 拍平后的渲染行（分组标题行 + 会话行）。 */
  @Prop @Watch('onRowsChange') sideRows: SideRow[] = [];
  /** 会话总数（用于底部计数，与 sideRows 长度不同：后者含分组行）。 */
  @Prop totalCount: number = 0;
  /** 状态栏高度（vp）。 */
  @Prop topPad: number = 0;
  /** 手势条高度（vp）。 */
  @Prop bottomPad: number = 0;
  /** 输入法高度（vp），未弹出为 0。 */
  @Prop keyboardPad: number = 0;
  /** 账号昵称（网页侧抽取）。 */
  @Prop accountName: string = '';
  /** 账号头像 URL（网页侧抽取）。 */
  @Prop accountAvatar: string = '';
  /** 批量删除进行中。 */
  @Prop deleteBusy: boolean = false;
  /** 批量删除进度。 */
  @Prop deleteDone: number = 0;
  /** 批量删除总数。 */
  @Prop deleteTotal: number = 0;

  onOpenSession: (id: string) => void = () => {};
  onNewChat: () => void = () => {};
  /**
   * 手动刷新会话列表（下拉列表触发）。
   * 第十六轮起**真的有调用者**了：`build()` 里用官方 `Refresh` 包住列表，
   * 用户下拉即触发（审计 U-2：此前 `onRefresh` 只有声明与传参、工程内无 `Refresh` 组件，
   * 是一条"注释说能下拉刷新、实际根本没有"的死参数）。
   */
  onRefresh: () => void = () => {};
  onReveal: () => void = () => {};
  /** 关闭侧栏（面板内的 × 用）。 */
  onClose: () => void = () => {};
  /** 收起官方账号菜单（原生菜单被取消时调用，避免官方菜单留在展开态）。 */
  onCloseAccount: () => void = () => {};
  /**
   * 选择账号菜单里的某一项。
   * 第十六轮第三批起菜单为**「系统设置」+「退出登录」**两项（「帮助与反馈」维持移除）。
   * 口径变更史：最初是三项 → 因"点击不生效"收成只剩「退出登录」→ 用户要求恢复「系统设置」，
   * 恢复时**没有**退回"自由入参"，而是原生侧与桥侧共用一份**白名单常量**
   * （`ACCOUNT_OPTION_SETTINGS` / `ACCOUNT_LOGOUT_LABEL`），保证可驱动面是封闭集合。
   * "点击不生效"的真因也在第三批查清并修好（`runJavaScript` 回传值带引号 + 隐藏抽屉不接收
   * 点击 + 链路是两步），见 `ShellScript.pickAccountOption` 与 `tapInHidden` 的注释。
   */
  onPickAccountOption: (label: string) => void = () => {};
  /** 批量删除选中的会话。 */
  onDeleteSessions: (ids: string[]) => void = () => {};
  /**
   * 选择模式开关变化。
   * 网页侧的删除接口带"安全闩"：只有这里明确进入选择模式时才会开闸，
   * 任何直接调 `__dshShellApi.deleteSession` 的调试脚本都会被拒（防误删用户数据）。
   */
  onSelectModeChange: (on: boolean) => void = () => {};

  @State queryText: string = '';
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  @State avatarFailed: boolean = false;
  /**
   * 下拉刷新指示器（官方 `Refresh` 的 `$$` 双向绑定目标：用户下拉越过阈值时由框架置 true，
   * 复位由本组件负责，见 settleRefresh）。
   */
  @State refreshing: boolean = false;
  /**
   * 当前会话行的 id —— **渲染层的唯一判据**。
   *
   * 为什么不直接在行内读 `row.active`：`row` 是 `@Builder` 的**值参数**，而 ArkUI 的
   * `@Builder` 值参数**不因内容变化重新求值**（§3.0-38）—— ForEach 复用行组件时，
   * 行内读到的永远是首建时那个 `row`。于是会出现"数据层已经置 1、`activeIndex()` 定位
   * 也正确，但行就是不亮"这种**只在渲染层断链**的缺陷。第十六轮实证（模拟器 + hilog 配对）：
   * Index 侧 `route filled: active=1`、SidePane 侧 `sideRows in: active=1 / filter recomputed:
   * active=1`，而行 `accessibilityDescription` 仍是"会话"、像素无高亮 —— 数据全对，只有渲染层没跟上。
   *
   * 正解与本组件的**勾选态**同款（`isSelected` 那条路径已被 B1 实测证明有效）：把"会变的标记"
   * 提升为 `@State`，行内读 `this.isActive(row)` —— `@State` 只要被 `build()` 读到就登记
   * **元素级依赖**，变化直接驱动该行更新，不依赖 ForEach 是否重建该行。
   */
  @State activeId: string = '';
  private listScroller: Scroller = new Scroller();
  /** 定位滚动的补发定时器（B-8：此前这一类 `setTimeout` 没登记，页面销毁后仍可能跑）。 */
  private locateTickTimer: number = -1;
  /** 下拉刷新指示器的兜底复位定时器。 */
  private refreshTimer: number = -1;
  /**
   * 已经滚到视野中心的是**哪一个会话**（'' = 本次打开还没定位过）。
   *
   * 为什么用 id 而不是布尔标记：定位有"面板打开"与"行数据到达"两条路径，而打开顺手 rescan
   * 会让同一份列表在进场动画期间再送一次 —— 布尔标记表达不了"目标没变、不必再滚"。
   */
  private locatedKey: string = '';

  aboutToAppear(): void {
    // **必须补一次初始消费**：`@Prop` 的 `@Watch` 在初始化时不回调（本工程第七轮已在
    // 预览页实证过同源缺陷）。若面板在页面创建时就是展开态（状态恢复 / 深链 / 启动参数），
    // "清搜索词 + 定位当前会话"这条链路永远不会触发，看起来就像功能坏了。
    // 注意这里**不改 panelOpen**（改它反而会触发一次多余的 Watch），只补跑一次逻辑。
    if (this.panelOpen) {
      this.onPanelOpenChange();
    }
  }

  aboutToDisappear(): void {
    if (this.locateTickTimer !== -1) {
      clearTimeout(this.locateTickTimer);
      this.locateTickTimer = -1;
    }
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  // —— 打开 / 数据变化 ——
  private onPanelOpenChange(): void {
    if (!this.panelOpen) {
      // 关面板即退出选择模式：半开的选择态留到下次打开只会让人困惑。
      // 删除队列仍在跑时**不落闩** —— 那是"用户已确认、网页侧正在逐条删"的进行态，
      // 提前 arm=false 会把剩下几条全部变成 locked（与 exitSelecting 同源的时序缺陷）；
      // 队列走完后由 Index.pumpDelete 收尾落闩。
      let wasSelecting: boolean = this.selecting;
      this.selecting = false;
      this.applySelection([]);
      if (wasSelecting && !this.deleteBusy) {
        this.onSelectModeChange(false);
      }
      // 关面板顺手忘掉"已定位到哪一行"：下次打开要重新把当前会话滚到视野中心。
      // （关闭期间 rows 照样会到，但下面 onRowsChange 的 `panelOpen` 早退保证不会去滚不可见的列表。）
      this.locatedKey = '';
      return;
    }
    // 每次打开都是完整列表，避免"上次搜过、这次打开是空的"错觉
    this.queryText = '';
    this.invalidateFilter();
    // —— 几何量在**进场之前**就算好（本轮修"开合闪一下"）——
    // 旧写法打开时只立"等定位"标记 + 900ms 兜底，真正滚动发生在**行数据到达之后**
    // （打开顺手 rescan，数据 100~300ms 才回来，正落在面板 350ms 进场动画里）⇒ 列表先停在
    // 顶部、再"啪"地跳到当前会话。现在打开当拍就用**手上已有的行数据**定位（面板还在屏幕外、
    // 列表早已布局），第一帧即终态；rescan 数据到达时因"目标会话没变"直接跳过。
    this.locatedKey = '';
    this.locateIfNeeded();
  }

  /**
   * 数据到达时定位（抽取是异步的：面板打开当拍可能还没有行数据）。
   *
   * **幂等**：只在"目标会话变了"时才滚 —— 否则每次 3s 巡检把同一份列表推回来都会把用户
   * 翻到的位置拉走。（旧写法用布尔 pendingLocate，分不清"已定位好"与"数据还没到"：
   * 打开当拍没有行数据时它会立刻作废，等数据真到了反而不定位。）
   */
  private onRowsChange(): void {
    // 诊断日志（第十六轮补，与 Index 的 route/applySessions 日志配对）：
    // 「Index 侧 active 已经置 1，但侧栏不亮」这种缺陷横跨组件边界，
    // 只有两侧都留读数才能判定是"数据没传过来"还是"传过来没渲染"。
    hilog.info(0x0000, 'DeepSeekShell', 'sideRows in: n=%{public}d active=%{public}d',
      this.sideRows.length, this.countActive(this.sideRows));
    // 行数据换了，过滤缓存（含 id 缓存）必须立刻失效（与 queryText 变化时的清空是双保险：
    // 只要有一条漏了，用户就会看到"搜索框里还写着关键词、列表却按新数据没过滤"）
    this.invalidateFilter();
    // 渲染层的"当前会话"标记同步（理由见 activeId 的注释：行内不能读 @Builder 值参数）
    this.syncActiveId();
    // 下拉刷新：行数据到达即视为"这次刷新有结果了"，把指示器收掉（与超时兜底二者取先）。
    // 放在早退分支之前：面板关着时行数据照样会到，指示器不能因此卡在转圈态。
    if (this.refreshing) {
      this.settleRefresh();
    }
    if (!this.panelOpen) {
      return;
    }
    // 空态（"正在读取会话列表…"）不定位：List 还没挂载，scrollToIndex 打在不存在的索引上；
    // 列表落地后会再触发一次 onRowsChange，那时才定位。
    if (this.sideRows.length === 0 || this.filteredRows().length === 0) {
      return;
    }
    // ⚠️ 这里**不要**顺手作废 locateTickTimer：目标没变时 locateIfNeeded 会直接早退，
    // 而那次补发是"首帧布局没完成、第一次 scrollToIndex 被丢弃"的唯一救兵（掐掉就停在列表顶部）。
    this.locateIfNeeded();
  }

  /**
   * 把当前会话滚到列表中心（**幂等**：目标没变就什么都不做）。
   *
   * 为什么要幂等：调用点有两个（面板打开、行数据到达），而"打开侧栏"顺手会 rescan 一次
   * —— 同一份列表会在进场动画期间**第二次**送达；若每次都滚，第二次就发生在动画中途，
   * 用户看到列表"啪"地跳一下。判据用**会话 id**（`activeId`）而不是布尔标记。
   */
  private locateIfNeeded(): void {
    let key: string = this.activeId;
    if (key.length === 0 || key === this.locatedKey) {
      return;
    }
    let idx: number = this.activeIndex();
    if (idx < 0) {
      // 该行被搜索词滤掉、或还没进列表：现在不滚，等行数据/过滤条件变化时再来。
      // 注意**不能**在这里写 locatedKey —— 没滚过就不是"已定位"。
      return;
    }
    this.locatedKey = key;
    this.scrollTo(idx);
    if (this.locateTickTimer !== -1) {
      clearTimeout(this.locateTickTimer);
    }
    // 补发一次**同一个下标**：List 的 Item 由 ForEach 一次性创建、但**布局**是按需的，
    // 目标项还没完成首次布局时这一帧的 scrollToIndex 会被静默丢弃（面板刚打开时最常见）。
    // 因为补发的目标与首次完全相同，它最多是"补上第一跳"，不会造成第二次跳变。
    // 不用 getUIContext().postFrameCallback：它的参数类型 FrameCallback 是**抽象类**，
    // 传箭头函数编译不过（本项目已在别处踩过）。
    this.locateTickTimer = setTimeout(() => {
      this.locateTickTimer = -1;
      this.scrollTo(idx);
    }, LOCATE_RETRY_MS);
  }

  private scrollTo(idx: number): void {
    try {
      // smooth:false —— 面板还在进场动画里，平滑滚动会和面板位移互相干扰
      this.listScroller.scrollToIndex(idx, false, ScrollAlign.CENTER);
    } catch (err) {
    }
  }

  // —— 下拉刷新（官方 Refresh）——
  /**
   * 起兜底复位计时器。
   * 为什么需要兜底：`onRefresh` 只是让网页侧派发一次重新抽取，**没有完成回执**；
   * 若这次抽取没有任何变化（行数据不更新），`onRowsChange` 也就不会触发，
   * 指示器必须靠定时器收掉，否则会一直转（`refreshing` 只有本组件能置回 false）。
   */
  private armRefreshSettle(): void {
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      if (this.refreshing) {
        this.refreshing = false;
      }
    }, REFRESH_SETTLE_MS);
  }

  /** 收尾下拉刷新（幂等）：清定时器 + 落指示器。 */
  private settleRefresh(): void {
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    if (this.refreshing) {
      this.refreshing = false;
    }
  }

  // —— 过滤与定位 ——
  /**
   * 过滤结果记忆化（P2-2；第十六轮补齐"所有路径"）。
   *
   * 为什么需要：`filteredRows()` 在 build 里被调用多次（列表渲染、空态判断、
   * `activeIndex()`、`visibleSessionIds()`、全选判据），每次都要遍历整份行数组并做
   * `toLowerCase()` + `indexOf()`。会话上百条时，侧栏每一次重绘要白跑好几遍。
   *
   * **只按 `queryText` 记忆化，绝不对 @Prop 做缓存**：ArkUI V1 的 @Prop 是单向同步的
   * 值拷贝，父侧换了数组引用时本组件的字段会被覆写而不一定触发我们自己的失效逻辑 ——
   * 把结果挂在 @Prop 上做缓存，漏失效就是"列表明明换了却不更新"这种最难查的隐蔽 bug。
   * `queryText` 是本组件自己的 @State，变化点唯一且可控（onChange 与打开面板时清空），
   * 因此这里只以它为键；`onRowsChange` 里也显式清一次，双保险。
   *
   * 本轮补齐的两处：①**空关键词也走缓存**（旧实现直接 `return this.sideRows`，
   * 于是"清空搜索后 id 缓存仍是上一次的过滤结果"这条路径没有失效点）；
   * ②过滤结果的会话 id 单独缓存（`visibleSessionIds()` 不再是每次 build 都新建数组）。
   */
  private filterCacheKey: string | null = null;
  private filterCacheRows: SideRow[] = [];
  /** 过滤结果里的会话 id；`null` = 尚未计算（懒算，只在选择模式/计数时才要）。 */
  private filterCacheIds: string[] | null = null;

  /** 让过滤缓存失效。三个调用点：行数据变化、搜索词变化、打开面板。 */
  private invalidateFilter(): void {
    this.filterCacheKey = null;
    this.filterCacheIds = null;
  }

  private filteredRows(): SideRow[] {
    let q: string = this.queryText.trim().toLowerCase();
    if (this.filterCacheKey === q) {
      return this.filterCacheRows;
    }
    let out: SideRow[] = [];
    if (q.length === 0) {
      // 无关键词：直接复用父侧数组的引用（不新建、不拷贝，零分配）
      out = this.sideRows;
    } else {
      for (let i = 0; i < this.sideRows.length; i++) {
        let row: SideRow = this.sideRows[i];
        if (row.kind === 'session' && row.text.toLowerCase().indexOf(q) >= 0) {
          out.push(row);
        }
      }
    }
    this.filterCacheKey = q;
    this.filterCacheRows = out;
    // 行集合换了，id 缓存必须跟着作废（同一处赋值，杜绝"两套缓存走岔"）
    this.filterCacheIds = null;
    // 诊断日志：只在**真正重算**时打（缓存命中不打，避免每帧刷屏）。
    // 它回答的问题是"build 拿去渲染的那份数据里，当前会话行到底带没带上 active"。
    hilog.info(0x0000, 'DeepSeekShell', 'filter recomputed: n=%{public}d active=%{public}d q=%{public}s',
      out.length, this.countActive(out), q.length > 0 ? '(key)' : '(empty)');
    return out;
  }

  /** 统计一份行数组里"当前会话"行数（诊断用；与 Index.activeRowCount 配对）。 */
  private countActive(list: SideRow[]): number {
    let n: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i].kind === 'session' && list[i].active) {
        n = n + 1;
      }
    }
    return n;
  }

  /** 把行数据里的"当前会话 id"提到 `@State activeId`（渲染层依赖它，理由见 activeId 注释）。 */
  private syncActiveId(): void {
    let found: string = '';
    for (let i = 0; i < this.sideRows.length; i++) {
      let r: SideRow = this.sideRows[i];
      if (r.kind === 'session' && r.active) {
        found = r.id;
        break;
      }
    }
    if (this.activeId !== found) {
      this.activeId = found;
    }
  }

  /** 某行是否"当前会话"：**只读 `@State`**，不读 `@Builder` 值参数（§3.0-38）。 */
  private isActive(row: SideRow): boolean {
    return row.id.length > 0 && this.activeId === row.id;
  }

  private activeIndex(): number {
    let rows: SideRow[] = this.filteredRows();
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].kind === 'session' && rows[i].active) {
        return i;
      }
    }
    return -1;
  }

  // —— 批量选择 ——
  /**
   * 勾选集合的 O(1) 查表镜像。
   *
   * 为什么要有它：`selectedIds` 是 `string[]`，`indexOf` 是 O(n)；面板每次重绘要按行问一次
   * "这行选中了吗"（n 行 ⇒ O(n²)），`SelectBar` 判"是否全选"还要再扫一遍（审计 §3 P1 项）。
   *
   * **为什么用"引用比较 + 懒重建"而不是自己维护增删**：所有写点都收敛在 `applySelection()`，
   * 每次都换新数组引用，因此"引用没变 ⇒ 内容没变"成立；万一某次引用比较失配，
   * 最坏结果是多重建一次 Set（仍然正确），**不存在"读到过期集合"的方向**
   * （内容变 ⇒ 引用必变）。写点分散去手动增删反而会留下漏同步的隐患。
   */
  private selSetRef: string[] | null = null;
  private selSet: Set<string> = new Set<string>();

  private selectionSet(): Set<string> {
    if (this.selSetRef !== this.selectedIds) {
      this.selSet = toIdSet(this.selectedIds);
      this.selSetRef = this.selectedIds;
    }
    return this.selSet;
  }

  private isSelected(id: string): boolean {
    return this.selectionSet().has(id);
  }

  /** 勾选集合的**唯一写入口**：@State 引用与 O(1) 镜像同步更新。 */
  private applySelection(ids: string[]): void {
    this.selectedIds = ids;
    this.selSet = toIdSet(ids);
    this.selSetRef = ids;
  }

  private toggleSelected(id: string): void {
    if (this.selectionSet().has(id)) {
      let out: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== id) {
          out.push(this.selectedIds[i]);
        }
      }
      this.applySelection(out);
      return;
    }
    let next: string[] = this.selectedIds.slice();
    next.push(id);
    this.applySelection(next);
  }

  /** 当前可见（过滤后）的会话 id。全选只作用于"看得见的那批"，搜索后全选更符合直觉。 */
  private visibleSessionIds(): string[] {
    let rows: SideRow[] = this.filteredRows();
    if (this.filterCacheIds !== null) {
      return this.filterCacheIds;
    }
    let out: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].kind === 'session') {
        out.push(rows[i].id);
      }
    }
    this.filterCacheIds = out;
    return out;
  }

  /**
   * 可见会话是否**全部**已选。
   * 旧实现比的是"选中数 === 可见数"，当选中集合里含有被搜索词滤掉的行时会误判
   * （长度凑巧相等即翻成"取消全选"）——这里改成按集合逐个判定，语义正确且仍是 O(n)。
   */
  private allVisibleSelected(): boolean {
    let ids: string[] = this.visibleSessionIds();
    if (ids.length === 0) {
      return false;
    }
    let sel: Set<string> = this.selectionSet();
    for (let i = 0; i < ids.length; i++) {
      if (!sel.has(ids[i])) {
        return false;
      }
    }
    return true;
  }

  private toggleSelectAll(): void {
    if (this.allVisibleSelected()) {
      this.applySelection([]);
      return;
    }
    this.applySelection(this.visibleSessionIds().slice());
  }

  /**
   * 退出选择模式（UI 侧）。
   *
   * **不在这里落删除安全闩**：删除是异步队列，`confirmDelete` 会先退选择模式再抛出删除请求，
   * 若此处 `onSelectModeChange(false)` 先跑，网页侧收到的 arm=false 会排在 deleteSession 之前
   * → 整批删除被闩拒（返回 locked）且**静默**，用户以为删了其实一条没删（本轮修复的首要缺陷）。
   * 因此落闩只留两个真正的"用户已不在场"时机：
   *   ① 没有删除在跑时退出选择模式；
   *   ② 删除队列走完（`Index.pumpDelete` 收尾，唯一落闩点）。
   */
  private exitSelecting(): void {
    this.selecting = false;
    this.applySelection([]);
    if (!this.deleteBusy) {
      this.onSelectModeChange(false);
    }
  }

  private confirmDelete(): void {
    let n: number = this.selectedIds.length;
    if (n === 0) {
      return;
    }
    let ids: string[] = this.selectedIds.slice();
    let param: AlertDialogParamWithButtons = {
      title: '删除对话',
      message: '将删除选中的 ' + n.toString() +
        ' 个对话，删除后不可恢复；由这些对话生成的分享链接也会失效。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.shell_danger'),
        action: () => {
          // **顺序不能颠倒（本轮真机实测的根因）**：先 `onDeleteSessions` 再 `exitSelecting`。
          // `startDelete` 会同步把父组件的 `deleteBusy` 置 true（普通成员赋值 + @State 赋值
          // 都是同步的），因此随后 `exitSelecting()` 读到的 `deleteBusy` 必为 true —— 它才
          // 不会去落闩。反过来写就会出现：exitSelecting 落闩（下发 clearDeleteToken）→
          // 紧接着的 deleteSession 带的是已经作废的通行证 → 整批返回 locked 一条都删不掉。
          // （这条缺陷第一次修完仍然复现，用页面侧探针记录 set/clear/del 的调用序才定位到
          //   "clear 排在 del 之前" —— 即顺序问题，不是守卫条件问题。）
          this.onDeleteSessions(ids);
          this.exitSelecting();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
  }

  /**
   * 打开账号菜单。
   *
   * 链路（与第十五轮相同）：官方菜单渲染在隐藏抽屉里（用户看不见），必须先在网页侧把它展开，
   * 再在原生侧弹一份同样选项的菜单；选中某一项时回网页侧按**常量文案**点官方那一项。
   *
   * **口径变更史（第十六轮内改了两次）**：先按用户要求把「系统设置」「帮助与反馈」两项去掉
   * （它们要驱动隐藏抽屉里的官方菜单项，隔着 React 异步渲染 + 文案匹配，用户实测"点击后不生效"），
   * 菜单只剩「退出登录」；**本批按用户要求恢复「系统设置」**。恢复时**没有**退回"自由入参"：
   * 原生侧（`Index.onPickAccountOption`）与桥侧（`ShellScript.pickAccountOption`）各有一道
   * **同一份白名单**，只有这两个字面量能下发 —— 保证"可驱动面"是封闭集合（§3.0-93 同源）。
   * 「帮助与反馈」维持移除：用户本轮只点名要求恢复「系统设置」。
   */
  private openAccountMenu(): void {
    // **不再"预点"官方账号入口**（第十六轮第三批真机实测）：官方账号入口点一下打开的就是
    // **设置弹层本身**（不是老版本的下拉菜单），于是在弹原生菜单之前先点一次，会让
    // **设置页在原生弹窗背后被悄悄打开** —— 用户一按取消，它就残留在下面（看起来像"莫名其妙
    // 进了设置页"）。现在改成**按需驱动**：只有用户真的选了「系统设置」，才回网页侧去打开它
    // （见 `ShellScript.pickAccountOption` 的幂等分支）。
    // 旧写法保留在下面一行供对照（**不要**恢复）：
    //   this.onOpenAccount();
    // **形态：居中 AlertDialog → 官方动作菜单（第十九轮，R19）**
    // 依据：iOS 的账号操作是**锚定/底部 action sheet**（不是居中弹窗）；而本工程 §5 的纪律是
    // "能用官方组件就不自绘"。ArkUI 里对应的官方组件是 `UIContext.getPromptAction().showActionMenu()`
    // （SDK 实证：`@ohos.arkui.UIContext.d.ts` 的 `showActionMenu`；`@ohos.promptAction.d.ts:1636`
    //  的 `ActionMenuOptions`，字段 `title` + `buttons`(最多 6 个 `{text, color}`)）——
    // 手机上它渲染为**底部弹出的动作菜单**，正是 iOS 的 action sheet 形态。
    // 旧实现是 `showAlertDialog(AlertDialogParamWithOptions)`：居中、带一段技术口吻的副标题
    // （"这些操作会直接在 DeepSeek 官方页面上执行"）——iOS 的 action sheet **没有副标题**，
    // 且这句话是写给实现者看的、不是写给用户看的，故一并去掉（标题保留用户名，用户仍知道"这是谁的账号"）。
    let param: promptAction.ActionMenuOptions = {
      title: this.accountName.length > 0 ? this.accountName : '账号',
      buttons: [
        { text: '系统设置', color: $r('app.color.text_primary') },
        { text: '退出登录', color: $r('app.color.shell_danger') }
      ]
    };
    // 取消（点菜单外 / 返回键）必须**同样收起官方菜单**：官方菜单是 toggle 语义，
    // 留着展开态会让用户下次点"账号"先把它关掉，表现得像"点了没反应"。
    // ⚠️ 取消的回传形态不唯一（`index < 0` 与 Promise reject 两种都见过），**两条路都要兜**。
    this.getUIContext().getPromptAction().showActionMenu(param)
      .then((res: promptAction.ActionMenuSuccessResponse) => {
        if (res.index === 0) {
          this.onPickAccountOption('系统设置');
        } else if (res.index === 1) {
          this.onPickAccountOption('退出登录');
        } else {
          this.onCloseAccount();
        }
      })
      .catch(() => {
        this.onCloseAccount();
      });
  }

  // —— 视图 ——
  // 图标按钮**没有**本文件自己的配方：直接调 `common/ShellUi.ets` 的全局构建函数
  // `ShellIconButton`。原先这里有一个只做转发的 `PanelIcon`，转发层本身就是"第二份配方"
  // （改令牌的人得先判断该改哪一层），零收益，本轮删除（§RULES "同类控件只留一套配方"）。

  /**
   * 文字按钮（胶囊 + TEXTUAL），走 §3.0-49 的官方配方。
   * 面板里的「完成 / 全选 / 取消全选」都用它，高度锁 `BTN_H_SM` —— 同类文字按钮一个高度，
   * 不要一个 30 一个 32 地各写一份（审计 U-5）。
   *
   * `.responseRegion()` 把**可点高度**补到 `HOT_MIN`(44)：可见胶囊仍是 32，手指范围满足
   * iOS HIG 的 44×44 下限。只补高度 —— 宽度由文字决定，最短的「完成」也有 50vp 以上。
   */
  @Builder
  TextAction(label: string, action: () => void) {
    Button({ type: ButtonType.Capsule, stateEffect: true, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Text(label)
        .fontSize(FS_LABEL)
        .fontColor($r('app.color.accent'))
        .fontWeight(FontWeight.Medium)
    }
    .height(BTN_H_SM)
    .padding({ left: GAP_MD, right: GAP_MD })
    .backgroundColor(Color.Transparent)
    .responseRegion({ x: 0, y: -(HOT_MIN - BTN_H_SM) / 2, width: '100%', height: HOT_MIN })
    .accessibilityText(label)
    .accessibilityDescription(label)
    .accessibilityLevel('yes')
    .onClick(action)
  }

  /** 面板内的发丝线：左右内缩 `SEP_INSET`（`specs/UI-DESIGN.md` §3.2 第 2/6 条），粗细走 `HAIRLINE`。 */
  @Builder
  Hairline() {
    Divider()
      .color($r('app.color.line_color'))
      .strokeWidth(HAIRLINE)
      .margin({ left: SEP_INSET, right: SEP_INSET })
  }

  @Builder
  PanelHeader() {
    Row() {
      if (this.selecting) {
        Text('已选 ' + this.selectedIds.length.toString() + ' 项')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        this.TextAction('完成', () => {
          this.exitSelecting();
        })
      } else {
        Text('DeepSeek')
          .fontSize(FS_BRAND)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        // 图标按钮组：组内间距与顶栏右槽同源（`Row({ space: GAP_XS })`）。旧实现是三个平铺
        // 按钮 —— 组内间距只剩"44 盒减 21 字形"的 23vp 隐式留白，与顶栏的显式 4vp 两套观感。
        Row({ space: GAP_XS }) {
          // 批量选择的入口。原先是一个蓝色文字按钮「选择」，与旁边的 ⊕ / × 两个圆形
          // 图标按钮风格不一致（面板头部只有它一个是文字）；现改为同款圆形图标按钮
          // （list_checkmark = 带勾的清单，符号名已在 SDK id_defined.json 实证）。
          // 第 4 个实参 `raised=false`：面板头部是**三个相邻按钮**，且抽屉形态**没有 iOS 参考素材**
          // （R19 W4 的 ios-reference.md §6：App Store 10 张官方截图里没有一张是抽屉展开态，
          //  侧栏形态为 C 级「未找到可靠来源」）⇒ 不引入顶栏那套"浅底圆"（三个圆贴在一起会连成一块），
          // 保持"裸图标"并与旁边的 × 同款。**顶栏传 true**（那里有 A 级截图实证）。
          ShellIconButton($r('sys.symbol.list_checkmark'), '选择对话', () => {
            this.selecting = true;
            this.applySelection([]);
            this.onSelectModeChange(true);
          }, false)
          ShellIconButton($r('sys.symbol.plus'), '新建对话', () => {
            this.onNewChat();
          }, false)
          // 面板内收口：面板占 82% 屏宽，顶栏的 ☰ 被盖在面板之下（屏幕派发按"最上层可命中
          // 组件"选择目标，实测展开态点 ☰ 收不到事件），所以关闭入口必须给在面板自己里面。
          ShellIconButton($r('sys.symbol.xmark'), '关闭侧栏', () => {
            this.onClose();
          }, false)
        }
      }
    }
    .width('100%')
    .height(ROW_H)
    // 左 16 / 右 8：44 的圆形按钮自带 4vp 视觉内边距，右侧贴 8 才不会显得压边
    // （令牌 ICON_BTN 40 → 44 后头部仍有余量：16 + 品牌名 + 3×44 + 8 ≈ 244 < 面板 308vp）。
    .padding({ left: GAP_LG, right: GAP_SM })
  }

  /**
   * 搜索框。
   *
   * 第十五轮改为**官方 `Search` 组件**（P2-1）：原先用 `Row { SymbolGlyph + TextInput + 清除图标 }`
   * 自绘，问题有三个 —— ①清除按钮只有 16vp 图标那么大的热区（远低于 40vp 下限），
   * 手指很难点中；②占位符/光标/清除按钮的显隐时机全要自己管；③无障碍语义为零。
   * 官方组件把这三件事都包了：`cancelButton` 自带 ≥40vp 热区与"有内容才出现"的语义，
   * `searchIcon` 由主题着色，`onChange` 语义与 TextInput 一致。
   *
   * 第十六轮改**内缩口径**（审计 U-14）：旧实现是 `Search` 自己挂 `margin({left:12,right:12})`，
   * 与同面板其它地方（`padding`）两套口径 —— ArkUI 的百分比宽度按**父 content-box** 解析、
   * margin 不参与扣减，右侧有被裁的风险（§3.0-141 同源：百分比宽度 + 父容器边距就是溢出）。
   * 现在由外层 `Column` 用 `padding` 统一内缩 `LIST_INSET`，`Search` 自己 `width('100%')`
   * 正好铺满"内缩后的内容区"，与列表卡片的左右边缘对齐。
   */
  @Builder
  SearchRow() {
    Column() {
      Search({ value: this.queryText, placeholder: '搜索会话' })
        // searchIcon 吃的是 IconOptions（不是 Resource）：SDK search.d.ts 里
        // `searchIcon(value: IconOptions | SymbolGlyphModifier)` —— 直接喂 $r(...) 编译不过。
        .searchIcon({ size: ICON_INLINE, color: $r('app.color.text_secondary'),
          src: $r('sys.symbol.magnifyingglass') })
        .placeholderColor($r('app.color.text_secondary'))
        .placeholderFont({ size: FS_BODY })
        .textFont({ size: FS_BODY })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .height(SEARCH_H)
        // `chip_bg` → `field_bg`（第十九轮，R19）：搜索框此前借用"能力 chip"的底色，
        // 而 chip 是**品牌蓝调**的（浅 #E9EEF9 / 深 **#1E2A44 深海军蓝**）——真机深色基线上
        // 它渲染成一块**深蓝底贴在浅色面板上**（tmp/r19-baseline/dark-side.jpeg），既突兀又不是
        // iOS 形态（iOS 搜索字段是**中性灰**：浅 systemGray5 / 深 systemGray6）。
        // 新键 `field_bg` 浅 #E5E5EA / 深 #1C1C1E，**深浅两文件逐键成对**（UI-DESIGN §1 第 4 条）。
        .backgroundColor($r('app.color.field_bg'))
        .borderRadius(RADIUS_SM)
        // 官方「搜索」按钮（第二十一轮新增）：输入关键词后出现在框右侧，点击 = 收起键盘 + 提交。
        // 与 iOS 的 SearchBar「搜索」键同形态；SDK `searchButton(value, option)`（@since 8，
        // `search.d.ts:524`），点击触发 `onSubmit`（同软键盘搜索键）。
        // `fontColor: accent` 与全工程文字按钮同色；`fontSize: FS_BODY` 与框内文字同档。
        .searchButton('搜索', { fontSize: FS_BODY, fontColor: $r('app.color.accent') })
        .onSubmit(() => {
          // 与 iOS 一致：点「搜索」= 收起键盘，过滤结果已经在输入过程中实时更新。
          this.getUIContext().getFocusController().clearFocus();
        })
        .onChange((value: string) => {
          this.queryText = value;
          // 过滤结果按 queryText 记忆化：queryText 一变就得让缓存（含 id 缓存）整体失效
          this.invalidateFilter();
        })
    }
    .width('100%')
    .padding({ left: LIST_INSET, right: LIST_INSET, top: GAP_XS, bottom: GAP_SM })
    // 搜索区进出（选择模式切换）用纯 opacity 过渡：只改不参与排版的属性，
    // 动 width/height/padding 会每帧重排（`specs/UI-DESIGN.md` §4 硬性要求）。
    .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
  }

  @Builder
  SessionRow(row: SideRow) {
    Row() {
      if (this.selecting) {
        // 勾选圈比按钮图标略小（ICON_INLINE 18 < FS_ICON 21）：它要与行内文字同高，取 21 会把行撞高
        SymbolGlyph(this.isSelected(row.id) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(ICON_INLINE)
          .fontColor([this.isSelected(row.id) ? $r('app.color.accent') : $r('app.color.text_secondary')])
          .margin({ right: GAP_SM })
      }
      Text(row.text)
        .fontSize(FS_BODY)
        .fontColor(this.isActive(row) && !this.selecting ? $r('app.color.accent') : $r('app.color.text_primary'))
        .fontWeight(this.isActive(row) && !this.selecting ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(LIST_ROW_H)
    // 行内容左边缘 = SEP_INSET，与上下两条 `List.divider` 的 startMargin 取同一个值 ——
    // iOS 的 inset separator 就是"分隔线从文字起始处起画"，两者必须同源才对得齐。
    .padding({ left: SEP_INSET, right: SEP_INSET })
    .borderRadius(RADIUS_SM)
    .backgroundColor(this.selecting && this.isSelected(row.id)
      ? $r('app.color.shell_item_active_bg')
      : (this.isActive(row) && !this.selecting ? $r('app.color.shell_item_active_bg') : Color.Transparent))
    // 按压反馈（官方 stateStyles 配方，与 PickerRow 同款）：
    // 行本来只有选中态、没有"按下瞬间"的反馈，手指压下去到位移前有一段无响应窗口。
    .stateStyles({
      normal: { .backgroundColor(this.selecting && this.isSelected(row.id)
        ? $r('app.color.shell_item_active_bg')
        : (this.isActive(row) && !this.selecting ? $r('app.color.shell_item_active_bg') : Color.Transparent)) },
      pressed: { .backgroundColor($r('app.color.shell_item_active_bg')) }
    })
    // **必须写在 backgroundColor / stateStyles 之后**：`.animation()` 只作用于它前面已声明的属性。
    // 选中/激活/按压的底色因此是"过渡"而不是硬切（`specs/UI-DESIGN.md` §3.1、时长 MOTION_FAST）。
    .animation({ duration: MOTION_FAST, curve: CURVE_STD })
    // 无障碍：行内只有一个 Text，读屏需要知道"这是一条会话、名字是什么"；
    // 选择模式下描述换成"已选/未选"，`uitest dumpLayout` 也能据此断言勾选态。
    .accessibilityText(row.text)
    .accessibilityDescription(this.selecting
      ? (this.isSelected(row.id) ? '已选' : '未选')
      : (this.isActive(row) ? '当前会话' : '会话'))
    .accessibilityLevel('yes')
    .onClick(() => {
      if (this.selecting) {
        this.toggleSelected(row.id);
      } else {
        this.onOpenSession(row.id);
      }
    })
  }

  /**
   * 会话列表（inset grouped）。
   *
   * **为什么仍然"拍平"成 `ListItem`，不用官方 `ListItemGroup({header})` + `.sticky(StickyStyle.Header)`**：
   * 吸顶分组头要把现在的一维 `SideRow[]`（分组标题行 + 会话行）重构成二维（分组 → 行），
   * 而 `ListItemGroup` 是**整体重建**粒度：组内任意一行变化都会重建整个组；
   * 这直接打回 P0-2 刚刚定下的"标题变化只重建那一行、勾选只刷新相关元素"的刷新粒度
   * （第十四轮返工修复的正是"侧栏标题停在旧值"，见 内部验证记录 §2.9）。
   * 要在保留粒度的前提下拿到吸顶头，需要自己做"漂浮分组头 + 滚动位置联动"的替代实现，
   * 属单独一轮的活。本轮的取舍：**保刷新粒度**（正确性优先），分组语义用"分组标题行 +
   * 行间分隔线 + 缩进"表达到位；因此也**不做分组圆角卡片底色** ——
   * 拍平模型下一行一卡（`RADIUS_SM` 圆角 + 选中/按压底色），这与 iOS 侧边栏的观感一致。
   */
  @Builder
  SessionList() {
    List({ scroller: this.listScroller }) {
      ForEach(this.filteredRows(), (row: SideRow) => {
        ListItem() {
          if (row.kind === 'group') {
            Text(row.text)
              .fontSize(FS_CAPTION)
              .fontColor($r('app.color.shell_group_text'))
              .width('100%')
              .height(GROUP_ROW_H)
              .padding({ left: SEP_INSET })
              .textAlign(TextAlign.Start)
          } else {
            this.SessionRow(row)
          }
        }
        // 官方进/退场转场（第二十一轮）：新行滑入 + 淡入，被删行淡出（位移会"对穿"补位行）。
        // 令牌与依据见 common/ShellUi.ets 的 listItemTransition()；只作用于组件插入/删除，
        // 不影响行内按压/选中过渡（那条仍走 .animation()，两者互不干扰）。
        .transition(listItemTransition())
        // key 必须含**所有会变的字段**：`sideRows` 是普通 interface（非 @Observed），
        // 行内容变化只能靠 key 变化触发重建。早先漏了 `row.text`，于是"首条消息发出后
        // 官方自动命名"这种**只改标题**的变化不会重建该行，侧栏标题永远停在旧值
        // （原生顶栏因为走 displayTitle() 读同一份数据，会出现"顶栏变了、侧栏没变"的观感）。
        // P0-2 的这条修复**不得回退**：`row.text` 是"非响应式数据字段"，没有依赖可登记，
        // 只有进 key 才有刷新路径（§3.0-138：key 相同 ⇒ 复用组件 ⇒ 值参数 @Builder 不重跑）。
        // 注意：`row.active` **不在**此列 —— 同理可证它"读得到但不会触发刷新"（B8 实证），
        // 所以它改走 `@State activeId`（见下面第十六轮那段说明），而不是靠 key 兜。
        // 不把行号写进 key：id 本身已唯一，加下标会让"列表重排"变成全量重建。
        //
        // 第十六轮**把勾选态移出 key**（审计 §3 P1）：旧 key 里含 `this.isSelected(row.id)`，
        // 那是每行一次 `indexOf` ⇒ 生成全部 key 是 O(n²)，且每点一次勾选就要重跑整轮 key 比较。
        // 勾选态不需要进 key：它是**本组件的 @State**，行内的 `this.isSelected(...)` 读取会在
        // **元素级**登记依赖，`selectedIds` 一变，这些元素自己重绘（与"非响应式数据字段"不同，
        // 后者没有依赖可登记才必须进 key）。于是勾选只刷新相关元素，既没有 O(n²) 也不掉刷新。
        //
        // 第十六轮**"当前会话"同理移出 key**（B8 实证：`row.active` 进 key 是**不可靠的刷新路径**）：
        // 实测数据层 `active=1` 时行仍不亮 —— 因为 key 是否变化依赖 `filteredRows()` 在**这一次
        // build 里**是否已拿到新数据，而 @Watch 里的缓存失效与 build 的求值顺序不受我们控制。
        // 现在改由 `@State activeId` + 行内 `this.isActive(row)` 驱动（元素级更新，与勾选态同一条路），
        // 既确定生效，也免掉"切换会话时把带 `:1` 的新 key 铺开、逼整表比较一遍"的开销。
      }, (row: SideRow) => row.key + ':' + row.text)
    }
    .width('100%')
    .height('100%')
    // inset grouped：列表整体左右内缩 LIST_INSET，行卡片再各自留 SEP_INSET 的内容内边距。
    .padding({ left: LIST_INSET, right: LIST_INSET, top: GAP_XS, bottom: GAP_SM })
    // 分隔线用官方 `List.divider`（不自己画 Divider 节点）：左右各内缩 SEP_INSET，
    // 从文字起始处起画而不是齐边（iOS inset separator 的关键细节，`specs/UI-DESIGN.md` §3.1）。
    .divider({
      strokeWidth: HAIRLINE,
      color: $r('app.color.line_color'),
      startMargin: SEP_INSET,
      endMargin: SEP_INSET
    })
    .scrollBar(BarState.Off)
    // 不设 cachedCount：SDK 原文（component/list.d.ts）—— 默认值 = **屏内可见的节点数**（上限 16），
    // 语义是"可视区上下各预加载并布局 N 行"。旧值 6 反而**低于**默认（本面板列表可见约 12~13 行），
    // 是往回退优化；ForEach 下所有子组件本已一次性创建，cachedCount 只影响布局预取，
    // 故直接删掉、回到官方默认（第十六轮实测依据见 内部验证记录 报告）。
    //
    // 为什么仍然保留 `ForEach` 而不是换 `LazyForEach`：真实登录态实测会话数 56~57 条
    // （audit §0），上限按 100 估；此时 ForEach 建约 300 个节点，LazyForEach 省下的内存
    // 在 300 节点量级上不足以抵消它的代价（要引入 IDataSource、把行数据与 key 的关系
    // 全部改写成 notifyDataChange 驱动，且会动到 P0-2 刚定下的 key 刷新语义）。
    // 结论：会话量级再上一个数量级（≥500）时再评估。
  }

  /**
   * 空态①：会话列表还没读到（首次进入 / 桥没回来）。
   *
   * 两个空态各写一个 Builder、**都不带值参数**：`@Builder` 的值参数不会因内容变化重建
   * （§3.0-38 / §3.0-46），空态里的文案若走值参数，搜索词一变就会停在旧值。
   * 统一的是"规格"而不是"代码"：同一档字号（FS_LABEL）、同一档转圈（SPINNER_SIZE）、
   * 同一组间距（GAP_SM/GAP_XS）—— 审计 U-11 指出旧实现是 18 与 26 两套转圈尺寸。
   */
  @Builder
  LoadingPlaceholder() {
    Column({ space: GAP_SM }) {
      LoadingProgress()
        .width(SPINNER_SIZE)
        .height(SPINNER_SIZE)
        .color($r('app.color.accent'))
      Text('正在读取会话列表…')
        .fontSize(FS_LABEL)
        .fontColor($r('app.color.text_secondary'))
      Button('打开网页侧栏')
        .height(BTN_H_MD)
        .fontSize(FS_LABEL)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.chip_bg'))
        .margin({ top: GAP_XS })
        .accessibilityText('打开网页侧栏')
        .accessibilityDescription('交还官方网页侧栏')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.onReveal();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
  }

  /** 空态②：搜索无匹配。文案直接读 `this.queryText`（不用值参数，理由见 LoadingPlaceholder）。 */
  @Builder
  NoMatchPlaceholder() {
    Column() {
      Text('没有匹配「' + this.queryText.trim() + '」的会话')
        .fontSize(FS_LABEL)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
  }

  @Builder
  PanelFooter() {
    Row() {
      Text(this.totalCount > 0 ? ('共 ' + this.totalCount.toString() + ' 个会话') : '')
        .fontSize(FS_FOOTNOTE)
        .fontColor($r('app.color.shell_group_text'))
        .layoutWeight(1)
        .padding({ left: GAP_LG })
      // 这里原本还有一个「刷新」按钮，已按需求去掉：会话列表本来就是网页侧 3s 一次的 rescan
      // 推上来的，这个按钮既冗余、又占着右下角最显眼的位置。
      // **第十六轮起"下拉刷新"是真的了**：官方 `Refresh` 包住列表（见 build() 的列表分支），
      // 下拉即触发网页侧重新抽取 —— 旧注释曾这么写但当时工程内根本没有 Refresh 组件，
      // 属"注释与实现不符"（审计 U-2），本次已补齐实现。
    }
    .width('100%')
    // **44 → 30（第十九轮，R19）**：本行只装一行 11vp 的计数文案，却沿用 `BTN_H_MD`(44)
    // ——那是"按钮行"的高度档，于是计数上下各空 15.6vp，真机上"共 N 个会话"与账号行之间
    // 观感偏空（Lead 真机复核项 5；dumpLayout 实测：计数行 131px/44vp、账号行 155px/52vp，
    // 两个文字中心相距 144px ≈ 48.4vp）。
    // 30 = `GROUP_ROW_H`：与列表里的分组标题行**同一档**（都是"只做语义的矮行"），
    // 计数因此紧贴列表下沿、账号行上移 14vp。
    // ⚠️ 代价（如实记录）：选择模式的 `SelectBar` 仍是 `BTN_H_MD`(44)（它装 32vp 的按钮 +
    // `responseRegion` 热区，不能压到 30），所以**进入选择模式时账号行会下移 14vp**。
    // 该跳变发生在"整个底部条换内容 + 搜索行消失"的同一次重排里，故判定可接受；
    // 若要零跳变，需把 SelectBar 也压到 30 并给按钮单独补热区（本轮不做，留给真机观感复核）。
    .height(GROUP_ROW_H)
  }

  /** 选择模式下的底部操作条：替换掉"共 N 个会话"。 */
  @Builder
  SelectBar() {
    Row() {
      if (this.deleteBusy) {
        LoadingProgress()
          .width(SPINNER_SIZE)
          .height(SPINNER_SIZE)
          .color($r('app.color.accent'))
        Text('正在删除 ' + this.deleteDone.toString() + '/' + this.deleteTotal.toString())
          .fontSize(FS_LABEL)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .margin({ left: GAP_SM })
      } else {
        // 全选判据走集合判定（O(n) 且语义正确，见 allVisibleSelected）
        this.TextAction(this.allVisibleSelected() ? '取消全选' : '全选', () => {
          this.toggleSelectAll();
        })
        Blank()
        Button('删除 (' + this.selectedIds.length.toString() + ')')
          .height(BTN_H_SM)
          .fontSize(FS_LABEL)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.selectedIds.length > 0
            ? $r('app.color.shell_danger')
            : $r('app.color.text_secondary'))
          .enabled(this.selectedIds.length > 0)
          // 与 TextAction 同一条口径：可见高度 32、可点高度补到 HOT_MIN(44)
          .responseRegion({ x: 0, y: -(HOT_MIN - BTN_H_SM) / 2, width: '100%', height: HOT_MIN })
          .accessibilityText('删除选中的会话')
          .accessibilityDescription('删除已勾选的 ' + this.selectedIds.length.toString() + ' 个会话')
          .accessibilityLevel('yes')
          .onClick(() => {
            this.confirmDelete();
          })
      }
    }
    .width('100%')
    .height(BTN_H_MD)
    // 左右内边距与头部 / 页脚 / 账号行统一到同一对刻度（左 16 / 右 8）。
    // 旧值左右各 GAP_MD(12)：全面板只有这一行用 12 当"页面内缩"，比上下两行各偏 4vp。
    .padding({ left: GAP_LG, right: GAP_SM })
  }

  /**
   * 账号页脚：头像 + 昵称 + 入口图标，整行点击打开账号菜单。
   *
   * **菜单现在是「系统设置」+「退出登录」两项**（白名单常量，见 openAccountMenu；
   * 「帮助与反馈」维持移除）。
   * 行本身仍是 `Row + stateStyles` 而不是 `Button`：它承载图像 + 两段文字 + 图标，
   * 语义是"一行"而不是"一个按钮"，套 Button 会引入按钮的默认内边距与最小尺寸约束，
   * 反而破坏 `ROW_H` 的行高（审计 U-7 提过这一点，本轮的取舍是：保留行语义 + 补齐三件套 + 底色按压态）。
   */
  @Builder
  AccountRow() {
    Row() {
      if (this.accountAvatar.length > 0 && !this.avatarFailed) {
        Image(this.accountAvatar)
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(AVATAR_SIZE / 2)
          .objectFit(ImageFit.Cover)
          .margin({ left: GAP_LG, right: GAP_SM })
          .onError(() => {
            this.avatarFailed = true;
          })
      } else {
        Stack() {
          Text(this.accountName.length > 0 ? this.accountName.substring(0, 1) : '?')
            .fontSize(FS_LABEL)
            .fontColor($r('app.color.on_accent'))
        }
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_SIZE / 2)
        .backgroundColor($r('app.color.accent'))
        .margin({ left: GAP_LG, right: GAP_SM })
      }
      Text(this.accountName.length > 0 ? this.accountName : '账号与设置')
        .fontSize(FS_LABEL)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 尾图标 = **「更多操作」**。P2-1 曾把字符 '⋯' 换成 `sys.symbol.more`，但
      // **`more` 在 SDK 里是 2×2 的方块网格**（R19 用 SDK 自带符号字体 HMSymbolVF.ttf
      // 把 `id_defined.json` 里每个符号名渲染成图逐一看过：more = 四个圆角方块，见
      // tmp/r19-w2/symbols-used.png）——真机截图里它读作"应用/网格/二维码"，与"打开账号菜单"
      // 语义不符（这其实是 P2-1 换错了符号：`more` 并不是省略号）。
      // 现改为 `ellipsis_circle`（圆圈内三点）= 通用的"更多操作"，与 iOS 一致；
      // 它同样经 SDK 实证存在（id_defined.json 的 symbol 段 + 字体里有同名字形）。
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(FS_ICON)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ right: GAP_LG })
    }
    .width('100%')
    .height(ROW_H)
    .stateStyles({
      normal: { .backgroundColor(Color.Transparent) },
      pressed: { .backgroundColor($r('app.color.shell_item_active_bg')) }
    })
    .animation({ duration: MOTION_FAST, curve: CURVE_STD })
    .accessibilityText(this.accountName.length > 0 ? this.accountName : '账号与设置')
    .accessibilityDescription('打开账号菜单')
    .accessibilityLevel('yes')
    .onClick(() => {
      this.openAccountMenu();
    })
  }

  build() {
    Column() {
      // 面板本体：贴左、右侧两角圆角、右侧投影
      Column() {
        this.PanelHeader()

        this.Hairline()

        if (!this.selecting) {
          this.SearchRow()
        }

        if (this.sideRows.length === 0) {
          this.LoadingPlaceholder()
        } else if (this.filteredRows().length === 0) {
          this.NoMatchPlaceholder()
        } else {
          // 列表区：官方 `Refresh` 包 `List` —— 这就是 audit U-2 指出的"下拉刷新根本不存在"
          // 的补法（`onRefresh` 从此真的有调用者），也是 iOS 的列表刷新手势。
          //
          // **`$$` 双向绑定直接写在 build() 里，不放进 @Builder**：`$$` 是编译期语法糖，
          // 而 ArkUI 在 `@Builder` 语境下 `$$` 还另有一个含义（"按引用传递参数"的范式记号），
          // 两者同名不同义；官方文档与示例里的系统组件双向绑定都写在 build()，
          // 放这里可以把这个作用域不确定性直接消掉（写入语义见 SDK refresh.d.ts：
          // `refreshing` "supports two-way binding through $"）。
          // 用户下拉越过阈值 → 框架把 `refreshing` 置 true → 本组件负责置回 false
          // （复位时机见 armRefreshSettle：网页侧 rescan 没有完成回执，
          //  只能"行数据到达 or 超时"二者取先）。
          Refresh({ refreshing: $$this.refreshing }) {
            this.SessionList()
          }
          .width('100%')
          .layoutWeight(1)
          .onRefreshing(() => {
            // 发请求 + 起兜底复位；`refreshing` 已由 $$ 绑定在框架侧置 true，这里不重复置。
            this.onRefresh();
            this.armRefreshSettle();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_NORMAL, curve: CURVE_STD }))
        }

        if (this.selecting || this.deleteBusy) {
          this.SelectBar()
        } else {
          this.PanelFooter()
        }

        this.Hairline()

        this.AccountRow()
      }
      // 宽度保持 100%：ArkUI 的百分比宽度按**父容器的 content-box** 解析（不含 padding），
      // 面板底色即抽屉的全宽（82% 屏宽），圆角与投影贴着自己的右缘。
      // **注意**：面板与网页内容之间没有额外留缝 —— 旧注释曾声称"面板底色 = 容器减掉
      // `DRAWER_RIGHT_GAP`"，与实现不符（本轮据实订正）；那个零消费者的令牌已在
      // ShellUi.ets 里**删除**（Lead 收尾），两侧口径现在一致：右缘不留缝。
      // （也不要写 width('calc(100% - 6vp)')：ArkUI 的 Length 字符串不解析 CSS calc。）
      .width('100%')
      .layoutWeight(1)
      // —— 高斯模糊（磨砂玻璃）——
      // 用 backgroundEffect 而不是 backdropBlur：SDK 里 backdropBlur 只有 radius 和
      // grayscale 两个旋钮，而 grayscale 是"色阶调整"——文档原文「第一个参数表示对黑色的
      // 提亮程度，第二个表示对白色的压暗程度…黑白趋于灰」；默认 [0,0] 不动，等于没有
      // 深浅色适配能力。backgroundEffect 才有 saturation / brightness / color 三个可调项，
      // 且 color 吃 ResourceColor，可以直接喂双值资源，深浅色天然分档。
      //
      // **玻璃色的 alpha 是观感与色差线的唯一旋钮**（真机逐像素实测）：
      //   旧值 #C4F9FAFB（alpha≈77%）把面板压成 rgb(250,251,253)，而网页底色是纯白
      //   rgb(255,255,255) —— 两者差 5 级，面板右缘于是出现一条肉眼可辨的竖向界线，
      //   顶栏（玻璃色更深）与面板之间还有一道横向界线。
      //   现在压到 alpha≈20%：背后是纯白时面板≈rgb(251,251,251)，界线基本消失；
      //   背后是深色文字/卡片时模糊层透出来，"磨砂"才真的看得见（旧值把内容糊成一片灰白）。
      // 不能用 backgroundBlurStyle：那是"材质"，自带近乎不透明的浅色遮罩且会接管
      // backgroundColor（alpha 调到 4% 甚至 Color.Transparent 都毫无变化），会把背后的
      // 网页内容整片盖掉——真机逐张截屏实证，见 内部验证记录、§3.0-74。
      //
      // saturation / brightness 走统一的模糊令牌：顶栏与本面板**必须同值**，
      // 否则两者各自模糊同一片内容却一浓一淡（本轮把三处各写一遍的写法收敛成一对令牌）。
      // 亮度 1.0 的依据仍是那条实测："模糊本身中性、色差 100% 来自玻璃色" —— 所以这里
      // 用 `BLUR_BRIGHTNESS`（中性值）而不是名字看起来"更对"的 `DARK_BRIGHTNESS`。
      .backgroundEffect({
        radius: PANEL_BLUR,
        saturation: BLUR_SATURATION,
        brightness: BLUR_BRIGHTNESS,
        color: $r('app.color.shell_panel_glass')
      })
      .borderRadius({ topRight: PANEL_RADIUS, bottomRight: PANEL_RADIUS })
      // —— 子节点裁到面板圆角轮廓（第十七轮 T6，用户反馈"变黑层没有圆角优化，阴影/色块超出圆角"）——
      // 根因：ArkUI **默认不把子节点裁到父容器的圆角**（SDK common.d.ts: clip 默认 false ⇒
      // "the area of child components extending beyond the current component's bounds is not clipped by default"）。
      // 而面板里几乎每一块底色都是**整宽的矩形**：AccountRow 的 stateStyles.pressed
      //（shell_item_active_bg）、会话行选中态的 isActive 底色、SearchRow 的按压底色 ——
      // 面板右侧两角是 PANEL_RADIUS(22vp) 的弧线，这些矩形色块却一路铺到面板的**边界矩形**右缘，
      // 于是在右上/右下两个圆角处露出一块"直角"的色块（用户看到的就是"色块超出圆角"；
      // 同 §3.0-141 那类"整宽子节点按父的边界矩形而非可视轮廓排布"的坑）。
      // clip(true) 的语义正是"按父容器的**边缘轮廓**裁剪子节点"（SDK 原文 edge contour），
      // 轮廓含圆角 ⇒ 圆角处的溢出被真正裁掉；它只作用于子节点，面板自身的 .shadow() 不受影响
      //（真机复核清单：色块被圆角裁掉 / 面板投影仍在 / 列表滚动不越界 / 顶部圆角同样正常）。
      // 副作用（SDK 明示）：被裁掉的区域不再响应手势 —— 本面板没有任何需要越界的可点元素，可接受。
      .clip(true)
      // **面板右缘不再画收边发丝线**（第十六轮真机第三批：用户反馈"侧边栏和其他页面还是
      // 有明显界线"）。这条 0.5vp 的描边原本是为了把"磨砂↔清晰"的不连续"讲清楚"，但真机上
      // **它本身就是那条醒目的竖线** —— 密度 560 下 0.5vp = 1.5px 的深色线，比它想掩饰的
      // 模糊过渡显眼得多；而且只画右边，导致它在上下两个圆角处**突然开始 / 结束**，
      // 端点又是一处硬边（与大圆角叠在一起尤其明显）。
      // 现在边界完全交给"磨砂玻璃色差 + 对称淡晕投影"表达：两者都是渐变的，
      // 用户看到的是逐层淡出的过渡，而不是一条线。`shell_panel_edge` 资源随之删除
      // （零消费者不留 —— 同 `DRAWER_RIGHT_GAP` / `PANEL_SHADOW_DX` 的处置纪律）。
      // 投影：**对称淡晕**，不做横向偏移。
      //
      // 旧值是 `offsetX: PANEL_SHADOW_DX(6)`（"面板贴左、投影只向右投"）。真机实测
      // （2026-09-15 第十六轮真机复核，Mate70 Pro+）：**这个横向偏移会在面板右上/右下
      // 两个圆角处留下一条明显的分界线** —— 阴影是按组件的**边界矩形**投影的，整体右移 6vp
      // 之后，它的右外缘是一条**竖直直边**，而面板在圆角处向内收 → 圆角外侧就露出一块
      // "本该被裁掉"的投影，且它的外缘与圆角的弧线不重合，于是浅色网页内容上出现一条
      // 突兀的竖直硬边（圆角越大越明显）。对称晕则沿圆角轮廓均匀扩散，圆角处连续无拐点。
      //
      // 半径仍走令牌 `SHADOW_R_MD`(16)；`DRAWER_RIGHT_GAP` 时代留下的 `PANEL_SHADOW_DX`
      // 已随之删除（零消费者常量不留 —— 同 `DRAWER_RIGHT_GAP` 的处置）。
      .shadow({
        radius: SHADOW_R_MD,
        color: $r('app.color.shell_panel_shadow'),
        offsetX: 0,
        offsetY: 0
      })
    }
    .width('100%')
    .height('100%')
    // 避让集中在这一处：上=状态栏，下=手势条 / 输入法（键盘弹出时面板整体上收）。
    //
    // 下避让取 max 而不是相加：**系统上报的输入法避让区已经把手势条那一段含在内了**
    // （真机实测：键盘上沿 y=1733、屏高 2832 ⇒ 上报 1099px；而手势条避让区是 98px，
    //  1099px 的起点本就落在手势条之上）。相加会重复扣一次手势条，面板在键盘上方
    //  白留 33vp。这与"网页 body padding 与 Web 组件位置双重下移"是同一类
    //  **重复补偿** 缺陷，靠模拟器量不出来（模拟器手势条高度与 IME 组成比例不同），
    //  必须真机逐像素量。
    .padding({
      top: this.topPad + EDGE_GAP,
      bottom: Math.max(this.bottomPad, this.keyboardPad) + EDGE_GAP
    })
  }
}
