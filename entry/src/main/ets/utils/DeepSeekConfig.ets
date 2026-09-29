// DeepSeek 网页端常量与兜底适配脚本。
// 说明：官方网页端（chat.deepseek.com）本身已提供移动端布局，这里的脚本仅做
// "经验兜底"（参考 dsh-mobile 的 ZCode 移动适配原则），不强行改动官方样式。

export const DEEPSEEK_HOME: string = 'https://chat.deepseek.com/';
// 第十九轮删除：DEEPSEEK_SHARE_TEXT（'DeepSeek · 探索未至之境\nhttps://chat.deepseek.com/'）。
// 用户拍板按 iOS 移除顶栏「分享会话链接」→ pages/Index.ets 的 copyLink() 与对应 import 一并下线
// ⇒ 该常量全工程零消费者（代码行命中 0）。本工程纪律是不留"零消费者假旋钮"：
// 真需要时从 git 历史取回即可。证据见 内部验证记录 §4。

export const MOBILE_ADAPTER_JS: string = `
(function () {
  var STYLE_ID = '__deepseek_hm_mobile_style__';
  var VIEWPORT_ID = '__deepseek_hm_mobile_viewport__';
  // injectStyle() 的成品缓存（键 = topInset；理由见该函数开头的"结果缓存"段）
  var cssCacheKey = '';
  var cssCacheText = '';
  // 选中态胶囊的公共声明串：三处（aria 选择器 / 页签 accent / 分段 accent）逐字相同，
  // 抽成常量既省下发字节，又保证三处永远一致（不一致 = 同一个选中态在两处长得不一样）。
  var ACCENT_DECL = '{ background: var(--dsh-set-card) !important; color: var(--dsh-set-text) !important; font-weight: 600 !important; box-shadow: 0 1px 3px var(--dsh-set-shadow) !important; }';

  // —— 顶层单例守卫（本轮新增，性能第一优先）——
  // 本脚本每次注入都会新建一整套闭包：若不设防，**每注入一次**就会多挂
  // 2 个 window 监听（DOMContentLoaded / load）、1 个 matchMedia 监听、1 个 5s 巡检定时器。
  // 而一次页面加载至少注入两次（onPageEnd + ready 补注入），键盘/避让区变化还会再叠加 ——
  // 实测连注 3 次后巡检定时器就有 3 份，网页侧白白多跑两倍的巡检。
  // 这里按 SHELL_JS 同款写法：首个实例把 alive 挂在 window 上，后续注入只做一次幂等修正即返回；
  // 同时把注入次数记进 boots，让回归脚本能直接读出"这一次页面加载到底注入了几次"。
  // 与 __deepseekHmAdapterActive（每次 run 都置 true，供巡检判活/调试钩子用）是两个用途不同的字段。
  var P = window.__deepseekHmAdapter;
  if (P && P.alive) {
    P.boots = P.boots + 1;
    try { P.run(); } catch (e0) {}
    return;
  }

  // 单例登记对象：**必须在文件最前面建好**（下面的巡检定时器闭包、可见性回调都要引用它）。
  // alive = 本脚本已经装过一次；boots = 注入次数（回归脚本据此断言"一次页面加载只装一份"）；
  // patrols / patrolSkipped = 巡检实跑次数与"因页面不可见而跳过"的次数。
  var ADAPTER = {
    alive: true,
    boots: 1,
    run: null,
    patrols: 0,
    patrolSkipped: 0
  };
  window.__deepseekHmAdapter = ADAPTER;

  function injectStyle() {
    // 侧栏防闪烁核心规则：官方底部 sheet（._519be07）原始几何 absolute/top:20px，
    // 会被 body 安全区 padding 挤压；旧方案靠 JS 延时 200ms 重锚定，而官方进场动画
    // （transform: translateY(36px)→0）恰好 0.2s —— 动画在原始几何里播完后再跳变，
    // 即用户看到的“打开闪烁”。改为样式表即效规则：sheet 首帧就以最终几何
    // （fixed / 状态栏+6 / 贴底）排版，transform 动画在正确几何内播放，全程无跳变。
    // 媒体条件与官方 sheet 规则一致（not all and (min-width:768px)），
    // 桌面/抽屉形态（≥768px）不受影响。
    // —— 结果缓存（本轮性能项）——
    // 本函数每次调用都要把下面那一整块（约 9 KB CSS）重新拼接一遍，只为和已挂载节点的
    // textContent 比一次字符串；而它在冷启动到首次交互之间会被调用 20 次以上
    //（run() 自身 + DOMContentLoaded/load 各排 3 次 + 每次 rescan→markShell + 重注入守卫分支）。
    // 拼接结果只依赖**一个输入** topInset（sheetTop / drawerPadCss / setTopCss 都只用它），
    // 故以它为键缓存成品文本：键没变且节点内容一致就直接返回；键变了（键盘/旋转/避让区变化）
    // 照旧重建。语义与"每次重建再比较"完全等价，只是省掉了重建这一步。
    var insetsForStyle = getInsets();
    var cachedNode = document.getElementById(STYLE_ID);
    if (String(insetsForStyle.top) === cssCacheKey && cachedNode !== null &&
      cachedNode.textContent === cssCacheText) {
      return;
    }
    cssCacheKey = String(insetsForStyle.top);
    var sheetTop = insetsForStyle.top > 0 ? (insetsForStyle.top + 6) : 20;
    // 抽屉（.dc04ec1d 为当前 bundle 的侧栏抽屉根类）安全区避让必须由 CSS 首帧保证：
    // 官方打开抽屉只产生一次 class 突变（动画为 CSS transition，合成器驱动），
    // JS 快速路径的写入时机存在不可控竞态（真机实测同一构建时灵时不灵），
    // 而防抖兜底要 200ms~1s——动画先在无避让几何里播放、结束后内容下移 52px，
    // 即“侧栏打开闪烁”。CSS 规则零时序依赖，首帧必然生效；官方改版类名变化时
    // 由 fastPath/防抖的 JS 路径（写 inline padT）兜底。
    var drawerPadCss = '';
    if (insetsForStyle.top > 0) {
      drawerPadCss = '@media not all and (min-width: 768px) { .dc04ec1d { padding-top: ' +
        (insetsForStyle.top + 6) + 'px !important; border-radius: 0px 24px 24px 0px !important; overflow: hidden !important; } }';
    }
    // —— 官方「系统设置」弹层 → 手机版设置页（第十七轮 T2）——
    // 观感基准是用户提供的对照物（华为「设置」）：全屏面板、标题行固定、页签一行排满、
    // 圆角卡片分组、行高 60、标签 16px、发丝分隔线。
    // 规则一律挂在适配器自己打的 data-dsh-settings* 属性上 —— 官方类名多是 CSS Module
    // hash（_6c040bb / b40079d7 …），跟着 hash 写样式会在官方某次发布后**静默失效**；
    // 打标那一步只用 ds-* 语义类 + 结构关系（见 markSettingsModal）。
    // 配色不写死十六进制：syncSettingsColors() 从弹层自身实测色采样后写成内联 CSS 变量
    //（--dsh-set-page/card/text/fill/hair…），页面主题一变（含"跟随系统"下的深色）自动跟上；
    // 下面这组只是采样落笔之前的兜底，避免注入瞬间闪一下默认色。
    // 整块包在 not all and (min-width: 768px) 里：桌面形态（≥768px）零影响。
    // 顶部让位 = 下发让位量（__dshTopInsetPx，R20 官方档已含完整顶栏让位 topInset + NAV_TITLE_SLOT_VP）。
    // 第二十一轮改：原值 20（R17 自绘顶栏时代的渐变过渡带防丢包加数）在 R20 官方档已失效 ——
    // 其一，R20 起顶栏改官方 Navigation 标题栏，渐变过渡带（TOPBAR_FADE_H）整体删除，
    //   __dshTopInsetPx 实测等于 body padding-top，即完整顶栏让位量（真机 111.714 CSS px），
    //   面板让位再多加 20px 会让标题行比顶栏下沿低 20px、中间露出一块面板底色（本轮修的设置页空白）；
    // 其二，R18 已用 hitTestBehavior 根治顶栏丢包带（见 pitfalls 3.0-159），关闭钮中心实测在可点区，无需再加防护。
    // 故置 0：设置面板标题行紧贴磨砂顶栏下沿、与网页正文让位同源无缝。
    var TOPBAR_FADE_GUARD = 0;
    // —— 深色兜底变量的唯一真源（两份字面量会漂移，抽成常量）——
    // 下面这两组都**各被两条判据**引用：媒体特性（系统深色 + 网页 Auto）与站点自己的
    // html.dark（见 darkRules 的说明）。写在两处的字面量一旦改一处漏一处，就是
    // "某个主题下配色对、另一个主题下不对"这类最难查的静默不一致。
    var SET_DARK_VARS = '--dsh-set-page: #151517; --dsh-set-card: #2c2c2e; --dsh-set-text: #f9fafb; --dsh-set-fill: #43454a; --dsh-set-hair: rgba(249, 250, 251, 0.12); --dsh-set-muted: rgba(249, 250, 251, 0.62); --dsh-set-shadow: rgba(0, 0, 0, 0.40);';
    var GLASS_DARK_VARS = '--dsh-glass-ring: rgba(255, 255, 255, 0.22); --dsh-glass-glow: rgba(255, 255, 255, 0.08); --dsh-glass-fill: rgba(255, 255, 255, 0.07);';
    // 站点深色判据（**首帧**就成立的那一条）。真机实测 prefers-color-scheme 恒为 false：
    // 站点把主题放在 html 的 dark 类上，不是媒体特性
    //（内部验证记录 原文："站点用的是自己的 html.dark 类"）。
    // 只写媒体查询 ⇒ 用户选"深色"而系统是浅色时，设置弹层与悬浮圆框会先按浅色兜底值画一帧，
    // 要等 syncSettingsColors() 采样（JS，晚于首帧）才变深 —— 就是"打开设置页白闪一下"。
    // html/body 两条都写上：类挂在哪个元素上官方改版过，多写一条只多几十字节，判错就是整块失效。
    var SITE_DARK_SEL = 'html.dark, body.dark';
    var setTopCss = insetsForStyle.top > 0 ? ((insetsForStyle.top + TOPBAR_FADE_GUARD) + 'px') : 'env(safe-area-inset-top, 0px)';
    var settingsCss = [
      '@media not all and (min-width: 768px) {',
      '[data-dsh-settings-root="1"] { --dsh-set-page: #f1f3f5; --dsh-set-card: #ffffff; --dsh-set-text: #0f1115; --dsh-set-fill: #f1f3f5; --dsh-set-hair: rgba(15, 17, 21, 0.09); --dsh-set-muted: rgba(15, 17, 21, 0.55); --dsh-set-shadow: rgba(0, 0, 0, 0.10); }',
      // 外壳：贴原生磨砂顶栏下沿（top = topInset）一直铺到屏幕底。顶上 padding 那段
      //（原生顶栏覆盖区）也刷面板底色：磨砂顶栏底下有自己的底色，才不会透出一条灰带。
      '[data-dsh-settings-root="1"] { position: fixed !important; top: 0 !important; left: 0 !important; right: 0 !important; bottom: 0 !important; width: 100vw !important; height: auto !important; max-height: none !important; padding: ' + setTopCss + ' 0 0 0 !important; margin: 0 !important; background: var(--dsh-set-page) !important; overflow: hidden !important; display: flex !important; flex-direction: column !important; }',
      // 三级 flex 链 wrapper → .ds-modal → focus-lock → 面板：都 flex:1 + min-height:0
      // 才能吃满剩余高度，否则官方 max-height:800px 会把面板截在半空。
      '[data-dsh-settings-lock="1"], [data-dsh-settings-modal="1"] { display: flex !important; flex-direction: column !important; flex: 1 1 auto !important; min-height: 0 !important; height: auto !important; margin: 0 !important; }',
      '[data-dsh-settings-panel="1"] { display: flex !important; flex-direction: column !important; flex: 1 1 auto !important; min-height: 0 !important; height: auto !important; max-height: none !important; border-radius: 0 !important; box-shadow: none !important; background: var(--dsh-set-page) !important; }',
      '[data-dsh-settings-main="1"] { display: flex !important; flex-direction: column !important; flex: 1 1 auto !important; min-height: 0 !important; padding: 0 16px !important; }',
      '[data-dsh-settings-maininner="1"] { display: flex !important; flex-direction: column !important; flex: 1 1 auto !important; min-height: 0 !important; }',
      // 第二十一轮改（用户需求）：四个页签移到底部做底部功能栏（参考 aa-hm 底部功能栏形态）。
      // mainInner 是 flex column：内容 body 在上（order 默认 0 即可，占满剩余高），
      // 页签行 tabs 用 order:2 压到最底、贴手势条上方，作为底部功能栏常驻。
      '[data-dsh-settings-body="1"] { flex: 1 1 auto !important; min-height: 0 !important; margin: 0 !important; order: 1 !important; }',
      // 内容区**末端留白** = 胶囊高 + 手势条避让那一段（第二十一轮十一改）：滚到底时最后一行停在
      // 这段留白上方、不会被胶囊永久盖住；而滚动**过程中**的内容会从胶囊背后穿过 ⇒ 磨砂才有内容可糊。
      // ⚠️ 留白必须放在**内容区**（这里），不能靠页签行撑 —— 真机实测那样会把页签行撑到 152px、
      //    body 只到 800 而面板到 952，底部多出一段死空白（几何读数见 内部验证记录）。
      '[data-dsh-settings-bodyinner="1"] { padding: 2px 0 92px 0 !important; min-height: 0 !important; }',
      // ★ 第二十一轮·三改（用户要求「将系统设置那一行做成整页的标题栏，将 ✕ 换成 <」，
      //   且「标题栏要用官方组件，实现模糊效果和沉浸光感」）：
      // 这一行整行交给**原生官方标题栏**承载 —— 本工程顶栏本来就是官方 Navigation 标题栏
      // + 官方沉浸材质（R20），所以「标题栏用官方组件」这条在原生侧**已经成立**，
      // 这里要做的是把网页这一行**让出去**：高度归 0（内容上移到原生标题栏下沿）、标题整条不画。
      // 观感结果：原生标题槽居中显示「系统设置」、左槽是原生返回钮（尖括号图标，走官方沉浸光感）。
      '[data-dsh-settings-panel="1"] > .ds-modal-content__header-wrapper { height: 0 !important; min-height: 0 !important; padding: 0 !important; margin: 0 !important; border: 0 !important; overflow: visible !important; background: transparent !important; }',
      '[data-dsh-settings-panel="1"] .ds-modal-content__title { display: none !important; }',
      // ✕ 的**几何必须保留**：原生返回钮的关闭动作用的就是「对它派发一次点击」（桥 closeSettings）。
      // ⇒ 不能用 display:none（rect 会全 0，tap() 会退到祖先、点错元素）。
      // 做法：fixed 定位到「屏幕底部、原生底栏胶囊的正中」+ opacity:0 ——
      // 不可见，且该位置被**上层原生底栏**盖住 ⇒ 真实触摸到不了它，只有程序化 dispatchEvent 能到
      // （避免用户点底栏时顺手把设置页关掉）。
      '[data-dsh-settings-panel="1"] > .ds-modal-content__header-wrapper > .ds-button { position: fixed !important; left: 50% !important; bottom: 48px !important; width: 44px !important; height: 44px !important; margin: 0 0 0 -22px !important; opacity: 0 !important; z-index: 0 !important; }',
      // 页签行：官方是"横向滚动条 + 右侧渐隐箭头"，4 个 108px 页签在 403px 里必裁掉最后一个。
      // 改成 flex:1 1 0 + min-width:0 等分整行；文字过长在页签内部省略 ⇒ scrollWidth 恒等于
      // clientWidth（这也是验收断言里"不横滚"的那一条）。overflow:hidden 兜住任何残留溢出。
      // tabs 容器：压到 mainInner 底部（order:2）、贴手势条上方；底部留底部安全区 + 一点呼吸。
      // margin 顶部与内容区分开、底部让出手势条（insetsForStyle.bottom 即下发的底部避让量）。
      // ★ 第二十一轮（用户要求「参考 aa-hm 的底部功能栏，重新写设置页的功能栏」）：
      // 这行页签**不再承担视觉** —— 四个页签由**原生**渲染（最终档 = Stack 浮层里的自绘胶囊，
      // 见 view/SettingsTabBar.ets 文件头）。它留在页面里承担两件事：
      //   ① **接派发**：原生底栏点某项 → 桥调 setSettingsTab(i) → 对这个不可见页签派发点击；
      //   ② **底部让位**（第二十一轮十一改恢复）：靠 order: 2 在文档流里占住面板尾部，
      //      并用 padding-bottom 留出**胶囊高 + 手势条避让**那一段 —— 于是：
      //        · 内容**末端**停在胶囊上方，不会被永久盖住；
      //        · 而滚动**过程中**的内容会从胶囊背后穿过 ⇒ 那层 18vp 磨砂才有内容可糊
      //          （这正是用户拍板「改回浮层 + 让内容穿过」要的观感）。
      //      ⚠️ 工具条那条路（占位式）之所以被换掉，就是因为没有这一段 —— 底栏背后永远是纯色。
      //
      // ⚠️ 隐藏只能用 opacity（R17 实测结论：visibility / pointer-events 会破坏合成事件命中，
      //    而这条链路**全靠 dispatchEvent**，见 EXPERIENCE 第 1.11-80 条）；
      //    opacity:0 保留真实 rect（tap() 取的坐标才有效）。
      // ⚠️ pointer-events: none 仍然必需：这一行虽然不可见，但它在文档流里占着屏幕底部那一段，
      //    不关掉命中测试的话，落在它上面的**真实触摸**会被它吃掉（该处真实触摸应归原生胶囊）。
      //    程序化 dispatchEvent 不受 pointer-events 影响 ⇒ 派发链路照常。
      '[data-dsh-settings-tabs="1"] { order: 2 !important; flex: 0 0 auto !important; width: 100% !important; margin: 0 !important; padding: 4px 0 30px 0 !important; overflow: hidden !important; opacity: 0 !important; pointer-events: none !important; }',
      // 条带间距 6px → 4px：这 6px 是**每行固定成本**（3 个间隙），收掉 2px 就还给页签
      // 6px 的可用宽度。相对于"按内容定宽"的修法，这里动的是行成本而不是每个页签的预算。
      '[data-dsh-settings-tabstrip="1"] { display: flex !important; width: 100% !important; padding: 0 !important; margin: 0 !important; gap: 4px !important; }',
      '[data-dsh-settings-deco="1"]:not([data-dsh-settings-tabstrip="1"]) { display: none !important; }',
      // —— 本轮修「页签文字被省略号截断」（模拟器 通用…/账号…/数据…/服务…）——
      // 旧值 flex:1 1 0 = **基准宽 0、只按 1/4 等分**：每个页签恒等于行宽/4，与内容无关，
      // 于是"内容比 1/4 宽"就必然截断 —— 模拟器与真机 CSS 视口不同（真机 443、模拟器按
      // density 560 折算约 376），真机 98px/页签放得下、模拟器 81px 放不下，就成了
      // "同一份 CSS 只差字体度量就翻到截断"的脆弱布局。
      // 改成 flex:1 1 auto = **基准宽 = 内容宽**：放得下就绝不截断（行内富余按 grow 分配），
      // 放不下仍按 flex-shrink 收缩（min-width:0 保留），因此"4 个页签全在行内、不横滚"
      // 这两条 r17 不变量**只会更稳**，不会退化。
      // 同时把每页签的固定成本收掉约 8px（内边距 4→2、图标与文字间距 6→4），
      // 给"基准宽 = 内容宽"留出余量。
      // 底部功能栏单项（第二十一轮改）：从顶部横排胶囊改为 aa-hm 式竖排 tab（图标上、文字下）。
      // 无圆角底、透明背景，选中态靠颜色而非胶囊底；整项可点高度 ≥ 44。
      '[data-dsh-settings-tab="1"] { flex: 1 1 0 !important; width: auto !important; min-width: 0 !important; max-width: none !important; margin: 0 !important; height: 54px !important; padding: 0 !important; border-radius: 0 !important; background: transparent !important; display: flex !important; flex-direction: column !important; align-items: center !important; justify-content: center !important; gap: 3px !important; color: var(--dsh-set-muted) !important; }',
      // 文字仍**保留** ellipsis（不改成 clip）：真正修好之后这里根本不会触发；
      // 万一将来落在极窄视口（内容宽总和 > 行宽）上被 shrink 到放不下，省略号能让用户
      // 看出"字没显示全"，clip 则是静默截断 —— 后者更难发现，不该作为兜底。
      // letter-spacing 显式归零：官方按钮可能带字距，4 个汉字上多出的字距正好压在临界值上。
      '[data-dsh-settings-tab="1"] .ds-button__content { font-size: 11px !important; letter-spacing: 0 !important; white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis !important; }',
      '[data-dsh-settings-tab="1"] .ds-button__icon { width: 20px !important; height: 20px !important; font-size: 20px !important; }',
      // 页签与分段的图标层同款，合并成一组选择器
      '[data-dsh-settings-tab="1"] .ds-button__icon, [data-dsh-settings-seg="1"] .ds-button__icon { flex: 0 0 auto !important; }',
      // 官方的按压/聚焦环是 .ds-button__background::after 上的 inset:-2px 外扩层，
      // 它让每个页签的"布局溢出"比自身宽 2px —— 4 个页签排满整行时，最后那 2px 会把
      // 页签行的 scrollWidth 顶到 clientWidth 之上（"不横滚"这条断言就会失败）。
      // 收成 inset:0 并跟随胶囊圆角：环仍然在，只是不再越出页签自身。
      '[data-dsh-settings-tab="1"] .ds-button__background::after { inset: 0 !important; border-radius: 10px !important; }',
      '[data-dsh-settings-seg="1"] .ds-button__background::after { inset: 0 !important; border-radius: 9px !important; }',
      // 官方的描边是独立的 .ds-button__border 层（0.67px rgba(0,0,0,.1)）：页签是 borderless
      // 没有它，但主题三选一带着 —— 段控件里每项都描边会显得很"网页"，去掉。
      '[data-dsh-settings-tab="1"] .ds-button__border, [data-dsh-settings-seg="1"] .ds-button__border { display: none !important; }',
      // 选中态胶囊：官方那套 aria 标记当前版本没有，真正的选中标记是个 hash 类，
      // 由 ensureSettingsAccent() 在打标时"现场发现"后写进一张小样式表（见那里的注释）。
      // 底部功能栏选中态（第二十一轮改）：aa-hm 式「选中 = 变色 + 加粗」，**不画卡片底**
      // （ACCENT_DECL 那套卡片底 + 阴影是顶部横排胶囊的选中形态，用在竖排透明项上会长出一块底）。
      // 颜色用 var(--dsh-set-text) 保证深浅色都跟随主题。
      '[data-dsh-settings-tab="1"][aria-selected="true"], [data-dsh-settings-tab="1"][aria-current="page"] { background: transparent !important; box-shadow: none !important; color: var(--dsh-set-text) !important; font-weight: 600 !important; }',
      // 内容：行 → 圆角卡片。连续的行共用一张卡（first/mid/last 定圆角与发丝分隔线，
      // 用 inset box-shadow 而不是 border：不改盒模型、不产生 1px 高度抖动）。
      '[data-dsh-settings-row="1"] { display: flex !important; align-items: center !important; min-height: 60px !important; padding: 0 16px !important; font-size: 16px !important; background: var(--dsh-set-card) !important; color: var(--dsh-set-text) !important; }',
      '[data-dsh-settings-row="1"][data-dsh-settings-cardpos="first"] { border-radius: 16px 16px 0 0 !important; }',
      '[data-dsh-settings-row="1"][data-dsh-settings-cardpos="mid"] { box-shadow: inset 0 1px 0 var(--dsh-set-hair) !important; }',
      '[data-dsh-settings-row="1"][data-dsh-settings-cardpos="last"] { border-radius: 0 0 16px 16px !important; box-shadow: inset 0 1px 0 var(--dsh-set-hair) !important; margin-bottom: 12px !important; }',
      '[data-dsh-settings-row="1"][data-dsh-settings-cardpos="only"] { border-radius: 16px !important; margin-bottom: 12px !important; }',
      // 行右侧的值：官方是"填充色小胶囊"，手机版设置页里应是**素色文字 + 箭头**。
      '[data-dsh-settings-row="1"] .ds-select { background: transparent !important; color: var(--dsh-set-muted) !important; }',
      // 分组卡片（当前只有"主题"一张）：卡内标题 + 三选一。
      '[data-dsh-settings-group="1"] { background: var(--dsh-set-card) !important; border-radius: 16px !important; padding: 14px 16px 16px 16px !important; margin: 0 0 12px 0 !important; font-size: 16px !important; color: var(--dsh-set-text) !important; }',
      // 三选一改成分段控件观感（官方是三张 82px 高的描边大卡，手机上太"网页"）。
      '[data-dsh-settings-segrow="1"] { display: flex !important; gap: 4px !important; background: var(--dsh-set-fill) !important; border-radius: 12px !important; padding: 3px !important; margin: 12px 0 0 0 !important; }',
      '[data-dsh-settings-seg="1"] { flex: 1 1 0 !important; min-width: 0 !important; width: auto !important; height: 44px !important; border-radius: 9px !important; display: flex !important; flex-direction: row !important; align-items: center !important; justify-content: center !important; gap: 6px !important; color: var(--dsh-set-muted) !important; }',
      '[data-dsh-settings-seg="1"] .ds-button__content { font-size: 13px !important; white-space: nowrap !important; }',
      // —— 设置页打开期间的"无滑块"四步（第十七轮 T6 第二单）——
      // 用户看到的"滑块"：触摸拖动后右侧出现一条竖向滚动条（截图实测 x=1248..1256、
      // #919294、y 212..2828）——**跨度几乎整屏**，所以不能只写设置页内的容器，
      // 必须把 html/body 本身也覆盖（文档级滚动条同样会被画在 fixed 面板之上）。
      // 标记由 markSettingsModal 打/摘（data-dsh-settings-open），关页即恢复，绝不影响其它弹层。
      'html[data-dsh-settings-open="1"], html[data-dsh-settings-open="1"] body { scrollbar-width: none !important; -ms-overflow-style: none !important; overflow: hidden !important; overscroll-behavior: none !important; }',
      'html[data-dsh-settings-open="1"] * { scrollbar-width: none !important; }',
      // ArkWeb 是 Chromium 内核 ⇒ 真正生效的是 ::-webkit-scrollbar；标准属性留着以防内核切换。
      // 本页所有容器的 offsetWidth-clientWidth 都是 0（无经典占位滚动条），
      // 所以隐藏滚动条不会引起任何布局位移（真机实测：宽度数字前后一致）。
      'html[data-dsh-settings-open="1"]::-webkit-scrollbar, html[data-dsh-settings-open="1"] body::-webkit-scrollbar, html[data-dsh-settings-open="1"] *::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }',
      'html[data-dsh-settings-open="1"]::-webkit-scrollbar-thumb, html[data-dsh-settings-open="1"] *::-webkit-scrollbar-thumb { background: transparent !important; }',
      // 官方自绘滚动条槽（.ds-scroll-area__gutters 是 sticky 列 + 竖条，位置正好落在
      // 用户截图那条 x≈420(CSS) 处）——整体隐藏，它已经没有任何表达功能。
      '[data-dsh-settings-body="1"] .ds-scroll-area__gutters, [data-dsh-settings-body="1"] .ds-scroll-area__vertical-gutter, [data-dsh-settings-body="1"] .ds-scroll-area__horizontal-gutter, [data-dsh-settings-body="1"] .ds-scroll-area__vertical-bar, [data-dsh-settings-body="1"] .ds-scroll-area__horizontal-bar { display: none !important; }',
      // 亚像素溢出的源头：官方 .ds-scroll-area__content--stretch 用 min-height 撑到**整数**
      // 734px，而滚动区内容盒是小数 733.57px ⇒ 内容恒比滚动区高 0.43px（scrollHeight/clientHeight
      // 取整后都是 734，肉眼看不见，但"能滚 0.4px"成立，触摸拖动时浏览器就画出滑块）。
      // 收掉 min-height（已并入上面那条同名规则）：内容按自身高度排布 ⇒ 短内容零溢出、
      // 长内容照常可滚（见 pinSettingsBody）。
      // 钉住：滑动不再传给背后的聊天页（overscroll 链式滚动 / 回弹）。
      // touch-action 只收到 pan-y：整页不许横拖/缩放手势，但**必须**给纵向 pan 留口子 ——
      // 内容真超长时它还得能滚（touch-action: none 会把内层滚动一起掐死）。
      '[data-dsh-settings-root="1"], [data-dsh-settings-lock="1"], [data-dsh-settings-modal="1"], [data-dsh-settings-panel="1"], [data-dsh-settings-main="1"], [data-dsh-settings-maininner="1"], [data-dsh-settings-body="1"] { overscroll-behavior: contain !important; }',
      '[data-dsh-settings-root="1"] { touch-action: pan-y !important; }',
      '}',
      // 深色兜底之一：媒体查询**嵌套**写（外层是手机上有效的唯一判据）。不能写成
      // '@media not all and (min-width:768px) and (prefers-color-scheme: dark)' ——
      // not 否定的是整条查询，那条规则在"浅色手机"上同样成立，深色配色会反噬浅色。
      '@media not all and (min-width: 768px) { @media (prefers-color-scheme: dark) {',
      '[data-dsh-settings-root="1"] { ' + SET_DARK_VARS + ' }',
      '} }',
      // 深色兜底之二：**站点自己的深色类**（首帧判据，见 SITE_DARK_SEL 处的实证）。
      // 选择器特异性 (0,2,0) 高于上面那条 [data-dsh-settings-root="1"]，故与声明顺序无关。
      '@media not all and (min-width: 768px) {',
      SITE_DARK_SEL + ' [data-dsh-settings-root="1"] { ' + SET_DARK_VARS + ' }',
      '}'
    ].join('');
    var cssText = [
      'html, body { max-width: 100vw !important; overflow-x: hidden !important; }',
      'body { min-width: 0 !important; width: 100% !important; }',
      '*, *::before, *::after { box-sizing: border-box; }',
      '#app, #root, main, .main, .app, .content { min-width: 0 !important; max-width: 100vw !important; }',
      'pre, code, table, .code-block { max-width: 100% !important; white-space: pre-wrap !important; overflow-wrap: anywhere !important; overflow-x: auto !important; }',
      'img, svg, video, canvas { max-width: 100% !important; height: auto !important; }',
      'input, textarea, select { max-width: 100% !important; }',
      // 推广元素与“首页新建对话”隐藏：官方框架会在隐藏后 ~4ms 用 inline style
      // 恢复 display（真机实测拉锯循环），单纯写 style.display 无效——改用
      // data 属性标记 + !important 样式表压制（React 重渲染不管理未知 data
      // 属性，无法被恢复）；style.display='none' 保留作首帧兜底。
      // 两条同款规则合成一组选择器（合并重复样式片段，语义完全不变）
      '[data-dsh-promo="1"], [data-dsh-home-hidden="1"] { display: none !important; }',
      // 侧栏圆角：用带 !important 的样式表规则（内联样式赢不过它，React 重渲染不会冲掉）
      '[data-dsh-drawer="left"] { border-radius: 0px 24px 24px 0px !important; overflow: hidden !important; }',
      '[data-dsh-drawer="right"] { border-radius: 24px 0px 0px 24px !important; overflow: hidden !important; }',
      // 抽屉“透底闪屏”修复（2026-09-07 模拟器逐帧取证）：官方打开动画期间面板子元素
      // （b8812f16，h=765）以 opacity 0→1 交叉淡入约 300ms，而抽屉根元素背景透明——
      // 滑动全程主页面内容从抽屉里透出来（用户所见“闪屏”）。对策：JS 在打标抽屉时把
      // 面板子元素的不透明底色抄写为根元素上的 CSS 自定义属性 --dsh-drawer-bg，并用
      // ::before 伪元素铺在“避让线以下”（top=--dsh-drawer-padtop，即根 padding-top 处，
      // 与面板矩形重合），圆角 inherit 跟随根（0 24 24 0）——状态栏条带仍透出页面底，
      // 顶缘圆角保持在避让线处（官方避让形态不变）。
      // 踩坑记录：①根元素直接 background 铺色（border-box）把圆角顶到屏幕顶，与避让
      // 冲突；②改 background-clip: content-box 后顶角又没了——content-box 的圆角半径
      // 要减去 padding（24-44.86→0），顶角退化成直角把面板圆角填平。::before 方案
      // 铺色范围与圆角都独立可控。自定义属性写在根上、规则走样式表 !important：
      // React 恢复 inline style 也管不到它。
      '[data-dsh-drawer][style*="--dsh-drawer-bg"]::before { content: ""; position: absolute; left: 0; right: 0; bottom: 0; top: var(--dsh-drawer-padtop, 0px); background: var(--dsh-drawer-bg); border-radius: inherit; pointer-events: none; }',
      // 底部 sheet 锚定后强制保持官方上圆角，任何情况下上角不得退化成直角
      '[data-dsh-sheet="1"] { border-radius: 24px 24px 0 0 !important; }',
      // 侧栏开关按钮“透明悬浮圆框”（2026-09-07 需求）：给左上角图标开关按钮
      // （data-dsh-floatbtn，由 markSidebarToggleButtons 按几何打标）外挂一圈
      // ::after 圆框——半透明磨砂底 + backdrop 模糊 + 1px 环 + 柔影，呈悬浮玻璃感；
      // 官方按压/悬停光效在 .ds-button__background 子层，::after pointer-events:none
      // 完全不影响官方光效叠加。深浅色用 CSS 变量切换（媒体特性 + 站点 dark 类两条判据）。
      ':root { --dsh-glass-ring: rgba(0, 0, 0, 0.16); --dsh-glass-glow: rgba(0, 0, 0, 0.10); --dsh-glass-fill: rgba(255, 255, 255, 0.42); }',
      // 深色两判据（与设置页那组同源，见 SITE_DARK_SEL）：圆框只在"原生外壳把顶栏
      // 交还官方"时才会出现（data-dsh-floatbtn），而那种状态下页面主题同样由官方那套
      // 三态开关决定 —— 只写媒体特性时，"系统浅色 + 站点深色"会给出一圈深色环（看不清）。
      '@media (prefers-color-scheme: dark) { :root { ' + GLASS_DARK_VARS + ' } }',
      SITE_DARK_SEL + ' { ' + GLASS_DARK_VARS + ' }',
      // z-index:0 使按钮自成层叠上下文，::after 用 z-index:-1 沉到“图标与官方
      // .ds-button__background 光效层之下、按钮透明底之上”：图标不被玻璃糊住，
      // 官方悬停/按压光效原样叠加在圆框之上。
      '[data-dsh-floatbtn="1"] { position: relative; z-index: 0; }',
      // inset 从 -4px 收到 -2px：首版圆框离图标太远（44px 按钮套 52px 框显大），
      // 2px 外扩贴合“外边圆框”的观感。
      '[data-dsh-floatbtn="1"]::after { content: ""; position: absolute; inset: -2px; z-index: -1; border-radius: 999px; pointer-events: none;',
      '  background: var(--dsh-glass-fill); border: 1px solid var(--dsh-glass-ring);',
      '  box-shadow: 0 2px 10px var(--dsh-glass-glow);',
      '  -webkit-backdrop-filter: blur(10px) saturate(1.4); backdrop-filter: blur(10px) saturate(1.4);',
      '  transition: transform 0.14s ease, opacity 0.14s ease; }',
      // 按压反馈：环随按钮收缩变淡（呼应原生 stateStyles pressed 的 scale+brightness 配方）
      '[data-dsh-floatbtn="1"]:active::after { transform: scale(0.9); opacity: 0.72; }',
      '@media not all and (min-width: 768px) { ._519be07 { position: fixed !important; top: ' + sheetTop + 'px !important; bottom: 0 !important; left: 0 !important; right: 0 !important; width: 100vw !important; max-width: none !important; margin: 0 !important; } }',
      drawerPadCss,
      settingsCss,
      // —— 原生悬浮顶栏配套 ——
      // Web 组件铺满整个窗口后，网页视口比改造前高出一个 topInset；顶栏悬浮其上，
      // 滚动内容顶部必须留出 topInset 的占位（节点由 ShellScript.ensureTopSpacer 插入，
      // 只在这里定样式）。
      '[data-dsh-topspacer="1"] { flex: 0 0 auto !important; width: 100% !important; pointer-events: none !important; }',
      // —— 输入坞下移 ——
      // 对话页滚动容器自带 margin-bottom: env(safe-area-inset-bottom)（真机实测 33px），
      // 再叠加官方在输入框下方的免责声明行（28px），输入坞距屏幕底被顶到 62px，观感上
      // "离底栏还很远"。收到 12px 后输入框底边落到屏幕底上方约 33px，免责声明行正好落在
      // 手势胶囊之前，两者不重叠。
      '.ds-virtual-list { margin-bottom: 12px !important; }',
      '@supports (padding: env(safe-area-inset-bottom)) { body { padding-bottom: env(safe-area-inset-bottom); } }'
    ].join('');
    // 记下成品：下次同 key 直接复用（见函数开头的"结果缓存"）。
    cssCacheText = cssText;
    // 幂等：内容未变时保留原 <style> 节点。旧写法每次都移除重建，侧栏打开期间
    // 若适配器重注入（如主题切换），圆角/锚定规则会短暂失效造成二次闪烁。
    var old = document.getElementById(STYLE_ID);
    if (old && old.textContent === cssText) {
      return;
    }
    if (old && old.parentNode) {
      old.parentNode.removeChild(old);
    }
    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = cssText;
    document.head.appendChild(style);

    var viewport = document.getElementById(VIEWPORT_ID);
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.id = VIEWPORT_ID;
      viewport.setAttribute('name', 'viewport');
      document.head.appendChild(viewport);
    }
    viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=3.0, viewport-fit=cover');
  }

  function markHost() {
    if (document.documentElement) {
      document.documentElement.classList.add('deepseek-hm-host');
    }
    if (document.body) {
      document.body.classList.add('deepseek-hm-host');
    }
  }

  // 全屏沉浸：Web 铺满整个窗口（状态栏、导航条之下也是网页自身背景）。
  // body 按实测避区 padding：普通内容避开状态栏/导航条，padding 区域保留页面背景色，
  // 因此顶部“时间条”底色与页面统一，底部由页面背景完全覆盖，不再有应用层色条。
  function getInsets() {
    var top = Number(window.__dshTopInsetPx || 0);
    var bottom = Number(window.__dshBottomInsetPx || 0);
    return { top: top, bottom: bottom };
  }

  // —— 「原生外壳」改造后的性能红线（2026-09-10）——
  // 官方会话抽屉已交给原生侧栏渲染，只作为会话列表数据源保留在 DOM
  // （ShellScript 给它打 data-dsh-hide-drawer，visibility:hidden）。但它开合时的
  // class 突变仍会打到本适配器的观察器上——只要还继续对抽屉子树做同步排版测量
  // （逐节点 getComputedStyle + getBoundingClientRect），侧栏动画期间渲染主线程
  // 照样被占满，这**正是**本次要根治的卡顿。因此所有热路径对抽屉子树整体短路：
  // 一次 contains 判定（O(深度)）换掉成百次强制排版。
  function inNativeDrawer(el) {
    var d = window.__dshNativeDrawer;
    if (!d || !el) {
      return false;
    }
    try {
      if (d === el || d.contains(el)) {
        perf.drawerSkip = perf.drawerSkip + 1;
        return true;
      }
      return false;
    } catch (ignore) {
      return false;
    }
  }

  // 原生外壳是否已接管官方顶栏（ShellScript 隐藏顶栏时置位）。置位后“推广入口
  // 隐藏 / 首页右上角 ⊕ 几何兜底 / 侧栏开关悬浮圆框”全部失去目标——它们原本只
  // 存在于官方顶栏里。这些分支分别要做全文档遍历与逐节点几何判定，跳过它们是
  // 本次流畅性改造的第二大收益（原生外壳未生效时自动回退到旧行为）。
  function shellOwnsChrome() {
    return window.__dshShellOwnsChrome === true;
  }

  // 性能探针（轻量整数自增，供 CDP/DevTools 读取 diff 做回归断言）：
  // 「侧栏开合不再触发网页同步排版」这一改造目标靠它客观验证——
  // 改造后打开原生侧栏，fastNode/fixedScan 的增量应≈0；
  // 若把原生接管开关关掉复现旧路径，增量会立刻涨到数百。
  // 计数对象挂 window 跨注入复用，不与页面自身状态耦合。
  var perf = window.__dshPerf;
  if (!perf) {
    perf = { fastNode: 0, drawerSkip: 0, fixedScan: 0, homeScan: 0 };
    window.__dshPerf = perf;
  }
  // 原地复位（**不能**替换 window.__dshPerf 对象：本闭包持有首次创建的那个引用，
  // 外部替换对象会让计数与读取端分家，读数恒为 0 —— 回归脚本请一律用本钩子）
  window.__deepseekHmPerfReset = function () {
    perf.fastNode = 0;
    perf.drawerSkip = 0;
    perf.fixedScan = 0;
    perf.homeScan = 0;
  };

  function applySafeArea() {
    var body = document.body;
    var html = document.documentElement;
    if (!body || !html) {
      return;
    }
    var insets = getInsets();
    if (html.style.minHeight !== '100%') {
      html.style.minHeight = '100%';
    }
    if (body.style.minHeight !== '100%') {
      body.style.minHeight = '100%';
    }
    var bg = window.getComputedStyle(body).backgroundColor;
    if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)' &&
      html.style.backgroundColor !== bg) {
      html.style.backgroundColor = bg;
    }
    if (insets.top > 0 && body.style.paddingTop !== (insets.top + 'px')) {
      body.style.paddingTop = insets.top + 'px';
    }
    if (insets.bottom > 0 && body.style.paddingBottom !== (insets.bottom + 'px')) {
      body.style.paddingBottom = insets.bottom + 'px';
    }
  }

  // 官方移动端侧栏（会话历史/工具抽屉）是自下而上的圆角 sheet：
  //   ._519be07 (+ _233f913/scrollable) { position:absolute; top:20px; bottom:0;
  //     left:0; right:0; width:100vw; border-radius:24px 24px 0 0 }
  // 它锚定在“页面内定位容器”上，会被 body 安全区 padding 顶/底挤压，
  // 表现为只展开在屏幕中部、伸展不到顶/底。
  // 处理：<768px 时改锚到视口（fixed）：top=状态栏+6px（避开手机时间栏），
  // bottom=0（真正贴到底、由面板背景覆盖导航条区域），左右 0、宽 100vw；
  // 面板内部滚动填充补底部安全区内边距（列表最后一项不被手势条盖住）。
  function adjustMobileSheet() {
    try {
      var vw = window.innerWidth;
      if (vw >= 768) {
        return;
      }
      var insets = getInsets();
      var wantTop = insets.top > 0 ? (insets.top + 6) : 20;
      var nodes = document.querySelectorAll('._519be07');
      // ① 已知 bundle 的官方类（底部圆角 sheet）
      var anchored = 0;
      for (var i = 0; i < nodes.length; i = i + 1) {
        anchorSheetToViewport(nodes[i], wantTop, insets);
        if (nodes[i].getAttribute('data-dsh-sheet') === '1') {
          anchored = anchored + 1;
        }
      }
      // ① 已经锚定住了 ⇒ ② 只可能在同一棵子树里重复命中（anchorSheetToViewport 会给目标
      // 打 data-dsh-sheet，而 ② 的第一件事就是跳过带该标记的元素），直接返回。
      // 这一条 gate 有实打实的收益：② 要对**全文档** div/aside/nav/section 逐个
      // getComputedStyle，而本函数在每个 run()（冷启动 7 次）与每次防抖几何清理里都会跑。
      if (anchored > 0) {
        return;
      }
      // ② bundle 无关的几何兜底：absolute 全宽近全高的“底部 sheet”（旧/新版类名不同）
      try {
        var all = document.querySelectorAll('div, aside, nav, section');
        for (var k = 0; k < all.length; k = k + 1) {
          var el = all[k];
          if (!el || !el.isConnected || el.getAttribute('data-dsh-sheet') === '1') {
            continue;
          }
          if (inNativeDrawer(el)) {
            continue;
          }
          var cs = window.getComputedStyle(el);
          if (cs.position !== 'absolute' || cs.display === 'none' || cs.visibility === 'hidden') {
            continue;
          }
          var r = el.getBoundingClientRect();
          if (r.width < vw * 0.9 || r.height < vw * 0.6) {
            continue;
          }
          if (r.left > 2 || r.right < vw - 2) {
            continue;
          }
          if (r.top < 2 || r.top > insets.top + 80) {
            continue;
          }
          // 贴底部 + 高 z-index 的 sheet 面板
          if (r.bottom > vw - 2 && Number(cs.zIndex) >= 500) {
            anchorSheetToViewport(el, wantTop, insets);
          }
        }
      } catch (ignore) {
      }
    } catch (ignore) {
    }
  }

  function anchorSheetToViewport(el, wantTop, insets) {
    try {
      if (!el || !el.isConnected) {
        return;
      }
      var cs = window.getComputedStyle(el);
      var r = el.getBoundingClientRect();
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        return;
      }
      if (r.width < 120 || r.height < 40) {
        return;
      }
      if (cs.position === 'fixed' && Math.abs(parseFloat(el.style.top) - wantTop) < 1 &&
        el.style.bottom === '0px') {
        return;
      }
      el.setAttribute('data-dsh-sheet', '1');
      el.removeAttribute('data-dsh-drawer');
      el.style.position = 'fixed';
      el.style.top = wantTop + 'px';
      el.style.bottom = '0px';
      el.style.left = '0px';
      el.style.right = '0px';
      el.style.width = '100vw';
      el.style.maxWidth = 'unset';
      el.style.margin = '0px';
    } catch (ignore) {
    }
  }

  // 背景是否“不透明”：半透明遮罩（rgba alpha<0.9）与透明背景视为遮罩，
  // 不透明的全屏层视为“全屏页”（如侧栏搜索），需要做顶部安全区避让。
  function isOpaqueBg(bg) {
    if (!bg || bg === 'transparent' || bg === 'rgba(0, 0, 0, 0)') {
      return false;
    }
    var m = /rgba?\\(([^)]+)\\)/.exec(bg);
    if (m) {
      var parts = m[1].split(',');
      if (parts.length >= 4) {
        var a = parseFloat(parts[3]);
        if (!isNaN(a) && a < 0.9) {
          return false;
        }
      }
    }
    return true;
  }

  // 侧栏搜索等全屏展开页：fixed/absolute 锚在视口（或根元素），吃不到 body 的
  // 安全区 padding，顶部内容会被状态栏（时间/信号/电量）遮住。这里给不透明的
  // 全屏面板补顶部安全区内边距——内容下移、背景仍铺满到状态栏之下（保持沉浸，
  // 与 Android 版全屏页一致）。半透明遮罩/低 z 容器/应用根（z auto）不动。
  function tryPadFullScreen(el, cs, r, insets) {
    try {
      if (!el || !el.isConnected || insets.top <= 0) {
        return false;
      }
      // 幂等短路：已补过的面板直接跳过（防止自身 style 写入经属性监听
      // 再次触发本函数，配合 0.5px 容差杜绝浮点回读误差造成的反复写入）
      if (el.getAttribute('data-dsh-fullpad') === '1') {
        return true;
      }
      if (el.getAttribute('data-dsh-sheet') === '1') {
        return false;
      }
      cs = cs || window.getComputedStyle(el);
      if (cs.position !== 'fixed' && cs.position !== 'absolute') {
        return false;
      }
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        return false;
      }
      r = r || el.getBoundingClientRect();
      var vw = window.innerWidth;
      var vh = window.innerHeight;
      if (r.left > 2 || r.top > 2) {
        return false;
      }
      if (r.width < vw * 0.95 || r.height < vh * 0.95) {
        return false;
      }
      if (!isOpaqueBg(cs.backgroundColor)) {
        return false;
      }
      var z = Number(cs.zIndex);
      if (!(z >= 10)) {
        return false;
      }
      var cur = parseFloat(cs.paddingTop) || 0;
      if (cur < insets.top - 0.5) {
        el.style.paddingTop = insets.top + 'px';
        el.setAttribute('data-dsh-fullpad', '1');
        console.info('[DSH] fullscreen pad tag=' + el.tagName +
          ' cls=' + String(el.className).slice(0, 80) + ' padT=' + insets.top);
      } else {
        el.setAttribute('data-dsh-fullpad', '1');
      }
      return true;
    } catch (ignore) {
      return false;
    }
  }

  // 抽屉“透底闪屏”根因（模拟器逐帧取证 2026-09-07）：打开时官方给面板子元素
  // （position:relative、不透明底色、h≈全高）挂 opacity 0→1 交叉淡入约 300ms，
  // 抽屉根元素背景透明——滑动全程主页面内容从抽屉透出。这里把面板子元素的
  // 不透明底色抄写为根元素 CSS 自定义属性 --dsh-drawer-bg（注入样式表规则消费），
  // 根元素即刻铺上该色。面板在关闭态就已存在且底色不透明（实测 rgb(27,27,28)），
  // 故打标时即可抄色；深浅色切换/重挂载后再次同步（幂等，值相同不写）。
  // 跳过 position:fixed 子元素（那是关闭态头部条，透明底、打开时官方淡出）。
  function syncDrawerBackdrop(el) {
    try {
      if (!el || !el.children) {
        return;
      }
      // 铺底 ::before 的顶边 = 根 padding-top（避让线），随底色一起抄写
      var padTop = parseFloat(window.getComputedStyle(el).paddingTop) || 0;
      var wantPad = padTop + 'px';
      if (el.style.getPropertyValue('--dsh-drawer-padtop') !== wantPad) {
        el.style.setProperty('--dsh-drawer-padtop', wantPad);
      }
      for (var i = 0; i < el.children.length; i = i + 1) {
        var k = el.children[i];
        if (!k.tagName) {
          continue;
        }
        var cs = window.getComputedStyle(k);
        if (cs.position === 'fixed' || cs.position === 'absolute') {
          continue;
        }
        var bg = cs.backgroundColor;
        if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)') {
          if (el.style.getPropertyValue('--dsh-drawer-bg') !== bg) {
            el.style.setProperty('--dsh-drawer-bg', bg);
          }
          return;
        }
      }
    } catch (ignore) {
    }
  }

  // 全高抽屉/面板首帧修正（防闪烁核心）：顶部安全区内边距 + 左右侧抽屉圆角标记。
  // 旧链路里这段逻辑只存在于 adjustFixedPanels（MutationObserver → 200ms~1s 限流防抖），
  // 而官方抽屉进场动画约 0.3s——动画在“无避让几何”里播完后防抖回调才补写 padding，
  // 内容整体下移 ~52px 并突现圆角，即真机上的“侧栏打开闪烁”。
  // 现在抽成独立函数：fastCheckNode 在观察器回调（微任务、绘制前）同步调用，
  // 首帧即以最终几何排版，动画全程无跳变；adjustFixedPanels 复用同一函数保证行为一致。
  // 调用方需保证 el 是面板级元素（fixed/absolute），position 限制 fixed 与旧行为一致。
  function tryFixFullHeightPanel(el, cs, r, insets) {
    try {
      if (!el || !el.isConnected) {
        return false;
      }
      cs = cs || window.getComputedStyle(el);
      if (cs.position !== 'fixed') {
        // 非 fixed 全高面板不做几何改写，仅保留侧栏圆角标记兜底
        return tryMarkDrawer(el, cs, r);
      }
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        return false;
      }
      var vw = window.innerWidth;
      var vh = window.innerHeight;
      r = r || el.getBoundingClientRect();
      // 不设宽度下限：官方抽屉关闭态 width=0（left=-261 屏外 + 宽度过渡起点），
      // 打开瞬间的 class 突变到达微任务时宽度尚未展开——若在此拒判，首帧修正
      // 被跳过且 class 只变一次、快速路径再无触发机会，只能等 200ms~1s 防抖
      // （真机实测闪烁）。关闭态写入 padT 无视觉影响（width=0 不可见），展开时
      // 自带避让，正是所需。
      if (r.height < 40) {
        return false;
      }
      if (!(r.top <= 2 && r.bottom >= vh - 2)) {
        return false;
      }
      // 顶部安全区内边距：0.5px 容差防“写入→回读浮点误差→再写入”自激循环
      if (insets.top > 0) {
        var curPt = parseFloat(cs.paddingTop) || 0;
        var wantPt = insets.top + 6;
        if (curPt < wantPt - 0.5) {
          el.style.paddingTop = wantPt + 'px';
        }
      }
      // 侧栏圆角：贴左/右屏边、宽度不足 90vw 的全高抽屉标记 data-dsh-drawer，
      // 由注入样式表以 !important 应用内侧 24px 圆角
      if (r.left <= 2 && r.width < vw * 0.9) {
        if (el.getAttribute('data-dsh-drawer') !== 'left') {
          el.setAttribute('data-dsh-drawer', 'left');
        }
        syncDrawerBackdrop(el);
      } else if (r.right >= vw - 24 && r.width < vw * 0.9) {
        if (el.getAttribute('data-dsh-drawer') !== 'right') {
          el.setAttribute('data-dsh-drawer', 'right');
        }
        syncDrawerBackdrop(el);
      }
      if (!el.getAttribute('data-dsh-drawer-log')) {
        el.setAttribute('data-dsh-drawer-log', '1');
        var lr = el.getBoundingClientRect();
        var lcs = window.getComputedStyle(el);
        console.info('[DSH] drawer adjusted rect=' + Math.round(lr.left) + ',' + Math.round(lr.top) + ' ' +
          Math.round(lr.width) + 'x' + Math.round(lr.height) +
          ' padT=' + lcs.paddingTop + ' padB=' + lcs.paddingBottom +
          ' radius=' + lcs.borderRadius + ' side=' + el.getAttribute('data-dsh-drawer'));
      }
      return true;
    } catch (ignore) {
      return false;
    }
  }

  // 通用处理 fixed 面板：抽屉/弹窗如果从视口顶部开始，会顶到状态栏下面。
  // 全高面板（侧栏抽屉等）保持原有 top/bottom/height 几何不变，只在面板内部加
  // 安全区内边距——背景仍铺满到状态栏之下（Android 侧栏同款沉浸），内容避开
  // 状态栏/导航条；非全高小面板仍按避区微移。
  function adjustFixedPanels() {
    var insets = getInsets();
    if (insets.top <= 0 && insets.bottom <= 0) {
      return;
    }
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    // 收窄选择器（性能）：本函数只可能命中 fixed/absolute 面板，而面板必为
    // div/aside/nav/section/header/footer/main；旧写法 'body *' 会把每个
    // span/svg/path/button 都过一遍 getComputedStyle，是侧栏期间的主要抖动源之一。
    var all = document.querySelectorAll('div, aside, nav, section, header, footer, main');
    for (var i = 0; i < all.length; i = i + 1) {
      var el = all[i];
      if (!el || !el.isConnected) {
        continue;
      }
      if (inNativeDrawer(el)) {
        continue;
      }
      // 官方移动端侧栏（._519be07）由 adjustMobileSheet 视口锚定，跳过通用修正，避免互相覆盖
      if (el.classList && el.classList.contains('_519be07')) {
        continue;
      }
      if (el.getAttribute && el.getAttribute('data-dsh-sheet') === '1') {
        continue;
      }
      perf.fixedScan = perf.fixedScan + 1;
      var cs = window.getComputedStyle(el);
      if (cs.position !== 'fixed') {
        continue;
      }
      var r = el.getBoundingClientRect();
      // 宽度下限移除：官方抽屉关闭态 width=0，需在关闭/展开过渡中都能被识别
      // （展开与收起都只有一次 class 突变，错过即要等防抖）。全高与贴边判定
      // 由 tryFixFullHeightPanel 内部把关。
      if (r.height < 40) {
        continue;
      }
      // 全屏层分两类：透明/半透明遮罩（跳过）与不透明全屏页（侧栏搜索等，
      // 补顶部安全区内边距避免被状态栏遮挡）。
      var isFullScreen = r.width > vw * 0.95 && r.height > vh * 0.95;
      if (isFullScreen) {
        tryPadFullScreen(el, cs, r, insets);
        continue;
      }
      // 全高抽屉：几何不动，仅顶部安全区内边距 + 侧向圆角标记（fastPath 已首帧处理，
      // 这里是防抖兜底）；未命中时保留旧的非全高小面板避让逻辑。
      if (!tryFixFullHeightPanel(el, cs, r, insets)) {
        var r2 = el.getBoundingClientRect();
        if (insets.top > 0 && r2.top >= 0 && r2.top < insets.top + 2) {
          el.style.top = (insets.top + 6) + 'px';
        }
        if (insets.bottom > 0 && r2.bottom > vh - insets.bottom - 2 && r2.bottom <= vh + 2) {
          el.style.bottom = (insets.bottom + 6) + 'px';
        }
      }
    }
  }

  // 侧栏抽屉圆角兜底：真机实测官方侧栏可能是“左侧抽屉”而非 100vw 底部 sheet。
  // 真机结构实测结论：抽屉根元素（fixed，透明背景）被 adjustFixedPanels 加
  // padding-top=状态栏+6 后，白色背景其实是根元素里的内层列（static 定位），
  // 白色从 padding 下沿开始——根元素自身的圆角只能裁到内层白块的底角（贴底），
  // 顶角落在直边上仍然是直角。因此这里做几何兜底，**不限制 position 与 z-index**：
  // 贴左/右屏边、宽度 120..90vw、高度 ≥60vh、纵向跨顶部/底部 1/4 区、带底色的
  // 面板级元素（含 static 内层）全部补标 data-dsh-drawer，由注入样式表给内侧
  // 上/下角 24px 圆角。误标防护：主内容区左侧被抽屉推离屏边（left>2），
  // 全宽元素（≥90vw，如全屏遮罩/主内容/app 壳）不标。
  // 单元素抽屉判定（cs/r 可复用调用方已读出的值，避免重复排版开销）。
  function tryMarkDrawer(el, cs, r) {
    try {
      if (!el || !el.isConnected) {
        return false;
      }
      var tag = el.tagName;
      if (tag !== 'DIV' && tag !== 'ASIDE' && tag !== 'NAV' && tag !== 'SECTION') {
        return false;
      }
      if (el.getAttribute('data-dsh-sheet') === '1') {
        return false;
      }
      if (el.getAttribute('data-dsh-drawer') === 'left' ||
        el.getAttribute('data-dsh-drawer') === 'right') {
        return false;
      }
      var vw = window.innerWidth;
      var vh = window.innerHeight;
      cs = cs || window.getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        return false;
      }
      r = r || el.getBoundingClientRect();
      if (r.width < 120 || r.width >= vw * 0.9 || r.height < vh * 0.6) {
        return false;
      }
      if (r.top > vh * 0.25 || r.bottom < vh * 0.75) {
        return false;
      }
      var bg = cs.backgroundColor;
      if (!bg || bg === 'transparent' || bg === 'rgba(0, 0, 0, 0)') {
        return false;
      }
      if (r.left <= 2) {
        el.setAttribute('data-dsh-drawer', 'left');
        console.info('[DSH] sideDrawer marked left tag=' + tag +
          ' cls=' + String(el.className).slice(0, 100) +
          ' rect=' + Math.round(r.left) + ',' + Math.round(r.top) + ' ' +
          Math.round(r.width) + 'x' + Math.round(r.height));
        return true;
      }
      if (r.right >= vw - 2) {
        el.setAttribute('data-dsh-drawer', 'right');
        console.info('[DSH] sideDrawer marked right tag=' + tag +
          ' cls=' + String(el.className).slice(0, 100) +
          ' rect=' + Math.round(r.left) + ',' + Math.round(r.top) + ' ' +
          Math.round(r.width) + 'x' + Math.round(r.height));
        return true;
      }
    } catch (ignore) {
    }
    return false;
  }

  // 收起侧栏后，切换按钮立即翻转成“打开边栏”态并获得触点 hover/focus，
  // 其 tooltip 会在左上角短暂闪出“打开边栏”字幕。触屏设备不需要该提示：
  // 发现文案匹配的 ds-tooltip 弹层立即隐藏（MutationObserver 在绘制前触发，
  // 用户看不到闪现）。
  var SIDEBAR_TOOLTIP_LABELS = ['打开边栏', '收起边栏', '打开侧边栏', '收起侧边栏',
    'Open sidebar', 'Close sidebar'];

  function hideSidebarTooltips() {
    try {
      var tips = document.querySelectorAll('.ds-tooltip');
      for (var i = 0; i < tips.length; i = i + 1) {
        var tip = tips[i];
        var txt = (tip.textContent || '').replace(/[\\s]+/g, ' ').trim();
        if (txt.length === 0 || txt.length > 20) {
          continue;
        }
        for (var k = 0; k < SIDEBAR_TOOLTIP_LABELS.length; k = k + 1) {
          if (txt === SIDEBAR_TOOLTIP_LABELS[k]) {
            if (tip.style.display !== 'none') {
              tip.style.display = 'none';
            }
            break;
          }
        }
      }
    } catch (ignore) {
    }
  }

  // 侧栏开关按钮识别（透明悬浮圆框的打标通道）：官方改版后按钮无 aria-label，
  // 按几何+结构特征识别左上角图标开关：主栏顶栏区（top 30..120 / left ≤90）、
  // 28..64px 方形、几乎无文本、含图标、非推广/非隐藏、可点击语义
  // （.ds-button / button / [role=button]）。开/关两态下该按钮都在同一位置
  // （开态时它位于抽屉头部，仍是“收起”开关），一并打标。
  function matchSidebarToggleButton(el) {
    try {
      var tag = el.tagName;
      var isBtn = tag === 'BUTTON' || tag === 'A' ||
        (el.getAttribute && el.getAttribute('role') === 'button') ||
        (typeof el.className === 'string' && el.className.indexOf('ds-button') >= 0);
      if (!isBtn) {
        return false;
      }
      if (typeof el.className === 'string' && el.className.indexOf('ds-button__') === 0) {
        return false; // 官方按钮内部子层（background/icon），不打标（避免 ::after 叠加）
      }
      if (el.getAttribute('data-dsh-home-hidden') === '1' || el.getAttribute('data-dsh-promo') === '1') {
        return false;
      }
      // 零排版开销的判据全部前置、几何判据留到最后（本轮提速）：本函数在
      // markSidebarToggleButtons 与 fastCheckNode 里对成百个候选逐个调用，
      // 原来的顺序让每个候选（含消息列表里的长文本 <a>/<button>）都先吃一次
      // getBoundingClientRect。判据本身逐字未变（只换了求值顺序，纯谓词可交换）。
      var txt = (el.textContent || '').replace(/[ \\t\\n\\r]+/g, ' ').trim();
      if (txt.length > 2) {
        return false;
      }
      if (!el.querySelector || !el.querySelector('svg, img, [class*="icon"]')) {
        return false;
      }
      var r = el.getBoundingClientRect();
      if (r.width < 28 || r.width > 64 || r.height < 28 || r.height > 64) {
        return false;
      }
      if (r.top < 30 || r.top > 120 || r.left > 90) {
        return false;
      }
      return true;
    } catch (ignore) {
      return false;
    }
  }

  function markSidebarToggleButtons() {
    try {
      var all = document.querySelectorAll('.ds-button, button, [role="button"]');
      for (var i = 0; i < all.length; i = i + 1) {
        var el = all[i];
        if (!el || !el.isConnected || el.getAttribute('data-dsh-floatbtn') === '1') {
          continue;
        }
        if (matchSidebarToggleButton(el)) {
          el.setAttribute('data-dsh-floatbtn', '1');
          console.info('[DSH] floatbtn marked cls=' + String(el.className).slice(0, 60));
        }
      }
    } catch (ignore) {
    }
  }

  // 去除官方网页里的“下载应用”推广（图标 + 设置里的“下载手机应用”等）。
  // 图标按钮按 aria-label/title 短文案匹配；设置项按页面可见文本匹配；
  // 只隐藏最近的可点击容器，避免误伤聊天内容/整块面板。
  var PROMO_LABELS = [
    '下载应用', '下载手机应用', '下载APP', '下载 App', '下载App', '下载鸿蒙',
    '下载客户端', '下载手机版', '手机应用下载', '手机版下载', '前往下载', '立即下载',
    'Download App', 'DownloadApp', 'Download the app', 'Get the app', 'Get App',
    '扫二维码下载', '下载DeepSeek', '下载 DeepSeek'
  ];

  // 有界文本提取（第十六轮新增，性能 P0 的核心）：语义等价于
  //   el.textContent 先做"空白游程折叠成单个空格"、再去首尾空白（旧实现就是那条正则 + trim）。
  //
  // 空白判据（第二十一轮补齐，修掉 r19 W1 差分实测登记的 P2-9 边界差异）：
  //   旧实现只认 空格 / TAB / LF / CR 四个字符，而 trim() 剥掉的是**全部 Unicode 空白**
  //   （U+00A0 NBSP、U+2000..U+200A、U+1680、U+2028/2029、U+202F、U+205F、U+3000、U+FEFF、
  //   U+000B/000C）。于是当元素文本的**首尾**出现上述"非四字符"的空白时，out 会比旧式
  //   多出这些字符 ⇒ 长度可能刚好越过 limit ⇒ over 由 false 变 true（r19 差分实测
  //   随机树 220 万例中 381,724 例差异全部由该边界造成，生成器限制在 ASCII 空白时 0 差异）。
  //   现在把判据收敛到 isFoldWs() = JS 正则空白类（与 trim 集完全相等）+ U+200B 零宽空格
  //   （旧正则式显式包含它），boundedText 与"旧正则折叠 + trim"逐字等价。
  //   影响面收回：isPromoText 的长度门（40）在"首尾带 NBSP 且总长恰在 40 附近"时不再漏判。
  //   ⚠️ 这里**故意不抄正则字面量、也不列转义序列**：注释身处 ArkTS 模板字符串内，反斜杠
  //   会被求值成真实控制字符落进注入产物把注释截断成语法错误（§3.0-5 同源，预检把关）。
  // 但**边遍历边累计、一旦确定超过 limit 就立刻返回**，绝不把整棵子树的文本物化成一个长字符串。
  // 根因（audit §3「CPU / 流畅度」P0）：removeDownloadPromos 对 'a,button,li,span,div,p,[role]'
  // 全体候选逐个调 isPromoText，而 isPromoText 先算 el.textContent（递归拼接整个子树，
  // 子树越深拷贝越多）**之后**才判长度 —— 守卫写在拼接之后等于没有守卫，理论 O(N²)；
  // 该扫描每次 DOM 突变后都会被调度（限流 1 次/秒 + 5s 巡检），长对话页尤其吃亏。
  // 等价性依据：这里按"空白游程折叠成单个空格 + 去首尾空白"逐字符实现，与上面那条规则 + trim
  // 加 trim 一致 —— 跨文本节点边界的空白游程由 pending 标记承接，nodeType 8(注释) 与
  // textContent 一样不计入。**只在累计长度已确定超过 limit 时**才带 over 标记提前返回，
  // 因此不会把"长于 limit"误判成"短于 limit"：40 字是"是否推广行"的判据，一旦判错就会
  // 漏隐藏推广行、或把含"下载应用"4 字的顶栏整块隐藏（踩坑见 hasNonPromoInteractive）。
  // 空白字符判据：与 JS 正则空白类（等价于 trim 的去除集）+ U+200B 零宽空格。
  // 用 charCode 区间判断而不是正则，避免模板字面量转义坑（§3.0-5）；
  // 9..13 覆盖 TAB/LF/VT/FF/CR，2000..200A 是 Unicode 空格分隔符连续段。
  function isFoldWs(ch) {
    var c = ch.charCodeAt(0);
    if (c === 32 || (c >= 9 && c <= 13)) { return true; }
    if (c === 160 || c === 0x200b || c === 0xfeff) { return true; }
    if (c === 0x1680 || c === 0x202f || c === 0x205f || c === 0x3000) { return true; }
    if (c >= 0x2000 && c <= 0x200a) { return true; }
    if (c === 0x2028 || c === 0x2029) { return true; }
    return false;
  }

  function boundedText(el, limit) {
    var out = '';
    var pending = false;
    // 统一栈 + 逆序入栈 = **文档序**先序遍历（与 textContent 的顺序一致）。
    // 注意第一版写错了：文本节点在循环里就地累加、元素节点才入栈，于是同一层的文本
    // 被倒序拼到元素子树之前 —— 随机树 A/B 对照 20 万例当场暴露（顺序错会让
    // "下载应用"这类跨元素边界的文案 indexOf 落空，推广行就漏隐藏了）。
    // 现在文本节点与元素节点**一起入栈**，出栈顺序即文档序。
    var stack = [el];
    while (stack.length > 0) {
      var node = stack.pop();
      if (node.nodeType === 3) {
        var s = node.nodeValue || '';
        for (var c = 0; c < s.length; c = c + 1) {
          var ch = s.charAt(c);
          if (isFoldWs(ch)) {
            pending = true;
            continue;
          }
          if (pending) {
            if (out.length > 0) { out = out + ' '; }
            pending = false;
          }
          out = out + ch;
          if (out.length > limit) {
            return { text: out, over: true };
          }
        }
        continue;
      }
      if (node.nodeType !== 1) {
        continue;
      }
      var kids = node.childNodes;
      if (!kids || kids.length === 0) {
        continue;
      }
      for (var i = kids.length - 1; i >= 0; i = i - 1) {
        var k = kids[i];
        if (k.nodeType === 3 || k.nodeType === 1) {
          stack.push(k);
        }
      }
    }
    return { text: out, over: false };
  }

  function isPromoText(el) {
    if (!el) {
      return false;
    }
    var aria = el.getAttribute && el.getAttribute('aria-label') ? el.getAttribute('aria-label') : '';
    var title = el.getAttribute && el.getAttribute('title') ? el.getAttribute('title') : '';
    var attrText = (aria + ' ' + title).toLowerCase();
    if (attrText.length > 0 && attrText.length <= 30 &&
      (attrText.indexOf('下载') >= 0 || attrText.indexOf('download') >= 0)) {
      return true;
    }
    // 有界提取（守卫前置，性能 P0）：超过 40 字直接判定"不是推广行"，不再为它把
    // 整棵子树的文本拼成大字符串（旧写法见上方 boundedText 注释）。
    var bt = boundedText(el, 40);
    var text = bt.text;
    if (bt.over || text.length === 0 || text.length > 40) {
      return false;
    }
    for (var i = 0; i < PROMO_LABELS.length; i = i + 1) {
      if (text.indexOf(PROMO_LABELS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  // 候选容器内是否含有“非推广”的可交互后代。
  // 真机踩坑：官方顶栏容器（.the-header 父级）的 textContent 恰为“下载应用”4 字
  // （顶栏自带下载胶囊按钮），isPromoText 会整体命中；而顶栏内部还有侧栏开关等
  // 其他按钮——若把这种容器当“推广行”隐藏，整个顶栏（含侧栏入口）一起消失，
  // 表现为“打开 App 顶栏全无、侧栏都打不开”。故短文本行兜底必须排除
  // 含任何非推广可交互后代的容器，只允许隐藏纯推广元素（如下载按钮本身）。
  function hasNonPromoInteractive(el) {
    var inner = el.querySelectorAll('button, [role="button"], a, input, textarea, select, .ds-button');
    for (var i = 0; i < inner.length; i = i + 1) {
      if (!isPromoText(inner[i])) {
        return true;
      }
    }
    return false;
  }

  function findHideTarget(node) {
    var cur = node;
    for (var depth = 0; depth < 8; depth = depth + 1) {
      if (!cur) {
        break;
      }
      var tag = (cur.tagName || '').toLowerCase();
      if (tag === 'a' || tag === 'button' || tag === 'li') {
        return cur;
      }
      // 官方 ds-button 是 div 按钮（class 含 ds-button），直接隐藏该 div
      if (typeof cur.className === 'string' && cur.className.indexOf('ds-button') >= 0) {
        return cur;
      }
      if (cur.getAttribute) {
        var role = cur.getAttribute('role');
        if (role === 'button' || role === 'menuitem' || role === 'option') {
          return cur;
        }
      }
      cur = cur.parentNode;
    }
    // 侧栏“设置”等场景：推广行是无 button/role 语义的普通 div 行（图标 + 文字），
    // 上面的可点击容器匹配会落空导致整行残留。按“短文本行”兜底：沿父链向上取
    // 最外层“行级”容器（自身文本 ≤24 字、行高 ≤96px）整行隐藏 —— 图标与文字
    // 一并移除；一旦父容器变高/文本变长（已进入面板级）即停，防止误伤整块面板。
    // 含非推广可交互后代的容器一律跳过（防顶栏/工具栏被整体误隐藏）。
    var best = null;
    var cur2 = node;
    for (var d2 = 0; d2 < 6; d2 = d2 + 1) {
      if (!cur2 || !cur2.tagName) {
        break;
      }
      var tag2 = (cur2.tagName || '').toLowerCase();
      if (tag2 === 'body' || tag2 === 'html') {
        break;
      }
      var txt2 = (cur2.textContent || '').replace(/[ \\t\\n\\r]+/g, ' ').trim();
      if (txt2.length > 24) {
        break;
      }
      var r2 = cur2.getBoundingClientRect();
      if (r2.height > 96) {
        break;
      }
      if (txt2.length > 0 && r2.height >= 10 && r2.width >= 80 && !hasNonPromoInteractive(cur2)) {
        best = cur2;
      }
      cur2 = cur2.parentNode;
    }
    return best;
  }

  // 已压制推广行的后代短路（本轮新增，性能 P0）。
  // 依据：findHideTarget 命中后给目标打 data-dsh-promo="1" **并**同时写 style.display='none'，
  // 而 injectStyle 里有 [data-dsh-promo="1"] 的 display:none !important 规则 ——
  // 官方框架用 inline style 恢复 display 也赢不过 !important（这套"data 属性 + !important"
  // 就是为了打赢那场拉锯，见 injectStyle 注释）。所以**带标记的节点及其整棵子树必然不可见**，
  // 没有再评估的价值；但它的全部后代仍在 removeDownloadPromos 的候选表里（'a,button,li,span,
  // div,p,[role]' 是平坦的 querySelectorAll）—— 不短路的话每次调度都要把这些不可见后代
  // 重新过一遍 isPromoText，这正是"扫描量恒定不降"的原因。
  // 用一次 closest() 的原生选择器匹配替代"逐层 getAttribute"（本文件外已有同款用法）：
  // 一次原生调用换掉整棵子树的重扫；closest 不存在（老内核）时回退为只判自身，行为不劣化。
  function inHiddenPromo(el) {
    try {
      if (typeof el.closest === 'function') {
        return el.closest('[data-dsh-promo="1"]') !== null;
      }
      return el.getAttribute && el.getAttribute('data-dsh-promo') === '1';
    } catch (ignore) {
      return false;
    }
  }

  function removeDownloadPromos() {
    var candidates = document.querySelectorAll('a, button, li, span, div, p, [role]');
    for (var i = 0; i < candidates.length; i = i + 1) {
      var el = candidates[i];
      if (!el || !el.isConnected) {
        continue;
      }
      if (inHiddenPromo(el)) {
        continue;
      }
      if (isPromoText(el)) {
        var target = findHideTarget(el);
        if (target && target.getAttribute('data-dsh-promo') !== '1') {
          target.style.display = 'none';
          target.setAttribute('data-dsh-promo', '1');
        }
      }
    }
  }

  // —— 首页/对话页图标差异化 ——
  // 需求：首页右上角不显示「新建对话」图标；进入对话后右上角保留「分享」与
  // 「新建对话」。官方是 SPA，会话路由为 /a/chat/s/<id>，首页为 /。
  // 实现：路由非会话时隐藏右上角的新建对话图标按钮（仅顶部右侧小图标按钮、
  // 且不在侧栏/sheet 内部），进入会话路由后恢复；pushState/replaceState/
  // popstate 全量监听，SPA 路由切换即时生效。
  var HOME_NEWCHAT_LABELS = ['新建对话', '开启新对话', '新对话', 'New chat', 'New Chat', 'new chat'];
  var lastRoutePath = null;

  function getRoutePath() {
    try {
      // __dshRouteOverride 仅供 PC 端自动化回归（file:// 页面无法 pushState 改路径）
      if (typeof window.__dshRouteOverride === 'string' && window.__dshRouteOverride.length > 0) {
        return window.__dshRouteOverride;
      }
      return location.pathname || '/';
    } catch (ignore) {
      return '/';
    }
  }

  function isConversationRoute() {
    return getRoutePath().indexOf('/a/chat/s/') >= 0;
  }

  function isInDrawerOrSheet(el) {
    var cur = el;
    for (var d = 0; d < 10 && cur; d = d + 1) {
      if (cur.getAttribute) {
        if (cur.getAttribute('data-dsh-sheet') === '1' || cur.getAttribute('data-dsh-drawer')) {
          return true;
        }
      }
      if (cur.classList && cur.classList.contains('_519be07')) {
        return true;
      }
      cur = cur.parentNode;
    }
    return false;
  }

  function resolveNewChatTarget(el) {
    var cur = el;
    for (var d = 0; d < 5 && cur; d = d + 1) {
      var tag = (cur.tagName || '').toLowerCase();
      if (tag === 'button' || tag === 'a') {
        return cur;
      }
      if (cur.getAttribute) {
        var role = cur.getAttribute('role');
        if (role === 'button') {
          return cur;
        }
      }
      if (typeof cur.className === 'string' && cur.className.indexOf('ds-button') >= 0) {
        return cur;
      }
      cur = cur.parentNode;
    }
    return el;
  }

  // 命中“首页右上角新建对话图标按钮”时返回应隐藏的目标元素，否则 null。
  function findHomeNewChatTarget(el) {
    try {
      var cur = el;
      for (var d = 0; d < 4 && cur && cur.getAttribute; d = d + 1) {
        var aria = cur.getAttribute('aria-label') || '';
        var title = cur.getAttribute('title') || '';
        // 注：这里**不能**换成 boundedText（本轮实测它与本式不等价，见文件内 boundedText
        // 注释里的"边界 Unicode 空白"一节）—— 保持逐字原式。
        var txt = (aria + ' ' + title + ' ' + (cur.textContent || '')).replace(/[ \\t\\n\\r]+/g, ' ').trim();
        if (txt.length > 0 && txt.length <= 18) {
          for (var i = 0; i < HOME_NEWCHAT_LABELS.length; i = i + 1) {
            if (txt.indexOf(HOME_NEWCHAT_LABELS[i]) >= 0) {
              var target = resolveNewChatTarget(cur);
              var r = target.getBoundingClientRect();
              // 仅顶部右侧的小图标按钮：避开侧栏内入口与正文区同名按钮
              if (r.width < 16 || r.width > 72 || r.height < 16 || r.height > 72) {
                return null;
              }
              if (r.top < 0 || r.top > 90) {
                return null;
              }
              if (r.right < window.innerWidth - 110) {
                return null;
              }
              if (isInDrawerOrSheet(target)) {
                return null;
              }
              return target;
            }
          }
        }
        cur = cur.parentNode;
      }
    } catch (ignore) {
    }
    return null;
  }

  // 单元素几何判定：右上角“新建对话”⊕图标（顶部 ≤90px / 右侧 110px 内 /
  // 16..72px 方形 / 几乎无文本 / 非推广 / 不在侧栏或 sheet 内）。
  function matchHomeNewChatGeometry(el) {
    // 零排版开销的判据前置、几何判据留到最后（本轮提速）：本函数在
    // findHomeNewChatIconByGeometry 里对全文档候选逐个调用，原来的顺序让每个候选
    // 都先吃一次 getBoundingClientRect。判据逐字未变，只换了纯谓词的求值顺序。
    var txt = (el.textContent || '').replace(/[ \\t\\n\\r]+/g, ' ').trim();
    if (txt.length > 4 || isPromoText(el)) {
      return false;
    }
    if (isInDrawerOrSheet(el)) {
      return false;
    }
    var r = el.getBoundingClientRect();
    if (r.width < 16 || r.width > 72 || r.height < 16 || r.height > 72) {
      return false;
    }
    if (r.top < 0 || r.top > 90 || r.right < window.innerWidth - 110) {
      return false;
    }
    return true;
  }

  // 几何兜底：官方改版后顶栏按钮全部没有 aria-label（实测全页 [aria-label] 数量为 0），
  // 文本匹配对纯图标按钮失效。首页右上角的“新建对话”⊕图标按几何特征识别，
  // 取最右一个符合者（推广按钮由 isPromoText 排除、promo 逻辑负责隐藏）；
  // 会话页右上角有分享+新建对话两个图标，但会话路由由调用方短路，不会走到这里。
  function findHomeNewChatIconByGeometry() {
    perf.homeScan = perf.homeScan + 1;
    var all = document.querySelectorAll('[role="button"], button, a');
    var best = null;
    // bestLeft 缓存"当前最优"的 left：旧写法在比较式里对 el 与 best 各读一次
    // getBoundingClientRect（每个候选多两次布局读取），且 best 每次都被重读。
    var bestLeft = 0;
    for (var i = 0; i < all.length; i = i + 1) {
      var el = all[i];
      if (!el || !el.isConnected || el.style.display === 'none') {
        continue;
      }
      if (el.getAttribute('data-dsh-home-hidden') === '1') {
        continue;
      }
      if (!matchHomeNewChatGeometry(el)) {
        continue;
      }
      var hr = el.getBoundingClientRect();
      if (!best || hr.left > bestLeft) {
        best = el;
        bestLeft = hr.left;
      }
    }
    return best;
  }

  function syncHomeNewChat() {
    try {
      var inChat = isConversationRoute();
      // 进入会话：恢复全部曾被隐藏的首页按钮（对话页右上角保留分享 + 新建对话）
      var hidden = document.querySelectorAll('[data-dsh-home-hidden="1"]');
      for (var i = 0; i < hidden.length; i = i + 1) {
        if (inChat || !hidden[i].isConnected) {
          hidden[i].style.display = '';
          hidden[i].removeAttribute('data-dsh-home-hidden');
        }
      }
      if (inChat) {
        return;
      }
      var all = document.querySelectorAll('button, a, [role="button"], [aria-label]');
      for (var k = 0; k < all.length; k = k + 1) {
        var el = all[k];
        if (!el || !el.isConnected || el.getAttribute('data-dsh-home-hidden') === '1') {
          continue;
        }
        var target = findHomeNewChatTarget(el);
        if (target && target.style.display !== 'none') {
          target.style.display = 'none';
          target.setAttribute('data-dsh-home-hidden', '1');
          console.info('[DSH] home new-chat hidden aria=' +
            (target.getAttribute('aria-label') || '') + ' path=' + getRoutePath());
        }
      }
      // 无 aria-label 时代的几何兜底（官方改版后新建对话图标无任何可读标识）
      var iconBtn = findHomeNewChatIconByGeometry();
      if (iconBtn && iconBtn.style.display !== 'none') {
        iconBtn.style.display = 'none';
        iconBtn.setAttribute('data-dsh-home-hidden', '1');
        console.info('[DSH] home new-chat hidden by geometry path=' + getRoutePath());
      }
    } catch (ignore) {
    }
  }

  function onMaybeRouteChange() {
    domMutationCount = domMutationCount + 1;
    try {
      var p = getRoutePath();
      if (p === lastRoutePath) {
        return;
      }
      lastRoutePath = p;
      syncHomeNewChat();
      scheduleFixedCleanup();
    } catch (ignore) {
    }
  }

  function installRouteListener() {
    // window 级标记防止适配器重注入时重复包裹 history（包裹会叠乘）
    if (window.__dshRoutePatched) {
      return;
    }
    window.__dshRoutePatched = true;
    try {
      var wrap = function (orig) {
        return function () {
          var ret = orig.apply(this, arguments);
          try {
            onMaybeRouteChange();
          } catch (ignore) {
          }
          return ret;
        };
      };
      if (window.history && history.pushState) {
        history.pushState = wrap(history.pushState);
      }
      if (window.history && history.replaceState) {
        history.replaceState = wrap(history.replaceState);
      }
      window.addEventListener('popstate', onMaybeRouteChange);
      window.addEventListener('hashchange', onMaybeRouteChange);
    } catch (ignore) {
    }
  }

  var promoCleanupTimer = null;
  var lastPromoCleanup = 0;

  // 巡检门控状态：domMutationCount 记录 DOM 活动次数（主观察器 / 面板观察器 /
  // 路由回调各自入口自增），lastPatrolCount 记录上次巡检已见计数（-1 = 从未巡检，
  // 保证 2s 巡检首查必跑），patrolTicks 为巡检心跳计数（周期性强制全查用）。
  var domMutationCount = 0;
  var lastPatrolCount = -1;
  var patrolTicks = 0;

  // 巡检的实际动作。抽成函数的原因：定时器分支与"回前台补查"分支要跑**同一套**逻辑，
  // 早先"回前台"分支是我复制了一份 —— 两份实现迟早会走偏（本工程在别处踩过同源坑）。
  // 这里保持行为与改造前完全一致，只把外层节奏从 2s 放宽到 5s。
  function patrolAll() {
    // 弹层打标放在门控之前：它自带幂等短路，代价只有一次 .ds-modal-content__title 的
    // 全文档查询（结果集极小、无布局测量），却是"点击后最迟 5s 内必定被打上标"这条
    // 硬指标的兜底 —— 页面进入静默（没有突变）时，快路径根本没机会被触发。
    markSettingsModal();
    // 原生外壳接管顶栏后，推广/新建对话/悬浮圆框都无目标：跳过（含
    // findHomeNewChatIconByGeometry 的 'body *' 全文档几何扫描）
    if (!shellOwnsChrome()) {
      removeDownloadPromos();
      markSidebarToggleButtons();
      if (!isConversationRoute()) {
        var iconBtn = findHomeNewChatIconByGeometry();
        if (iconBtn && iconBtn.style.display !== 'none') {
          iconBtn.style.display = 'none';
          iconBtn.setAttribute('data-dsh-home-hidden', '1');
        }
      } else {
        syncHomeNewChat();
      }
    }
  }

  function schedulePromoCleanup() {
    if (promoCleanupTimer !== null) {
      return;
    }
    // 最小间隔限流：属性监听后页面高频 class/style 变化会不断触发本调度，
    // 若连续做全文档扫描会把主线程占满（真机曾因此假死）。限流到 ≤1 次/秒，
    // 时效性由 MutationObserver 内的同步快速路径保证，这里只做兜底。
    var wait = Math.max(200, 1000 - (Date.now() - lastPromoCleanup));
    promoCleanupTimer = window.setTimeout(function () {
      promoCleanupTimer = null;
      lastPromoCleanup = Date.now();
      // 原生外壳接管顶栏时与 patrolAll 保持同一口径（audit §3 CPU P0）：
      // 推广入口只存在于官方顶栏/官方抽屉里，而这两块都被原生外壳让位（顶栏 hidden、
      // 抽屉打 data-dsh-hide-drawer + visibility:hidden，官方侧只剩数据源角色）——
      // 此时继续每 1s 跑一遍全文档推广扫描纯属空转。patrolAll 早就带了这个门控，
      // 唯独这条 1s 防抖路径漏了，于是"接管后仍每秒全文档扫描"一直留着。
      // 用户交还官方外壳时会由 ShellScript.reveal() 把 __dshShellOwnsChrome 置回 false，
      // 两条路径随之恢复，不会出现"让位后推广再也藏不住"。
      if (!shellOwnsChrome()) {
        removeDownloadPromos();
      }
    }, wait);
  }

  var fixedCleanupTimer = null;
  var lastFixedCleanup = 0;

  function scheduleFixedCleanup() {
    if (fixedCleanupTimer !== null) {
      return;
    }
    // 同上：最小间隔限流，防止全文档几何扫描连续占用主线程
    var wait = Math.max(200, 1000 - (Date.now() - lastFixedCleanup));
    fixedCleanupTimer = window.setTimeout(function () {
      fixedCleanupTimer = null;
      lastFixedCleanup = Date.now();
      applySafeArea();
      adjustFixedPanels();
      adjustMobileSheet();
      // markSideDrawers() 本轮从热路径里**真正摘掉**（P1-8）。
      // run() 里早已不调它（注释声明"已下线"），但这里还留着 —— 于是每次 DOM 突变后的
      // 防抖清理都会跑一遍它的 querySelectorAll('body *') 全文档遍历。
      // 它要修的"抽屉白块圆角"已由原生侧栏接管（ShellScript 给抽屉打 data-dsh-hide-drawer，
      // 且 injectStyle 的 CSS 首帧规则给 .dc04ec1d 定了 0/24 圆角），另有
      // tryFixFullHeightPanel 兜底 —— 删除该调用后已真机复核侧栏圆角与投影正常。
    }, wait);
  }

  // —— 防闪烁快速路径 ——
  // 旧链路：MutationObserver → 200ms 防抖 → 才修正 sheet/抽屉几何；而官方 sheet
  // 进场动画恰好 0.2s —— 动画在原始（被安全区挤压的）几何里播完后再跳变，
  // 即用户看到的“打开闪烁”。现在观察器回调里同步处理新增节点（MutationObserver
  // 微任务在绘制前执行，用户看不到中间态），200ms 全量防抖保留为布局兜底。
  // 真机实测补充：侧栏开合/搜索页显隐是 class 切换（元素早已挂载，无节点插入），
  // 只监听 childList 会让修正在打开瞬间完全不触发——故观察器同时监听 class/style
  // 属性变化，目标元素及其面板级子树同步过一遍（见 fastPath 的 attributes 分支）。
  var FASTPATH_BUDGET = 300;

  // inDrawerChecked = true 表示**调用方刚刚做过** inNativeDrawer(el) 且结论是"不在抽屉里"，
  // 本函数不重复判定（抽屉短路本身是一次 contains()，热路径上同一节点曾被连判三次）。
  // csIn = 调用方已为该节点取过的 computed style，直接复用 —— 原来 fastPath 与
  // handlePanelMutation 都对同一个节点取了两次 getComputedStyle。
  function fastCheckNode(el, inDrawerChecked, csIn) {
    if (!el || !el.isConnected || el.nodeType !== 1) {
      return;
    }
    if (inDrawerChecked !== true && inNativeDrawer(el)) {
      return;
    }
    perf.fastNode = perf.fastNode + 1;
    var tag = el.tagName;
    // ① 官方底部 sheet（已知类名）：立即按最终几何锚定（CSS 规则已首帧生效，此处兜底）
    if (el.classList && el.classList.contains('_519be07')) {
      if (window.innerWidth < 768) {
        var insets0 = getInsets();
        anchorSheetToViewport(el, insets0.top > 0 ? insets0.top + 6 : 20, insets0);
      }
      return;
    }
    // ② 短文本节点：推广行 / 首页右上角新建对话（文本判定先行，零排版开销）
    // 原生外壳接管顶栏后整块跳过：这些目标已随官方顶栏一起被隐藏。
    if (!shellOwnsChrome() && (tag === 'A' || tag === 'BUTTON' || tag === 'LI' ||
      tag === 'SPAN' || tag === 'DIV' || tag === 'P')) {
      if (isPromoText(el)) {
        var hideTarget = findHideTarget(el);
        if (hideTarget && hideTarget.getAttribute('data-dsh-promo') !== '1') {
          hideTarget.style.display = 'none';
          hideTarget.setAttribute('data-dsh-promo', '1');
        }
      }
      // 侧栏开关按钮（React 重挂载后补标透明悬浮圆框）
      if (el.getAttribute('data-dsh-floatbtn') !== '1' && matchSidebarToggleButton(el)) {
        el.setAttribute('data-dsh-floatbtn', '1');
      }
      if (!isConversationRoute() && el.getAttribute('data-dsh-home-hidden') !== '1') {
        var isControl = (tag === 'A' || tag === 'BUTTON' ||
          (el.getAttribute && el.getAttribute('role') === 'button'));
        var ncTarget = findHomeNewChatTarget(el);
        // 官方改版无 aria-label：新挂载的右上角小图标按钮按几何兜底，
        // 防止 React 重挂载（无路由变化）后 ⊕ 图标短暂回归
        if (!ncTarget && isControl && matchHomeNewChatGeometry(el)) {
          ncTarget = el;
        }
        if (ncTarget && ncTarget.style.display !== 'none') {
          ncTarget.style.display = 'none';
          ncTarget.setAttribute('data-dsh-home-hidden', '1');
        }
      }
    }
    // ③ 面板级容器：全屏页（搜索）安全区避让 / 全高抽屉首帧修正（padT + 圆角标记）
    if (tag === 'DIV' || tag === 'ASIDE' || tag === 'NAV' || tag === 'SECTION') {
      var cs = csIn || window.getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        return;
      }
      if (cs.position === 'fixed' || cs.position === 'absolute') {
        var r = el.getBoundingClientRect();
        // getInsets() 每次都会新建一个对象：原来这里连着调了两次（两次分配），
        // 而本函数是热路径上最常被调用的一个。
        var ins = getInsets();
        if (tryPadFullScreen(el, cs, r, ins)) {
          return;
        }
        // 全高抽屉（侧栏）：本回调是微任务、先于绘制——首帧即写入安全区 padding，
        // 官方进场动画在正确几何内播放，消除“动画播完后内容下移 52px”的闪烁。
        // 注意：抽屉以 class 切换显隐（元素长驻），打开瞬间的 attributes 突变
        // 就会走到这里；若无此快速路径，修正要等 200ms~1s 防抖（实测 765ms）。
        if (tryFixFullHeightPanel(el, cs, r, ins)) {
          return;
        }
      } else {
        // 真机抽屉的白色背景在内层 static 列上，static 也要过一遍几何兜底
        tryMarkDrawer(el, cs, null);
      }
    }
  }

  // 风暴保护：页面高频 class/style 变化（动画、埋点 SDK 等）都会触发本路径，
  // 超频时进入“降级模式”——只做面板级首帧修正（侧栏抽屉 padT/圆角，开销极小、
  // 又是防闪烁的关键路径），跳过文本扫描与子树遍历；全量兜底仍交给 200ms 防抖。
  // 旧写法超限直接 return，侧栏打开瞬间赶上页面繁忙时首帧修正被整体跳过，
  // 退化为防抖时序（实测 390~765ms），闪烁复现。
  function fastPathLite(mutations) {
    var insets = getInsets();
    for (var i = 0; i < mutations.length; i = i + 1) {
      var mut = mutations[i];
      var t = mut.target;
      if (!t || t.nodeType !== 1 || !t.tagName) {
        continue;
      }
      if (inNativeDrawer(t)) {
        continue;
      }
      var tag = t.tagName;
      if (tag !== 'DIV' && tag !== 'ASIDE' && tag !== 'NAV' && tag !== 'SECTION') {
        continue;
      }
      var cs = window.getComputedStyle(t);
      if (cs.display === 'none' || cs.visibility === 'hidden') {
        continue;
      }
      if (cs.position !== 'fixed' && cs.position !== 'absolute') {
        continue;
      }
      // 只按高度过滤：抽屉关闭态 width=0（宽度过渡起点），按宽度过滤会漏掉
      // 打开瞬间的首帧修正；宽度/贴边判定交给 tryFixFullHeightPanel。
      if (t.getBoundingClientRect().height < window.innerHeight * 0.5) {
        continue;
      }
      if (tryPadFullScreen(t, cs, null, insets)) {
        continue;
      }
      tryFixFullHeightPanel(t, cs, null, insets);
    }
  }

  // 风暴保护：页面高频 class/style 变化（动画、埋点 SDK 等）都会触发本路径，
  // 超频时直接交给 200ms 防抖兜底，避免主线程被同步排版测量占满。
  var fastPathHits = [];

  function fastPath(mutations) {
    if (!window.__deepseekHmAdapterActive) {
      return;
    }
    // 官方设置弹层是**新挂到 body 下**的一棵子树：这里用"body 有没有弹层壳"做廉价门，
    // 弹层挂载后的第一批突变即可打标（打标幂等，且内部还有 200ms 限流）。
    maybeMarkSettings();
    var now = Date.now();
    var kept = [];
    for (var q = 0; q < fastPathHits.length; q = q + 1) {
      if (now - fastPathHits[q] < 1000) {
        kept.push(fastPathHits[q]);
      }
    }
    fastPathHits = kept;
    if (fastPathHits.length >= 20) {
      fastPathLite(mutations);
      return;
    }
    fastPathHits.push(now);
    var budget = FASTPATH_BUDGET;
    for (var i = 0; i < mutations.length && budget > 0; i = i + 1) {
      var mut = mutations[i];
      // class/style 切换分支：侧栏开合（.dc04ec1d 去掉 collapsed 类）、
      // 搜索页显隐（._4cbcd96 切换 display 类）等——元素早已挂载，只有属性变化。
      // 目标元素几何即刻改变，同步处理目标 + 其面板级子树（绘制前生效）。
      if (mut.type === 'attributes') {
        var t = mut.target;
        if (!t || t.nodeType !== 1) {
          continue;
        }
        if (inNativeDrawer(t)) {
          continue;
        }
        budget = budget - 1;
        var tTag = t.tagName;
        var tIsPanel = (tTag === 'DIV' || tTag === 'ASIDE' || tTag === 'NAV' || tTag === 'SECTION');
        // 同一节点的 computed style 只取一次（本轮提速）：原来 fastCheckNode 内部取一次、
        // 紧接着为判"要不要扫子树"又取一次。CSSStyleDeclaration 是活对象，且这两条分支
        // 都不会改 position，故复用与"再取一次"等价。
        var tcs = tIsPanel ? window.getComputedStyle(t) : null;
        fastCheckNode(t, true, tcs);
        if (tIsPanel && t.querySelectorAll && budget > 0 && tcs &&
          (tcs.position === 'fixed' || tcs.position === 'absolute')) {
          var sub = t.querySelectorAll('div, aside, nav, section, a, button, li, span, p');
          for (var s2 = 0; s2 < sub.length && budget > 0; s2 = s2 + 1) {
            budget = budget - 1;
            fastCheckNode(sub[s2]);
          }
        }
        continue;
      }
      var added = mut.addedNodes;
      for (var j = 0; j < added.length && budget > 0; j = j + 1) {
        var node = added[j];
        if (!node || node.nodeType !== 1) {
          continue;
        }
        if (inNativeDrawer(node)) {
          continue;
        }
        budget = budget - 1;
        fastCheckNode(node, true);
        if (budget > 0 && node.querySelectorAll) {
          var desc = node.querySelectorAll('div, aside, nav, section, a, button, li, span, p');
          for (var k = 0; k < desc.length && budget > 0; k = k + 1) {
            budget = budget - 1;
            fastCheckNode(desc[k]);
          }
        }
      }
    }
  }

  // —— 定向属性观察（真机假死后的最终方案）——
  // 教训：对 documentElement 全子树监听 class/style 属性会把页面海量属性变化
  // 全部喂进回调（同步排版测量），真机渲染主线程被直接压死（CDP 无响应）。
  // 方案：主观察器只盯 childList；另设 panelObserver 只对“面板级元素自身”
  // （position:fixed/absolute 的容器，含 display:none 的预挂载面板）做定向
  // 属性观察——侧栏开合（.dc04ec1d class 切换）、搜索页显隐（._4cbcd96）等
  // 打开瞬间仍能同步修正，其余位置的风暴与我们彻底无关。
  var panelObserver = null;

  function watchPanel(el) {
    try {
      if (!el || el.nodeType !== 1 || el.__dshWatched || !panelObserver) {
        return;
      }
      el.__dshWatched = true; // expando 标记，不产生 mutation
      panelObserver.observe(el, { attributes: true, attributeFilter: ['class', 'style'] });
    } catch (ignore) {
    }
  }
  // 在 scope 子树里发现面板级容器并挂定向观察（一次性轻量扫描）。
  function discoverPanels(scope) {
    try {
      if (!scope || !scope.querySelectorAll) {
        return;
      }
      var nodes = scope.querySelectorAll('div, aside, nav, section');
      var limit = Math.min(nodes.length, 400);
      for (var i = 0; i < limit; i = i + 1) {
        var el = nodes[i];
        if (el.__dshWatched) {
          continue;
        }
        if (inNativeDrawer(el)) {
          continue;
        }
        var cs = window.getComputedStyle(el);
        if (cs.position === 'fixed' || cs.position === 'absolute') {
          watchPanel(el);
        }
      }
    } catch (ignore) {
    }
  }

  // 面板自身属性变化后的处理：目标快速处理 + 限量子树扫描（绘制前生效）
  function handlePanelMutation(target) {
    if (inNativeDrawer(target)) {
      return;
    }
    fastCheckNode(target, true);
    if (!target.querySelectorAll) {
      return;
    }
    var sub = target.querySelectorAll('div, aside, nav, section, a, button, li, span, p');
    var limit = Math.min(sub.length, 200);
    for (var i = 0; i < limit; i = i + 1) {
      var sTag = sub[i].tagName;
      var sIsPanel = (sTag === 'DIV' || sTag === 'ASIDE' || sTag === 'NAV' || sTag === 'SECTION');
      // 同上：面板级节点的 computed style 只取一次，既喂给 fastCheckNode 也用于
      // "要不要给它挂定向属性观察"的判据（原来这两处各取一次）。
      var scs = sIsPanel ? window.getComputedStyle(sub[i]) : null;
      fastCheckNode(sub[i], false, scs);
      if (sub[i].__dshWatched) {
        continue;
      }
      if (sIsPanel && scs && (scs.position === 'fixed' || scs.position === 'absolute')) {
        watchPanel(sub[i]);
      }
    }
  }

  function installPanelObserver() {
    // 适配器会被重复注入（每次 onPageEnd/主题切换一个新闭包）：观察器实例挂
    // window 级共享，闭包间复用同一个，杜绝观察者累积造成的回调风暴。
    if (window.__dshPanelObserver) {
      panelObserver = window.__dshPanelObserver;
    } else {
      try {
        panelObserver = new MutationObserver(function (mutations) {
          domMutationCount = domMutationCount + 1;
          try {
            var seen = [];
            for (var i = 0; i < mutations.length; i = i + 1) {
              var t = mutations[i].target;
              if (!t || t.nodeType !== 1 || seen.indexOf(t) >= 0) {
                continue;
              }
              seen.push(t);
              handlePanelMutation(t);
              if (seen.length >= 12) {
                break;
              }
            }
          } catch (ignore) {
          }
          scheduleFixedCleanup();
          schedulePromoCleanup();
        });
        window.__dshPanelObserver = panelObserver;
      } catch (ignore) {
        return;
      }
    }
    discoverPanels(document.body);
  }

  // —— 官方「系统设置」弹层 → 手机版设置页（打标部分，第十七轮 T2）——
  // 目标观感：全屏面板贴原生磨砂顶栏下沿、标题行固定、4 个页签一行排满不裁切、
  // 内容圆角卡片分组、行高 60、标签 16px、发丝分隔线（对照物：华为「设置」）。
  // 为什么"打标 + 属性选择器"而不是直接写官方类名：官方类名多是 CSS Module hash
  //（_6c040bb / b40079d7 / d316d158 …），跟着 hash 写的样式会在官方某次发布后**静默失效**。
  // 定位判据只有一个：.ds-modal-content__title 的文本 === '系统设置' ——
  // 分享 / 删除确认等其它弹层天然不相干（不得波及它们是本轮红线之一）。
  // 打标是幂等的：每个部分各自"已打标就短路"，重复调用只花一次小范围属性查询。
  var settingsProbeAt = 0;
  var settingsAccentTokens = {};

  function findSettingsPanel() {
    var titles = document.querySelectorAll('.ds-modal-content__title');
    for (var i = 0; i < titles.length; i = i + 1) {
      if ((titles[i].textContent || '').trim() !== '系统设置') {
        continue;
      }
      var el = titles[i];
      // 向上找**精确**的 .ds-modal-content：必须用 classList 精确 token 判定，
      // 不能用 [class*="ds-modal-content"] —— __title 也含这个子串，会把自己认成弹层根。
      while (el && !(el.classList && el.classList.contains('ds-modal-content'))) {
        el = el.parentElement;
      }
      if (el) {
        return el;
      }
    }
    return null;
  }

  function markSettingsShell(panel) {
    // 外壳三级（.ds-modal-wrapper → .ds-modal → .ds-modal-focus-lock）都只用 ds-* 语义类。
    // 手机版"页"的底色刷在最外层 wrapper 上：顶部 topInset 那段（原生磨砂顶栏覆盖区）
    // 也刷同一底色，磨砂底下才不会是页面背景色、透出一条灰带。
    var el = panel.parentElement;
    var k = 0;
    var outer = panel;
    var rootFound = false;
    while (el && el !== document.body && k < 6) {
      outer = el;
      if (el.classList && el.classList.contains('ds-modal-wrapper')) {
        el.setAttribute('data-dsh-settings-root', '1');
        rootFound = true;
        break;
      }
      if (el.classList && el.classList.contains('ds-modal-focus-lock')) {
        el.setAttribute('data-dsh-settings-lock', '1');
      }
      if (el.classList && el.classList.contains('ds-modal')) {
        el.setAttribute('data-dsh-settings-modal', '1');
      }
      el = el.parentElement;
      k = k + 1;
    }
    if (!rootFound && outer !== panel) {
      // 官方换了外壳结构（找不到 .ds-modal-wrapper）时的兜底：把最外层祖先当根，
      // 全屏与底色这两件事仍然成立（只是可能少了一层 flex 传递）。
      outer.setAttribute('data-dsh-settings-root', '1');
    }
    panel.setAttribute('data-dsh-settings-panel', '1');
    var main = panel.querySelector('.ds-modal-content__main');
    if (main) {
      main.setAttribute('data-dsh-settings-main', '1');
    }
  }

  function findTabRowByButtons(panel, body) {
    // 兜底：把"同一个父节点下 ≥3 个 .ds-button 兄弟"的那一组认作页签条带。
    // 先排除内容区里的按钮（主题三选一也是 3 个同级按钮，不排除会认错）。
    var all = panel.querySelectorAll('.ds-button');
    var owners = [];
    var counts = [];
    for (var i = 0; i < all.length; i = i + 1) {
      var el = all[i];
      if (body && body.contains(el)) {
        continue;
      }
      var p = el.parentElement;
      if (!p || (p.classList && p.classList.contains('ds-button'))) {
        continue;
      }
      var idx = owners.indexOf(p);
      if (idx < 0) {
        owners.push(p);
        counts.push(1);
      } else {
        counts[idx] = counts[idx] + 1;
      }
    }
    var best = null;
    var bestN = 0;
    for (var k = 0; k < owners.length; k = k + 1) {
      if (counts[k] > bestN) {
        bestN = counts[k];
        best = owners[k];
      }
    }
    return bestN >= 3 && best ? best.parentElement : null;
  }

  function findActiveToken(items) {
    // 官方用"给选中项加一个 hash 类"表示选中态（真机实测：未选中 _266abb8，选中
    // _266abb8 + _699d482；主题三选一同理）。这里**刻意不写死那个 hash**：
    // 取"只出现在一个项上 + 该项背景不透明（官方选中态就是给底色）"的 hash token，
    // 官方改版换 hash 后依然自适配；两条都不满足时返回 null（样式优雅退化，不报错）。
    var counts = {};
    var lists = [];
    var i;
    var j;
    var tk;
    for (i = 0; i < items.length; i = i + 1) {
      var toks = String(items[i].getAttribute('class') || '').split(' ');
      lists.push(toks);
      for (j = 0; j < toks.length; j = j + 1) {
        tk = toks[j];
        if (tk.indexOf('_') !== 0) {
          continue;
        }
        counts[tk] = (counts[tk] || 0) + 1;
      }
    }
    for (i = 0; i < items.length; i = i + 1) {
      var bg = window.getComputedStyle(items[i]).backgroundColor;
      if (!bg || bg === 'transparent' || bg === 'rgba(0, 0, 0, 0)') {
        continue;
      }
      for (j = 0; j < lists[i].length; j = j + 1) {
        tk = lists[i][j];
        if (tk.indexOf('_') === 0 && counts[tk] === 1) {
          return tk;
        }
      }
    }
    return null;
  }

  function ensureSettingsAccent(key, token) {
    // 把"现场发现的选中态 hash 类"写成一张独立小样式表：选中胶囊由 CSS 负责，
    // 用户切页签时官方类名自己变、高亮跟着走 —— 不需要监听点击、也不需要重排样式表。
    if (!token) {
      return;
    }
    settingsAccentTokens[key] = token;
    var css = '@media not all and (min-width: 768px) {';
    if (settingsAccentTokens.tabs) {
      // 底部功能栏选中态：与静态规则一致，只变色 + 加粗、不画卡片底（竖排透明项）。
      css = css + '[data-dsh-settings-tab="1"][class~="' + settingsAccentTokens.tabs + '"] { background: transparent !important; box-shadow: none !important; color: var(--dsh-set-text) !important; font-weight: 600 !important; }';
    }
    if (settingsAccentTokens.seg) {
      css = css + '[data-dsh-settings-seg="1"][class~="' + settingsAccentTokens.seg + '"] ' + ACCENT_DECL;
    }
    css = css + '}';
    var id = '__deepseek_hm_settings_accent__';
    var old = document.getElementById(id);
    if (old && old.textContent === css) {
      return;
    }
    if (old && old.parentNode) {
      old.parentNode.removeChild(old);
    }
    var style = document.createElement('style');
    style.id = id;
    style.textContent = css;
    document.head.appendChild(style);
  }

  // 供 SHELL_JS 查询当前选中的设置页签下标（原生底栏打开设置页时对齐初始高亮用）。
  // 两个判据：官方 aria 标记 + 本适配器现场发现的选中 hash 类（settingsAccentTokens.tabs）。
  // 都拿不到返回 -1 —— 调用方（SHELL_JS 的 currentSettingsTab）据此保持原生侧 active 不动。
  // 该函数是**跨脚本的只读出口**：SHELL_JS 与本适配器各自闭包互不可见，只能经 window 互调
  // （本工程既有同款通道：__dshNativeDrawer / __deepseekHmApplySafeArea）。
  window.__dshSettingsTabIndex = function () {
    var ns = document.querySelectorAll('[data-dsh-settings-tab="1"]');
    for (var i = 0; i < ns.length; i++) {
      var el = ns[i];
      if (el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-current') === 'page') {
        return i;
      }
      var tk = settingsAccentTokens.tabs;
      if (tk && (' ' + el.className + ' ').indexOf(' ' + tk + ' ') >= 0) {
        return i;
      }
    }
    return -1;
  };

  function markSettingsTabs(panel) {
    var body = panel.querySelector('.ds-scroll-area');
    // 页签行在结构上就是内容滚动区的**前一个兄弟**（官方把两者放进同一个 flex 列），
    // 这条结构关系比任何类名都稳，故作为首选；结构也变了才退到"按钮兄弟分组"兜底。
    var tabsRow = body && body.previousElementSibling ? body.previousElementSibling : null;
    if (!tabsRow || !tabsRow.querySelector('.ds-button')) {
      tabsRow = findTabRowByButtons(panel, body) || tabsRow;
    }
    if (!tabsRow) {
      return;
    }
    tabsRow.setAttribute('data-dsh-settings-tabs', '1');
    var holder = tabsRow.parentElement;
    if (holder && !(holder.classList && holder.classList.contains('ds-modal-content__main'))) {
      // 页签行与内容区的共同父（官方 hash 类 f2ff50b5）：flex 链要经过它才能把剩余高度
      // 传给内容滚动区，否则面板会在半空被官方的 max-height 截断。
      holder.setAttribute('data-dsh-settings-maininner', '1');
    }
    // 条带 = 直接子节点里 .ds-button 最多的那个。教训：**不能**用
    // querySelector('.ds-button') 取"第一个按钮"再拿它的 parentElement ——
    // 官方会按横向滚动位置动态插入两端渐隐层（_17296f2 的两个变体），
    // 渐隐层里各有一个箭头按钮，且左侧那个会排在条带**前面**；照"第一个按钮"取，
    // 会把渐隐层认成条带、把真条带打成装饰层隐藏掉，整行塌成 0 高度（实测踩到）。
    var kids = tabsRow.children;
    var strip = null;
    var bestN = 0;
    for (var j = 0; j < kids.length; j = j + 1) {
      var btnN = kids[j].querySelectorAll ? kids[j].querySelectorAll('.ds-button').length : 0;
      if (btnN > bestN) {
        bestN = btnN;
        strip = kids[j];
      }
    }
    if (bestN < 2) {
      strip = null; // 认不出条带就什么都不标（宁可不动，也不能误伤到真条带）
    }
    if (strip && strip !== tabsRow) {
      strip.setAttribute('data-dsh-settings-tabstrip', '1');
    }
    // 装饰层（两端占位与渐隐箭头）在"一行排满"之后已无意义：隐藏 —— 否则那个
    // 36px 的箭头按钮会被当成第 5 个"页签"挤在行尾。渐隐层是动态增删的，
    // 所以这段每次调用都跑（代价只是几个子节点的属性写），能自我修复。
    for (var k = 0; k < kids.length; k = k + 1) {
      if (kids[k] !== strip) {
        kids[k].setAttribute('data-dsh-settings-deco', '1');
      }
    }
    if (!strip || tabsRow.querySelector('[data-dsh-settings-tab="1"]')) {
      return;
    }
    var tabs = strip.querySelectorAll('.ds-button');
    for (var i = 0; i < tabs.length; i = i + 1) {
      tabs[i].setAttribute('data-dsh-settings-tab', '1');
    }
    ensureSettingsAccent('tabs', findActiveToken(tabs));
  }

  function isSettingsRow(el) {
    // 行判定：内容区直接子节点里"display:flex 且高度不夸张"的那些（官方设置行就是
    // flex 容器、60px 高）；分组块（主题那张）是 display:block，自然落到分组分支。
    if (!el || el.nodeType !== 1 || !el.tagName) {
      return false;
    }
    if (window.getComputedStyle(el).display !== 'flex') {
      return false;
    }
    var h = el.getBoundingClientRect().height;
    return h > 0 && h < 96;
  }

  function flushSettingsRun(run) {
    // 连续的几行共用一张圆角卡片：first/mid/last/only 决定圆角与发丝分隔线，
    // 卡片之间靠最后一个行元素的下外边距留白。
    for (var i = 0; i < run.length; i = i + 1) {
      var pos = 'only';
      if (run.length > 1) {
        pos = i === 0 ? 'first' : (i === run.length - 1 ? 'last' : 'mid');
      }
      run[i].setAttribute('data-dsh-settings-row', '1');
      run[i].setAttribute('data-dsh-settings-cardpos', pos);
    }
  }

  function markSettingsGroup(el) {
    el.setAttribute('data-dsh-settings-group', '1');
    el.setAttribute('data-dsh-settings-cardpos', 'only');
    var kids = el.children;
    for (var i = 0; i < kids.length; i = i + 1) {
      var btns = kids[i].querySelectorAll ? kids[i].querySelectorAll('.ds-button') : null;
      if (!btns || btns.length < 2) {
        continue;
      }
      kids[i].setAttribute('data-dsh-settings-segrow', '1');
      var segs = [];
      for (var j = 0; j < btns.length; j = j + 1) {
        if (btns[j].parentElement === kids[i]) {
          btns[j].setAttribute('data-dsh-settings-seg', '1');
          segs.push(btns[j]);
        }
      }
      ensureSettingsAccent('seg', findActiveToken(segs));
    }
  }

  function markSettingsRows(panel) {
    var body = panel.querySelector('.ds-scroll-area');
    if (!body) {
      return;
    }
    body.setAttribute('data-dsh-settings-body', '1');
    pinSettingsBody(body);
    var inner = body.querySelector('.ds-scroll-area__content');
    if (!inner) {
      return;
    }
    inner.setAttribute('data-dsh-settings-bodyinner', '1');
    // 已打过标就短路（用内容区范围内的属性查询判定，不做任何测量）；
    // 反过来，如果官方重挂了内容节点（标记随旧节点消失），这里会自动重打。
    if (inner.querySelector('[data-dsh-settings-row="1"], [data-dsh-settings-group="1"]')) {
      return;
    }
    var run = [];
    var kids = inner.children;
    for (var i = 0; i <= kids.length; i = i + 1) {
      var el = i < kids.length ? kids[i] : null;
      if (el && isSettingsRow(el)) {
        run.push(el);
        continue;
      }
      flushSettingsRun(run);
      run = [];
      if (el) {
        markSettingsGroup(el);
      }
    }
  }

  function parseColorParts(color) {
    // 刻意不用正则：模板字面量里写 ( 这类转义会被**静默**吃掉（本工程踩过，
    // check-injected-js.mjs 会拦）—— 切括号 + 逗号够了。
    if (!color) {
      return null;
    }
    var open = color.indexOf('(');
    var close = color.indexOf(')', open + 1);
    if (open < 0 || close < 0) {
      return null;
    }
    var parts = color.slice(open + 1, close).split(',');
    if (parts.length < 3) {
      return null;
    }
    var r = parseFloat(parts[0]);
    var g = parseFloat(parts[1]);
    var b = parseFloat(parts[2]);
    if (isNaN(r) || isNaN(g) || isNaN(b)) {
      return null;
    }
    return { r: r, g: g, b: b, a: parts.length > 3 ? parseFloat(parts[3]) : 1 };
  }

  function colorLuma(c) {
    return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) / 255;
  }

  function cssRgb(c, alpha) {
    return 'rgba(' + Math.round(c.r) + ', ' + Math.round(c.g) + ', ' + Math.round(c.b) + ', ' + alpha + ')';
  }

  function setStyleVar(el, name, value) {
    if (value && el.style.getPropertyValue(name) !== value) {
      el.style.setProperty(name, value);
    }
  }

  function mixColor(a, b, t) {
    return {
      r: Math.round(a.r + (b.r - a.r) * t),
      g: Math.round(a.g + (b.g - a.g) * t),
      b: Math.round(a.b + (b.b - a.b) * t),
      a: 1
    };
  }

  function readOfficialPalette(panel) {
    // 采样必须拿到**官方原本的**颜色：我们的样式表已经把面板底色（--dsh-set-page）、
    // 选中页签底色（--dsh-set-card）和下拉框底色都改写过了，戴着属性读只会读到自己写的值
    //（自我循环：实测把卡片色采成了页面色）。这里在读取前临时摘掉面板属性、
    // 读完立刻挂回 —— 同步执行，中间不产生绘制，用户看不到任何中间态。
    var had = panel.getAttribute('data-dsh-settings-panel');
    if (had) {
      panel.removeAttribute('data-dsh-settings-panel');
    }
    var probe = { card: window.getComputedStyle(panel).backgroundColor, text: window.getComputedStyle(panel).color, fill: null };
    var sel = panel.querySelector('.ds-select');
    if (sel) {
      probe.fill = window.getComputedStyle(sel).backgroundColor;
    }
    if (had) {
      panel.setAttribute('data-dsh-settings-panel', had);
    }
    return probe;
  }

  function syncSettingsColors(panel) {
    // 配色全部从弹层自身实测色采样，而不是写死一套主题色：页面主题由"跟随系统/浅色/深色"
    // 三态决定，写死 prefers-color-scheme 会在"用户选了固定深色而系统是浅色"时配色错位。
    // 采样官方自己的面板底/文字/填充色，天然跟着主题走（主题一变，下一轮就会重采并覆盖）。
    var root = panel;
    while (root && !(root.classList && root.classList.contains('ds-modal-wrapper'))) {
      root = root.parentElement;
    }
    if (!root || !root.style) {
      root = panel;
    }
    // 廉价幂等短路：body 底色是"页面上我没改写过"的主题信号，没变就一次测量都不做
    //（巡检每 5s 会摸到这里，不能每次都做摘属性 + 多次 getComputedStyle）。
    var bodyColor = window.getComputedStyle(document.body).backgroundColor;
    if (root.getAttribute('data-dsh-set-key') === bodyColor) {
      return;
    }
    var probe = readOfficialPalette(panel);
    var card = parseColorParts(probe.card);
    if (!card) {
      return;
    }
    var text = parseColorParts(probe.text) || { r: 15, g: 17, b: 21, a: 1 };
    var light = colorLuma(card) > 0.5;
    // 填充色（下拉框/分段控件的底）：官方 ds-select--filled 在深浅两套主题下都是不透明色，
    // 拿不到时按"底色向文字色混 5%/10%"自造一个，保证分段控件仍有可辨的槽底。
    var fill = parseColorParts(probe.fill);
    if (!fill || fill.a === 0) {
      fill = mixColor(card, text, light ? 0.05 : 0.1);
    }
    // 页面底色：浅色主题下官方 body 就是白色，做"灰底白卡"要借官方填充色（≈#f2f3f4）；
    // 深色主题下官方 body 是近黑（#151517），本身就是想要的页面底色。
    var page = light ? fill : parseColorParts(bodyColor);
    if (!page) {
      page = card;
    }
    setStyleVar(root, '--dsh-set-card', probe.card);
    setStyleVar(root, '--dsh-set-text', probe.text);
    setStyleVar(root, '--dsh-set-page', cssRgb(page, 1));
    setStyleVar(root, '--dsh-set-fill', cssRgb(fill, 1));
    setStyleVar(root, '--dsh-set-hair', cssRgb(text, light ? 0.09 : 0.12));
    setStyleVar(root, '--dsh-set-muted', cssRgb(text, light ? 0.55 : 0.62));
    setStyleVar(root, '--dsh-set-shadow', light ? 'rgba(0, 0, 0, 0.10)' : 'rgba(0, 0, 0, 0.40)');
    root.setAttribute('data-dsh-set-key', bodyColor);
  }

  function setSettingsOpenMark(open) {
    // 设置页"打开/关闭"这个全局状态只写一个属性在 <html> 上：样式表用它来隐藏滚动条、
    // 锁文档滚动（见 injectStyle 的"无滑块四步"）。摘标记必须与打标记成对 ——
    // 关页后其它弹层（分享/删除确认）的遮罩与滚动条要完全恢复原状，这是本轮的硬约束。
    var root = document.documentElement;
    if (!root) {
      return;
    }
    if (open) {
      if (root.getAttribute('data-dsh-settings-open') !== '1') {
        root.setAttribute('data-dsh-settings-open', '1');
      }
    } else if (root.getAttribute('data-dsh-settings-open') === '1') {
      root.removeAttribute('data-dsh-settings-open');
    }
  }

  function pinSettingsBody(sc) {
    // 亚像素溢出的**兜底**钉子：源头已由 CSS 的 min-height:0 消掉，这里再钉一道 ——
    // 内容在 1px 容差内放得下时把 scrollTop 复位到 0（拖动后恒为 0 是可判定的验收项）。
    // 内容真的超长（小屏 / 键盘弹出把可视区压扁）时**不干预**：宁可"能滚但无滑块"，
    // 也不要把内容裁掉 —— 这条取舍是用户明确要的。
    if (!sc || sc.__dshPinned) {
      return;
    }
    sc.__dshPinned = true;
    sc.addEventListener('scroll', function () {
      if (sc.scrollTop !== 0 && sc.scrollHeight - sc.clientHeight <= 1) {
        sc.scrollTop = 0;
      }
    }, { passive: true });
  }

  function markSettingsModal() {
    if (window.innerWidth >= 768) {
      return;
    }
    var panel = findSettingsPanel();
    if (!panel) {
      // 找不到弹层 = 设置页没开（或已关）⇒ 摘掉全局标记，滚动条与文档滚动立刻恢复。
      // 这一步每次都跑，但只是一次属性读取 + 一次字符串比较，代价可忽略。
      setSettingsOpenMark(false);
      return;
    }
    setSettingsOpenMark(true);
    markSettingsShell(panel);
    markSettingsTabs(panel);
    markSettingsRows(panel);
    syncSettingsColors(panel);
  }

  function hasModalWrapperAtBody() {
    // 官方弹层是**新挂到 body 下**的一个 .ds-modal-wrapper（真机实测：开=插入、
    // 关=移除）。所以"body 子元素里有没有它"是 O(body 子元素数) 的廉价门，
    // 用它把绝大多数突变成交在本函数第一行，不进全文档查询。
    var kids = document.body ? document.body.children : null;
    if (!kids) {
      return false;
    }
    for (var i = 0; i < kids.length; i = i + 1) {
      if (kids[i].classList && kids[i].classList.contains('ds-modal-wrapper')) {
        return true;
      }
    }
    return false;
  }

  function maybeMarkSettings() {
    // 热路径入口（主观察器 → fastPath）。**门的顺序本轮对调**：先用廉价门看"body 子元素里
    // 有没有弹层壳"（O(body 子元素数)，个位数，零排版开销），再决定要不要限流。
    // 为什么必须对调（本轮修的首帧时序）：设置弹层是"点账号 → 点系统设置"之后**新挂到 body 下**
    // 的一棵子树，r17 逐帧实测（内部验证记录
    // 点击后约 200ms 弹层已在屏上）—— 而旧顺序是"先限流 200ms、再看壳"，于是弹层插入后
    // 头 200ms 的突变批次全被吞掉，那正好是**官方布局（半屏卡片 + 贴右下角）会被真正绘制出来**
    // 的窗口 ⇒ 用户看到的就是"设置页先按官方样子闪一帧、再跳成手机版"。
    // 现在：有壳就同步打标（markSettingsModal 幂等，各子步骤各自短路，代价 = 一次
    // .ds-modal-content__title 类查询 + 一次 body 底色读取）；限流只留给"壳不在"的高频路径。
    if (!hasModalWrapperAtBody()) {
      // 壳不在 = 设置页必然是关的 ⇒ 摘标记。这一步在正常浏览时每批突变都会走到，保留限流。
      var now = Date.now();
      if (now - settingsProbeAt < 200) {
        return;
      }
      settingsProbeAt = now;
      // 摘掉标记：弹层壳都不在，设置页必然是关的 —— 不让 data-dsh-settings-open
      // 有机会滞留在 <html> 上（滞留 = 全站滚动条一直被隐藏）。
      setSettingsOpenMark(false);
      return;
    }
    markSettingsModal();
  }

  // —— 主题变更 → 立刻重采设置面板配色（第十七轮补丁）——
  // 为什么需要：syncSettingsColors 用 body 底色当幂等键，只有"有人来调 markSettingsModal"才会重采。
  // 而真机上 prefers-color-scheme 恒为 false（官方把主题放在 body 的 class 上，不是媒体特性），
  // installThemeListener 的 matchMedia 回调**根本不会触发** ⇒ 用户在设置页里切"深色"后，
  // 面板要等 5s 巡检的 dirty / 每 6 拍（真机实测最长约 30s）才换色，中间一直是浅色卡片贴在深色页面上。
  // 修法：**定向**观察 body 与 html 的 class 属性（只这两个元素、不做子树）——一变就重打标 + 重采样。
  // 成本可控：class 变更本就稀少（主题/语言/滚动锁），且 syncSettingsColors 有 data-dsh-set-key
  // 幂等短路，没真变时一次测量都不做。**绝不能**扩成 subtree 的属性监听：文件里记着那条教训
  //（全子树 class/style 监听曾把真机渲染主线程压死，主观察器因此只盯 childList）。
  var themeClassObserver = null;

  function installThemeClassObserver() {
    if (themeClassObserver) {
      return;
    }
    try {
      themeClassObserver = new MutationObserver(function () {
        try { markSettingsModal(); } catch (e0) {}
      });
      themeClassObserver.observe(document.body, { attributes: true, attributeFilter: ['class'] });
      themeClassObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    } catch (e1) {
      themeClassObserver = null;
    }
  }

  function run() {
    injectStyle();
    markHost();
    applySafeArea();
    adjustFixedPanels();
    adjustMobileSheet();
    // markSideDrawers() 已下线：官方抽屉由原生侧栏接管（ShellScript 打
    // data-dsh-hide-drawer 保持 visibility:hidden），不再需要给它修圆角，
    // 而它本身是 'body *' 全文档遍历，留在 run() 里纯属浪费。
    markSidebarToggleButtons();
    removeDownloadPromos();
    hideSidebarTooltips();
    // 官方「系统设置」弹层可能在本适配器注入时就已打开（主题切换会整页 refresh）
    markSettingsModal();
    installThemeListener();
    installThemeClassObserver();
    installRouteListener();
    installPanelObserver();
    lastRoutePath = getRoutePath();
    syncHomeNewChat();
    window.__deepseekHmAdapterActive = true;
  }

  // 页面主题在内部切换（不刷新 DOM 时 ArkWeb 类 Chromium 会触发媒体查询变化）：
  // 重新同步 body/html 背景与安全区，保证沉浸底色跟主题一起实时变化。
  var themeListenerInstalled = false;

  function installThemeListener() {
    if (themeListenerInstalled) {
      return;
    }
    themeListenerInstalled = true;
    try {
      var mql = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
      if (!mql) {
        return;
      }
      var onChange = function () {
        applySafeArea();
        adjustFixedPanels();
        // 页面主题切换后重新采样设置面板配色（采样法保证深/浅两套观感都跟着走）
        markSettingsModal();
      };
      if (mql.addEventListener) {
        mql.addEventListener('change', onChange);
      } else if (mql.addListener) {
        mql.addListener(onChange);
      }
    } catch (ignore) {
    }
  }

  function schedule() {
    // run() 自己第一件事就是 installThemeListener()，而后者自带 installed 闩 ——
    // 这里原来又调了一次，纯冗余（行为等价），删掉。
    run();
    window.setTimeout(run, 120);
    window.setTimeout(run, 450);
  }

  try {
    if (document.head) {
      run();
    }
  } catch (ignore) {
  }

  // —— 单例登记（run 就绪后补上引用）——
  // 后续注入走开头的守卫分支，只会再跑一次 run()。
  ADAPTER.run = run;

  // DOMContentLoaded / load 只在首次注入时注册：这两个事件不需要重复监听，
  // 重复注册还会让 schedule() 里的三次 run() 成倍放大。
  window.addEventListener('DOMContentLoaded', schedule);
  window.addEventListener('load', schedule);

  try {
    // 主观察器只盯 childList（全子树 class/style 属性监听曾把真机渲染主线程压死，
    // 见下方“定向属性观察”注释）；面板级元素的属性变化交给 window.__dshPanelObserver
    // 定向观察。观察器实例挂 window 级共享：适配器重复注入（onPageEnd/主题切换）时
    // 复用首个实例，杜绝回调叠加。
    if (!window.__dshMainObserver) {
      var observer = new MutationObserver(function (mutations) {
        domMutationCount = domMutationCount + 1;
        markHost();
        hideSidebarTooltips();
        fastPath(mutations);
        onMaybeRouteChange();
        schedulePromoCleanup();
        scheduleFixedCleanup();
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      window.__dshMainObserver = observer;
    }
  } catch (ignore) {
  }

  // 供外部（调试/自动化复核）调用
  try {
    window.__deepseekHmRemovePromos = removeDownloadPromos;
    window.__deepseekHmAdjustFixedPanels = adjustFixedPanels;
    window.__deepseekHmAdjustMobileSheet = adjustMobileSheet;
    window.__deepseekHmHideSidebarTooltips = hideSidebarTooltips;
    window.__deepseekHmSyncHomeNewChat = syncHomeNewChat;
    window.__deepseekHmPadFullScreen = tryPadFullScreen;
    window.__deepseekHmMarkFloatBtn = markSidebarToggleButtons;
    window.__deepseekHmMarkSettings = markSettingsModal;
    window.__deepseekHmSyncDrawerBackdrop = syncDrawerBackdrop;
    // 安全区落地的钩子：ShellScript 的避让轻量通道（window.__dshSetInsets）除了重跑占位
    // 与路由上报，还要补跑这里的 applySafeArea —— body 的内边距只有本模块持有。
    window.__deepseekHmApplySafeArea = applySafeArea;
  } catch (ignore) {
  }

  // 静默页面兜底巡检：MutationObserver 只在有 DOM 突变时触发。真机实测缺陷场景：
  // 顶栏“下载应用”胶囊在适配器首跑后才渲染完成，若此后页面进入静默（无突变），
  // 防抖巡检不再排队，按钮长期可见（冷启动 8s 后仍 flex，手动调用立即生效）；
  // React 重渲染恢复被隐藏按钮的场景同理。低频巡检做一次短文本全扫 +
  // 右上角几何兜底，成本可控，仅适配器激活期间运行。
  //
  // 本轮三处调整（性能第一优先，且不引入 pauseAllTimers —— 那会连官方网页自己的
  // 定时器一起停掉，属于污染宿主页面）：
  //   ① 2s → 5s：原生外壳已接管顶栏，巡检里最贵的那几支（推广隐藏/几何兜底/悬浮圆框）
  //      在 shellOwnsChrome() 为真时整块跳过，剩下的只是低保真兜底，5s 足够；
  //   ② **可见性门控**：页面被隐藏（切后台、应用退到后台）时不跑巡检 ——
  //      此时既没有用户在看，也没有触摸要响应，跑了纯属浪费；
  //   ③ 回前台立即补查一次：门控不能变成"漏查"，切回来时把漏掉的这一次补上。
  var patrolInterval = 5000;
  try {
    window.setInterval(function () {
      if (!window.__deepseekHmAdapterActive) {
        return;
      }
      if (document.visibilityState === 'hidden') {
        ADAPTER.patrolSkipped = ADAPTER.patrolSkipped + 1;
        return;
      }
      ADAPTER.patrols = ADAPTER.patrols + 1;
      hideSidebarTooltips();
      // 流畅性门控（行为语义不变）：lastPatrolCount 初始 -1 保证首查必跑，覆盖
      // “适配器注入前已渲染、之后页面静默的推广按钮”历史踩坑；dirty 门控消除
      // 静默期全文档扫描；%6 即约 30 秒一次强制全查作为安全网（5s × 6）；hideSidebarTooltips
      // 廉价（.ds-tooltip 小选择器）保持无条件。
      patrolTicks = patrolTicks + 1;
      var forced = (patrolTicks % 6) === 0;
      var dirty = (domMutationCount !== lastPatrolCount);
      if (!dirty && !forced) {
        return;
      }
      lastPatrolCount = domMutationCount;
      patrolAll();
    }, patrolInterval);
  } catch (ignore) {
  }

  // 回前台补查一次：可见性门控必然会让隐藏期间的那几次巡检落空，
  // 切回来时立刻补一次，避免"切回来看到推广按钮还挂着"这类观感回退。
  try {
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible' && window.__deepseekHmAdapterActive) {
        ADAPTER.patrols = ADAPTER.patrols + 1;
        hideSidebarTooltips();
        patrolAll();
      }
    });
  } catch (ignore2) {
  }
})();
`;

