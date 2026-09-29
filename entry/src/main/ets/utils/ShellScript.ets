// 「原生外壳 + ArkWeb 聊天区」的网页侧桥脚本。
//
// 性能红线（本文件存在的理由）：侧边栏卡顿的根因是旧适配器在**侧栏开合动画期间**
// 对抽屉子树做同步排版测量（panelObserver → handlePanelMutation → 逐节点
// getComputedStyle + getBoundingClientRect，叠加 200ms 防抖的 adjustFixedPanels
// 全文档扫描 = layout thrashing）。本脚本把侧栏整块搬给原生组件渲染，网页侧只剩：
//   1) 一次性/低频抽取官方会话列表（TreeWalker + textContent，**零排版测量**）
//   2) 上报路由、标题、会话列表（javaScriptProxy）
//   3) 把官方顶栏与会话抽屉让位给原生（抽屉只保留在 DOM 里当数据源，visibility:hidden）
//   4) 暴露 window.__dshShellApi 供原生驱动导航（切会话/新建/返回）
//
// 抽取只在三处触发：脚本注入时、路由变化时、以及原生显式请求时（打开原生侧栏），
// 另有 3s 低频兜底（带 dirty 门控）。开合动画期间不参与任何测量。

export const SHELL_JS: string = `
(function () {
  // —— 删除安全闩的一次性密钥交接 ——
  // 为什么不能像早先那样在页面对象上放一个 armDelete(on)：那等于把"开闸"能力也交给页面，
  // 任何脚本（调试会话里的探针、页面里被注入的第三方脚本）都能自己开闸，闩就白加了。
  // 现在的做法是：**密钥由原生侧生成、写进一次性的 window.__dshArmSecret**
  // （Index.ets 的 rotateDeleteNonce），setDeleteToken() 在同一个同步求值周期里读走它
  // 并立刻 delete 掉那个属性 ——
  //   ① 闭包内的 state.deleteToken 在页面上没有读取出口；
  //   ② 页面脚本能调的所有方法都**不接受**密钥入参，只做校验；
  //   ③ 交接属性存在期只有一个同步求值周期，页面脚本没有插手的机会。
  // 本轮清理：这里原本还有一条 window.__dshArm -> ARM_SECRET 的**旧**交接通道（该通道在
  // 改名成 __dshArmSecret 之后遗留），全工程零消费者 —— 删掉（证据见 W1-inject.md）。

  var G = window.__dshNativeShell;
  if (G && G.alive) {
    // 适配器会被重复注入（onPageEnd / 主题切换）：复用同一实例，幂等重扫一次
    try { G.rescan(true); } catch (e) {}
    return;
  }

  var BRIDGE = 'dshBridge';
  var STYLE_ID = '__dsh_native_shell_style__';
  // injectStyle() 的成品缓存（CSS 是静态常量，理由见该函数开头）
  var STYLE_CSS = '';
  // 隐藏容器里"临时点亮祖先链"的一次性原值记录（见 tapInHidden 的说明）
  var hiddenRestoreTimer = 0;
  var hiddenTouched = [];
  // 设置链路"浮层视觉闩"的属性名（语义见 armMenuVeil，样式表规则见 injectStyle）。
  // **必须声明在这一段**：injectStyle() 在首次 rescan（markShell）时就会被调用，而 var 只
  // 提升声明、不提升赋值 —— 写在文件后段的话，首次注入会拼出 [undefined="1"] 这种选择器，
  // 规则整条失效且**不报任何错**（与 §3.0-5 那类沉默失效同源）。
  var MENU_VEIL_ATTR = 'data-dsh-menu-veil';
  var SESSION_RE = new RegExp('/a/chat/s/([A-Za-z0-9_-]{4,})');
  var UUID_RE = new RegExp('[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
  // 反复出现的定位选择器抽成常量：改口径时只改一处（散在多处的字面量迟早漂移，
  // 漂移的后果是"某一处静默匹配不到"，正是本文件记着的那类最难查的故障）。
  // 账号菜单白名单的**两个字面量**（口径变更史见 pickAccountOption 上方那段）。
  // **必须声明在这一段**：routeInfo() 在设置浮层打开时要用 ACCOUNT_OPTION_SETTINGS 当上报标题，
  // 而 routeInfo 在首次 rescan（文件末尾的 boot）就会被调到 —— var 只提升声明、不提升赋值，
  // 写在文件后段就会拼出 undefined 标题（与上面 MENU_VEIL_ATTR 同一条坑）。
  // 契约：Index.ets 的 ACCOUNT_OPTION_SETTINGS / ACCOUNT_LOGOUT_LABEL 必须与本处**逐字一致**。
  var ACCOUNT_OPTION_SETTINGS = '系统设置';
  var ACCOUNT_LOGOUT_LABEL = '退出登录';
  var SEL_SESSION_LINK = 'a[href*="/a/chat/s/"]';
  var SEL_MENU = '[class*="ds-dropdown-menu"]';
  var SEL_MENU_OPTION = '[class*="ds-dropdown-menu-option"]';
  var GROUP_LABELS = ['今天', '昨天', '7天内', '7 天内', '近7天', '近 7 天', '30天内', '30 天内',
    '近30天', '更早', '本周', '本月', 'Today', 'Yesterday', 'Previous 7 Days',
    'Previous 30 Days', 'Last 7 Days', 'Last 30 Days', 'Older'];

  // 注：state 里没有 alive 字段 —— 重复注入的幂等判据看的是 window.__dshNativeShell.alive
  // （见本函数顶部 G 守卫）。旧写法在 state 里也留了一份 alive，全脚本零读取，本轮删除。
  var state = {
    drawer: null,
    drawerSearchedAt: 0,
    topbar: null,
    toggle: null,
    revealOff: false,
    sessions: [],
    // sessionsSent（本轮提速）：上一次 sessions 桥消息**确实送达**过没有。
    // 冷启动期脚本会被重复注入，每次重入都走一次强制重扫；旧写法"force 就无条件重发"
    // 于是把同一份 62 条列表在 1.7s 内发了 4 遍（原生侧 applySessions 是整表替换，
    // 同内容重发是幂等的 —— 纯属白花 IPC + JSON 序列化 + 整表重建）。
    sessionsSent: false,
    // extractRoot（本轮提速）：上一次做全量抽取时用的抽屉根节点，用于证明"子树没变过"。
    extractRoot: null,
    routePath: '',
    dirty: true,
    // 路由脏标记（本轮新增）：history 三入口置 true，tick 里消费后清 false。
    // 与 dirty 分开是因为语义不同 —— dirty 是"抽屉内 DOM 变了"，routeDirty 是
    // "URL 变了"，后者只影响 reportRoute（占位/钉高），不必触发整条 rescan。
    routeDirty: false,
    prewarmDone: false,
    scrims: 0,
    observer: null,
    observedRoot: null,
    watchesDone: false,
    tick: 0,
    taps: 0,
    accountSig: null,
    deleteBusy: false,
    deleteDriving: 0,
    // 删除安全闩：密钥由原生侧生成并保管（见 setDeleteToken / deleteSession 顶部说明）。
    // deleteTokenAssigned 标记"当前这个密钥是原生侧下发过的" —— 没有它就一律拒绝，
    // 于是即使页面脚本把 deleteToken 改成空串（想绕开"必须匹配"的判据）也照样被拦。
    deleteToken: '',
    deleteTokenAssigned: false,
    /** 本次删除链路开工时的路由签名（null = 无链路在跑），用于"路由变了就中止"。 */
    deleteRoute: null,
    pinned: 0,
    fullH: 0,
    resizeTimer: 0,
    pinTimer: 0,
    // 设置链路"浮层视觉闩"（见 armMenuVeil）：menuVeil 1 = 开着；
    // menuVeilStamped 记"确实压到过菜单"，菜单节点从 DOM 消失即落闩（主路径）。
    menuVeil: 0,
    menuVeilStamped: 0,
    menuVeilTimer: 0,
    menuVeilObserver: null
  };

  function log(m) {
    try { console.info('[DSH-SHELL] ' + m); } catch (e) {}
  }

  function bridge(obj) {
    try {
      if (window[BRIDGE] && typeof window[BRIDGE].post === 'function') {
        window[BRIDGE].post(JSON.stringify(obj));
        return true;
      }
    } catch (e) {}
    return false;
  }

  function textOf(el) {
    if (!el) { return ''; }
    var s = el.textContent || '';
    return s.replace(/[\\s\\u00A0\\u200b]+/g, ' ').trim();
  }

  function injectStyle() {
    // 成品缓存（本轮性能项）：本函数的 CSS 是**静态常量**（唯一插值 MENU_VEIL_ATTR 在
    // 文件顶部就赋好了），而它在冷启动被调用十几次（boot rescan 到 markShell、每次
    // rescan、1000/2600ms 补扫、每次路由变化），每次都把这一整块重新拼一遍纯属浪费。
    // 命中缓存且已挂载节点内容一致就直接返回 —— 语义与原"拼完再比较"完全等价，
    // 只是省掉了拼接。
    if (STYLE_CSS !== '') {
      var cachedStyle = document.getElementById(STYLE_ID);
      if (cachedStyle && cachedStyle.textContent === STYLE_CSS) {
        return;
      }
    }
    // 顶栏 / 抽屉 / 遮罩三条让位规则：后两条声明块逐字相同，合并成一组选择器
    //（每条选择器的特异性与命中面都不变，语义等价，少下发一份重复声明）。
    var css = '[data-dsh-hide-topbar="1"]{display:none !important;}' +
      '[data-dsh-hide-drawer="1"],[data-dsh-hide-scrim="1"]' +
      '{visibility:hidden !important;pointer-events:none !important;}' +
      // 原生侧串行驱动批量删除时，官方那层「删除该对话」确认弹窗必须**看不见**。
      //
      // 真机实证（Mate70 Pro+，2026-09-11，截图 d2-modal.jpeg）：官方确认弹窗是
      // ds-modal-overlay(z=1025, rgba(0,0,0,.36) 全屏遮罩) + .ds-modal-wrapper(z=1026)，
      // 它挂在**文档级**、不在隐藏抽屉里 —— 抽屉被 visibility:hidden 挡不住它。
      // 侧栏面板只占 82% 宽，于是用户看到：点了原生「删除」之后，面板右下方又冒出
      // 半张官方弹窗（含红色「删除该对话」按钮）、整页同时被压暗 36%，随后才消失。
      // 用户已经在原生弹窗上确认过，这里只是"驱动官方 DOM"的必经步骤，让它露出来纯属穿帮。
      //
      // 用 visibility 而不是 display：visibility:hidden 保留几何，tap() 派发的事件
      // （不经过命中测试）照旧能落到「删除该对话」上，clientX/clientY 也是真实坐标 ——
      // display:none 会让 rect 全为 0，事件坐标失真。
      '[data-dsh-delete-driving="1"] .ds-modal-overlay,' +
      '[data-dsh-delete-driving="1"] .ds-modal-wrapper,' +
      '[data-dsh-delete-driving="1"] [data-dsh-hide-modal="1"]{visibility:hidden !important;}' +
      // 设置链路"浮层视觉闩"（第十七轮）：语义与生命周期见 armMenuVeil。
      // 只压 opacity —— 官方账号下拉菜单是 React portal、挂在 body 级浮层容器下，**不在**
      // tapInHidden 那条祖先链里，第一步点开它时会整块露在屏幕左下角约 290ms（探针实测）。
      // opacity 不参与命中测试，第二步 tap 菜单项（合成事件，见 tap）照旧生效。
      // transition:none 是必须的：官方给菜单挂了淡入淡出（实测 opacity 0 -> 1 用了 100ms），
      // 不掐掉动画就会被它从 0 拉回 1，等于压不住。
      '[' + MENU_VEIL_ATTR + '="1"]{opacity:0 !important;transition:none !important;}' +
      // 输入框里那条"假滑块"要关掉（用户报"输入长文本后滑动出现两条滑块"）。
      //
      // 官网输入框（._24fad49）里有三个同尺寸的兄弟层：
      //   [0] div.ds-scroll-area__gutters（overflow:visible，空）
      //   [1] textarea.ds-scroll-area（真正能滚的那个，overlay 滑块跟着手指走）
      //   [2] 一个无类名的镜像 div（overflow-y:auto、**pointer-events:none**、
      //       scrollTop 恒为 0）—— 它只是"量内容高度"用的，自己从不滚动，
      //       于是它的滑块永远停在轨道顶部（长度 = 336/492），叠在 textarea 的滑块上：
      //       两条滑块顶端不重合，看起来就是"两条"（真机截屏 sb-08 vs sb-09 对照）。
      // 判据用"行为"而不是类名（类名是构建期哈希）：滚动层 + pointer-events:none。
      // 只标记 textarea 的兄弟，绝不碰消息列表等其它滚动区。
      '[data-dsh-noscrollbar="1"]{scrollbar-width:none !important;}' +
      '[data-dsh-noscrollbar="1"]::-webkit-scrollbar{display:none !important;width:0 !important;height:0 !important;}';
    STYLE_CSS = css;
    var old = document.getElementById(STYLE_ID);
    if (old) {
      if (old.textContent === css) { return; }
      if (old.parentNode) { old.parentNode.removeChild(old); }
    }
    var s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  // 官方会话抽屉定位。关闭态抽屉 width=0 / 左移出屏，所以**不能**用宽度或 left 判存在，
  // 只认：高度占屏 ≥40%、宽度不超 90vw（排除 body/app 根）、内部含 ≥2 条会话链接。
  // 命中后缓存；未命中时 5s 内不重复遍历（几何兜底会做 getBoundingClientRect）。
  function findDrawer() {
    if (state.drawer && state.drawer.isConnected) { return state.drawer; }
    var i;
    var known = document.querySelectorAll('._519be07, .dc04ec1d');
    for (i = 0; i < known.length; i = i + 1) {
      var cand = known[i];
      if (!cand.isConnected) { continue; }
      // 已知类名是强信号：只要它够高，或内含会话链接，就认它
      if (cand.querySelector(SEL_SESSION_LINK) ||
        cand.getBoundingClientRect().height >= window.innerHeight * 0.4) {
        state.drawer = cand;
        return cand;
      }
    }
    var now = Date.now();
    if (now - state.drawerSearchedAt < 5000) { return null; }
    state.drawerSearchedAt = now;
    var all = document.querySelectorAll('div, aside, nav, section');
    var lim = Math.min(all.length, 2500);
    var best = null;
    var bestScore = 0;
    for (i = 0; i < lim; i = i + 1) {
      var el = all[i];
      if (!el.isConnected) { continue; }
      var n = el.querySelectorAll(SEL_SESSION_LINK).length;
      if (n < 2) { continue; }
      var r = el.getBoundingClientRect();
      if (r.width > window.innerWidth * 0.9) { continue; }
      if (r.left > 4) { continue; }
      if (r.height < window.innerHeight * 0.4) { continue; }
      var score = n * 1000000000 - Math.max(1, r.width) * r.height;
      if (score > bestScore) { bestScore = score; best = el; }
    }
    state.drawer = best;
    return best;
  }

  // 深色半透明底的 alpha；不是「深色 + 半透明」就返回 -1（不用正则，避免模板字面量转义）。
  function scrimAlpha(el) {
    var bg = '';
    try { bg = window.getComputedStyle(el).backgroundColor || ''; } catch (e) { return -1; }
    if (bg.indexOf('rgba(') !== 0) { return -1; }
    var p = bg.slice(5, bg.length - 1).split(',');
    if (p.length !== 4) { return -1; }
    var a = parseFloat(p[3]);
    if (!(a > 0.05 && a < 0.95)) { return -1; }
    var lum = (parseFloat(p[0]) + parseFloat(p[1]) + parseFloat(p[2])) / 3;
    if (!(lum < 140)) { return -1; }
    return a;
  }

  // 空遮罩：内部没有任何可交互元素、也没有文字。用来和「承载内容的全屏层」区分开。
  function isBlankScrim(el) {
    try {
      if (el.querySelector('a, button, input, textarea, [role="button"]')) { return false; }
      return (el.textContent || '').trim().length === 0;
    } catch (e) { return false; }
  }

  // 官方抽屉的遮罩是抽屉的**兄弟节点**，不是子节点 —— 只隐藏抽屉本体（见 markShell）
  // 会把它漏在页面上。
  //
  // 真机实证（Mate70 Pro+，443x952 CSS px，2026-09-11）：官方在这个视口下抽屉**默认就是
  // 打开态**（重载后第一帧 performance.now()=518ms 时 dc04ec1d 已无 collapsed、宽 261，
  // 遮罩 visible，此时会话链接还是 0，即与本脚本无关），于是 ._4cbcd96 这层
  // fixed 全屏 rgba(0,0,0,.4) 遮罩一直盖在页面上，两个后果：
  //   ① 整页被压暗 40%（实测白色 255 → 153，观感是「整个页面蒙了一层灰」）；
  //   ② 它 pointer-events:auto，**页面所有真实触摸都被它吃掉**（合成派发的事件不经过
  //      命中测试，所以此前「点会话 / 删会话」在自动化里看不出问题，真人操作会点不动）。
  // 判据：抽屉的兄弟 + fixed + 覆盖大半个视口 + 深色半透明底 + 内部无可交互内容/文字。
  function markDrawerScrim(dr) {
    state.scrims = 0;
    if (!dr || !dr.parentElement) { return 0; }
    var kids = dr.parentElement.children;
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    for (var i = 0; i < kids.length; i = i + 1) {
      var s = kids[i];
      if (s === dr) { continue; }
      var cs = null;
      try { cs = window.getComputedStyle(s); } catch (e0) { continue; }
      if (!cs || cs.position !== 'fixed') { continue; }
      if (scrimAlpha(s) < 0) { continue; }
      var r = s.getBoundingClientRect();
      if (r.width < vw * 0.8 || r.height < vh * 0.5) { continue; }
      if (!isBlankScrim(s)) { continue; }
      if (s.getAttribute('data-dsh-hide-scrim') !== '1') {
        s.setAttribute('data-dsh-hide-scrim', '1');
        log('drawer scrim hidden (fixed overlay ate page touches)');
      }
      state.scrims = state.scrims + 1;
    }
    return state.scrims;
  }

  function isGroupLabel(txt) {
    if (!txt || txt.length > 12) { return false; }
    for (var i = 0; i < GROUP_LABELS.length; i = i + 1) {
      if (txt === GROUP_LABELS[i]) { return true; }
    }
    return false;
  }

  // 会话列表抽取：TreeWalker 顺序遍历，按“最近一个分组标题”归组。
  // 只用 textContent/getAttribute —— 不读几何、不触发排版。
  function extractSessions(root) {
    var out = [];
    if (!root) { return out; }
    var walker = null;
    try {
      walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, null);
    } catch (e) {
      return out;
    }
    var seen = {};
    var cur = '';
    var node = walker.currentNode;
    var guard = 0;
    while (node && guard < 8000) {
      guard = guard + 1;
      var tag = node.tagName;
      if (tag === 'A') {
        var m = SESSION_RE.exec(node.getAttribute('href') || '');
        if (m && !seen[m[1]]) {
          var title = textOf(node);
          if (title && title.length <= 120) {
            seen[m[1]] = 1;
            out.push({ id: m[1], title: title, group: cur, active: false });
          }
        }
      } else if (tag === 'DIV' || tag === 'SPAN' || tag === 'P' || tag === 'LI' ||
        tag === 'H3' || tag === 'H4') {
        // 分组标题是叶子文案：先卡子元素个数，避免对大容器做整棵 textContent
        if (!node.children || node.children.length <= 1) {
          var t = textOf(node);
          if (t && isGroupLabel(t)) { cur = t; }
        }
      }
      node = walker.nextNode();
    }
    return out;
  }

  // 兜底抽取：官方若把历史项渲染成 div + onClick（没有 <a href>），
  // 上面的锚点通道会全空。此时按“携带 UUID 的属性”反查会话 id——
  // 抽屉里带 UUID 的节点几乎只可能是会话项（会话路由 /a/chat/s/<uuid>）。
  function extractByAttr(root) {
    var out = [];
    if (!root) { return out; }
    var seen = {};
    var cur = '';
    var nodes = root.querySelectorAll('*');
    var lim = Math.min(nodes.length, 3000);
    for (var i = 0; i < lim; i = i + 1) {
      var el = nodes[i];
      var id = '';
      var attrs = el.attributes;
      if (attrs) {
        for (var k = 0; k < attrs.length; k++) {
          var m = UUID_RE.exec(String(attrs[k].value || ''));
          if (m) { id = m[0]; break; }
        }
      }
      var t = '';
      if (!el.children || el.children.length <= 1) { t = textOf(el); }
      if (id) {
        if (!seen[id] && t && t.length <= 120) {
          seen[id] = 1;
          out.push({ id: id, title: t, group: cur, active: false });
        }
      } else if (t && isGroupLabel(t)) {
        cur = t;
      }
    }
    return out;
  }

  function routeInfo() {
    var path = '/';
    try { path = window.location.pathname || '/'; } catch (e) { path = '/'; }
    var kind = 'other';
    var id = '';
    var m = SESSION_RE.exec(path);
    if (m) {
      kind = 'chat';
      id = m[1];
    } else if (path === '/' || path.indexOf('/a/chat') === 0) {
      kind = 'home';
    }
    // —— 官方「系统设置」是网页区**整屏浮层**，但它不改 URL ——
    // MOBILE_ADAPTER_JS 在它开/关时已经把 html[data-dsh-settings-open="1"] 打上/摘掉（r17 落地），
    // 这里只读**这一个属性**（零新增扫描、零选择器）。浮层开着时对外报 kind='settings'：
    // 原生顶栏据此不渲染任何按钮，并按上报的 title 显示「系统设置」。
    // **id 不动**：用户仍然在那个会话里，侧栏高亮要继续落在当前会话行上。
    var setOpen = false;
    try {
      setOpen = document.documentElement.getAttribute('data-dsh-settings-open') === '1';
    } catch (e2) {}
    if (setOpen) { kind = 'settings'; }
    return { path: path, kind: kind, id: id, setOpen: setOpen };
  }

  // 删除链路的"路由未变"判据：三步之间各隔着数百毫秒，期间路由/锚点一变，
  // 场上元素就整体换了一批，继续按文案点红色确认键有误点风险。
  // **同时取 pathname 与 hash**：官方用 hash 承载一部分子页状态，
  // 只看 pathname 会漏掉"同一路径不同 hash"的跳转。
  function routeSignature() {
    var p = '';
    var h = '';
    try { p = window.location.pathname || ''; } catch (e) { p = ''; }
    try { h = window.location.hash || ''; } catch (e2) { h = ''; }
    return p + h;
  }

  // 链路是否已被取消：①deleteBusy 被复位（收尾/被新链路顶掉）；
  // ②路由相对开工时变了。两条都表示"这一步不该再往下点"。
  function deleteChainAborted(id) {
    if (!state.deleteBusy) { return true; }
    if (state.deleteRoute !== null && routeSignature() !== state.deleteRoute) {
      log('abort: route changed during delete chain (' + id + ')');
      return true;
    }
    return false;
  }

  // —— 原生悬浮顶栏配套：顶栏下方必须"有东西可糊"，同时内容不能被顶栏压住 ——
  // Web 组件铺满整个窗口（含原生顶栏那一条）后，网页视口比改造前高出一个 topInset。
  // 按"页面是否可滚动"分两种策略（真机实测，见 内部验证记录）：
  //
  //  A. 有滚动容器的页面（对话页）：占位插进 ds-virtual-list 内部。这样内容既能滚到
  //     顶栏下面（顶栏才糊得到东西），滚到顶时又不会被顶栏压住。**不能**改用
  //     padding-top：该容器的内容容器 ds-virtual-list-items 的 inline padding-top 是
  //     虚拟化器"可视窗口上方高度"的自有变量（配 visible-items 的 translateY），覆写
  //     必然与虚拟化打架；插兄弟节点完全旁路。实测下推量 === topInset、滚动范围同步
  //     增长、虚拟化仍在工作、内容文本前后一致无跳位。
  //
  //  B. 无滚动容器的页面（首页等）：把应用根的布局盒用 padding-top 还原成改造前的几何
  //     （内容区高 = 整屏 − topInset）。这类页面内容本来就不会滚到顶栏下面，硬塞占位
  //     只会让整页下移 —— 真机实测首页主标题因此下移了 85px。
  function ensureTopSpacer() {
    var px = Number(window.__dshTopInsetPx || 0);
    if (!(px > 0)) { return; }
    var sc = document.querySelector('.ds-virtual-list');
    var root = document.querySelector('.cb86951c');
    var i = 0;
    var mode = sc ? 'scroll' : 'root';
    if (root) {
      if (mode === 'scroll') {
        // 交还给官方那条 env(safe-area-inset-top) 规则
        if (root.style.paddingTop) {
          root.style.removeProperty('padding-top');
          root.style.removeProperty('box-sizing');
        }
      } else {
        // !important 覆盖官方那条，给足全量 topInset（内容区高 = 整屏 − topInset）
        var rootWant = Math.round(px) + 'px';
        if (root.style.paddingTop !== rootWant) {
          root.style.setProperty('padding-top', rootWant, 'important');
          root.style.setProperty('box-sizing', 'border-box', 'important');
        }
      }
    }
    var sp = null;
    var host = sc || root;
    if (host) {
      for (i = 0; i < host.children.length; i = i + 1) {
        var ch = host.children[i];
        if (ch.getAttribute && ch.getAttribute('data-dsh-topspacer') === '1') { sp = ch; break; }
      }
    }
    if (mode === 'scroll' && host) {
      // 关键：应用根自己已经吃掉了 env(safe-area-inset-top)。Web 铺到屏幕最顶之后，
      // ArkWeb 开始上报顶部安全区（真机 45.71px，等于系统状态栏高），官方 CSS 据此给
      // 应用根加了同高的 padding-top —— 改造前 Web 起点在状态栏之下，这个值是 0。
      // 所以占位高度必须减去它，否则就是"官方补一次 + 我再补一次"的重复下移
      // （实测：不减时内容顶端落后 46px）。直接量实际值，官方改版也不会失配。
      var rootPad = 0;
      if (root) { rootPad = parseFloat(getComputedStyle(root).paddingTop) || 0; }
      var need = Math.round(px - rootPad);
      if (need < 0) { need = 0; }
      if (!sp && need > 0) {
        sp = document.createElement('div');
        sp.setAttribute('data-dsh-topspacer', '1');
        if (host.firstChild) { host.insertBefore(sp, host.firstChild); } else { host.appendChild(sp); }
      }
      if (sp) {
        var want = need + 'px';
        if (sp.style.height !== want) { sp.style.height = want; }
      }
      return;
    }
    // 非滚动页：撤掉占位，几何由根上的 padding-top 承担（!important 覆盖官方那条，给足全量）
    if (sp && sp.parentNode) { sp.parentNode.removeChild(sp); }
  }

  // —— 输入坞下移：收窄免责声明行的上下内边距 ——
  // 官方在输入框下方留了一行 28px 的"内容由 AI 生成，请仔细甄别"（padding 6+6）。
  // 这一行属于合规提示，必须保留，只收窄内边距，回收约 8px 让输入框更贴近底部。
  // 用 textContent 关键字定位而不是类名：类名是构建期哈希，官方改版即失效。
  function tightenDock() {
    var ta = document.querySelector('textarea');
    if (!ta) { return; }
    var dock = null;
    var cur = ta;
    var i = 0;
    for (i = 0; i < 10 && cur; i = i + 1) {
      var cs = null;
      try { cs = window.getComputedStyle(cur); } catch (e) { cs = null; }
      if (cs && cs.position === 'sticky') { dock = cur; break; }
      cur = cur.parentElement;
    }
    if (!dock) { return; }
    var k = 0;
    for (k = 0; k < dock.children.length; k = k + 1) {
      var ch = dock.children[k];
      if (ch.querySelector && ch.querySelector('textarea, button, input')) { continue; }
      var t = (ch.textContent || '');
      if (t.indexOf('甄别') < 0 && t.indexOf('AI 生成') < 0 && t.indexOf('AI-generated') < 0) { continue; }
      if (ch.style.paddingTop !== '2px') {
        ch.style.setProperty('padding-top', '2px', 'important');
        ch.style.setProperty('padding-bottom', '2px', 'important');
      }
    }
  }

  // —— 首页视口钉高：输入法弹出时"首页输入框保持不动" ——
  //
  // 真机实测（Mate70 Pro+，2026-09-11，CDP 逐值取证）：
  //   ArkWeb 的键盘避让默认是 WebKeyboardAvoidMode.RESIZE_CONTENT（SDK 注释亦如此），
  //   键盘弹出时**布局视口**跟着收缩：innerHeight 952 → 583（键盘高 369 CSS px）。
  //   官网首页的问候语 + 输入框是"在可视高度里垂直居中"的（._660ca72 绝对定位、
  //   高 = 视口高 − 98 的 padding-top），于是输入框跟着从 y=466 跳到 y=281 ——
  //   用户看到的就是"输入法一出来，首页输入框整个上移"。
  //
  // 修法：首页把应用根 .cb86951c 的高度**钉在"键盘未弹出时的高度"**上，
  //   让官网那套居中计算继续按整屏算，输入框原地不动（实测 y 由 281 回到 465，
  //   与无键盘时的 466 只差 1px 的取整误差）；同时把 html 的用户滚动关掉 ——
  //   钉高之后文档比视口高 369px，不关的话用户能把输入框滑走（overflow:hidden
  //   只禁用户滚动，不禁脚本滚动，故脚本侧的 scrollTo 不受影响）。
  //
  // 只在**首页**钉：对话页的输入坞是"贴视口底"的 sticky，钉高会让它沉到键盘底下。
  // 高度取「见过的最大 innerHeight」而不是常量：旋转/分屏都会改视口高，
  // 记最大值天然拿到"没有键盘时的高度"，且不需要任何屏幕参数注入。
  //
  // 二次修正（键盘弹出 + 输入框变高时）：块体是**在整屏高度里居中**的，草稿一变高就会
  // 上下各长一半 —— 下半截沉到键盘底下（真机实测：12 行草稿让输入框底从 526 跑到 645，
  // 键盘上沿在 583）。所以还要按"输入框底不越过键盘上沿"反推虚拟高度：居中的位移
  // 恰好是高度变化的一半，故 高度 -= 2 × 越界量。效果是输入框沿原底边**向上长**。
  var TA_BOTTOM_MARGIN = 30;
  var PIN_MIN_RATIO = 0.5;

  function pinHomeLayout(isHome) {
    var h = window.innerHeight || 0;
    if (h > state.fullH) { state.fullH = h; }
    var html = document.documentElement;
    var root = document.querySelector('.cb86951c');
    if (isHome && state.fullH > 320) {
      var target = state.fullH;
      var ta = document.querySelector('textarea');
      if (h < state.fullH - 40 && root && ta) {
        var tr = ta.getBoundingClientRect();
        var over = (tr.bottom + TA_BOTTOM_MARGIN) - h;
        if (over > 0) {
          target = state.fullH - over * 2;
          if (target < state.fullH * PIN_MIN_RATIO) { target = state.fullH * PIN_MIN_RATIO; }
        }
      }
      var want = Math.round(target) + 'px';
      if (root && root.style.height !== want) { root.style.setProperty('height', want, 'important'); }
      if (html.style.overflow !== 'hidden') { html.style.setProperty('overflow', 'hidden', 'important'); }
      state.pinned = 1;
      return 1;
    }
    if (state.pinned === 1) {
      if (root) { root.style.removeProperty('height'); }
      html.style.removeProperty('overflow');
      state.pinned = 0;
    }
    return 0;
  }

  // —— 输入框"第二条滑块"清理 ——
  //
  // 真机逐像素定位（Mate70 Pro+，2026-09-11）：输入框里有**两根**竖滑块，各自来源不同：
  //   ① **官方自绘的浅色滑块** div.ds-scroll-area__vertical-gutter >
  //      div.ds-scroll-area__vertical-bar（真正的颜色画在它的 ::after 上：
  //      background: rgb(229,229,229)）。
  //      它是设计系统自己的滚动条，输入框有焦点时（ds-scroll-area--show-on-focus-within）
  //      **一直显示**、跟着滚动条位置走 —— 这就是用户说的"浅色长条一直保留"。
  //   ② **引擎默认的 overlay 滚动条**（textarea 自己的，深色）。平时淡出，
  //      **一滑动就冒出来**叠在浅色那条上 —— 用户说的"滑动时深色长条会短暂出现"。
  //      两条顶端不重合，于是看起来是"两条滑块"。
  // 结论：要留的是官方那根（它是设计的一部分、且只在输入框聚焦期间显示），
  // 要关掉的是**引擎默认那根重复的**。做法仍是打标记 + CSS 隐藏滚动条：
  //   - textarea 自己 → 关掉引擎 overlay 滚动条（不影响官方自绘那根，也不影响滚动能力）
  //   - textarea 的"不可交互的滚动兄弟层"（官方用来量内容高度的镜像层）→ 一并关掉，
  //     否则它在某些状态下会画出第三根。
  // 只扫 textarea 及其同容器的兄弟，绝不碰消息列表 / 官方抽屉等其它滚动区。
  // 判据不绑构建期哈希类名；找不到 textarea 就什么都不做（不标记 → 不隐藏 → 不误伤）。
  function markInputScrollbars() {
    var ta = document.querySelector('textarea.ds-scroll-area');
    if (!ta) { return 0; }
    var n = 0;
    if (ta.getAttribute('data-dsh-noscrollbar') !== '1') {
      ta.setAttribute('data-dsh-noscrollbar', '1');
      n = n + 1;
    }
    var kids = ta.parentElement ? ta.parentElement.children : null;
    if (!kids) { return n; }
    for (var i = 0; i < kids.length; i = i + 1) {
      var el = kids[i];
      if (el === ta) { continue; }
      var cs = null;
      try { cs = window.getComputedStyle(el); } catch (e) { continue; }
      if (!cs) { continue; }
      if (cs.overflowY !== 'auto' && cs.overflowY !== 'scroll') { continue; }
      if (cs.pointerEvents !== 'none') { continue; }
      if (el.getAttribute('data-dsh-noscrollbar') !== '1') {
        el.setAttribute('data-dsh-noscrollbar', '1');
        n = n + 1;
      }
    }
    if (n > 0) { log('input duplicate scrollbar hidden x' + n); }
    return n;
  }

  function reportRoute(force) {
    // 每 tick 都跑（廉价，两次 querySelector）：路由切换会重建滚动容器，
    // 占位必须跟着补回来。
    try { ensureTopSpacer(); } catch (e3) {}
    try { tightenDock(); } catch (e4) {}
    try { markInputScrollbars(); } catch (e7) {}
    try { reportAccount(); } catch (e5) {}
    var ri = routeInfo();
    // 设置浮层开着时 kind 已被 routeInfo 覆写成 settings ⇒ 这里自然不钉首页高度。
    // 它是整屏浮层、盖住了网页区，松开钉高用户看不见；浮层一关（属性被摘掉）本函数会被
    // 下面的 observer 再叫一次，届时 kind 回到 home、钉高自动补回。
    try { pinHomeLayout(ri.kind === 'home'); } catch (e6) {}
    // 去重键 = 路径 + 浮层标记：设置浮层**不改 URL**，只比 path 的话开/关两个方向都会被
    // 当成"路由没变"而漏报（原生顶栏就会一直停在旧语义上）。
    var rkey = ri.path + (ri.setOpen ? '|set' : '');
    if (!force && rkey === state.routePath) { return ri; }
    var title = '';
    try { title = document.title || ''; } catch (e) {}
    // 浮层页的标题必须**显式给**：Index.displayTitle() 对非 home/chat 的路由回落到文档标题，
    // 而设置浮层不改 URL ⇒ 文档标题仍是**会话名**（真机 m1 的 settings.jpeg 就是这个现象）。
    if (ri.setOpen) { title = ACCOUNT_OPTION_SETTINGS; }
    // 只有真的送达才记账：桥对象是 javaScriptProxy 注入的，页面极早期可能尚未就位，
    // 提前记账会让这条变更**永远不会重发**（签名已相同）。
    if (bridge({ t: 'route', path: ri.path, kind: ri.kind, id: ri.id, title: title })) {
      state.routePath = rkey;
    }
    return ri;
  }

  // 会话列表"变了没有"的判据（P2-2 重构）。
  //
  // 旧实现把整份列表拼成一个长字符串（id + 标题 + 分组，带分隔符）再整体比较 ——
  // 每次 collect 都要分配一个几十 KB 的字符串（56 条会话约 3~4KB，上百条更大），
  // 而这函数每 3s 就跑一次。改为**逐条 (id, title) 元组比较**：
  //  ① 只在**真正变了**的时候才需要区分（早退路径几乎零成本）；
  //  ② 不变时不分配任何大对象；
  //  ③ 诊断日志里的那个签名一并去掉，改报"变了没有"。
  // 只比 id/title 不看 group/active：分组与 active 是本脚本自己按同一份 DOM 算出来的派生量，
  // 跟着 id/title 一起变；把它们纳入判据只会让"标题改了但分组没变"这类正常变化被当成未变。
  function sessionsEqual(a, b) {
    if (a === b) { return true; }
    if (!a || !b || a.length !== b.length) { return false; }
    for (var k = 0; k < a.length; k = k + 1) {
      if (a[k].id !== b[k].id || a[k].title !== b[k].title) { return false; }
    }
    return true;
  }

  // 本轮去重（"提高运行速度"的实打实收益点，见 W1-inject.md §2b）：
  //   ① **抽取去重**：只有能证明"抽屉子树自上次抽取以来一个字节都没变过"时才跳过全量抽取。
  //      证明条件（四条全满足，缺一不可）：根节点还是同一个 / 观察器确实装在这个根上 /
  //      观察器没报过任何突变 / 上次抽到的列表非空（空列表可能是"还没渲染"，不能当结论）。
  //      observeDrawer() 每次（重）装观察器都会把 extractRoot 置空 —— 因为"上一次抽取到
  //      观察器装上"之间有一段没人看着的窗口，那一段必须真抽一次。
  //   ② **发送去重**：force 的原意是"绕过'变了没有'的比较"（冷启动补扫 / 原生开侧栏 /
  //      重注入都要求重扫一次），但**重扫 ≠ 重发**。列表与上次逐条相同、且上次确实送达过时
  //      再发一条一模一样的是幂等空操作。保留"没送达就重发"这条：桥对象在页面极早期可能
  //      尚未就位，那一次 bridge() 返回 false、sessionsSent 不置位，后续任何一次都会重发。
  function collect() {
    var root = findDrawer();
    var items;
    var reused = root && state.dirty !== true && state.sessions.length > 0 &&
      state.extractRoot === root && state.observedRoot === root;
    if (reused) {
      items = state.sessions;
    } else {
      items = extractSessions(root);
      if (items.length === 0) {
        items = extractByAttr(root);
      }
      state.extractRoot = root;
    }
    // 抽取完成即消费脏标记（旧写法由 ticker 在 rescan **之前**清，那样 collect 就再也
    // 看不到"这一拍确实脏过"了 —— 会误判成可复用）。ticker 的门控读的是清之前的值。
    state.dirty = false;
    var ri = routeInfo();
    var i;
    for (i = 0; i < items.length; i = i + 1) {
      items[i].active = (items[i].id === ri.id);
    }
    var changed = !sessionsEqual(items, state.sessions);
    state.sessions = items;
    var sent = false;
    if (changed || state.sessionsSent !== true) {
      if (bridge({ t: 'sessions', items: items })) { state.sessionsSent = true; }
      sent = true;
    }
    log('sessions=' + items.length + ' drawer=' + (root ? 'yes' : 'no') +
      ' changed=' + (changed ? 'yes' : 'no') + ' reused=' + (reused ? 'yes' : 'no') +
      ' sent=' + (sent ? 'yes' : 'no'));
    return items;
  }

  // —— 官方外壳让位 ——
  // 顶栏整体 display:none（原生顶栏接管，网页内容靠 __dshTopInsetPx 下移）；
  // 抽屉只 visibility:hidden（**必须留在 DOM 里**：它仍是会话列表的数据源）。
  //
  // 定位官方顶栏里的侧栏开关。
  // **判据必须排除“屏外/隐藏抽屉里的同款按钮”**：会话抽屉里也有同款图标按钮，且
  // 关闭态下 left 为负（真机实测 -198、宽 34），文档顺序还排在官方顶栏之前。
  // 旧判据只写 r.left > 110，负坐标直接放行 → 命中的是抽屉里的按钮 →
  // findTopBar() 从抽屉往上走，祖先全是 855 高的容器，永远撞不到 60px 的顶栏容器
  // → 返回 null → 官方顶栏从未被隐藏。真机表现：原生顶栏下方多出一排官方图标
  // （含重复的 ☰），消息列表被那 60px 白条压住。
  function findSidebarToggle() {
    var bar = Number(window.__dshStatusBarPx || 0);
    var maxTop = bar + 90;
    var drawer = null;
    try { drawer = window.__dshNativeDrawer || null; } catch (e0) { drawer = null; }
    var nodes = document.querySelectorAll('button, a, [role="button"], .ds-button');
    var n = Math.min(nodes.length, 500);
    for (var i = 0; i < n; i = i + 1) {
      var el = nodes[i];
      var cls = (typeof el.className === 'string') ? el.className : '';
      if (cls.indexOf('ds-button__') === 0) { continue; }
      if (drawer && drawer.contains(el)) { continue; }
      var r = el.getBoundingClientRect();
      // 必须在屏内：left 不能为负、不被右边缘裁掉、底部还在屏内
      if (r.left < 0 || r.right > window.innerWidth + 4 || r.bottom <= 0) { continue; }
      if (r.width < 22 || r.width > 68 || r.height < 22 || r.height > 68) { continue; }
      if (r.top < 0 || r.top > maxTop) { continue; }
      if (r.left > 110) { continue; }
      if (textOf(el).length > 2) { continue; }
      if (!el.querySelector || !el.querySelector('svg, img, [class*="icon"]')) { continue; }
      return el;
    }
    return null;
  }

  // 官方顶栏容器 = 开关所在的那条 60px 横条。
  // **必须取最外层匹配的祖先，不能在第一个匹配处早退**：真机实测这条横条是两层 ——
  // 外层占位容器（443x60，在流内，与消息滚动区并列）套内层 the-header（首页 443x60、
  // 对话页 384x60）。两层都满足宽度判据，早退只会隐藏内层，外层 60px 占位仍在流内
  // → 消息列表纹丝不动（实测 scroller 恒为 y=60），原生顶栏下方白留一条。
  function findTopBar(btn) {
    if (!btn) { return null; }
    var el = btn;
    var hops = 0;
    var best = null;
    while (el && hops < 8) {
      var r = el.getBoundingClientRect();
      if (r.width >= window.innerWidth * 0.8 && r.height >= 24 && r.height <= 130) {
        best = el;
      }
      el = el.parentElement;
      hops = hops + 1;
    }
    return best;
  }

  function markShell(force) {
    injectStyle();
    // 用户点过「打开网页侧栏」：在原生侧栏被再次显式打开（rescan(true)）之前不再接管，
    // 否则 3s 兜底 tick 会把刚交还的官方外壳又藏回去，兜底按钮等于死路。
    if (force === true) { state.revealOff = false; }
    if (state.revealOff === true) {
      try { window.__dshShellOwnsChrome = false; } catch (e1) {}
      return;
    }
    if (!state.topbar || !state.topbar.isConnected) {
      // 开关引用要留住：顶栏被 display:none 之后几何判据必然失效，prewarm() 只能靠它。
      state.toggle = findSidebarToggle();
      state.topbar = findTopBar(state.toggle);
    }
    if (state.topbar && state.topbar.getAttribute('data-dsh-hide-topbar') !== '1') {
      state.topbar.setAttribute('data-dsh-hide-topbar', '1');
      log('topbar handed over to native');
    }
    // 告诉旧适配器：顶栏已由原生接管 —— 让它整块跳过“推广隐藏 / 首页 ⊕ 几何兜底 /
    // 悬浮圆框打标”那套全文档扫描（这些目标原本都只存在于官方顶栏里）。
    try { window.__dshShellOwnsChrome = (state.topbar ? true : false); } catch (e0) {}
    var dr = findDrawer();
    if (dr && dr.getAttribute('data-dsh-hide-drawer') !== '1') {
      dr.setAttribute('data-dsh-hide-drawer', '1');
      log('drawer kept as data source, hidden from view');
    }
    // 遮罩与抽屉同生共死：抽屉开着时那层 fixed 全屏暗遮罩会压暗整页并吃掉所有真实触摸
    markDrawerScrim(dr);
    // 供 MOBILE_ADAPTER_JS 跳过该子树（避免动画期同步测量）
    try { window.__dshNativeDrawer = dr || null; } catch (e) {}
  }

  // —— 真实触摸派发 ——
  // 官方 ds-button 是 div + React pointer 事件，模拟器/真机实测 .click() 不生效，
  // 必须补齐 pointerdown/mousedown/pointerup/mouseup/click 序列。
  function tap(el) {
    if (!el) { return false; }
    try {
      var r = el.getBoundingClientRect();
      // 目标自身可能"没有几何"：隐藏抽屉里的行内「⋯」平时是 0x0（宽度靠 hover 才出现，
      // 实测 getBoundingClientRect 全 0）。此时按 (0,0) 派发事件等于点在屏幕左上角，
      // 官方 React 收不到有效坐标 —— 表现就是"点了 ⋯ 菜单不弹"。
      // 退到最近的**有几何的祖先**（行/列表项）取其中心，事件坐标才是真实的行位置。
      if ((r.width < 2 || r.height < 2) && el.parentElement) {
        var p = el.parentElement;
        var hop = 0;
        while (p && hop < 4) {
          var pr = p.getBoundingClientRect();
          if (pr.width > 2 && pr.height > 2) { r = pr; break; }
          p = p.parentElement;
          hop = hop + 1;
        }
      }
      var cx = Math.round(r.left + r.width / 2);
      var cy = Math.round(r.top + r.height / 2);
      var mo = { bubbles: true, cancelable: true, composed: true, view: window,
        clientX: cx, clientY: cy, button: 0 };
      var pd = { bubbles: true, cancelable: true, composed: true, view: window,
        clientX: cx, clientY: cy, button: 0, buttons: 1, pointerId: 1,
        pointerType: 'touch', isPrimary: true, width: 2, height: 2 };
      var pu = { bubbles: true, cancelable: true, composed: true, view: window,
        clientX: cx, clientY: cy, button: 0, buttons: 0, pointerId: 1,
        pointerType: 'touch', isPrimary: true, width: 2, height: 2 };
      try { el.dispatchEvent(new PointerEvent('pointerdown', pd)); } catch (e0) {}
      try { el.dispatchEvent(new MouseEvent('mousedown', mo)); } catch (e1) {}
      try { el.dispatchEvent(new PointerEvent('pointerup', pu)); } catch (e2) {}
      try { el.dispatchEvent(new MouseEvent('mouseup', mo)); } catch (e3) {}
      try { el.dispatchEvent(new MouseEvent('click', mo)); } catch (e4) {}
      state.taps = state.taps + 1;
      return true;
    } catch (e) {
      return false;
    }
  }

  // —— 设置页底部功能栏（第二十一轮）——
  // 原生底栏点了某一项 → 这里驱动网页切页签。网页自己那一行页签由适配器用
  // visibility:hidden 藏掉（**不能 display:none**：rect 会全 0，tap 退到祖先就点错元素，
  // 见 EXPERIENCE 第 1.2-30 条），因此必须保留几何、靠 tap() 派发真实坐标。
  // 页签上的 data-dsh-settings-tab 标记由 MOBILE_ADAPTER_JS 的 markSettingsModal 打。
  function settingsTabNodes() {
    return document.querySelectorAll('[data-dsh-settings-tab="1"]');
  }
  // 当前选中下标：优先问适配器（它持有官方选中态的 hash 类，见 ensureSettingsAccent），
  // 拿不到再退回 aria 判据；两者都拿不到返回 -1（原生侧据此保持自己的 active 不动）。
  function currentSettingsTab() {
    try {
      if (typeof window.__dshSettingsTabIndex === 'function') {
        var idx = Number(window.__dshSettingsTabIndex());
        if (idx >= 0) { return idx; }
      }
    } catch (e1) {}
    var ns = settingsTabNodes();
    for (var i = 0; i < ns.length; i++) {
      var el = ns[i];
      if (el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-current') === 'page') { return i; }
    }
    return -1;
  }
  function setSettingsTab(index) {
    var ns = settingsTabNodes();
    var i = Number(index);
    if (!(i >= 0) || i >= ns.length) { return 'out-of-range'; }
    // 不做「已是当前项就短路」：适配器那边的选中判据（hash 类）本脚本读不到，
    // 短路判错就会静默不切换；重复派发点击是幂等的，代价只有一次事件。
    return tap(ns[i]) ? 'ok' : 'fail';
  }
  // 关闭官方「系统设置」浮层（第二十一轮）—— 由原生标题栏的返回钮（尖括号图标）调用。
  //
  // ⚠️ **不能**用 history.back()：官方设置浮层**不改 URL**，back() 退的是聊天页，
  //    会把用户从设置页直接赶回会话（甚至退到上一个会话）。关闭只能走它自己的 ✕ 入口。
  // ⚠️ 那一行已整行交给原生标题栏（标题与 ✕ 都被适配器藏了），但 ✕ 的**几何仍然保留**
  //    （适配器把它 fixed 定位到屏幕底部、opacity:0）⇒ 这里能对它派发点击。
  //    这也是为什么适配器不能用 display:none —— rect 会全 0，tap 会退到祖先点错地方。
  function closeSettings() {
    var panel = document.querySelector('[data-dsh-settings-panel="1"]');
    if (!panel) { return 'not-open'; }
    var btn = panel.querySelector('.ds-modal-content__header-wrapper > .ds-button');
    if (!btn) { return 'no-button'; }
    return tap(btn) ? 'ok' : 'fail';
  }

  // 预热：官方抽屉关闭态可能尚未渲染完整列表，隐藏态下点开一次再关回，
  // 全程 visibility:hidden（用户看不见），只为把列表烘进 DOM。
  function prewarm() {
    if (state.prewarmDone) { return; }
    state.prewarmDone = true;
    // 顶栏此刻已被 display:none（原生接管），几何判据必然失效 —— 只能用 markShell()
    // 留下的开关引用。display:none 的元素照样能接收派发事件（与抽屉里的会话链接同理，
    // 真机已实证 taps 生效），所以这里点得动。
    var btn = (state.toggle && state.toggle.isConnected) ? state.toggle : findSidebarToggle();
    if (!btn) { log('prewarm skipped: toggle not found'); return; }
    log('prewarm: render hidden official drawer once');
    tap(btn);
    window.setTimeout(function () { collect(); reportRoute(false); }, 900);
    window.setTimeout(function () {
      if (btn && btn.isConnected) { tap(btn); }
      window.setTimeout(function () { collect(); reportRoute(false); }, 600);
    }, 1900);
  }

  function rescan(force) {
    markShell(force === true);
    // collect() 不再接 force：重扫仍照旧发生（抽取照跑），只是"列表没变就不重发"
    // —— 见 collect() 顶部说明。force 对 markShell / reportRoute 的语义不变。
    collect();
    reportRoute(force === true);
    if (!state.prewarmDone && state.sessions.length === 0) { prewarm(); }
  }

  // —— 原生驱动接口 ——
  function findLink(id) {
    var links = document.querySelectorAll(SEL_SESSION_LINK);
    for (var i = 0; i < links.length; i = i + 1) {
      var m = SESSION_RE.exec(links[i].getAttribute('href') || '');
      if (m && m[1] === id) { return links[i]; }
    }
    return null;
  }

  function openSession(id) {
    if (!id) { return 'skip'; }
    var a = findLink(id);
    if (a) { tap(a); return 'tap'; }
    try {
      window.history.pushState({}, '', '/a/chat/s/' + id);
      window.dispatchEvent(new PopStateEvent('popstate'));
      return 'push';
    } catch (e) {}
    try { window.location.href = '/a/chat/s/' + id; return 'href'; } catch (e2) {}
    return 'fail';
  }

  function findNewChatButton() {
    var root = findDrawer() || document.body;
    var sels = ['button[aria-label*="新建对话"]', 'button[aria-label*="新对话"]',
      'button[aria-label*="New chat"]', '[data-testid*="new-chat"]',
      '[data-testid*="newChat"]'];
    var i;
    var j;
    for (i = 0; i < sels.length; i = i + 1) {
      var nodes = root.querySelectorAll(sels[i]);
      for (j = 0; j < nodes.length; j = j + 1) { return nodes[j]; }
    }
    var cand = root.querySelectorAll('div, span, a, button, li');
    var lim = Math.min(cand.length, 400);
    for (i = 0; i < lim; i = i + 1) {
      var t = textOf(cand[i]);
      if (t === '新建对话' || t === '新对话' || t === 'New chat') { return cand[i]; }
    }
    return null;
  }

  function newChat() {
    var btn = findNewChatButton();
    if (btn) { tap(btn); return 'tap'; }
    try {
      window.history.pushState({}, '', '/');
      window.dispatchEvent(new PopStateEvent('popstate'));
      return 'push';
    } catch (e) {}
    return 'fail';
  }

  function observeDrawer() {
    var root = findDrawer();
    if (!root || state.observedRoot === root) { return; }
    state.observedRoot = root;
    // 从"上一次抽取"到"观察器装上"之间有一段没人看着的窗口：那段里发生的突变不会被
    // 记进 dirty。所以每次（重）装观察器都必须让抽取复用失效，逼下一次真抽一遍。
    state.extractRoot = null;
    try {
      if (!state.observer) {
        state.observer = new MutationObserver(function () { state.dirty = true; });
      }
      state.observer.disconnect();
      state.observer.observe(root, { childList: true, subtree: true, characterData: true });
    } catch (e) {}
  }

  function startTicker() {
    if (state.watchesDone) { return; }
    state.watchesDone = true;
    try {
      var wrap = function (name) {
        var orig = window.history[name];
        if (typeof orig !== 'function') { return; }
        window.history[name] = function () {
          var ret = orig.apply(this, arguments);
          // 路由脏标记（audit §3 CPU P0，本轮新增）：3s 兜底 tick 曾**每个 tick** 都跑
          // 一整条 reportRoute（ensureTopSpacer + tightenDock + markInputScrollbars +
          // reportAccount + routeInfo + pinHomeLayout ≈ 5~8 次 querySelector + 多次
          // getComputedStyle）——空闲态纯属空转。现在只有"路由确实动过"才需要在 tick 里补
          // 这一次报告；SPA 换路由必经 pushState/replaceState/popstate/hashchange
          // （本函数与下面两个监听就是全部入口），故脏标记不会漏。
          state.routeDirty = true;
          window.setTimeout(function () { rescan(false); }, 40);
          return ret;
        };
      };
      wrap('pushState');
      wrap('replaceState');
    } catch (e) {}
    try {
      window.addEventListener('popstate', function () {
        state.routeDirty = true;
        window.setTimeout(function () { rescan(false); }, 40);
      });
      window.addEventListener('hashchange', function () {
        state.routeDirty = true;
        window.setTimeout(function () { rescan(false); }, 40);
      });
      // 回前台补一次全量重扫（audit §3 CPU P0，本轮新增）：
      // 下面 5s 兜底 tick 现在带「页面不可见就整条跳过」的门控，跳过的 tick 不推进
      // state.tick —— 也就是说 App 在后台待了 10 分钟，回来后不会靠补跑 tick 追上，
      // 必须在这里显式补一次 rescan（force=true），保证回到前台的**第一帧**侧栏数据、
      // 路由、顶栏让位状态就是新的。visibilitychange 是"醒来"的唯一可靠信号，
      // resize 在部分机型切后台时并不触发。
      document.addEventListener('visibilitychange', function () {
        try {
          if (document.visibilityState !== 'visible') { return; }
          window.setTimeout(function () { rescan(true); }, 60);
        } catch (eVis) {}
      });
      // 视口高度变化（键盘弹出/收起、旋转）：钉高与路由判定要立刻跟上，
      // 不能等 3s 兜底 tick —— 首页输入框"上移"只发生在键盘弹出后的前几帧。
      window.addEventListener('resize', function () {
        if (state.resizeTimer) { window.clearTimeout(state.resizeTimer); }
        state.resizeTimer = window.setTimeout(function () {
          state.resizeTimer = 0;
          try { reportRoute(false); } catch (e3) {}
        }, 60);
      });
      // 输入框长高（多行草稿）也要立刻重算钉高：否则要等 3s 兜底 tick 才把
      // 沉到键盘下面的那半截抬回来。只跑 pinHomeLayout（两次 querySelector），不跑整条 rescan。
      document.addEventListener('input', function () {
        if (state.pinTimer) { window.clearTimeout(state.pinTimer); }
        state.pinTimer = window.setTimeout(function () {
          state.pinTimer = 0;
          try { pinHomeLayout(routeInfo().kind === 'home'); } catch (e4) {}
        }, 80);
      }, true);
    } catch (e2) {}
    // 低频兜底（audit §3 CPU P0，本轮改）：
    // ① 后台门控：页面不可见时整条 tick 直接返回。ArkWeb 的 setInterval 在 App 切后台后
    //    仍会按调度唤醒网页主线程，而 tick 体（visibility 分支除外）要跑
    //    5~8 次 querySelector + 多次 getComputedStyle（tightenDock 还向上爬 10 层）——
    //    用户在别的 App 里，这些唤醒 100% 是纯浪费。跳过的 tick **不推进 state.tick**，
    //    避免"看不见的时间"把 30s 强制全查的安全网提前耗掉（醒来由上面的
    //    visibilitychange 监听补一次 rescan(true)，不依赖 tick 追平）。
    // ② 基础节奏 3s → 5s，与适配器巡检（P1-1 已放宽到 5s）一致；会话列表本身有
    //    "逐条 (id,title) 元组比较"兜着，真变了下一拍就被 dirty 抓到。
    // ③ 路由脏标记：无 dirty 且路由没动过时，连 reportRoute 都不跑（该函数是 tick 里
    //    最贵的一支）。等价性：SPA 换路由必经 history 三个入口，均已置脏（见上面 wrap）。
    // ④ 强制全查安全网按**墙钟**保持 ~30s（6 × 5s），不跟着基础节奏一起放宽 ——
    //    它本来就是"万一 dirty 漏了"的最后一道网，拉长它等于拉长漏检窗口。
    window.setInterval(function () {
      try {
        if (document.visibilityState !== 'visible') { return; }
      } catch (eVis2) {
      }
      state.tick = state.tick + 1;
      observeDrawer();
      if (state.dirty || (state.tick % 6) === 0) {
        // state.dirty 的清除**下移到 collect()**：在那里清才能让 collect 自己看到
        // "这一拍确实脏过"（否则抽取复用会把这一拍的突变当成没发生）。本行门控读的
        // 仍是清之前的值，判断不受影响。
        state.routeDirty = false;
        rescan(false);
      } else if (state.routeDirty) {
        reportRoute(false);
      }
    }, 5000);
  }

  // —— 设置浮层的路由语义：边沿触发（第十九轮 W1）——
  // 官方「系统设置」是网页区整屏浮层、**不改 URL** ⇒ reportRoute 没有任何被调用的机会，
  // 开/关两个方向都会漏报。MOBILE_ADAPTER_JS 在它开/关时会把 html 上的
  // data-dsh-settings-open 打上/摘掉（且只在值真的变化时才写），所以这里只需盯**这一个属性**。
  //
  // ⚠️ 这**不是**"全量扫描"，也**不是**本文件记着的那条压死渲染主线程的坑：
  //   那条教训是**对 documentElement 做 subtree 的 class/style 监听**（页面海量属性变化全喂进回调）；
  //   这里是 subtree:false + attributeFilter 单属性 + 目标只有 <html> 一个元素，
  //   而 html 的这个属性在一次设置页开/关里各只变一次。
  // 为什么用 observer 而不是"让适配器回调本脚本"：setSettingsOpenMark 有三个调用方
  // （maybeMarkSettings 的快路径 / markSettingsModal / patrolAll 巡检），observer 一次覆盖全部。
  function watchSettingsMark() {
    try {
      var ob = new MutationObserver(function () {
        // 用 reportRoute(false) 而不是 (true)：开/关会把去重键（path + |set）改掉，
        // 所以"真变了"一定能过门；而"属性没真变却触发了一次"则自然成为空操作。
        try { reportRoute(false); } catch (e0) {}
      });
      ob.observe(document.documentElement, {
        attributes: true, attributeFilter: ['data-dsh-settings-open']
      });
    } catch (e1) {}
  }

  // —— 账号信息（侧栏页脚用）——
  // 抽屉关闭时宽度被压成 0，内部元素几何全部不可用，所以只能按结构/属性定位：
  // 头像 img 的 src 含 user-avatar 且全文档唯一，从它上溯到 tabindex=0 的账号行；
  // 行内第一个"既不含 img 也不含 svg"的有文本子节点就是昵称。
  // 实测：昵称"爱莫能助"、头像 https://static.deepseek.com/user-avatar/...
  // img 可由调用方传入：accountInfo 已经查过一次同一个属性选择器，不重复做第二遍
  //（img[src*=...] 是属性子串匹配，浏览器要逐个 img 比对，白做一次没有意义）。
  function accountRow(img) {
    if (!img) { img = document.querySelector('img[src*="user-avatar"]'); }
    if (!img) { return null; }
    var row = img.parentElement;
    var i = 0;
    for (i = 0; i < 6 && row; i = i + 1) {
      if (row.getAttribute && row.getAttribute('tabindex') === '0') { return row; }
      row = row.parentElement;
    }
    return null;
  }

  function accountInfo() {
    var img = document.querySelector('img[src*="user-avatar"]');
    var row = accountRow(img);
    if (!img || !row) { return null; }
    var name = '';
    var k = 0;
    for (k = 0; k < row.children.length; k = k + 1) {
      var ch = row.children[k];
      if (ch.querySelector && ch.querySelector('img, svg')) { continue; }
      var t = textOf(ch);
      if (t.length > 0) { name = t; break; }
    }
    return { name: name, avatar: img.getAttribute('src') || '' };
  }

  function reportAccount() {
    var info = accountInfo();
    if (!info) { return; }
    var sig = info.name + '|' + info.avatar;
    if (sig === state.accountSig) { return; }
    if (bridge({ t: 'account', name: info.name, avatar: info.avatar })) {
      state.accountSig = sig;
    }
  }

  // —— 账号菜单（第十六轮收口：只剩「退出登录」）——
  // 点账号行展开官方 ds-dropdown-menu，再按可见文案点具体项。
  // 官方菜单渲染在隐藏抽屉里，用户看不见，所以原生侧自己画一份同样的菜单。
  function openAccountMenu() {
    var row = accountRow();
    if (!row) { return 'no-row'; }
    tap(row);
    return 'ok';
  }

  // 账号菜单里**允许被本桥驱动**的项（白名单，第十六轮第三批：按用户要求恢复「系统设置」）。
  // 这里换过两次口径，值得记一笔：
  //   · 最早 label 是**自由入参** —— 调用方传什么文案就去点官方菜单里的哪一项，等价于
  //     "任何能调到 __dshShellApi.pickAccountOption 的页面脚本都能点中账号菜单任意项"
  //     （含"注销账号"这类不可逆项），与 §3.0-93「破坏性入口不得暴露给网页侧」同源；
  //   · 第十六轮一度把原生菜单收成只剩「退出登录」，此处随之只剩一个常量；
  //   · 现在恢复「系统设置」，但**不收回到自由入参** —— 改成**两个字面量的白名单**：
  //     只认下面这两个值，其余一律回 'unsupported' 且不派发任何事件。"可驱动面"因此
  //     依然是一个**封闭集合**：官方菜单以后新增危险项也点不到。
  // 契约：Index.ets 的 ACCOUNT_OPTION_SETTINGS / ACCOUNT_LOGOUT_LABEL 必须与本处**逐字一致**。
  // （这两个 var 的**声明**已上移到文件顶部 MENU_VEIL_ATTR 那一段，理由见那里的注释。）
  //
  // ⚠️ **本段（以及 SHELL_JS 里任何注释）一处反引号都不能有**：SHELL_JS 是 ArkTS 模板字符串，
  // 注释里写反引号会**提前截断**它。写这段时真踩了 —— 预检报 "SHELL_JS 语法错误"、构建报
  // arkts-no-any-unknown，两处同源。同理不要在注释里抄正则字面量：反斜杠会被转义成真实
  // 控制字符落进产物（§3.0-5 已记录过两次）。

  // 官方账号菜单当前是否真的展开着（label 必须是白名单里的值）。
  // 为什么要多这一层：原生侧点某一项会先弹**原生 AlertDialog**，用户确认后才回网页侧
  // 点官方菜单项 —— 中间隔着一次异步渲染（tap 账号行 → React 挂载 ds-dropdown-menu，
  // 实测要 100ms 量级）。早先 pickAccountOption 是"查一次，查不到就放弃"，于是手快时会
  // 静默什么都不做（用户视角：点了"系统设置"没反应、面板还关了）。现在给原生侧一个
  // **可轮询的判据**：找不到返回 null → pickAccountOption 回 'not-found'，
  // 由原生侧按 140ms 重试最多 8 次（Index.pickAccountOption）。
  // 官方账号菜单当前是否已经展开（原生侧驱动分两步，第一步就是把它打开）。
  function accountMenuShown() {
    try { return !!document.querySelector(SEL_MENU); } catch (e) { return false; }
  }

  function accountMenuOption(label) {
    var el = menuOptionOf(label);
    if (!el) { return null; }
    // 隐藏父级下的元素几何不可用，这里只验"在文档里且可见（非 display:none）"
    try {
      if (el.offsetParent === null && window.getComputedStyle(el).position !== 'fixed') { return null; }
    } catch (e) { return null; }
    return el;
  }

  // 在官方账号菜单里找指定文案的那一项。入参**只能**是上面白名单里的两个字面量
  // （调用方 pickAccountOption 已先校验），不做任何"模糊匹配"。
  function menuOptionOf(label) {
    var opts = document.querySelectorAll(SEL_MENU_OPTION);
    var i = 0;
    for (i = 0; i < opts.length; i = i + 1) {
      var cls = String(opts[i].className || '');
      // 选项内部的文案子节点 ('...__label') 要跳过：否则 tap 会打到文字上而不是整行选项
      if (cls.indexOf('__label') >= 0) { continue; }
      if (textOf(opts[i]) === label) { return opts[i]; }
    }
    return null;
  }

  // 官方「系统设置」弹层当前是否已经呈现着。
  //
  // 为什么需要这个判据（第十六轮第三批真机 + CDP 实测）：**官方账号入口点一下，直接打开的就是
  // 设置弹层本身**（ds-modal-content__title 文本 = "系统设置"，内含 通用设置 / 账号管理 /
  // 数据管理 三个 tab），**不再是老版本那个下拉菜单** —— 于是老实现的
  // [class*="ds-dropdown-menu-option"] 一个都匹配不到，pickAccountOption 每次都走完
  // 原生侧 8 次重试、再弹一句"官方菜单未响应，请重试"，**而设置页其实早就开在弹窗背后了**。
  // 这就是"点了系统设置没反应（还弹个错）"的完整真相。
  //
  // 判据用"标题文本 + 弹层容器有实际尺寸"：与 accountMenuOption 同一条思路 ——
  // 隐藏父级下的几何不可用，所以只认"能取到正的宽高"。
  function settingsModalShown() {
    var titles = document.querySelectorAll('[class*="ds-modal-content__title"]');
    var i = 0;
    for (i = 0; i < titles.length; i = i + 1) {
      if (textOf(titles[i]) !== ACCOUNT_OPTION_SETTINGS) { continue; }
      var wrap = titles[i].closest('[class*="ds-modal-wrapper"]');
      if (!wrap) { return true; }
      try {
        var r = wrap.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) { return true; }
      } catch (e) { return true; }
    }
    return false;
  }

  // 在**隐藏容器**里点一个元素。
  //
  // 为什么必须有它（第十六轮第三批真机 + CDP 实证）：官方账号入口位于**隐藏抽屉**里，
  // 整条祖先链都是 visibility: hidden —— 而**隐藏元素不接收点击**，直接 tap() 派发的事件
  // 不会被 React 的点击处理器响应，表现就是用户说的"点了系统设置没反应"。
  // 更麻烦的是它**能被几何判据找到**（visibility: hidden 保留布局，rect 非零），
  // 所以"只查坐标"查不出问题 —— 必须真的去点，才会发现没反应。
  //
  // 做法：临时把整条祖先链改成 visibility: visible + opacity: 0 ——
  // 元素因此**可命中、可交互，但用户完全看不见**（只改 visibility 会让抽屉在屏幕上闪一下，
  // 这两个属性必须成对改）。点击是同步派发的，随后延迟 400ms 恢复：
  // React 打开弹层要重新渲染，立刻恢复有可能打断它。
  function restoreHiddenChain() {
    hiddenRestoreTimer = 0;
    var k = 0;
    for (k = 0; k < hiddenTouched.length; k = k + 1) {
      var node = hiddenTouched[k];
      var orig = node.__dshVisOrig;
      if (orig) {
        try {
          node.style.visibility = orig.v;
          node.style.opacity = orig.o;
          delete node.__dshVisOrig;
        } catch (e0) {}
      }
    }
    hiddenTouched = [];
  }

  // 恢复口径本轮修正（"点了没反应"的一种可复现形态，且与 reveal 兜底联动）。
  // 旧实现每次调用都把 style.visibility/opacity 的**当前值**当成"原值"就地记下、400ms 后回填。
  // 而 pickAccountOption 的既定链路就是"第一步没到位就回 not-found、原生侧 140ms 后重试"
  //（Index 侧最多 8 次），也就是 400ms 内本函数会被**再进一次**：第二次读到的"原值"其实是
  // 上一次自己写下的 opacity: 0，于是抽屉根被永久留在 inline opacity:0 上。
  // 而 reveal()（把官方外壳交还用户的那条兜底路径）只摘 data-dsh-hide-drawer，管不到
  // inline opacity —— 交还之后官方抽屉看不见，用户视角同样是"按钮点了没反应"。
  // 修法两条：① 原值**只在首次**记录（挂元素自身 expando：不产生 mutation、不喂给观察器）；
  // ② 恢复定时器**去抖**：同一次流程里的多次触碰只回填一次，并以最后一次为起点计时。
  function tapInHidden(el) {
    var cur = el;
    var i = 0;
    var touched = 0;
    for (i = 0; i < 8 && cur && cur !== document.body; i = i + 1) {
      var cs = null;
      try { cs = window.getComputedStyle(cur); } catch (e) { cs = null; }
      if (cs && cs.visibility === 'hidden') {
        if (!cur.__dshVisOrig) {
          cur.__dshVisOrig = { v: cur.style.visibility, o: cur.style.opacity };
          hiddenTouched.push(cur);
        }
        cur.style.visibility = 'visible';
        cur.style.opacity = '0';
        touched = touched + 1;
      }
      cur = cur.parentElement;
    }
    tap(el);
    if (touched > 0) {
      if (hiddenRestoreTimer) { window.clearTimeout(hiddenRestoreTimer); }
      hiddenRestoreTimer = window.setTimeout(restoreHiddenChain, 400);
    }
    return touched;
  }

  // —— 设置链路期间的"浮层视觉闩" ——
  //
  // 为什么需要（第十七轮真机 + CDP 探针，证据 tmp/dsh-r17/samples.json t=6020~6308）：
  // 官方账号下拉菜单是 React portal，挂在 body 级 .ds-floating-position-wrapper.ds-theme 下，
  // **不在** tapInHidden 那条"祖先链临时 visibility:visible + opacity:0"里 —— 于是第一步
  // 点开账号菜单时它整块露在屏幕上（rect≈[8,726,136,168]，viewport 443x952 ⇒ 左下角），
  // opacity 0 -> 1 -> 0、可见约 290ms。用户报的"点系统设置时左下角闪过官方菜单"就是它。
  //
  // 做法：给**含 .ds-dropdown-menu 的浮层**打 MENU_VEIL_ATTR，由常驻样式表（见 injectStyle）
  // 压成 opacity:0 !important + transition:none !important。三个取舍：
  //   · 用 opacity 而不是 visibility / pointer-events：opacity 不参与命中测试，
  //     第二步 tap 菜单项照旧生效（本节所有驱动都靠合成事件，见 tap 的注释）；
  //   · 用**属性 + 样式表**而不是逐个写 inline style：inline 得自己序列化并在落闩时回填原值，
  //     写坏就是永久 opacity:0；属性方案的"恢复"就是 removeAttribute，天然精确、必然完整；
  //   · 只压**含菜单**的浮层：本轮实测设置弹层的父节点是应用根节点（不在浮层里），
  //     但无差别压所有浮层等于把"哪天挪进浮层的设置弹层"一起藏掉 —— 收窄到含菜单的那一个。
  //
  // 生命周期（每条路径都必须能落闩，否则页面会永久停在一个看不见的账号菜单上）：
  //   arm → 立刻打标一次；同时装 MutationObserver。菜单是 React 在 tap 之后才挂上去的
  //         （实测 100ms 量级），观察器回调跑在**节点插入的那个微任务**里、早于本帧绘制，
  //         所以不会"先露一帧再被压掉"（setInterval 最小间隔就是一帧，会漏）。
  //   off → ① 菜单节点从 DOM 消失（官方自己收掉，实测 t=6308）—— **主路径**。
  //         只认"设置弹层已呈现"就落闩是不够的：实测弹层 t=6208 出现时菜单还是 opacity 1，
  //         要到 t=6300 左右才淡完，提前恢复等于白改；
  //         ② 硬超时 3s（弹层没开出来 / 链路被别的路径打断）—— 兜底；
  //         ③ 走「退出登录」分支时显式落闩（那条链路绝不能被罩住）。
  var MENU_VEIL_MS = 3000;

  // 给当前文档里所有"官方账号下拉菜单 + 它所在的浮层"打标；返回本次打到的节点数。
  function menuVeilApply() {
    var menus = [];
    try { menus = document.querySelectorAll('.ds-dropdown-menu'); } catch (e) { menus = []; }
    var n = 0;
    var i = 0;
    for (i = 0; i < menus.length; i = i + 1) {
      menus[i].setAttribute(MENU_VEIL_ATTR, '1');
      n = n + 1;
    }
    // 浮层容器一起打标：官方把淡入动画挂在容器这一层，且将来加进这个容器的兄弟节点
    // （遮罩之类）也在它下面 —— 压住容器才压得干净。只认确实含菜单的那一个。
    var j = 0;
    for (j = 0; j < menus.length; j = j + 1) {
      var w = menus[j].parentElement;
      var hop = 0;
      while (w && w !== document.body && hop < 4) {
        if (String(w.className || '').indexOf('ds-floating-position-wrapper') >= 0) {
          w.setAttribute(MENU_VEIL_ATTR, '1');
          n = n + 1;
          break;
        }
        w = w.parentElement;
        hop = hop + 1;
      }
    }
    if (n > 0) { state.menuVeilStamped = 1; }
    return n;
  }

  function menuVeilClear() {
    var marked = [];
    try { marked = document.querySelectorAll('[' + MENU_VEIL_ATTR + ']'); } catch (e) { marked = []; }
    var i = 0;
    for (i = 0; i < marked.length; i = i + 1) {
      try { marked[i].removeAttribute(MENU_VEIL_ATTR); } catch (e0) {}
    }
    return marked.length;
  }

  // 落闩：恢复视觉 + 拆掉观察器/定时器。幂等（未开闸时直接返回）。
  function menuVeilOff(reason) {
    if (!state.menuVeil) { return; }
    state.menuVeil = 0;
    if (state.menuVeilTimer) { window.clearTimeout(state.menuVeilTimer); state.menuVeilTimer = 0; }
    var ob = state.menuVeilObserver;
    state.menuVeilObserver = null;
    if (ob) { try { ob.disconnect(); } catch (e1) {} }
    var n = menuVeilClear();
    state.menuVeilStamped = 0;
    log('menuVeil off (' + reason + ') released=' + n);
  }

  function armMenuVeil() {
    if (state.menuVeil) { return; }
    state.menuVeil = 1;
    state.menuVeilStamped = 0;
    menuVeilApply();
    try {
      var ob = new MutationObserver(function () {
        try {
          var n = menuVeilApply();
          // 打过标（菜单确实挂上来过）之后菜单从 DOM 消失 = 官方自己收掉了 ⇒ 窗口期结束。
          if (n === 0 && state.menuVeilStamped) { menuVeilOff('menu-gone'); }
        } catch (e2) {}
      });
      ob.observe(document.body || document.documentElement, { childList: true, subtree: true });
      state.menuVeilObserver = ob;
    } catch (e3) { state.menuVeilObserver = null; }
    state.menuVeilTimer = window.setTimeout(function () { menuVeilOff('timeout'); }, MENU_VEIL_MS);
    log('menuVeil armed');
  }

  function pickAccountOption(label) {
    // **白名单闸门**：不在集合里的值一律拒绝，且不派发任何事件。
    if (label !== ACCOUNT_OPTION_SETTINGS && label !== ACCOUNT_LOGOUT_LABEL) { return 'unsupported'; }

    if (label === ACCOUNT_OPTION_SETTINGS) {
      // **幂等**：已经开着就直接回 ok —— 让原生侧立刻停止重试，也**不再弹那句误导人的
      // "官方菜单未响应"**（用户看到的是"设置明明打开了，却提示未响应"）。
      var shown = settingsModalShown();
      var entry = accountRow();
      var menuUp = accountMenuShown();
      log('pickAccount label=' + label + ' modal=' + (shown ? '1' : '0') +
        ' menu=' + (menuUp ? '1' : '0') + ' row=' + (entry ? 'yes' : 'no') +
        ' path=' + (window.location.pathname || '?'));
      if (shown) { return 'ok'; }

      // 从这里往下就要真派发点击了（第一步点开官方账号菜单）。**在派发之前**开闸，
      // 让菜单与它所在的浮层一出现就被压住（见 armMenuVeil 的完整说明）。
      armMenuVeil();

      // **两步走**（第十六轮第三批真机实测后定型）：官方账号入口点一下打开的是**下拉菜单**
      // （下载手机应用 / 系统设置 / 帮助与反馈 / 退出登录），设置弹层要**再点菜单里的那一项**。
      // 老实现只有第二步、没有第一步，而第一步的入口又在隐藏抽屉里（hidden 元素不接收点击），
      // 于是菜单从来没被打开过 —— 第二步自然永远 not-found。
      if (!menuUp) {
        if (!entry) { return 'not-found'; }
        // 第一步：打开官方账号菜单。入口在隐藏抽屉里 → 必须走 tapInHidden。
        tapInHidden(entry);
        // 回 not-found 表达"这一拍还没到位"，让原生侧按 140ms 重试；React 渲染菜单只要 100ms 量级。
        return 'not-found';
      }

      // 第二步：菜单已展开 → 点其中的「系统设置」。此时菜单是官方自己渲染的（可见），
      // 普通 tap 即可 —— 用 tapInHidden 反而会把可见菜单临时透明化。
      var el = accountMenuOption(ACCOUNT_OPTION_SETTINGS);
      if (!el) { return 'not-found'; }
      tap(el);
      return 'ok';
    }

    // 「退出登录」仍走老的"下拉菜单项"链路：它对应的**是**菜单项而不是弹层。
    // 显式落一次闩（幂等）：该链路绝不能被设置链路的浮层守卫罩住 —— 哪怕上一轮
    // 因异常没落闩，走到这里也一定恢复原样。
    menuVeilOff('logout-path');
    // 若官方哪天把退出登录也挪进设置弹层（账号管理 tab），这里会返回 'not-found'，
    // 原生侧照旧给可见提示 —— 不会静默失败。
    var el = accountMenuOption(label);
    if (!el) { return 'not-found'; }
    tap(el);
    return 'ok';
  }

  // 收起官方账号菜单（原生侧**取消退出登录确认**时用）。
  // 官方菜单挂在隐藏抽屉里，不收起的话用户下次点"账号"会先把它再展开一次 ——
  // 也就是 toggle 成"收起"，表现为"点了没反应"（§3.0-89 同源）。所以原生对话框被取消时
  // 也要把它收掉。收口后本函数的调用场景只剩"取消退出登录"这一条链路（原生
  // onCloseAccount），不再有为其它菜单项收尾的分支。
  function closeAccountMenu() {
    var opened = document.querySelector(SEL_MENU);
    if (!opened) { return 'none'; }
    var row = accountRow();
    if (!row) { return 'no-row'; }
    tap(row);
    return 'ok';
  }

  // —— 删除会话（驱动官方 DOM）——
  // 实测链路（真机 + CDP，证据 内部验证记录）：
  //   行内「⋯」(_2090548) → 菜单项「删除」→ 确认弹窗 ds-modal，按钮「删除该对话」
  //   （该按钮类名带 ds-button--error，用它兜底比文案更稳）。
  // 全程在隐藏抽屉/隐藏弹窗里派发事件，用户不可见。分步异步，每步给足官方渲染时间；
  // 完成后回报 {t:'deleted'}，原生侧据此串行推进下一条。
  // 定位某条会话行内的「⋯」按钮。
  //
  // ⚠️ 这里踩过一个很隐蔽的坑：早先版本是"从会话锚点向上找行容器，再取容器里第一个
  // _2090548 按钮"。当 closest('div') 命中的不是"单行"而是整个列表容器时，
  // querySelectorAll(...)[0] 返回的是**列表第一行**的按钮 —— 于是"删 A"实际打开的是
  // 第一行 B 的菜单，两条删除请求全打在 B 上：B 被删、A 从未被碰，而流程还会一路报成功。
  // 正解是**从按钮侧反查它所属的锚点**（按钮在锚点内部，closest('a') 可靠），
  // 彻底摆脱"容器边界在哪"这个假设。
  function findRowMoreButton(id) {
    var all = document.querySelectorAll('[class*="_2090548"]');
    var i = 0;
    for (i = 0; i < all.length; i = i + 1) {
      if (String(all[i].className || '').indexOf('ds-button__') === 0) { continue; }
      var a = null;
      try { a = all[i].closest(SEL_SESSION_LINK); } catch (e) { a = null; }
      if (!a) { continue; }
      if ((a.getAttribute('href') || '').indexOf(id) >= 0) { return all[i]; }
    }
    return null;
  }

  function anchorExists(id) {
    var ls = document.querySelectorAll(SEL_SESSION_LINK);
    var i = 0;
    for (i = 0; i < ls.length; i = i + 1) {
      if ((ls[i].getAttribute('href') || '').indexOf(id) >= 0) { return true; }
    }
    return false;
  }

  // 官方确认弹窗里的「删除该对话」按钮。
  //
  // **必须以弹窗 footer 为作用域**：早先写的是 var scope = foot || document ——
  // footer 找不到时退化成**全文档**匹配，于是"弹窗没出来"这种情况下会扫到页面上其它
  // 红色按钮（官方设置页/其它弹层的 error 按钮同样是 ds-button--error），在用户看不见的
  // 情况下点一下。删除是不可逆操作，宁可不做：找不到 footer 直接返回 null → 链路
  // 回报 'no-confirm' 中止。
  function confirmDeleteButton() {
    var foot = document.querySelector('[class*="ds-modal-content__footer"]');
    if (!foot) { return null; }
    var err = foot.querySelectorAll('[class*="ds-button--error"]');
    var i = 0;
    for (i = 0; i < err.length; i = i + 1) {
      if (String(err[i].className || '').indexOf('ds-button__') === 0) { continue; }
      return err[i];
    }
    var all = foot.querySelectorAll('[class*="ds-button"], [role="button"]');
    for (i = 0; i < all.length; i = i + 1) {
      if (String(all[i].className || '').indexOf('ds-button__') === 0) { continue; }
      var t = textOf(all[i]);
      if (t === '删除该对话' || t === '删除' || t === '确认') { return all[i]; }
    }
    return null;
  }

  function reportDelete(id, status) {
    bridge({ t: 'deleted', id: id, status: status });
  }

  // 批量删除期间把官方那层确认弹窗藏起来（规则见 injectStyle）。
  // 开关打在 <html> 上：弹窗是文档级节点，只要在它出现**之前**就位即可全程不可见。
  function setDeleteDriving(on) {
    try {
      var html = document.documentElement;
      if (on === true) {
        html.setAttribute('data-dsh-delete-driving', '1');
        state.deleteDriving = 1;
      } else {
        html.removeAttribute('data-dsh-delete-driving');
        state.deleteDriving = 0;
        var marked = document.querySelectorAll('[data-dsh-hide-modal="1"]');
        for (var k = 0; k < marked.length; k = k + 1) {
          marked[k].removeAttribute('data-dsh-hide-modal');
        }
      }
    } catch (e) {}
  }

  // 兜底：官方若把 ds-modal-* 类名改掉，上面的类选择器就失效 —— 从「删除该对话」
  // 这个确认按钮往上走几跳，把它所在的那层弹窗打上 data-dsh-hide-modal 一起隐藏。
  // 只在删除链路里调用（此时开关已置位），不会影响官方其它弹窗（分享/设置）。
  function markDrivenModal() {
    if (state.deleteDriving !== 1) { return 0; }
    var el = confirmDeleteButton();
    var hops = 0;
    var n = 0;
    while (el && hops < 3) {
      var r = null;
      var cs = null;
      try { r = el.getBoundingClientRect(); cs = window.getComputedStyle(el); } catch (e) { r = null; }
      if (r && cs && (cs.position === 'fixed' || cs.position === 'absolute') &&
        r.width >= window.innerWidth * 0.6 && r.height >= 60) {
        if (el.getAttribute('data-dsh-hide-modal') !== '1') {
          el.setAttribute('data-dsh-hide-modal', '1');
          n = n + 1;
        }
      }
      el = el.parentElement;
      hops = hops + 1;
    }
    return n;
  }

  // 链路收尾：无论成功、失败还是"没找到官方控件"，都必须把开关与 busy 复位，
  // 否则弹窗会一直被 CSS 藏着（官方其它弹窗也跟着遭殃）。
  function finishDelete(id, status) {
    state.deleteBusy = false;
    state.deleteRoute = null;
    setDeleteDriving(false);
    reportDelete(id, status);
  }

  // 官方下拉菜单是 **portal**（不在行容器里），它的 DOM 不带"我属于哪一行"的信息。
  // 于是存在一个危险路径：若上一步留下一个还开着的菜单，本步 tap(⋯) 又没成功弹出新菜单，
  // 紧接着的 menuOptionOf('删除') 会命中**残留菜单那一份** → 确认弹窗属于另一条会话 →
  // 用户选中的 A 没删、B 被删了（本工程 2026-09-11 的真机事故，见 PROJECT.md §15）。
  // 对策：动每一步之前先要求"场上没有菜单"，有就先收掉，收不掉就中止这一步，绝不将错就错。
  function dropdownCount() {
    return document.querySelectorAll(SEL_MENU_OPTION).length;
  }

  function closeDropdowns() {
    if (dropdownCount() === 0) { return 0; }
    try {
      window.dispatchEvent(new KeyboardEvent('keydown',
        { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
    } catch (e) {}
    // 补齐 **pointer 序列**：本文件 tap() 的实测结论是"官方控件是 React pointer 事件，
    // 只派发 mouse/click 收不到"（".click() 不生效"那条注释）。同一套 React 栈的
    // "点外部收起菜单"同理 —— 只发 mousedown/click 时官方下拉菜单可能收不掉，而
    // deleteSession 的前置判据是"场上有菜单就中止"（stale-menu），于是在用户视角就是
    // "点了删除没反应"。指向元素用 body：坐标不重要，React 只认"点在菜单之外"。
    // 中止语义未变：收不掉时调用方照样中止，宁可不删也不删错。
    // 只用 bubbles：这类"点外部收起"的判据是 event.target/路径，不读坐标，
    // 故不必像 tap() 那样补齐 clientX/clientY/pointerType（那些是给命中判定用的）。
    try { document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })); } catch (e4) {}
    try { document.body.dispatchEvent(new PointerEvent('pointerup', { bubbles: true })); } catch (e5) {}
    try { document.body.dispatchEvent(new MouseEvent('mousedown', { bubbles: true })); } catch (e2) {}
    try { document.body.dispatchEvent(new MouseEvent('mouseup', { bubbles: true })); } catch (e6) {}
    try { document.body.dispatchEvent(new MouseEvent('click', { bubbles: true })); } catch (e3) {}
    return 1;
  }

  function deleteSession(id, token) {
    if (!id) { return 'skip'; }
    // 破坏性操作的安全闩（本轮重做两次才做对）：
    //   ① 判据必须包含"原生侧真的下发过密钥"这一条（deleteTokenAssigned）——
    //      否则页面脚本只要把 state.deleteToken 改成空串（它做得到，因为能拿到 api 对象），
    //      就能用 deleteSession(id, '') 走默认匹配通过；
    //   ② 密钥本身由原生侧生成、存在闭包里（state.deleteToken），页面上没有读取出口；
    //   ③ 页面上**没有**能自行开闸的入口（旧实现是 armDelete(on)，一句就绕过去了）。
    if (!state.deleteTokenAssigned || state.deleteToken === '' ||
      typeof token !== 'string' || token !== state.deleteToken) {
      reportDelete(id, 'locked');
      return 'locked';
    }
    if (state.deleteBusy) {
      reportDelete(id, 'busy');
      return 'busy';
    }
    var btn = findRowMoreButton(id);
    if (!btn) { reportDelete(id, 'no-row'); return 'no-row'; }
    state.deleteBusy = true;
    // 链路开工前记录路由：三步之间隔着 550/800/1100ms，若期间官方发生路由跳转
    // （用户按了返回、页面自己 redirect），场上元素已经整体换了一批，
    // 后续"按文案点红色确认键"就可能点在**另一个页面**的控件上。
    // 每一步开工前比一次路由，变了就中止（宁可不删）。
    state.deleteRoute = routeSignature();
    // 从这一刻起官方确认弹窗全程不可见（用户已在原生弹窗上确认过，这层只是必经步骤）
    setDeleteDriving(true);
    closeDropdowns();
    if (dropdownCount() > 0) {
      // 收不掉的残留菜单：宁可不删，也不能删错（宁缺毋滥）
      log('abort: stale dropdown menu present');
      finishDelete(id, 'stale-menu');
      return 'stale-menu';
    }
    tap(btn);
    window.setTimeout(function () {
      if (deleteChainAborted(id)) {
        finishDelete(id, 'aborted');
        return;
      }
      var opt = menuOptionOf('删除');
      if (!opt) {
        // 隐藏抽屉里的「⋯」平时 0x0、要先"激活行"才可点：第一次点击常常只是把菜单
        // 渲染出来而没展开，补一次点击再判断。
        tap(btn);
        window.setTimeout(function () {
          if (deleteChainAborted(id)) {
            finishDelete(id, 'aborted');
            return;
          }
          step2(id, btn);
        }, 600);
        return;
      }
      step2(id, btn);
    }, 550);
    return 'started';
  }

  // 第二步：确认菜单真的开着（closeDropdowns 之后仍为空才算本次新开），点「删除」
  function step2(id, btn) {
    if (deleteChainAborted(id)) {
      finishDelete(id, 'aborted');
      return;
    }
    var opt = menuOptionOf('删除');
    if (!opt) { finishDelete(id, 'no-option'); return; }
    // 同理再挡一次"别人的弹窗"：场上已有官方弹窗时点确认键会点到那一份上
    if (document.querySelector('.ds-modal-wrapper')) {
      log('abort: stale modal present');
      finishDelete(id, 'stale-modal');
      return;
    }
    tap(opt);
    window.setTimeout(function () {
      if (deleteChainAborted(id)) {
        finishDelete(id, 'aborted');
        return;
      }
      markDrivenModal();
      var cf = confirmDeleteButton();
      if (!cf) { finishDelete(id, 'no-confirm'); return; }
      tap(cf);
      window.setTimeout(function () {
        // 最后一步只校验"链路还在不在"：此时删除请求已发出，路由若刚跳走也不该改判，
        // 仍以锚点是否存在判定真实结果。
        if (!state.deleteBusy) { return; }
        markDrivenModal();
        state.deleteBusy = false;
        state.deleteRoute = null;
        setDeleteDriving(false);
        // 不无条件报 done：确认点下去之后锚点必须真的消失，否则就是"点了但没删成"
        // （早先版本正是因为不校验，把"删错行"一路报成了成功）。
        reportDelete(id, anchorExists(id) ? 'verify-failed' : 'done');
      }, 1100);
    }, 800);
  }

  // 避让量的唯一落地实现（__dshNativeShell.setInsets / __dshShellApi.setInsets /
  // window.__dshSetInsets 三个入口共用，免得三份实现迟早走偏）。
  function setInsets(top, bottom) {
    try {
      window.__dshTopInsetPx = Number(top) || 0;
      window.__dshBottomInsetPx = Number(bottom) || 0;
      ensureTopSpacer();
      reportRoute(false);
      // Index.pushInsets 的注释承诺这条通道会"重跑 ensureTopSpacer / applySafeArea"，
      // 而 body 的安全区内边距由适配器持有（applySafeArea），只能经它暴露的钩子调 ——
      // 不补这一步，避让量虽然写进了 window，几何却要等下一次 resize 或 5s tick 才跟上。
      if (typeof window.__deepseekHmApplySafeArea === 'function') {
        window.__deepseekHmApplySafeArea();
      }
      return 'ok';
    } catch (e) {
      return 'fail';
    }
  }

  // —— 设置页数据的「本地缓存」（第二十一轮八改）——
  //
  // ## 为什么需要它（用户的真机反馈：「系统设置里有些界面每次打开都会刷新一下，转个圈再显示」）
  // 实测（hook XHR，真机 CDP）：**每次打开设置页**，官方都会重新发这三个 GET：
  //   /api/v0/users/settings   （用户设置：主题 / 语言）
  //   /api/v0/chat/tts/voices  （朗读音色列表）
  //   /api/v0/users/get_birthday（未成年人模式的生日）
  // 响应没落地到任何可复用的地方 ⇒ 弹层每次重挂载都要重新等一遍网络 ⇒ 用户看到的就是那个转圈。
  // 这是**官方组件的行为**，注入层改不动它的生命周期；能改的是「让它这一次请求不必走网络」。
  //
  // ## 做法：白名单 + 短 TTL 的**内存缓存**（命中就直接伪造响应，不发起真实请求）
  // · 只认这三个 URL、且只认 GET：其它接口一律原样放行（不做任何缓存，避免把动态数据钉死）；
  // · TTL 90 秒：足够覆盖「连续开关设置页」这个用户动作，又不会长期留着旧值；
  // · **任何设置面板内的点击都会立刻清空缓存** —— 用户改了主题/语言之后，
  //   下一次打开必须是新鲜数据（这是本条缓存最要紧的安全阀，别删）；
  // · 只改 XHR（实测官方走 XHR，不走 fetch）；不命中时**完全不介入**，行为与改动前逐字一致。
  //
  // ⚠️ 伪造响应时必须按 responseType 给值：官方若用 responseType='json'，
  //    访问 responseText 会直接抛 InvalidStateError ⇒ 两种都要支持。
  var reqCache = {};
  // 命中计数：验证脚本靠它断言「第二次打开设置页确实没走网络」（而不是「看起来快了」）。
  var reqCacheHits = 0;
  var reqCacheMiss = 0;
  var REQ_CACHE_TTL_MS = 90000;
  var REQ_CACHE_URLS = ['/api/v0/users/settings', '/api/v0/chat/tts/voices', '/api/v0/users/get_birthday'];
  function reqCacheKey(u) {
    var s = String(u || '');
    var i = s.indexOf('?');
    return i >= 0 ? s.slice(0, i) : s;
  }
  function reqCacheAllowed(u) {
    var k = reqCacheKey(u);
    for (var i = 0; i < REQ_CACHE_URLS.length; i++) {
      if (k.indexOf(REQ_CACHE_URLS[i]) >= 0) { return true; }
    }
    return false;
  }
  function reqCacheClear() {
    reqCache = {};
  }
  function installRequestCache() {
    if (window.__dshReqCacheInstalled) { return; }
    window.__dshReqCacheInstalled = true;
    var XP = XMLHttpRequest.prototype;
    var origOpen = XP.open;
    var origSend = XP.send;
    XP.open = function (m, u) {
      try {
        this.__dshReq = { m: String(m || 'GET').toUpperCase(), u: reqCacheKey(u), hit: false, origU: String(u || '') };
      } catch (e0) {}
      return origOpen.apply(this, arguments);
    };
    XP.send = function () {
      var meta = this.__dshReq;
      if (!meta || meta.m !== 'GET' || !reqCacheAllowed(meta.origU)) {
        return origSend.apply(this, arguments);
      }
      var now = Date.now();
      var c = reqCache[meta.u];
      if (c && (now - c.t) < REQ_CACHE_TTL_MS) {
        meta.hit = true;
        reqCacheHits = reqCacheHits + 1;
        var xhr = this;
        setTimeout(function () {
          try {
            var rt = '';
            try { rt = String(xhr.responseType || ''); } catch (e1) {}
            var payload = c.text;
            if (rt === 'json') { try { payload = JSON.parse(c.text); } catch (e2) {} }
            Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
            Object.defineProperty(xhr, 'status', { value: c.status, configurable: true });
            Object.defineProperty(xhr, 'statusText', { value: 'OK', configurable: true });
            Object.defineProperty(xhr, 'response', { value: payload, configurable: true });
            if (rt !== 'json') {
              Object.defineProperty(xhr, 'responseText', { value: c.text, configurable: true });
            } else {
              Object.defineProperty(xhr, 'responseText', { value: c.text, configurable: true });
            }
            xhr.getAllResponseHeaders = function () { return c.headers || 'content-type: application/json'; };
            xhr.getResponseHeader = function (n) {
              return String(n || '').toLowerCase() === 'content-type' ? 'application/json' : null;
            };
            if (typeof xhr.onreadystatechange === 'function') { xhr.onreadystatechange(); }
            if (typeof xhr.onload === 'function') { xhr.onload(); }
            try { xhr.dispatchEvent(new Event('load')); } catch (e3) {}
            try { xhr.dispatchEvent(new Event('loadend')); } catch (e4) {}
          } catch (e5) {}
        }, 0);
        return undefined;
      }
      reqCacheMiss = reqCacheMiss + 1;
      var self = this;
      try {
        self.addEventListener('load', function () {
          try {
            if (self.readyState === 4 && self.status >= 200 && self.status < 300) {
              var txt = '';
              try { txt = String(self.responseText); } catch (e6) {
                try { txt = JSON.stringify(self.response); } catch (e7) { txt = ''; }
              }
              if (txt.length > 0) {
                reqCache[meta.u] = { t: Date.now(), text: txt, status: self.status, headers: self.getAllResponseHeaders() };
              }
            }
          } catch (e8) {}
        });
      } catch (e9) {}
      return origSend.apply(this, arguments);
    };
    // 安全阀：**只有「改设置值」的那类控件**被点时才清缓存。
    //
    // ⚠️ 第一版写成「设置面板内任何点击都清」，真机实测**直接把自己的缓存废掉了**：
    //    关闭设置页要点面板头部的 ✕（在面板内）⇒ 每次关闭都清一次 ⇒ 下次打开必然 miss。
    //    实测读数：关闭后 keys=[]、第二次打开 miss 从 3 涨到 6、hits 恒为 0。
    // ⇒ 判据收紧到设置项本体（row / seg / group 三种标记）：
    //    · 页签切换（tabs）不清 —— 它不改任何数据；
    //    · 关闭钮（header 里的 .ds-button）不清 —— 那是本轮踩到的坑。
    try {
      document.addEventListener('click', function (ev) {
        var n = ev && ev.target;
        var hop = 0;
        while (n && hop < 12) {
          if (n.getAttribute) {
            var isValueCtl = n.getAttribute('data-dsh-settings-row') === '1'
              || n.getAttribute('data-dsh-settings-seg') === '1'
              || n.getAttribute('data-dsh-settings-group') === '1';
            if (isValueCtl) { reqCacheClear(); return; }
          }
          n = n.parentNode;
          hop = hop + 1;
        }
      }, true);
    } catch (ea) {}
  }

  // 脚本装载即生效（函数内部有幂等守卫）：缓存要在设置页第一次被打开**之前**就位。
  installRequestCache();

  window.__dshNativeShell = {
    alive: true,
    rescan: function (f) { rescan(f === true); },
    // 诊断出口（只读）：请求缓存的命中情况，供验证脚本断言。
    reqCache: function () {
      return JSON.stringify({ keys: Object.keys(reqCache), hits: reqCacheHits, miss: reqCacheMiss, ttl: REQ_CACHE_TTL_MS });
    },
    installRequestCache: function () { installRequestCache(); return 'ok'; },
    /**
     * 轻量避让通道（本轮新增）：只推两个数值 + 重跑两处几何修正，
     * 不重跑整个脚本。避让区在键盘反复弹出/收起时会连续变化，旧做法每次都把
     * 两个注入脚本（合并前约 2500 行）整份重跑 —— 现在这里是前者的百分之几。
     * 返回字符串而不是 undefined，宿主据此判断"通道到底有没有生效"（无效则回退整注入）。
     */
    setInsets: function (top, bottom) { return setInsets(top, bottom); },
    diag: function () {
      return JSON.stringify({
        drawer: findDrawer() ? 1 : 0,
        topbar: state.topbar ? 1 : 0,
        toggle: state.toggle ? 1 : 0,
        sessions: state.sessions.length,
        taps: state.taps,
        route: state.routePath,
        prewarm: state.prewarmDone ? 1 : 0,
        revealOff: state.revealOff ? 1 : 0,
        scrims: state.scrims,
        bridge: (window[BRIDGE] ? 1 : 0),
        topSpacer: document.querySelector('[data-dsh-topspacer="1"]') ? 1 : 0,
        pinned: state.pinned,
        fullH: state.fullH,
        innerH: window.innerHeight,
        deleteDriving: state.deleteDriving,
        // 只暴露"闩是否开着"这一个布尔（断言脚本需要），**不暴露通行证本身** ——
        // 页面上的 diag() 任何人都能调，把通行证读出来就等于把闩拆了。
        deleteArmed: state.deleteToken === '' ? 0 : 1,
        modalSeen: document.querySelectorAll('[data-dsh-hide-modal="1"]').length,
        sbHidden: document.querySelectorAll('[data-dsh-noscrollbar="1"]').length
      });
    }
  };

  window.__dshShellApi = {
    openSession: function (id) { return openSession(id); },
    newChat: function () { return newChat(); },
    back: function () { try { window.history.back(); return 'ok'; } catch (e) { return 'fail'; } },
    rescan: function () { rescan(true); return 'ok'; },
    // 宿主（native）的轻量避让通道入口；无轻量通道时返回 no-channel，宿主据此回退整注入
    setInsets: function (top, bottom) {
      var api = window.__dshNativeShell;
      if (!api || !api.setInsets) { return 'no-channel'; }
      return api.setInsets(top, bottom);
    },
    diag: function () { return window.__dshNativeShell.diag(); },
    // —— 账号页脚 ——
    account: function () { var i = accountInfo(); return i ? JSON.stringify(i) : 'null'; },
    openAccountMenu: function () { return openAccountMenu(); },
    pickAccountOption: function (label) { return pickAccountOption(label); },
    closeAccountMenu: function () { return closeAccountMenu(); },
    // —— 设置页底部功能栏（原生底栏 → 网页切页签）——
    // setSettingsTab：原生点了第 index 项 → 派发点击给官方页签；
    // settingsTab：读回当前选中下标（原生打开设置页时用来对齐初始高亮）。
    setSettingsTab: function (index) { return setSettingsTab(index); },
    // 原生标题栏的返回钮 → 关闭设置浮层（不能用 back()，理由见该函数顶部）。
    closeSettings: function () { return closeSettings(); },
    settingsTab: function () { return String(currentSettingsTab()); },
    // —— 批量删除（原生侧串行调用，每条等 deleted 回报再发下一条）——
    // 必须带原生侧保管的一次性密钥（token），见 setDeleteToken / deleteSession 顶部说明
    deleteSession: function (id, token) { return deleteSession(id, token); },
    // 删除安全闩：只有**拿到本次原生侧密钥**的调用才能设上。
    // 判据里的密钥由原生侧生成、经一次性的 window.__dshArmSecret 交接进闭包，
    // 页面上读不到 —— 于是"自己生成一个串当密钥"这条路（旧实现的真实漏洞）走不通。
    setDeleteToken: function (token) {
      // **一次性交接**：读走就删掉那个 window 属性。宿主的做法是"先写属性、再同步调本方法"，
      // 两次求值之间页面脚本没有执行机会；本方法执行完属性即消失，
      // 于是"页面脚本先读出密钥、再自己调 setDeleteToken 开闸"这条路被堵死。
      var secret = '';
      try {
        secret = window.__dshArmSecret || '';
        delete window.__dshArmSecret;
      } catch (e0) { secret = ''; }
      if (secret.length >= 16 && typeof token === 'string' && token === secret) {
        state.deleteToken = token;
        state.deleteTokenAssigned = true;
        log('delete latch armed');
        return 'armed';
      }
      log('delete latch arm REJECTED (secret mismatch)');
      return 'rejected';
    },
    // 落闩由原生侧调用；页面脚本调它只会把闩关得更死（不会造成任何破坏性后果）
    clearDeleteToken: function () {
      state.deleteToken = '';
      state.deleteTokenAssigned = false;
      log('delete latch cleared');
      return 'cleared';
    },
    // 兜底通道：会话抽取失败（官方改版等）时把官方外壳交还给用户，
    // 避免原生侧栏空成死路。用户下次打开原生侧栏时 markShell() 会自动重新接管。
    reveal: function () {
      try {
        state.revealOff = true;
        if (state.topbar) { state.topbar.removeAttribute('data-dsh-hide-topbar'); }
        var d = findDrawer();
        if (d) { d.removeAttribute('data-dsh-hide-drawer'); }
        // 连遮罩一起交还（否则官方抽屉被重新打开时点不动、且整页发灰）
        var marked = document.querySelectorAll('[data-dsh-hide-scrim="1"]');
        for (var k = 0; k < marked.length; k = k + 1) {
          marked[k].removeAttribute('data-dsh-hide-scrim');
        }
        state.scrims = 0;
        try { window.__dshShellOwnsChrome = false; } catch (e0) {}
        var btn = (state.toggle && state.toggle.isConnected) ? state.toggle : findSidebarToggle();
        if (btn) { tap(btn); return 'ok'; }
        return 'no-toggle';
      } catch (e) {
        return 'fail';
      }
    }
  };

  // 宿主（Index.pushInsets）找的**网页侧入口**就叫 window.__dshSetInsets，而本脚本
  // 此前只挂了 __dshShellApi.setInsets / __dshNativeShell.setInsets —— 那个 IIFE 因此
  // 每次都返回 'no-channel'（通道根本不存在），避让区变化只能等 resize 或 5s tick 才
  // 重算几何。这里补上同名全局入口，返回值语义与另两个入口完全一致（宿主只判
  // 'no-channel' / 'fail'）。
  window.__dshSetInsets = function (top, bottom) {
    return setInsets(top, bottom);
  };

  try {
    rescan(true);
    startTicker();
    watchSettingsMark();
    observeDrawer();
    window.setTimeout(function () { rescan(true); observeDrawer(); }, 1000);
    window.setTimeout(function () { rescan(true); observeDrawer(); }, 2600);
  } catch (e) {
    log('boot err ' + e);
  }
  // 首帧抢遮罩：官方抽屉在页面加载后约 400ms 才挂载（且默认打开），而固定那几次 rescan
  // 落在 1000ms —— 冷启动会闪一层灰。这里只重跑廉价的 markShell（findDrawer 有 5s 节流，
  // 抽屉不存在时不会反复全文档扫描），遮罩一到手就停。
  try {
    var tries = 0;
    var grabScrim = function () {
      tries = tries + 1;
      // 这里**不再**重复调 injectStyle()：boot 的 rescan(true) 到 markShell() 已经装过
      // 样式表，而这个循环每 120ms 跑一次（最多 16 次）。重复调用只是白跑一次
      // getElementById + 一份 CSS 文本比较；本循环只该干"抢遮罩"这一件真事。
      markDrawerScrim(findDrawer());
      if (state.scrims > 0 || tries >= 16) { return; }
      window.setTimeout(grabScrim, 120);
    };
    window.setTimeout(grabScrim, 120);
  } catch (e2) {}
  bridge({ t: 'ready', path: state.routePath });
})();
`;
