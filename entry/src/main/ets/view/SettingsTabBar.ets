/**
 * 设置页底部功能栏 —— **官方 `Tabs` 底部 TabBar + 官方沉浸材质**（第二十一轮最终档）。
 *
 * ## 为什么是这个形态（官方文档给的唯一路径，pitfalls §3.0-245）
 *
 * 官方原文要点：沉浸光感（`systemMaterial` / `ImmersiveMaterial`）自 HarmonyOS 7 起
 * 只有**四类位置**生效：①弹窗类 ②`Slider`/`Toggle`/`Select` ③`Navigation`/`NavDestination` 标题栏
 * ④**横向 `Tabs` 且 `barPosition = BarPosition.End` 的底部 TabBar**；其他区域**静默不生效**。
 *
 * 本工程底栏在「系统设置」浮层上，四类里唯一能用的就是 **④** ⇒
 * 必须用官方 `Tabs`（`barPosition: End`）+ `FloatingTabBarStyle.systemMaterial`，
 * **这也是 aa-hm 的「路线 A」**（用户要求参考 aa-hm）。
 *
 * ⚠️ 同一条文档还要求：材质**不要与 `backgroundColor` / `borderColor` / `borderWidth` / `shadow` 同用**
 * （材质会把它们接管）。⇒ 本组件**不画任何自绘层**（无渐变 / 无发丝线 / 无投影），表面交给材质。
 *
 * ## 与 Web 的层序（内容穿过）
 *
 * 本组件由宿主放在**根 `Stack` 的最顶层**（浮层）；下层是 `Web`（铺满全屏）。
 * `barOverlap(true)` 让 bar 叠在内容上 ⇒ 设置页滚动的**内容会从 bar 背后穿过**，
 * 官方材质（折射/模糊）才有内容可糊 —— 这是「沉浸」的前提。
 *
 * ## 几何（两条真机读数换来的）
 *
 * · `barHeight` 只表达胶囊自身高度；`barBottomMargin`（离底间隙）**也在 bar 带内** ⇒
 *   `Tabs` 的高度必须 = 胶囊高 + 离底间隙，否则胶囊上半被裁（真机实测：图标整条不可见）；
 * · `barOverlap(true)` 是 `barFloatingStyle` 生效的**前置条件**（SDK 原文），不许动。
 */
import {
  GAP_XS, TABBAR_BOTTOM_GAP, TABBAR_H, TABBAR_ICON, TABBAR_LABEL_FS,
  TABBAR_WIDTH_VP, officialImmersiveMaterial
} from '../common/ShellUi';

/** 底栏一项。key 是**下标**（与网页页签的 DOM 顺序一一对应，宿主据此下发切页签指令）。 */
export interface SettingsTabItem {
  key: number;
  label: string;
}

/**
 * 四项的顺序**必须**与网页页签一致（通用设置 / 账号管理 / 数据管理 / 服务协议）。
 * 顺序错位 = 点 A 切到 B，且不会报任何错 —— 改这里必须同时核对网页侧。
 */
export const SETTINGS_TABS: SettingsTabItem[] = [
  { key: 0, label: '通用设置' },
  { key: 1, label: '账号管理' },
  { key: 2, label: '数据管理' },
  { key: 3, label: '服务协议' }
];

/**
 * 下标 → 官方符号资源。
 *
 * 四个名字都用 D:/DevEco Studio/sdk/default/openharmony/toolchains/id_defined.json
 * 的 symbol 清单验过（4042 条 symbol，本工程纪律见 EXPERIENCE 第 1.5-5 条）：
 * gearshape / person / externaldrive / doc_text 全部命中，语义也与网页页签的图标一致。
 *
 * ⚠️ $r 只吃**字面量**（不能拼字符串），所以只能写成 if 分支 —— 不要在别处再抄一份。
 */
export function settingsTabIcon(key: number): Resource {
  if (key === 1) {
    return $r('sys.symbol.person');
  }
  if (key === 2) {
    return $r('sys.symbol.externaldrive');
  }
  if (key === 3) {
    return $r('sys.symbol.doc_text');
  }
  return $r('sys.symbol.gearshape');
}

/**
 * 单个 tab（`TabContent.tabBar()` 的内容）：图标在上、文字在下，选中项走 `accent`。
 *
 * ⚠️ 选中态**必须由本组件自己读**（`@StorageLink('settingsTabIndex')`），不能靠父级把
 * `active` 传进来：`.tabBar()` 吃的是 `@Builder`，而 `@Builder` 的值参数不会因父级重跑而重建
 * （内部踩坑表 的 38 号）—— 这也是 aa-hm `AaBottomTabItem` 的做法（它用 @StorageLink 读路由）。
 */
@Component
export struct SettingsTabItemView {
  /** 本项下标（与 SETTINGS_TABS 一致）。 */
  @Prop index: number = 0;
  /** 本项文案（静态）。 */
  @Prop label: string = '';
  /** 与宿主共享的选中下标（AppStorage 通道）。 */
  @StorageLink('settingsTabIndex') activeTab: number = 0;

  build() {
    Column({ space: GAP_XS }) {
      SymbolGlyph(settingsTabIcon(this.index))
        .fontSize(TABBAR_ICON)
        .fontColor([this.index === this.activeTab ? $r('app.color.accent') : $r('app.color.text_secondary')])
      Text(this.label)
        .fontSize(TABBAR_LABEL_FS)
        .fontColor(this.index === this.activeTab ? $r('app.color.accent') : $r('app.color.text_secondary'))
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 无障碍：整项可点，语义由 label 承担（读屏与 dumpLayout 都靠它）。
    .accessibilityText(this.label)
    .accessibilityDescription(this.label)
    .accessibilityLevel('yes')
  }
}

@Component
export struct SettingsTabBar {
  /** 离屏幕下缘的间隙（vp）= max(手势条避让, TABBAR_BOTTOM_GAP)，由宿主算好传入。 */
  @Prop bottomGap: number = TABBAR_BOTTOM_GAP;
  /** 选中下标：与宿主共享同一个 AppStorage 键，双向都通。 */
  @StorageLink('settingsTabIndex') activeTab: number = 0;
  /** 点选回调（宿主据此驱动网页切页签）。 */
  onSelect: (index: number) => void = () => {
  };

  /** tabBar 构造器。参数只吃下标常量 ⇒ 不存在「值参数不重建」的问题（选中态在子组件里读）。 */
  @Builder
  tabItem(index: number) {
    SettingsTabItemView({ index: index, label: SETTINGS_TABS[index].label })
  }

  /**
   * 官方悬浮底栏的形态 —— **官方沉浸材质的唯一入口**
   * （`systemMaterial` 属于 `FloatingTabBarStyle`，**不在** `TabsOptions` 里）。
   *
   * · `barWidth` 三段给同一个值：本工程是手机（md 断点），避免平板上宽度跳变；
   * · `barBottomMargin` = 宿主算好的离底间隙；
   * · `systemMaterial` = 官方沉浸材质（**含 lightEffect 光效**）。
   *
   * ⚠️ `materialColor` **必须带 alpha**（SDK 原文：完全 opaque 会挡死材质滤镜）。
   */
  private floatingBarStyle(): FloatingTabBarStyle {
    return {
      barWidth: {
        smallBarWidth: TABBAR_WIDTH_VP,
        mediumBarWidth: TABBAR_WIDTH_VP,
        largeBarWidth: TABBAR_WIDTH_VP
      },
      barBottomMargin: this.bottomGap,
      systemMaterial: officialImmersiveMaterial($r('app.color.shell_tabbar_glass'))
    };
  }

  build() {
    Column() {
      // 撑开：Tabs 只占底部一条，靠它把那条压到屏幕底。
      Blank()
      Tabs({ barPosition: BarPosition.End, index: this.activeTab }) {
        // 四个 TabContent 的内容**必须为空**：设置页真正的「内容」是下层的 Web。
        // ⚠️ 不能写 Blank()（只能嵌在 Row/Column/Flex 里，编译报 10905201），
        //    也不能写空的块容器（pitfalls 77 号）—— 用「带属性的 Column()」这种合法空容器。
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }.tabBar(this.tabItem(0))
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }.tabBar(this.tabItem(1))
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }.tabBar(this.tabItem(2))
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }.tabBar(this.tabItem(3))
      }
      // noMinHeightLimit = true：54 小于框架默认 56，不传会被抬到默认值。
      .barHeight(TABBAR_H, true)
      // 官方明写：barOverlap 是 barFloatingStyle 生效的**前置条件**，且自带官方 blur —— 不许动。
      .barOverlap(true)
      .barBackgroundColor(Color.Transparent)
      .divider(null)
      .animationDuration(0)
      // 横滑会绕过本组件唯一的状态源（选中态在 AppStorage 里）⇒ 必须关。
      .scrollable(false)
      .barMode(BarMode.Fixed)
      // 官方沉浸材质（含 lightEffect 光效）的唯一入口。
      .barFloatingStyle(this.floatingBarStyle())
      .onChange((index: number) => {
        this.onSelect(index);
      })
      .width('100%')
      // ⚠️ 高度 = **胶囊高 + 离底间隙**：`barHeight` 只表达胶囊自身高度，
      //    `barBottomMargin` 那段也在 bar 带内 —— 只给 54 会把胶囊上半裁掉（真机实测）。
      .height(TABBAR_H + this.bottomGap)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    // ⚠️ 整屏高的外层**必须** None（自身不吃、子节点照吃），否则整屏触摸全被它吃掉。
    .hitTestBehavior(HitTestMode.None)
  }
}
