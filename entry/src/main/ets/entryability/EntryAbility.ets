import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeepSeekHm';

/**
 * 首页 URL：**仅**供 `prepareForPageLoad` 预连接（DNS 预解析 + TCP 预连接），不参与任何导航判断。
 *
 * 为什么不 `import { DEEPSEEK_HOME } from '../utils/DeepSeekConfig'`：那个模块的顶层就是两段
 * 合计 124.5 KB 的注入脚本文本，ability 侧一旦 import，它会在 `onCreate`（首屏之前）被求值
 * —— 与"把内核初始化前移以缩短首屏"的目的正好相反。所以这里保留一份字面量，
 * 只要**同 origin**即可；若 `DeepSeekConfig.DEEPSEEK_HOME` 换域，这里必须同步。
 */
const HOME_URL: string = 'https://chat.deepseek.com/';
/** 预连接 socket 数（`prepareForPageLoad` 第 3 参）：非法值会抛 17100013，取 2 对本场景足够。 */
const PRECONNECT_SOCKETS: number = 2;
/**
 * 避让区写入 AppStorage 的去抖间隔（ms）。
 *
 * 为什么需要：`avoidAreaChange` 在输入法弹出/收起时**会连发多次**（键盘动画期间系统
 * 逐帧上报），每次上报都是一次 px2vp + 一次 @StorageProp 写入 —— 侧栏面板与网页注人
 * 都会跟着重算。100ms 去抖把同一轮变化收敛成一次写入（用户感知阈值 ~150ms，看不出延迟）。
 */
const AVOID_DEBOUNCE_MS: number = 100;
/** 避让值"同值不写"的容差（vp）：系统把同一个值复报一次时不做任何事。 */
const AVOID_EPSILON: number = 0.5;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  /** avoidAreaChange 监听器的引用：onWindowStageDestroy 里要 off 掉（否则窗口销毁后回调仍在跑）。 */
  private avoidAreaListener: ((data: window.AvoidAreaOptions) => void) | null = null;
  /** 避让区写入去抖定时器。 */
  private avoidTimer: number = -1;
  /** 待写入的三个避让值（去抖窗口内取最后一次为准）。 */
  private pendingTop: number = -1;
  private pendingBottom: number = -1;
  private pendingKeyboard: number = -1;
  /** 上一次真正写进 AppStorage 的值：同值不写（避免无意义的状态变更与重排）。 */
  private lastTop: number = -1;
  private lastBottom: number = -1;
  private lastKeyboard: number = -1;
  /** 上一次下发的系统栏四色（含透明底色）：同色不重设，避免反复走窗口服务。 */
  private lastSystemBarKey: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 原先这里（以及 onNewWant）还写一个 `launchWant`（整个 Want 对象）。第十九轮删除：
    // 全工程**零读者**（grep `launchWant` 只命中这两处写入点，页面侧从来只读 `launchAction`），
    // 而 Want 里带着拉起方的全部参数 —— 不留一个没人用、却把外部参数摊在全局状态里的键。
    AppStorage.setOrCreate('launchAction', EntryAbility.extractAction(want));
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    // 前后台状态初值：进程刚被拉起必然在前台，先落 true —— 页面侧（ui-main）用
    // `@StorageProp('appForeground')` 直接读得到初值，不必等第一次 onForeground 回调。
    AppStorage.setOrCreate('appForeground', true);
    // --ps colorMode 调试钩子显式指定了档位时，这一轮的主题以它为准：
    // 落一个布尔位给页面，让"站点主题偏好同步"（Index.syncSiteTheme）整体让位。
    // **无论有没有参数都要写**（不能只在有参数时写）：AppStorage 跨 ability 生命周期存活，
    // 一次带参启动之后若不归零，后续的普通启动会一直是"被锁死"的状态。
    AppStorage.setOrCreate('debugColorModeForced',
      EntryAbility.applyDebugColorMode(this.context, want));
    EntryAbility.warmUpWebEngine();
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
  }

  /**
   * 回到前台（audit §3「功耗」：网页侧两条常驻定时器早先完全不分前后台）。
   *
   * 为什么把状态落成 AppStorage 布尔位、而不是在这里直接去停页面里的定时器：
   * ① ability 拿不到网页上下文（定时器都在注入脚本里跑），必须由页面消费这个信号；
   * ② 用 AppStorage 而不是 eventHub —— eventHub 的 `on` 必须在页面 `aboutToDisappear` 里
   *    `off`，漏配就是回调泄漏，而 AppStorage 不需要配对解绑；本工程既有的跨层信号
   *    （`topHeightPx` / `bottomHeightPx` / `currentColorMode` / `launchAction`）一律走 AppStorage，同源。
   * 页面侧接入（`Index.ets` + 注入脚本）不在本次改动范围内，属 ui-main 的接口。
   */
  onForeground(): void {
    AppStorage.setOrCreate('appForeground', true);
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  /** 切到后台：与 onForeground 成对，页面据此停掉常驻定时器（省电），回前台再恢复。 */
  onBackground(): void {
    AppStorage.setOrCreate('appForeground', false);
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  /**
   * 系统内存压力回调（audit §3「内存」最后一条：全工程无 onMemoryLevel）。
   *
   * 为什么要做：本工程最吃内存的是 ArkWeb 渲染进程（audit 实测渲染进程 PSS 183 MB），
   * 系统内存吃紧时应用此前**没有任何动作**，只能等着被整进程杀掉 —— 丢的是当前对话与草稿。
   * 这里按压力档让 ArkWeb 内核回收它自己的缓存；**回收的只是内核缓存**，
   * cookie / localStorage 不在其中，登录态与云端历史不受影响。
   *
   * SDK 实证（工作区红线：API 名必须 grep d.ts）：
   *   · `AbilityConstant.MemoryLevel`（`@ohos.app.ability.AbilityConstant.d.ts:534`，since 9）：
   *     0 MODERATE / 1 LOW / 2 CRITICAL；API 24 起追加 3 UI_HIDDEN、
   *     4 BACKGROUND_MODERATE、5 BACKGROUND_LOW、6 BACKGROUND_CRITICAL。
   *   · `webview.WebviewController.trimMemoryByPressureLevel(level)` 是 **static**
   *     （`@ohos.web.webview.d.ts:4632`，since 14）—— 不需要持有 WebviewController 实例，
   *     ability 侧就能调（本工程的 controller 在 `Index.ets` 里，ability 既拿不到也不该拿）。
   *   · `webview.PressureLevel` 只有两档（`@ohos.web.webview.d.ts:318`）：
   *     1 MODERATE「回收重建成本低、非立即需要的缓存」/ 2 CRITICAL「能回收的全回收」。
   *
   * 档位映射口径：只有"系统还有余量"的档（MODERATE / UI_HIDDEN / 后台 MODERATE）用轻档，
   * 真吃紧（LOW / CRITICAL / 后台 LOW / 后台 CRITICAL）直上重档 —— 保命优先：
   * 宁可回前台后重新拉一次资源，也不要被系统杀进程。
   */
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    let pressure: webview.PressureLevel = EntryAbility.pressureLevelOf(level);
    try {
      webview.WebviewController.trimMemoryByPressureLevel(pressure);
      hilog.info(DOMAIN, TAG, 'onMemoryLevel %{public}d -> trim level %{public}d', level, pressure);
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'trimMemoryByPressureLevel failed: %{public}s', error.message);
    }
  }

  /** 系统内存档 → ArkWeb 回收档（映射理由见 onMemoryLevel 注释）。 */
  private static pressureLevelOf(level: AbilityConstant.MemoryLevel): webview.PressureLevel {
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE
      || level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_UI_HIDDEN
      || level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_BACKGROUND_MODERATE) {
      return webview.PressureLevel.MEMORY_PRESSURE_LEVEL_MODERATE;
    }
    return webview.PressureLevel.MEMORY_PRESSURE_LEVEL_CRITICAL;
  }

  /**
   * ArkWeb 内核预热 + 首页预连接（audit §3「启动速度」最后一条）。
   *
   * 时机是本方法存在的**全部理由**（风险点也在这里）：
   * `initializeWebEngine()` 的作用是把内核动态库加载从"首次创建 Web 组件时"前移到进程启动阶段，
   * 官方文档明确：**必须在 Web 组件创建之前调用**、全局生效、应用生命周期内只需一次、
   * 且不可在异步线程里调用。`onCreate` 是主线程同步执行、且早于
   * `onWindowStageCreate → loadContent('pages/Index')`（Web 组件在那之后才创建），
   * 是唯一正确的落点。SDK 实证：`@ohos.web.webview.d.ts:2765 static initializeWebEngine(): void`（since 9）。
   * 本工作区同款先例（可直接对照）：`dsh-mobile/.../EntryAbility.ets:29`、
   * `zcode-mobile/.../EntryAbility.ets:27`。
   *
   * 预连接：`static prepareForPageLoad(url, preconnectable, numSockets)`
   * （`@ohos.web.webview.d.ts:3843`，since 10）在加载前做 DNS 预解析 + TCP 预连接，
   * 省掉首屏的握手往返。它**只影响连接建立**：不预取内容、不改导航行为，失败无副作用。
   *
   * 两步各自 try/catch：任一步失败都不能拖累另一步（引擎预热失败仍要能正常起页面）。
   */
  private static warmUpWebEngine(): void {
    try {
      webview.WebviewController.initializeWebEngine();
      hilog.info(DOMAIN, TAG, 'web engine pre-initialized');
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'initializeWebEngine failed: %{public}s', error.message);
    }
    try {
      webview.WebviewController.prepareForPageLoad(HOME_URL, true, PRECONNECT_SOCKETS);
      hilog.info(DOMAIN, TAG, 'preconnect issued: %{public}s', HOME_URL);
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'prepareForPageLoad failed: %{public}s', error.message);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('launchAction', EntryAbility.extractAction(want));
    hilog.info(DOMAIN, TAG, 'EntryAbility onNewWant');
  }

  // 系统深浅色模式切换：同步原生沉浸窗口的系统栏内容色，并把新模式写入
  // AppStorage，由 Index 页校验网页媒体查询并实时刷新页面主题。
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onConfigurationUpdate colorMode: %{public}d', newConfig.colorMode ?? -2);
    let mode: number = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    // 同值不写：配置更新（如旋转、字体缩放）会带着同一个 colorMode 一起来，
    // 每次都写会让 @StorageProp 的 @Watch 链白跑一遍（Index.onColorModeChange 里有 runJavaScript）。
    if (AppStorage.get<number>('currentColorMode') !== mode) {
      AppStorage.setOrCreate('currentColorMode', mode);
    }
    this.applySystemBarContentColor(mode);
  }

  /**
   * 系统栏内容色 = 资源 `app.color.text_primary`（与原生文字色同源）。
   *
   * 为什么不再硬编码 #E5E5E5 / #111111：硬编码让"系统栏图标色"与"页面文字色"两套值
   * 各改各的，主题微调时必然脱钩（audit §1 U-17）。这里改成读资源（resId 段由编译期生成），
   * 按当前资源深浅色档解析出 ARGB 整数再转 #AARRGGBB。
   * 取不到资源时（理论上不会发生）退回原来的硬编码值，保证不会因为一个颜色读失败把
   * 系统栏搞成不可见。
   *
   * 注：深浅色档由**资源系统**按当前 colorMode 解析，所以 `dark` 参数只用于兜底硬编码值。
   */
  private systemBarContentColor(dark: boolean): string {
    try {
      let rm = this.context.resourceManager;
      let argb: number = rm.getColorSync($r('app.color.text_primary').id);
      if (typeof argb === 'number') {
        let v: number = argb >>> 0;
        let hex: string = (v & 0xFFFFFF).toString(16);
        while (hex.length < 6) {
          hex = '0' + hex;
        }
        return '#' + hex;
      }
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'read text_primary failed: %{public}s', error.message);
    }
    return dark ? '#E5E5E5' : '#111111';
  }

  /**
   * 下发系统栏四色（底色透明 + 内容色）。
   *
   * 四色整体做**同值不重设**缓存：`setWindowSystemBarProperties` 是跨进程 IPC，
   * 而配置更新（旋转、字体缩放、深浅色）会反复触发；只有深浅色真的变了才值得发一次。
   */
  private applySystemBarContentColor(colorMode: number): void {
    try {
      if (this.mainWindow === null) {
        return;
      }
      let dark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      let contentColor: string = this.systemBarContentColor(dark);
      let key: string = (dark ? 'd' : 'l') + contentColor;
      if (key === this.lastSystemBarKey) {
        return;
      }
      let properties: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      };
      this.lastSystemBarKey = key;
      this.mainWindow.setWindowSystemBarProperties(properties).catch((err: BusinessError) => {
        this.lastSystemBarKey = '';
        hilog.warn(DOMAIN, TAG, 'set system bar colors failed: %{public}s', err.message);
      });
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'apply system bar colors failed: %{public}s', error.message);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 直接进入「原生外壳 + ArkWeb 聊天区」主页面，跳过原生“软件界面”
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed. code: %{public}d', err.code);
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
    this.setupImmersive(windowStage);
  }

  /**
   * 窗口销毁：解绑避让监听并清掉去抖定时器、置空窗口引用。
   *
   * 为什么必须做（本轮补齐）：`mainWindow.on('avoidAreaChange', …)` 注册在**窗口对象**上，
   * 窗口销毁后该回调仍可能被触发，届时 `AppStorage.setOrCreate` 会写进一个已经没有页面的
   * 应用状态（并被下一次 onConfigurationUpdate 的"同值不写"判据误用）；同时
   * `this.mainWindow` 悬空引用会让 applySystemBarContentColor 对着已销毁窗口发 IPC。
   */
  onWindowStageDestroy(): void {
    if (this.avoidTimer !== -1) {
      clearTimeout(this.avoidTimer);
      this.avoidTimer = -1;
    }
    if (this.mainWindow !== null && this.avoidAreaListener !== null) {
      try {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaListener);
      } catch (err) {
        let error = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'off avoidAreaChange failed: %{public}s', error.message);
      }
    }
    this.avoidAreaListener = null;
    this.mainWindow = null;
    // "同值不写"的哨兵必须一并复位（本轮补）：窗口舞台是可以**被销毁后重建**的
    // （同一次 ability 生命周期内换窗口的场景），而 last*/pending* 是 ability 实例上的状态。
    // 不复位的话新窗口第一次上报会撞上"与旧窗口的值相同"而被整条跳过 ——
    // 后果是 topHeightPx / bottomHeightPx 停在旧窗口的值，避让区整块错位且没有任何日志。
    this.pendingTop = -1;
    this.pendingBottom = -1;
    this.pendingKeyboard = -1;
    this.lastTop = -1;
    this.lastBottom = -1;
    this.lastKeyboard = -1;
    // 系统栏四色也要重新下发一次（新窗口是全新的窗口对象，没有继承旧配置）
    this.lastSystemBarKey = '';
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy: avoidArea listener detached');
  }

  private static extractAction(want: Want): string {
    if (want.parameters === undefined) {
      return '';
    }
    let action: Object | undefined = want.parameters['action'];
    if (typeof action === 'string') {
      return action;
    }
    return '';
  }

  // 调试用强制配色（仅当启动参数显式给出 colorMode 时生效，否则完全跟随系统）：
  //   hdc shell "aa start -a EntryAbility -b com.example.deepseekhm --ps colorMode dark"
  // 来源：模拟器这台设备的控制中心没有“深色模式”磁贴，系统设置里逐级点击又受
  // 布局差异影响，无法稳定切到深色来核对原生外壳的双值资源。走 ApplicationContext
  // 的 setColorMode 让资源解析直接切档，验证完可用不带参数启动恢复跟随系统。
  //
  // 返回值 = "本次是否真的强制了档位"，用于落 `debugColorModeForced` 给页面：
  // 站点主题偏好同步（Index.syncSiteTheme）必须给调试通道让路，否则这个验证钩子
  // 会被站点偏好直接覆盖掉 —— 而它正是 UI 类验收唯一可复现的配色入口。
  private static applyDebugColorMode(context: common.UIAbilityContext, want: Want): boolean {
    if (want.parameters === undefined) {
      return false;
    }
    let mode: Object | undefined = want.parameters['colorMode'];
    if (typeof mode !== 'string') {
      return false;
    }
    try {
      let app: common.ApplicationContext = context.getApplicationContext();
      if (mode === 'dark') {
        app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (mode === 'light') {
        app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      hilog.info(DOMAIN, TAG, 'debug colorMode applied: %{public}s', mode);
      return true;
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'applyDebugColorMode failed: %{public}s', error.message);
      return false;
    }
  }

  /**
   * 避让区上报（去抖 + 同值不写）。
   *
   * 键盘弹出/收起期间系统会**连续多次**上报，早先是"每来一次就 px2vp + 写 AppStorage"，
   * 于是侧栏面板与网页避让注入跟着重算好几轮。现在把同一轮变化收敛成一次写入：
   * 100ms 去抖取最后一次值，且与上一次真正写入的值（0.5vp 容差）相同则完全跳过。
   */
  private flushAvoidArea(): void {
    this.avoidTimer = -1;
    if (this.mainWindow === null) {
      return;
    }
    if (this.pendingTop >= 0 && Math.abs(this.pendingTop - this.lastTop) >= AVOID_EPSILON) {
      this.lastTop = this.pendingTop;
      AppStorage.setOrCreate('topHeightPx', this.pendingTop);
      hilog.info(DOMAIN, TAG, 'avoid top -> vp=%{public}d', Math.round(this.pendingTop));
    }
    if (this.pendingBottom >= 0 && Math.abs(this.pendingBottom - this.lastBottom) >= AVOID_EPSILON) {
      this.lastBottom = this.pendingBottom;
      AppStorage.setOrCreate('bottomHeightPx', this.pendingBottom);
      hilog.info(DOMAIN, TAG, 'avoid bottom -> vp=%{public}d', Math.round(this.pendingBottom));
    }
    if (this.pendingKeyboard >= 0 && Math.abs(this.pendingKeyboard - this.lastKeyboard) >= AVOID_EPSILON) {
      this.lastKeyboard = this.pendingKeyboard;
      AppStorage.setOrCreate('keyboardHeightPx', this.pendingKeyboard);
      hilog.info(DOMAIN, TAG, 'avoid keyboard -> vp=%{public}d', Math.round(this.pendingKeyboard));
    }
  }

  private scheduleAvoidFlush(): void {
    if (this.avoidTimer !== -1) {
      clearTimeout(this.avoidTimer);
    }
    this.avoidTimer = setTimeout(() => {
      this.flushAvoidArea();
    }, AVOID_DEBOUNCE_MS);
  }

  private setupImmersive(windowStage: window.WindowStage): void {
    try {
      let mainWindow: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        mainWindow.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
          this.applySystemBarContentColor(this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        }).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'set system bar enable failed: %{public}s', err.message);
        });
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'set window layout full screen failed: %{public}s', err.message);
      });

      this.avoidAreaListener = (data: window.AvoidAreaOptions) => {
        try {
          // AvoidArea 的 Rect 单位是物理像素 px，而 Web 页面 CSS px == vp，
          // 必须 px2vp 换算后再注入网页（否则在 dpr≈3 的手机上偏大 3 倍）。
          let ui: UIContext = mainWindow.getUIContext();
          if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
            this.pendingTop = ui.px2vp(data.area.topRect.height);
          } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
            this.pendingBottom = ui.px2vp(data.area.bottomRect.height);
          } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
            // 输入法避让：只给原生侧栏用（搜索框获得焦点时面板整体上收，
            // 否则列表与底部计数被键盘盖住）。主内容区不消费这个值 —— 聊天输入框在
            // 网页里，改全局键盘避让模式会让官方页面二次补偿，风险更大。
            this.pendingKeyboard = ui.px2vp(data.area.bottomRect.height);
          } else {
            return;
          }
          this.scheduleAvoidFlush();
        } catch (err) {
          let error = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'avoidArea convert failed: %{public}s', error.message);
        }
      };
      mainWindow.on('avoidAreaChange', this.avoidAreaListener);
    } catch (err) {
      let error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'immersive setup failed: %{public}s', error.message);
    }
  }
}
