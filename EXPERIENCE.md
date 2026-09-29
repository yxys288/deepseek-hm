# DeepSeek 鸿蒙端（deepseek-hm）· 工程经验与验证细则

> ⚠️ **开源发布说明**：本文件由工程内部文档整理而来。「内部验证记录」= 开发期的验证证据目录
> （整机截屏 / CDP 探针 / `dumpLayout` 读数，**未随本仓库发布**）；「内部踩坑表 `§3.0-N`」=
> 开发工作区的跨工程通用踩坑表编号（同样未随本仓库发布），编号保留以便与本项目内部记录对照。

> 本文件是**本工程视角**的经验库：现象 → 根因 → 最终修法 → 涉及文件与函数 → 验证读数 → 可复用脚本。
> 通用坑的全表在 `内部踩坑表`（**253 条**，锚点 `#3.0-N` 永久稳定），
> 高频致命坑摘要见 `AGENTS.md` §4；本文件每条都带工程内定位
> （哪个文件、哪个函数、哪一轮），文末 §7 给出"本工程条目 ↔ `§3.0-N`"对照。
> 现状见 `PROJECT.md`，变更史见 `CHANGELOG.md`。
>
> **历史路径说明**：标注「第 N 轮」的记录写于 2026-09-11 迁移之前，当时的工程根目录
> 就是现在的仓库根目录。**该旧路径已在迁移时整体移除**
> （2026-09-15 实测 `ls /e/DeepSeekHm` → `No such file or directory`），
> 早期的"现为空壳目录、待删除"说法已过期。
> 早期排障脚本原在工程内 `verify\` 目录，该目录（headless 浏览器 profile `verify\.cdp-*`，
> 约 15302 文件 / 2.6GB）**已于 2026-09-11 整理时删除**；同批删除的还有 `preview\`、
> `entry\.preview`、`iconwork\.tmp1-4`、`Index.ets.disabled`、`.hvigor` / `.idea` / `entry\build`，
> 以及 `内部验证记录` 下 99 个 `blurtest*` 实验截图（该目录保留 `build-*.log` 与探针）。
> 现存的验证脚本都在 `内部验证记录\` 下（清单见 §2.1）。
>
> **材质状态说明**：本工程 `entry\src\main\module.json5` 的 `ohos.arkui.UIMaterial.state` 是
> `disable`，属**刻意**状态 —— 磨砂/光感走 `backgroundEffect` + 双值资源（第十轮定标），
> 从不使用 `systemMaterial`（原因见 §1.2-19），故**不要**把它改成 `enable`。
> 需与 2026-09-11 的另一次修复区分：`dsh-mobile` / `zcode-mobile` / `chatgpt-hm` / `UniChat`
> 四个容器工程曾把该值误写成大写 `"ENABLE"`（被系统静默忽略，等价于没开），当天已统一改为
> 小写 `"enable"` 并逐个重建通过。两件事不同源，别混为一谈。

---

## 1. 本工程踩坑与细则

按主题分组；每条尽量给到函数/常量名，便于在源码里直接检索。

### 1.1 官方框架对抗与 DOM 匹配

1. **官方框架对抗式恢复 inline style**（第二轮）：脚本写 `display:none` 后 **~4ms 内**被恢复为
   `inline-flex`（2s 拉锯循环，CDP style 写入日志实锤）。纯 style 写入无效 →
   改 **data 属性标记 + `!important` 样式表压制**（`[data-dsh-promo="1"]` /
   `[data-dsh-home-hidden="1"]`）：React 重渲染不管理未知 data 属性，无法被恢复。位置：
   `utils\DeepSeekConfig.ets` 的 `MOBILE_ADAPTER_JS`（注样式）+ `findHideTarget()`。
2. **官方 2026-09 改版后全页按钮已无 `aria-label`**（实测 `[aria-label]` 数量 0）：
   旧 aria 匹配全部失效。对策 = **几何兜底通道**（顶部 ≤90px、右侧 110px 内、16..72px 方形、
   几乎无文本、非推广、不在侧栏/sheet 内，取最右）。同类 CSS 类名硬编码也一律备几何兜底，
   因为官方改版就会换类名（已知历史类名：`._519be07` sheet、`.dc04ec1d` 抽屉、`._4cbcd96` 遮罩、
   `.cb86951c` 应用根、`._660ca72` 首页内容、`._2be88ba` 顶栏外层、`._7780f2e` 主内容、
   `._2090548` 行内「⋯」、`b8812f16 a2f3d50e` 面板子元素、`f3d18f6a` 分组叶子）。
3. **"短文本行=按钮"的兜底会误伤顶栏**（第二轮）：官方顶栏容器 `textContent` 恰为"下载应用"
   4 字（顶栏自带下载胶囊），"短文本行"兜底把 60px 高顶栏整体隐藏 → 侧栏开关一起消失。
   `findHideTarget()` 必须排除"含非推广可交互后代（`button` / `[role=button]` / `a` / `input` /
   `.ds-button`）"的容器。归因手法：恢复 → 重跑 → 再消失 的闭环实验。
4. **MutationObserver 只在突变时触发 → 静默页面无人补扫**（第二轮）：推广按钮在适配器首跑后
   渲染完成则冷启动 8s 后仍可见（手动调用立即生效）。加 **2s 低频巡检**（promo + 几何兜底）；
   注意 hook `window.__deepseekHm*` **测不到闭包内部调用**，此前"0 次调用"的读数是无效的。
5. **`sys.symbol.*` 符号名有 SDK 权威清单**（第六轮起）：`D:\DevEco Studio\sdk\default\openharmony\
   toolchains\id_defined.json`，条目形如 `{"type":"symbol","name":"xmark","order":2367}`，
   `Select-String '"<name>"'` 即可判定；另一视图是
   `openharmony\previewer\common\resources\entry\resources.txt`。交叉验证：已知非法的
   `square_and_arrow_up` / `ellipsis` 在该文件里正好 MISSING。
   **取代**第五轮"建临时探针页 + 一次构建拿非法名单"的做法（那是没找到清单时的办法）。
   本工程已确认合法：`line_3_horizontal` / `plus` / `share` / `chevron_left` / `arrow_clockwise` /
   `magnifyingglass` / `list_bullet` / `text_alignleft` / `plus_circle` / `xmark` /
   `xmark_circle` / `list_checkmark` / `arrowshape_turn_up_right`。

### 1.2 侧栏：闪烁、透底、卡顿三种症状

6. **侧栏"打开闪一下"其实是三种不同症状**（本工程连续三轮各修一种，别再混为一谈）：
   ①**几何跳变**（第二轮）——避让 padding 只在 200ms~1s 防抖链路里，而官方进场动画约 0.2~0.3s，
   动画在"无避让几何"里播完、结束后内容瞬间下移（真机 CDP t=64~365ms `padT=0` → t=765ms 跳变）；
   ②**透底叠影**（第四轮）——面板子元素 `opacity 0→1` 交叉淡入、抽屉根透明；
   ③**卡顿**（第五轮）——主线程被同步排版测量占满。三者的取证手段与修法完全不同。
7. **几何跳变的终解 = CSS 首帧规则，不是 JS 快速路径**（第二轮）：JS 首帧写入存在不可控竞态
   （同构建时灵时不灵；官方打开抽屉只产生一次 class 突变、动画为合成器驱动 CSS transition；
   关闭态 `width=0` 还曾触发 `width<120` 下限误拒）。终解写在
   `DeepSeekConfig.ets` 的 `injectStyle()`：
   `@media not all and (min-width:768px) { .dc04ec1d { padding-top: 状态栏+6px !important;
   border-radius: 0 24px 24px 0 !important } }` —— 零时序依赖，JS 路径降为类名改版兜底。
   **终版读数**：冷态开侧栏 rAF 逐帧 `t=83→363ms`（left −261→0）全程 `padT=51.71px`、圆角 `0/24px` 恒定。
8. **纯 opacity 动画造成的透底，几何采样永远看不见**（第四轮）：旧探针只读 rect / padT / 圆角，
   全程"正常"，但设备级截屏里侧栏区混入了主内容色（`rgb(33,33,33)`/`rgb(28,19,12)`）。
   真身 = 面板子元素（`b8812f16 a2f3d50e`，不透明底色、h=765）`opacity 0→1` 300ms 淡入，
   而抽屉根元素背景透明。
   **修法**：`ShellScript.ets` 的 `syncDrawerBackdrop()` 把面板不透明底色与根 `padding-top`
   抄成根元素 CSS 自定义属性 `--dsh-drawer-bg` / `--dsh-drawer-padtop`，注入
   `[data-dsh-drawer][style*="--dsh-drawer-bg"]::before { top: var(--dsh-drawer-padtop);
   background: var(--dsh-drawer-bg); border-radius: inherit }`——根元素**首帧起**不透明。
   `[style*=--var]` 属性选择器保证只对抄过色的元素生效，不误伤同样带 `data-dsh-drawer` 的内层列。
   读数：浅 `rgb(249,250,251)` / 深 `rgb(27,27,28)` 全程恒定。
9. **给"带安全区 padding 的面板根"补背景的两次返工**（第四轮，务必别再试）：
   根元素直接铺色（border-box）→ 把圆角顶到屏幕顶、破坏"避让线下方浮出 + 顶缘圆角"形态；
   改 `background-clip: content-box` → **圆角整个消失**（content-box 的圆角半径要减对应 padding：
   24 − 44.86 → 0）。**终版 = 独立 `::before` 伪元素铺底**：铺色范围与面板矩形重合、
   圆角独立可控、状态栏条带恢复透出页面底。
10. **侧栏卡顿的根因是适配器自己的同步测量，不是网页动画慢**（第五轮，代码级定位）：
    官方侧栏开合（class 突变，动画约 0.3s）会触发
    `panelObserver → handlePanelMutation()` 取子树最多 200 节点**逐个** `fastCheckNode()`，
    每节点交替 `getComputedStyle()` + `getBoundingClientRect()`（**强制同步排版 / layout thrashing**），
    再叠加 `scheduleFixedCleanup() → adjustFixedPanels()` 的 `querySelectorAll('body *')` 全文档扫描。
    **修法 = 抽屉子树整体短路**：`inNativeDrawer(el)` 一次 `window.__dshNativeDrawer.contains(el)`，
    在所有热路径（`fastCheckNode` / `fastPath` / `fastPathLite` / `handlePanelMutation` /
    `discoverPanels` / `adjustFixedPanels`）前置返回；配 `__dshShellOwnsChrome` 门控
    （官方顶栏让位后，推广隐藏 / 几何兜底 / 圆框打标整块跳过）+ 全文档选择器收窄为
    `div, aside, nav, section, header, footer, main`。
    **读数**：模拟器合成 A/B `fastNode 124 → 0`、`drawerSkip 0 → 129`；真机 `fastNode 636 → 0`、
    `fixedScan 1082 → 204`（第六轮）/ `fastNode 603 → 0`、`fixedScan 508 → 140`（第九轮）。
11. **真机与模拟器的抽屉 DOM 结构不同，修复不能绑死 class**（第二轮）：真机是"左侧抽屉 +
    内层 static 列"（白块画在内层列上，根元素圆角裁不到顶角），模拟器是"100vw sheet"。
    修法 = 按几何特征兜底（贴边 / 宽 120..90vw / 高 ≥60vh / 跨顶底 1/4 区 / 带底色）给白块补标记 +
    内上/下角圆角；**必须真机复核**。
12. **`getBoundingClientRect()` 的坐标判据必须"两侧都挡"，负坐标是最容易漏的一侧**（第六轮）：
    关闭态抽屉里的同款按钮 `left=-198`，且**文档顺序排在官方顶栏之前** →
    `if (r.left > LIMIT) continue` 这种只挡右侧的写法会**主动选中屏外元素**。
    一律写 `if (r.left < 0 || r.right > innerWidth + 4 || r.bottom <= 0) continue;`。
    涉及：`ShellScript.ets` 的 `findSidebarToggle()`；**同一个 bug 也出现在验证脚本里**
    （见 §2.3 第 3 条）。
13. **"隐藏一个容器"要取最外层匹配祖先，不能在第一个匹配处早退**（第六轮）：
    一条视觉横条常是"外层占位容器（在流内、决定兄弟排版）+ 内层内容容器（宽度可能不等）"两层，
    两层几何相近。只隐藏内层 → **藏了但没让位**（实测隐藏内层后兄弟滚动容器 top 恒为 `60px`）。
    判别手法：隐藏后量**兄弟滚动容器**的 top/left 有没有变，而不是量被隐藏元素自己。
    涉及 `findTopBar(btn)`：走满 8 跳、保留最后一个匹配；宽度阈值放宽到 `0.8*innerWidth`
    （外层的 384 vs 443 差异会让 0.85 判据临界）。
14. **顶上"官方顶栏从未被隐藏"的真机缺陷**（第六轮，两处判据早退叠加）：表现 = 原生顶栏下方
    多出一整排官方图标并压住消息列表。第 12、13 条各自早退一次，叠在一起才确诊；
    修后 `hiddenTopbarNodes=1`、`shellOwnsChrome=true`。**这条只跑模拟器永远看不见。**
15. **`prewarm()` 会被"隐藏顶栏"这个修复打瞎**（第六轮）：顶栏 `display:none` 后几何判据必然失效，
    重新 `findSidebarToggle()` 返回 null（尺寸 0x0）→ 冷启动预热静默跳过。
    修法：`markShell()` 把开关引用留在 `state.toggle`，`prewarm()` 优先复用
    （`display:none` 的元素照样能接派发事件，与抽屉内链接同理）；`diag()` 增 `toggle` 字段。
16. **关面板顺手收键盘要用 `getFocusController().clearFocus()`**（第六轮）：
    `TextInput` 持焦点时只把 `sidebarOpen=false` 不会收键盘（键盘一直悬在聊天区上，
    还会盖住"打开侧栏定位当前会话"的结果）。修法 = `Index.ets` 的 `closeSidebar()` 统一收口
    （`sidebarOpen=false` + `getUIContext().getFocusController().clearFocus()`），
    `openSession` / `doNewChat` / `revealOfficialSidebar` / 遮罩点击 / `onBackPress` 全走它。
17. **磨砂面板与页面之间的色差只有"tint 亮度贴近底色 + 低 alpha"一条路**（第十轮，
    **零 alpha 标定实验**）：把 `shell_panel_glass` 的 alpha 设成 **0** 后逐像素比对 ——
    **面板区与页面底色完全相等**（深色 `rgb(21,21,23)`、浅色 255）→ **模糊本身是中性**，
    面板与页面之间的一切色差 100% 来自玻璃色叠加。
    推论：用"比底色更暗/更亮的 tint + 高 alpha"在深色下**数学上不可能配平**
    （深色页面底色 21，任何 tint 亮度 ≠21 就会偏；实测旧值 `#C41B1B1C` 让面板停在 7 → **14 级色差
    就是那条竖向分界线**）。最终定标：浅色 `#40F2F2F3`（面板 251–252，差 3–4 级）、
    深色 `#1728282A`（面板 23，差 2 级）；配套 **`DARK_BRIGHTNESS` /
    `TOP_BAR_DARK_BRIGHTNESS` 回归 1.0**（深色再叠 `brightness < 1` 是"发灰"的元凶）。
18. **模糊半径会溢出组件边界**（第十轮）：`backgroundEffect(radius: 40)` 放在 82% 宽的面板上，
    模糊会去采样**面板外的清晰内容**，在右缘形成一条"糊 → 清"的**不连续带**（逐像素剖面可见）。
    收到与圆角同尺度（`PANEL_BLUR = 24`）即收敛；再给 0.5vp 淡描边
    （`shell_panel_edge` 浅 `#14000000` / 深 `#1FFFFFFF`）+ 20vp 柔投影，
    边界就从"渲染瑕疵"读成"有意的收边"。
    ⚠️ **投影必须是"对称淡晕"**（`offsetX: 0, offsetY: 0`）：第十六轮真机复核发现，
    原先的横向偏移投影（`offsetX: PANEL_SHADOW_DX(6)`）会在**圆角外侧**露出一块"本该被裁掉"的
    **直角阴影**（阴影按组件**边界矩形**投影，不跟着圆角走），与圆角弧线不重合 ⇒ 右上/右下角
    出现**一条竖直硬边**。该零消费者常量已删除（同 `DRAWER_RIGHT_GAP` 的处置纪律）。
19. **`backgroundBlurStyle` 是"材质"而不是"模糊"**（第八轮，四种写法逐张截图对照）：
    `backgroundBlurStyle(Regular/Thin)` = 模糊 **+ 一层近乎不透明的浅色遮罩**，
    而且**会接管 `backgroundColor`**（alpha 调到 4% 甚至 `Color.Transparent` 都毫无变化）。
    纯模糊要用 `backdropBlur(radius)`；要**按深浅色分别调**得用
    `backgroundEffect({radius, saturation, brightness, color})`（`color` 吃 `ResourceColor`，
    可直接喂双值资源）。另注意 `BlurOptions.grayscale` 是**色阶调整**
    （提亮黑 / 压暗白、黑白趋于灰，默认 `[0,0]`），**不是**锐度或深浅色适配开关。
    位置：`view\SidePane.ets` 的面板与 `pages\Index.ets` 的 `TopBar()`。
20. **`Stack` 默认 `alignContent: Center`**（第八轮）：往 Stack 里补悬浮层（顶栏、遮罩）会被摆到
    屏幕**正中间**。悬浮覆盖必须显式 `.alignContent(Alignment.Top)`。
21. **Web 组件铺到屏幕最顶会让 `env(safe-area-inset-top)` 从 0 变成状态栏高**（第八轮，
    实测 45.71px）：官方 CSS 据此给应用根补了同高 `padding-top`，此时自己再补一份就是
    **重复补偿**（实测内容顶端多落后 46px）。占位高度要写成
    **`topInset − 应用根实际 computed padding-top`**，别写死 topInset。
22. **虚拟列表"内容顶部留白"不能用 `padding-top`**（第八轮）：容器的 inline `padding-top`
    往往是虚拟化器"可视窗口上方高度"的自有变量（配合 `visible-items` 的 `translateY`），
    覆写必与虚拟化打架。正解 = 在滚动容器内、内容容器**之前插一个兄弟占位**
    （实测下推量 === 占位高、虚拟化仍工作、内容无跳位）；
    **没有滚动容器的页面要另走一路**（给容器补 padding 还原旧几何），否则整页下移。
    位置：`ShellScript.ets` 的 `ensureTopSpacer()`。
23. **`Stack` 里覆盖层的书写先后就是命中顺序**（第十轮）：一个整屏透明容器
    （用于"点空白处关闭"）一旦画在顶栏**之后**，就等于把顶栏整条点死 ——
    面板只占 82% 宽时，右上角明明露在外面的 ☰ / ⊕ 全部无响应（"看得见却点不动"的典型）。
    层序必须写成 **内容 → 接管层 → 顶栏 → 启动/错误覆盖层**（`Index.ets` 的 `MainPane()`）。
    另：`SideBarContainer` 的面板**天然全高**，展开时顶栏左半部分必然落在面板之下 →
    抽屉的关闭入口必须给在**面板内部**（本工程加了头部 ×），不能依赖被覆盖的顶栏按钮。
24. **顶栏 ☰ 只开不关**（第十轮）：无 toggle 语义 → `Index.ets` 的 `toggleSidebar()`。
25. **`@Prop` 的 `@Watch` 初始化时不回调 —— 本工程第三次复发**（第七/十轮）：
    第七轮临时预览页把 `panelOpen` 初值写 `true` → "清搜索词 + 定位当前会话"链路永不触发、
    **看起来像功能坏了**；第十轮是产品代码里"启动即展开"的同类情形。
    规则：**凡"初值即目标态"的链路，一律在 `aboutToAppear()` 里主动补一次初始消费**。
    位置：`view\SidePane.ets` 的 `aboutToAppear()` / `onPanelOpenChange()` / `onRowsChange()`。
26. **空态抢定位会让 `scrollToIndex` 打在不存在的索引上并白清 `pendingLocate`**（第十轮）：
    修法 = `onRowsChange` 加"空态不定位"守卫；定位后 60ms 补滚一次（虚拟列表首帧会丢弃）；
    关面板时一并清 `pendingLocate` + 取消定时器。
27. **侧栏右下角「刷新」按钮是冗余的**（第八轮修正）：列表本来就由网页侧 3s 一次的 `rescan`
    推上来，按钮既冗余又占着最显眼的位置 → 去掉，底栏只留 `共 N 个会话`。
28. **遮罩压暗会把"本来同色的两个面"变成"有细线的两个面"**（第八轮定位 / 第九轮补网页侧）：
    侧栏面板与原生顶栏本色同色（都是 24）时，遮罩只压到内容侧（`13 = 24 × (1−0.45)`）→
    面板右边缘出现竖向色差线；深色下相邻内容近黑、面板偏亮，观感就是"深色下面板发灰"。
    **定位手段是逐像素剖面比三个值**（面板本色 / 内容侧 / 那个"同色参照物"的本色），
    别凭肉眼先怀疑模糊 API。原生侧修法 = 遮罩 `Color.Transparent`（保留 `onClick` 关闭）+
    模糊 API 换 `backgroundEffect`；网页侧修法见第 29 条。

### 1.3 官方抽屉、遮罩与文档级 portal

29. **全屏遮罩常常是"本体的兄弟节点"，只隐藏本体等于没隐藏**（第九轮真机，**从第五轮起就潜伏**）：
    官方抽屉的遮罩 `div._4cbcd96` 是抽屉 `div.dc04ec1d` 的**兄弟**（`position:fixed`、整屏、
    `rgba(0,0,0,.4)`、`z-index:1001`、**`pointer-events:auto`**）。只给抽屉本体
    `visibility:hidden` → 遮罩仍盖在最上层：①整页被压暗 40%（实测白色 `255→153`，正好 `255×0.6`）；
    ②**页面所有真实触摸被它吃掉**。
    **修法**：`ShellScript.ets` 的新增 `markDrawerScrim(dr)` 扫本体**兄弟节点**，按
    "`position:fixed` + 覆盖 ≥80% 宽 & ≥50% 高 + 深色半透明底（`rgba` 且 alpha ∈ (0.05,0.95)
    且 RGB 均值 < 140）+ 内部无可交互内容/文字"打标 `data-dsh-hide-scrim`，
    配 CSS `visibility:hidden !important; pointer-events:none !important`；
    辅助函数 `scrimAlpha()` / `isBlankScrim()`（**不用正则**，避免模板字面量里的反斜杠转义）；
    `markShell()` 一起接管；**兜底把外壳交还官方（`reveal()`）时要一并摘标记**，
    否则兜底路径被自己打瞎；`diag().scrims` 供断言。
    冷启动抢首帧：`grabScrim` 每 120ms 重试（至多 16 次），只跑廉价的
    `injectStyle + markDrawerScrim + findDrawer`，遮罩一到手即停 —— 否则固定那几次 rescan
    落在 1000ms、冷启动会闪一层灰。
    两条方法论：**①同一容器里"本体 + 遮罩"必须成对处理**；**②验收必须至少补一次真机真实触摸**
    （`uinput -T -c x y` 后回读 `document.activeElement` / 视口高），因为 `dispatchEvent`
    合成事件**不经过命中测试**，全屏遮罩挡不住它 —— 自动化会一路"通过"而真人点不动。
30. **官方模态/下拉是"文档级 portal"，不属于被隐藏的抽屉**（第十一轮）：把抽屉隐藏之后，
    它自己的确认弹窗（`ds-modal-overlay` 36% 整屏遮罩 `z=1025` + `ds-modal-wrapper` `z=1026`）
    **照旧渲染在文档级**；侧栏面板只占 82% 宽时，用户会看到"面板右下方又冒出半张官方弹窗 +
    整页被压暗"。
    修法：删除期间在 `<html>` 上打 `data-dsh-delete-driving="1"` + CSS `visibility:hidden`
    （**不要 `display:none`** —— 保留几何，派发的事件才带真实坐标；`display:none` 会让 rect 全 0），
    并在链路收尾无条件摘标记（否则官方其它弹窗一起遭殃）。
    位置：`ShellScript.ets` 的 `setDeleteDriving()` / `markDrivenModal()` / `finishDelete()`。
31. **官方下拉菜单是单例复用且 DOM 不带归属信息 → 残留菜单会点错行**（第十一轮，
    **本轮真的误删了用户一条真实会话**）：`⋯ → 删除` 这类"按文案点菜单项"的链路，
    若场上残留一个还开着的菜单、而本步的 `⋯` 又没弹出新菜单，按文案定位会命中**别人那一份**，
    把用户没选的 B 删掉（用户选的 A 从未被碰，而流程一路报成功）。
    **对策**：动每一步之前先要求"场上无菜单/无弹窗"，收不掉就**中止这一步**
    （`stale-menu` / `stale-modal`，宁可不做不能做错）；并按**操作前后 id 差集**证明只动了目标。
    位置：`dropdownCount()` / `closeDropdowns()` / `deleteSession()` 的前置检查。
    另：`deepseekHmDiag().modalSeen` 之类的读数**必须能反映"官方弹窗被接管"**，否则断言等于没断。
32. **隐藏容器里元素的 `getBoundingClientRect()` 可能是全 0**（第十一轮）：抽屉里行内「⋯」
    的宽度靠 hover 才出现，平时 rect 全 0 —— 按 (0,0) 派发 pointer/mouse 序列等于点在屏幕左上角，
    React 收不到有效坐标（表现："点了 ⋯ 菜单不弹"）。
    修法：派发辅助函数 `tap()` 要能在**目标无几何时退到最近有几何的祖先**取中心坐标。
33. **"当前状态恰好正确"会掩盖"动作其实无效"**（第九轮，两个假象）：
    ①官方抽屉在本机视口（443×952）下**默认就是打开态**（重载后 `performance.now()=518ms` 时
    已无 `collapsed`、宽 261），于是靠合成 tap 驱动的 `prewarm()` 开合一直是空动作，
    却被"会话列表 54 条抽到了"这个正常结果掩盖。
    ②关键动作要加**效果回读**（tap 后校验目标的 class/尺寸/状态真的变了），
    否则"成功"可能只是"本来就是这个状态"。同理，A/B 脚本的触发动作也要回读，
    否则两相都是 0 会给出假 PASS。
34. **官方设置弹层打开时，其网页侧 backdrop 只压暗网页内容、原生顶栏仍亮**（第九轮遗留）：
    原生层在 Web 之上，属架构固有取舍，未处理。

### 1.4 键盘 / 视口 / 滚动条（网页侧几何治理）

35. **ArkWeb 的软键盘避让默认 `RESIZE_CONTENT`，布局视口真的会缩**（第十一轮）：
    `component/web.d.ts` 的 `WebKeyboardAvoidMode` 默认值就是 `RESIZE_CONTENT`
    （视觉 + 布局视口一起缩），于是**"网页自己会处理键盘"是错的** ——
    官网首页那类"在可视高度里垂直居中"的布局会整块上移（真机实测 `innerHeight 952→583`，
    输入框 y 466→281）。
    想让某页"原地不动"就**把应用根高度钉在键盘未弹出时的高度**（取见过的最大 `innerHeight`，
    免注入屏幕参数），**不要**去改全局 `setKeyboardAvoidMode`（会影响其它页面与弹层）。
    位置：`ShellScript.ets` 的 `pinHomeLayout(isHome)`。
    **钉高只对该页生效**：贴视口底的 sticky 输入坞（对话页）被钉高会沉到键盘下面
    （实测对话页 `pinned=0`、dock 底 571 < 583 正常）。
36. **钉高之后的二次修正必做：长草稿会把输入框底边顶到键盘下面**（第十一轮）：
    块体居中意味着"草稿变高时上下各长一半"，12 行草稿把底顶到 645（键盘上沿 583）。
    按"底边不越过键盘上沿"反推虚拟高度（居中位移 = 高度变化的一半 ⇒ 高度 −= 2×越界量），
    并挂 `document` 级 `input` 监听（80ms 防抖）立即重算，不必等 3s 兜底 tick。
    实测：根高 952 → **767**、`ta.bottom` 645 → **553** < 583。
    **方法论：任何"钉住布局"的修法都要用长草稿再测一次** —— 否则容易修掉一个视觉问题、
    引入一个可用性问题。
37. **`html{overflow:hidden}` 只禁用户滚动，不禁脚本滚动**（第十一轮）：`window.scrollTo()`
    照样生效，所以"能不能被滑走"必须按**用户手势**测，不能用 `scrollTo` 判定。
38. **输入框"滑动出现两条滑块"= 官方自绘滚动条 + 引擎默认 overlay 滚动条叠在一起**（第十一轮）：
    ①官方**自绘**滚动条 = `div.ds-scroll-area__vertical-gutter >
    div.ds-scroll-area__vertical-bar`，真正的色块画在它的 `::after`
    （`background: rgb(229,229,229)`）—— 输入框聚焦期间（`ds-scroll-area--show-on-focus-within`）
    **一直显示**、跟随滚动位置；②**引擎默认**的 overlay 滚动条（textarea 自己的滚动溢出）——
    平时淡出、**一滑动就冒出来**。用户原话"浅色长条一直保留，但滑动时深色长条会短暂出现"
    就是这两条的指纹。
    要留①（设计系统的一部分）关②：给 **textarea 自己**（以及同容器里"可滚动 +
    `pointer-events:none`"的镜像兄弟层——官方用来量内容高度，`scrollTop` 恒 0）打
    `data-dsh-noscrollbar="1"` + 注入
    `{scrollbar-width:none} / ::-webkit-scrollbar{display:none;width:0;height:0}`。
    ①是独立 DOM 元素、不是引擎滚动条，因此不受影响。
    **只扫 textarea 及其兄弟**，别碰消息列表 / 抽屉；找不到 textarea 就什么都不做（不标记 → 不误伤）。
    位置：`ShellScript.ets` 的 `markInputScrollbars()`；`diag().sbHidden` 应等于 2。
    验证按像素剖面：滑动中"深色像素 = 0"、静置只剩一段与官方 `::after` 同色（229）的浅色段。
    对照图：`内部验证记录`（修复前两条）vs `crop-withfix.png`（修复后一条）。

### 1.5 输入坞 / 间距 / 对话框 API

39. **输入坞离底太远的拆解与回收**（第八轮）：实测距屏底 62px = `5px`（卡片与包裹层）+
    **`28px` 官方免责声明行「内容由 AI 生成，请仔细甄别」** + **`33px`
    `env(safe-area-inset-bottom)`**（滚动容器自己的 `margin-bottom`）。
    做法：`.ds-virtual-list { margin-bottom: 12px !important }` 回收 21px +
    免责声明行 `padding` 6+6 → 2+2 回收 8px（**合规提示必须保留**，只收内边距）→ **62 → 32px**。
40. **ArkUI 的 padding 在 height 之内**（第六/七轮，踩过两次）：`SidePane` 底部行
    `.height(36).padding({bottom: bottomInset})` 会让手势条高度把文字压扁 →
    改 `.height(36 + this.bottomInset)`；第七轮把三重避让整体收敛成面板外层**一次 padding**
    （上 = 状态栏 + `EDGE_GAP`，下 = 手势条 + 输入法 + `EDGE_GAP`），避免"改一次要动两处"。
41. **`AlertDialogParamWithOptions` 的 `message` 是必填**（缺了直接编译报错）；
    `AlertDialogParamWithButtons` 则是 `primaryButton` / `secondaryButton` 两个必填。
42. **请用 SDK 清单而不是猜 API 名**（本轮通用纪律）：进度回调是 `onProgressChange`
    （不存在 `onProgress`，事件类型 `OnProgressChangeEvent`）；`AvoidAreaType.TYPE_KEYBOARD` = 3
    （已用 d.ts 实证）；`getFocusController()` 在 `@ohos.arkui.UIContext.d.ts`。
    **第二十一轮补充**：`TransitionEdge` 的枚举值是**全大写**（`BOTTOM` / `TOP` / `START` / `END`，
    `common.d.ts:5153`），写成 `Bottom` 会被编译器拦下（"Did you mean 'BOTTOM'?"）——
    与 `BarState.On` / `NavigationMode.Stack` 等同为 ArkUI 枚举的命名惯例（PascalCase 类型名 + 大写枚举值）。
    同轮另一条：`Search.searchButton` 吃的是 `ResourceStr` + 可选 `SearchButtonOptions`
    （`search.d.ts:524`），点击同时触发 `onSubmit`。
43. **"Function may throw exceptions" 告警**（第三轮）：`getPromptAction().showToast()` 等
    可抛调用要 try/catch 才能无告警构建（本项目保持 0 error / 0 warning 的基线）。

### 1.6 构建、设备与调试环境

44. **HarmonyOS 模拟器热启动快照损坏会让它"假死"**（第五轮）：强杀后
    `%LOCALAPPDATA%\Huawei\Emulator\deployed\<设备>\ram.img`（4GB 快照）失效，
    之后每次启动都卡在镜像校验后（**CPU 持续自旋、日志停在 `finish check image system.img`**，
    `config.ini` 里 `isHotBoot=true`）。正解：把 `config.ini` 的 `isHotBoot` 改成 `false`
    并删除 `ram.bin`/`ram.img`，**保留 `userdata.img.qcow2`**（应用数据/登录态不丢），再冷启动。
    冷启动期间**内核会重启一轮**（uptime 归零），连接抖动属正常。
45. **`hdc` 会话陈旧会误判成"设备没起来"**（第五轮）：模拟器已在 `127.0.0.1:5555` 监听、
    但 `hdc list targets` 为 `[Empty]` → `hdc kill -r` + `hdc tconn 127.0.0.1:5555` 即恢复。
46. **真机 `USB Offline` 用 `hdc kill -r` 即恢复**（第六轮）：设备已被 Windows 识别
    （`Get-PnpDevice` 能看到 `HDC Interface` 与手机型号）但 `hdc list targets -v` 显示
    `USB Offline` 时，重启 hdc 服务端立刻变 `Connected`，**不必重插 USB、不必重新授权**。
    重启后会丢掉已建立的 `tconn`（模拟器需补回）。
47. **`hdc fport rm` 对"指向已死 pid 的转发"无效**（第五/六/九轮反复重现）：
    `fport ls` 列着它，但 `fport rm tcp:9240` / `fport rm tcp:9240 tcp:9240` / `fport rm 9240`
    全部报 `ruler is not exist`。遇到 `TCP Port listen failed` 不要纠缠，**直接换一个新本机端口**。
    同理 `hdc rport` 的设备端口被上一轮遗留监听占住时也换端口（`hdc rport tcp:18090 tcp:18080`）。
48. **PowerShell 里别用 `$pid` 接 webview pid**（第五轮）：它是只读自动变量，赋值会报错并让
    后续表达式用错值。
49. **`hdc list targets` 多设备并存时命令会落到"另一台"设备上**（第十轮）：同时列着模拟器
    （`127.0.0.1:5555`）与真机（USB）时，不带 `-t <sn>` 的 `install/shell/file recv` 可能打到
    另一台，表现为"改动没生效 / 某个 UI 交互突然坏了"。本工程曾因此在模拟器上把
    "面板子控件整体点不动"误判成产品缺陷，换真机复核同一构建完全正常。
    **判定 UI 交互缺陷前，先确认命令打在哪台设备上**（多设备一律显式 `hdc -t <sn> …`）。
50. **`hdc uninstall` 会连 ArkWeb 的 Cookie 一起清掉**（第六轮，**本轮真的因此清了真机登录态**）：
    登录态、云端历史入口全没。覆盖安装一律用 `hdc install -r`（保留数据）；
    只有报 `install sign info inconsistent`（签名不一致）时才需要先卸载，**且要先确认登录态不重要**
    （清掉就得让用户重新登录，而真实登录态是验证"从官方 DOM 抽取数据"类功能的前提）。
51. **模拟器深色 Web 表面合成故障（间歇性 GPU 分块渲染损坏）**（第三轮）：
    症状 = 应用窗口顶部纯黑、仅底部一条残带刷新（残带色恰为网页 `html` 背景），
    而 CDP 内部截帧完全正常；系统设置等原生应用深色正常。
    诱发时序：加载期间 Web 直接暴露、或覆盖层经**透明度过渡动画**卸载揭露 Web。
    对策：**加载期用全屏不透明原生覆盖层盖住 Web、结束时瞬时移除（不加过渡动画）**——
    实测 3/3 稳定。同族现象在第七轮复现（网页区纯黑而同刻 CDP `readyState=complete`、
    桥在工作）→ **属模拟器图形栈故障，不是产品缺陷**；
    **容器渲染路径必须真机验证**。
52. **模拟器 VirtWifi 要手动连接**（第三轮）：`wlan0` 无 IP 时系统判定断网（状态栏 WiFi 带叉），
    即使 `eth0` NAT 能 ping 通，ArkWeb 也报 `ERR_INTERNET_DISCONNECTED`；且网络状态会周期抖动。
    冒烟前先 `ifconfig wlan0` 确认 IP。
53. **锁屏会拦截 `aa start`**（第三轮，Error `10106102`）：先 `power-shell wakeup` +
    `uinput -T -m 658 2600 658 800 500` 上滑解锁。
54. **调试用启动参数钩子是验证刚需**（第五/七/十轮）：`--ps colorMode dark|light`
    （`EntryAbility.applyDebugColorMode()` → `ApplicationContext.setColorMode()`，
    不带参数即跟随系统；来源是模拟器控制中心没有"深色模式"磁贴、系统设置逐级点击又受坐标差异影响）、
    `--ps action openSidebar|closeSidebar`（侧栏这类"原生组件、CDP 摸不到状态"的场景，
    合成 tap 受"面板当前是否展开"影响而不可复现，显式钩子把开合变成确定态）。
55. **登录态失效时用临时预览页喂假数据验证纯 UI**（第七轮）：`pages/SidePreview.ets` 用假数据
    （3 组 × 6 条、第 14 条设为当前会话）直接渲染 `SidePane`，避让值从 `AppStorage` 取系统真实
    上报值，外面套"主内容占位 + scrim"模拟真实层级。
    **验完三处临时改动必须全部还原**：`EntryAbility.loadContent`、`main_pages.json`、
    `Index` 的临时启动参数钩子。
56. **`内部验证记录\README.md` 里的历史路径保持原样**：证据文档写于迁移前，
    其中的 `.` 即现在的 `.`（见文首说明）。

### 1.7 网页文件选择与官方弹层（第十三轮）

57. **ArkWeb 的「选择上传」窗是系统窗、且没有进场动效**：网页里 `<input type=file>` 被点中、
    而应用没实现 `Web.onShowFileSelector` 时，ArkWeb 会自己弹一个系统窗
    （图库 / 拍照或录像 / 文件 / 取消）。它**不在本应用窗口里**（`uitest dumpLayout` 查不到，
    进程表出现 `com.huawei.hmos.photos:PickerUIExtensionAbility`），且**没有进场动效**：
    265ms/帧连拍 8 帧、8 帧 MD5 完全一致 —— 第一帧就是终态。
    → 要实现"有动效"只能**接管**：`onShowFileSelector` 返回 `true`，自己出选择界面。
58. **接管后必须用官方组件，别自绘**（用户当场指出的返工）：首版用自绘覆盖层 +
    `animateTo(springMotion)` 已经把动效做出来了，但"自绘得像官方"终究是仿制 ——
    用户要的是官方组件本身。最终用 `bindSheet`：
    `height: SheetSize.FIT_CONTENT`、`dragBar: false`、`showClose: false`、
    `title: { title: '选择上传' }`，弹出/收起动效、遮罩、圆角、材质、下拉关闭全部系统负责。
    注意 `bindSheet(isShow, builder, options)` 的 `isShow` 要 `$$` 双向绑定，
    否则用户点遮罩/下拉关掉面板后应用侧状态仍为 `true`，**下次再也弹不出来**；
    配合 `@Watch` 才能把"用户自己关掉"识别成取消（本项目另立 `pickerDecided` 标志区分
    "选来源/点取消"与"被关掉"，否则会把已选好的那次选择误判成取消）。
59. **选择器给的 URI 必须先落沙箱副本再 `handleFileList`**：图库/相机是
    `file://media/...`、文档是 `file://docs/...`，都是"选择器结果临时授权"的跨应用 URI，
    ArkWeb 渲染进程按普通路径读不到（表现是"选完了什么都没上传"）。
    `stageUploadFile()` 用 `fileIo.openSync(uri, READ_ONLY)` 开 fd 流式复制进 `cacheDir`，
    文件名保留原名 + 扩展名（网页按扩展名/MIME 判类型），下次选择前按前缀清理。
    写侧不要传 `offset`（顺序追加即可，与 PrismAgent 导入链路同款）。
60. **`cameraPicker.PickerProfile` 运行期只读**：`new cameraPicker.PickerProfile()` 之后再
    `profile.cameraPosition = …` 会抛 `Cannot assign to read only property`，相机根本起不来
    （真机 hilog 实证）。必须**对象字面量**构造：
    `const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK }`。
    三个选择器（`PhotoViewPicker` / `cameraPicker.pick` / `DocumentViewPicker`）都**不需要额外权限**。
61. **catch 不要无脑当"用户取消"吞掉**：系统选择器的"用户取消"是正常 resolve（返回空数组），
    能抛出来的都是真失败。吞掉之后的表现就是"点了某一项什么都没发生"——本轮相机那个只读 bug
    正是被这层静默藏了一轮。改为记 hilog + `toast('未能打开选择器：' + message)`。
62. **拉起系统选择器前先留 ~200ms**（`PICK_LAUNCH_DELAY_MS`）：系统选择器是独立 UIExtension
    窗口，会在拉起瞬间盖住整个应用；不隔这一段，用户看到的半模态收起动效会被整段切掉。
63. **取消不清已有附件**（真机实测）：取消/返回键回 `handleFileList([])`，
    网页侧对空列表不做处理，已挂的附件与沙箱副本都还在 —— 与浏览器"取消文件对话框不改动 input"
    的语义一致（"完成但 0 选"才会清）。

---

### 1.8 第十四轮（2026-09-14）：审查问题修复与性能优化

64. **前端「先退模式、再抛请求」会把安全闩提前落闩**（
    `SidePane.confirmDelete`）：确认回调里 `exitSelecting()` 在前、
    `onDeleteSessions(ids)` 在后 → 网页侧收到的是"先 disarm 再 delete"，
    整批返回 `locked`、**一条都删不掉**，而旧实现还把 `locked` 静默计成成功。
    修法是**调换顺序**（先抛请求、再退模式），而不是加判据；
    唯一落闩点留给队列收尾。详见 `§3.0-131`。
    **定位手法**：在页面侧探针里记录 `set/clear/del` 的调用**序**——
    我第一次只加了 `deleteBusy` 守卫，真机仍 100% 失败，看到调用序才明白是顺序问题。
65. **安全闩的"密钥通道"不能只做一半**（`ShellScript.setDeleteToken`）：
    第一版只把密钥改成"由 native 生成并随请求传参"，但 `setDeleteToken`
    仍接受**任何** ≥8 字符的串 → 页面脚本自造一个再自己开闸照样能删。
    收口做法：密钥经**一次性 `window.__dshArm` 交接**进脚本闭包（页面上无读取出口），
    加 `deleteTokenAssigned` 标记防"改成空串绕过匹配"，并**从页面对象上删掉 `armDelete`**。
    断言写成**三个攻击面全被拒 + id 差集 0**。
66. **容器适配脚本必须有顶层单例守卫**（`DeepSeekConfig` 头部）：
    只做"样式幂等"（`STYLE_ID` 复用）不够——每注入一次就多一套
    `DOMContentLoaded`/`load`/`matchMedia` 监听 + 一个巡检定时器。真机读数：单例后 `boots=2`
    且巡检间隔恒为 5s。另：巡检加 `visibilityState` 门控 + 回前台补查；
    切勿用 pauseAllTimers 类 API（会连官方网页自己的定时器一起停）。
    详见 `§3.0-132`。
67. **模板字面量里的注释不许出现反引号**（本轮实际踩到）：
    在模板字面量形式的 `export const JS: string = …` 注释里写一个反引号会**截断模板字面量**，
    报出一堆 `Cannot find name 'document'` 这种罕见错误。装机前必跑注入脚本预检。
    详见 `§3.0-133`。
68. **预检脚本要按"运行时字符串"断言**（`check-injected-js.mjs`）：
    `node --check` 只能拦语法错，拦不住"反斜杠被模板字面量静默吃掉"（语法合法）。
    本轮预设了 `/[\s]+/` 与 `rgba?\(` 两条断言。详见 `§3.0-130`。
    扫描器自身也要按"连续奇数个反斜杠才算转义"数，否则对 `[\s]` 误报。

### 1.9 第十五轮（2026-09-14）：官方组件替换与 UI 统一

69. **`accessibilityText` 在 `uitest dumpLayout` 里读不出来**（本轮实测）：
    只写 `accessibilityText` 时，5 个纯图标按钮在 dump 里的 `description` **全是空**，
    自动化无从断言"到底有没有名字"；而 `accessibilityDescription` 能读出来。
    做法：**两个都写**（前者是读屏取名字的正式属性，后者是本工程验证链能看见的字段），
    并加 `accessibilityLevel('yes')` 保证能被读屏聚焦（默认 `auto` 的识别权在无障碍服务与 ArkUI 手上）。
70. **`Search.searchIcon` 吃的是 `IconOptions` 不是 `Resource`**（本轮编译期当场拦下）：
    SDK `search.d.ts` 签名是 `searchIcon(value: IconOptions | SymbolGlyphModifier)`，
    得写 `{size, color, src}`。同类：`cancelButton` 吃 `CancelButtonOptions | CancelButtonSymbolOptions`。
    规矩还是 §1.5-42：用 SDK 清单而不是凭印象 —— 只不过这次是**编译器把我拦住了**（比真机上才发现好得多）。
71. **尺寸魔数必须只有一份**：本轮新增 `common/ShellUi.ets` 把图标按钮/行高/圆角/字号
    收成一张表。原先 `Index.ets` 与 `SidePane.ets` 各自写一份 38/52/24…，
    改一处忘一处就是"两个按钮差 2vp"这种肉眼看得见、却说不清来源的问题。
72. **吸顶分组头与"单行刷新粒度"是互斥的**：`ListItemGroup` 是二维结构，
    分组内任一行变化会重建整个 group —— 与 `ForEach` key 精细到单行的刷新策略直接冲突。
    遇到这种需求先问"哪一个是硬约束"，本工程选保粒度、放吸顶。

### 1.10 第十六轮（2026-09-15）：UI 统一 / 残余 BUG / 顶栏模糊对标官方

本轮的**技术重心是顶栏沉浸效果**：用户先后给了三轮反馈（"和内容有明显分界线"→"自下而上要由清晰
到模糊，参考华为系统设置"→"顶栏下内容不可见，模糊过重"→"要达到像官方那种效果，模糊还是过重"），
每一次的根因都不同，逐条记下来。

73. **`backgroundEffect` 的高斯模糊会向组件矩形「之外」继续采样（外溢）**：
    这是本轮最反直觉的一条。顶栏高度是 `topPad + TOP_BAR_H`，但**糊化实际生效的高度比它大** ——
    半径 24vp 时，顶栏下沿**外**约 10vp 处的正文行仍然是糊的（真机同位置 A/B：
    `内部验证记录` 顶栏下一行糊成灰块，`b6-3.jpeg` 同位置逐字可读）。
    用户的原话"**顶栏下内容不可见**"就是这个外溢造成的。
    **外溢量随半径单调增**，所以"降半径"一次修两件事：外溢收窄 + 穿栏内容变清晰。
    取证方法：**让长内容停在"被顶栏下沿切断"的位置**，直接看被切断那行的清晰度 —— 比量外溢像素省事得多。
74. **"磨砂 + 渐隐过渡"必须分层，不能糊在同一块上**：`backgroundEffect` 是**均匀**模糊，
    盖到哪儿哪儿糊。第一版把它加在"主体 + 过渡带"的整块上，于是过渡带里的内容**也是糊的** ——
    用户看到的是"内容只是变淡、并没有变清晰"。
    正解：**模糊只加在主体（三槽 `Row`）**，过渡带用 `Blank()` + 纯 `linearGradient`
    （玻璃色 → **同 RGB、alpha = 0**）—— 过渡带里的内容**是清晰的**，只是被逐渐淡出的色覆盖。
75. **判据必须是对标观感，不是任何中间量**（本轮最贵的一条教训）：
    第一次下调（24 → 12）后我验证了"**外溢已消除**"就认为达标了，用户回的却是"**还是过重**" ——
    因为 12vp 时**穿过顶栏的内容本身仍糊成一块**，而官方（华为系统设置 `hw-top.png`）的观感是
    "**字形轮廓仍清晰可辨**，只是被柔化 + 蒙一层薄色"。**"没有外溢"≠"像官方"**。
    凡是"对齐某个参考物"的需求，**验收就必须拿参考物并排比**，不能拿一个自己推出来的中间指标交差。
76. **`padding` 是覆盖不是合并**：`.padding({left, right})` 之后再 `.padding({top})`，
    后者把前者**整体覆盖** ⇒ 左右内边距**静默丢失**（不报错、不告警）。要写就写在一个对象里。
77. **空块容器 + 紧随父级闭合 `}` 会让 ArkTS 解析失败**：`Column() {\n}` 触发
    `arkts-no-any-unknown` / Rollup `Unexpected token`，而且**报错行号指向父级的修饰符**，
    极难定位。改用无子节点的基础组件 `Blank()`（本来就是"占位撑开"的语义）。
78. **`runJavaScript()` 回传的是 JSON 文本**（字符串带引号）⇒ 全等比较恒假 —— 本轮据此修好了
    账号菜单链路与主题探测两处**静默失败**，已沉淀为通用坑 `§3.0-153`。
79. **`hdc file recv` 的目标路径必须是反斜杠的 Windows 绝对路径**：写 `C:/Users/...` 时 hdc
    **不报错**，而是当作**相对路径**拼到当前工作目录（`仓库根目录\C:/Users/...`），
    表现为"截图莫名落进工程目录"（本轮与上一轮各发生一次，共 8 张，已全部清出）。
    拉取一律 `hdc ... file recv /data/local/tmp/x.jpeg 'C:\Users\...\x.jpeg'`。

### 1.11 第十七轮（2026-09-16）：设置入口闪窗 + 系统设置弹层改手机版布局

本轮两条用户反馈，**根因都在"官方 DOM 的边界"上**，不在原生侧：
"点系统设置左下角闪过网页原生弹窗"（浮层逃出祖先链）、
"设置还是网页版排布、不美观"（一行里固定 min-width 的项数超容器 ⇒ 裁掉最后一项）。
两条都属于**只看截图看不出来**的类型，全靠 CDP 把数字量出来。

80. **在祖先链上做隐藏（`visibility:hidden` / `opacity:0`）管不住 React portal** ——
    驱动隐藏抽屉里的账号入口时，本工程把它整条祖先链临时改成 `visibility:visible; opacity:0`；
    而官方账号下拉菜单是 portal，挂在 body 级 `.ds-floating-position-wrapper` 下，**不在那条链里** ⇒
    整块可见（rAF 采样：`[8,726,136,168]`、opacity 0→1→0、可见 ≈290ms，正是用户说的"左下角闪一下"）。
    正解与三条易错细节见通用坑 `§3.0-154`。
    **方法论**：这类"一闪而过"的东西**不要用整屏截图抓**（290ms 抓不到稳定帧），
    要么装 rAF 采样探针记 computed opacity 时间线，要么用"同一 DOM、只差一个属性"的 A/B 截图（T1 就是后者）。
81. **"手机上还是网页版排布"要先量 `scrollWidth > clientWidth`**：本轮实测页签行 452/403 ——
    官方媒体查询其实**生效了**（面板已 100vw 全宽、页签已转横向），问题是 **4 × min-width:108px 放不进 403px**，
    第 4 个页签 `360 → 468` 越界被裁。判据与两条暗坑（`.ds-button__background::after` 的 `inset:-2px` 按压环、
    两端动态插入的渐隐装饰层）见 `§3.0-155`。
82. **官方弹层的"装饰层"是动态插进来的，认结构不能认"第一个"**：官方页签行两端各有一个渐隐层
    （各含 1 个箭头按钮，**左侧那个排在真条带前面**）—— 用 `querySelector('.ds-button')` 取"第一个按钮的父节点"
    会把**真条带**当成装饰层隐藏掉，整行塌成 0 高。改成"子节点里按钮**最多**的那一个" + 真条带护栏。
    同源教训：`§3.0-141`（"按内容撑开"的容器里别用 `width('100%')`）。
83. **深色兜底用嵌套媒体查询，别把 `not` 和 `and` 混写**：`@media not all and (min-width:768px) and (prefers-color-scheme: dark)`
    里的 `not` 否定**整条**查询 ⇒ 浅色手机上深色规则照样命中（本轮实测：面板底色被刷成 `#151517`）。
    见 `§3.0-156`。
84. **打标式改官方样式（`data-*` 属性 + 属性选择器）比跟着 hash 类名写更耐改版**：
    官方类名是 CSS Module hash（`_6c040bb` / `b40079d7`），重新发布就变。
    本轮 T2 的做法：**只用 `ds-*` 语义类 + 结构关系**定位（`.ds-modal-content__title` 文本 === `'系统设置'`），
    打上 `data-dsh-settings-*`，CSS 全部写在属性选择器上，且**逐条以 `data-dsh-settings-` 开头**（无全局选择器）。
    选中态 hash 也是**现场发现**的（"只出现在一项上 + 该项背景不透明"），不写死。
    这与本工程既有的 `data-dsh-drawer` / `data-dsh-sheet` / `data-dsh-promo` 是同一套办法。
85. **注入脚本里"被拼接进字符串的常量"必须声明在使用点之前**：`var` 只提升声明不提升赋值，
    常量写在文件后段会让首次 `injectStyle()` 拼出 `[undefined="1"]` —— 规则整条失效且**无任何报错**
    （语法检查、构建告警都看不见它）。见 `§3.0-158`。
86. **ArkWeb DevTools 在应用切后台后"连得上但不回应"**：`curl` 显示 TCP 建连成功却 0 字节挂到超时，
    而 `fport ls` 里的 pid 是对的 —— 极易误判成"规则钉在死 pid 上"而白换端口。
    先 `aa start` 把应用拉回前台再查。见 `§3.0-157`。
87. **`HitTestMode.None` 只豁免"自身"，子节点照常参与命中测试** —— 一个"看不见的常驻气泡"
    因此能吃掉整整一片区域的触摸。真机实例（T4 逐点实测）：`NewChatTipLayer` 的**外层 Column 写了 None**，
    但里面那个"已是新对话"的 `Text` 没写 ⇒ 该气泡（opacity 0）在物理 `[1030,290]-[1281,380]` 上
    一直吃触摸，**设置弹层右上角的 ✕ 正好落在那里**（表现："要点好几下才关得掉"）。
    **判别手法**：同一 y 换 x —— 顶栏丢包带是**全宽**的，而气泡只在 `x 1030-1281`；
    实测 `(1000,363)/(1290,363)/(1300,363)` 各送达 7 个事件、`(1258,363)` 恒 0 ⇒ 一眼区分"全宽遮罩"与"局部遮挡"。
    已沉淀为 `§3.0-159`。
88. **主题兜底别只挂 `matchMedia`**：官方把主题放在 **body 的 class** 上（`zh_CN light deepseek-hm-host`），
    真机 `prefers-color-scheme` **恒为 false** ⇒ `installThemeListener` 的 matchMedia 回调**根本不会触发**，
    于是"采样式配色"要等 5s 巡检的 dirty / 每 6 拍才重采（T4 实测：切深色后 2s / 8s 面板仍是浅色、35s 才对）。
    修法：**定向**观察 `body` 与 `html` 的 `class` 属性（只这两个元素、**绝不做子树**）→ 一变就重打标 + 重采样。
    注意别顺手扩成 subtree 属性监听 —— 本文件里记着那条教训（全子树 class/style 监听曾把真机渲染主线程压死）。
89. **用户第二轮反馈（2026-09-17）两条，都属"看截图才认得出来"的类型**：
    ① **侧栏面板的圆角不裁子节点**：账号行（`width(100%)` + `stateStyles.pressed` 底色 `shell_item_active_bg`）
    被按压时是一条**矩形**色带，在面板右下圆角处露出直角 —— 用户描述为"变黑层没有圆角优化，导致阴影超出圆角"。
    ArkUI 的 `borderRadius` **只作用于组件自身背景**，子节点默认不被父圆角裁剪（SDK: not clipped by default）⇒
    给面板 Column 加 `.clip(true)`（真机 A/B：只裁子节点，面板自身 `.shadow()` 与顶角**逐像素不变**）。
    判据是**像素级**的：按住行 → 逐行取底色最右 x，收窄 **1px（改前）→ 80px（改后）**；
    已沉淀为 `§3.0-160`。
    ② **"内容放得下却出现滚动条"**：设置页 `scrollHeight == clientHeight == 734` 是**取整后**的读数，
    真实内容高 733.997 / 内容盒 733.571 ⇒ **恒溢出 0.426px** ⇒ 触摸时画滚动条、CDP 拖拽能把它滚走 0.336px
    （`scrollTop = 0.336` 就是这条缺陷的指纹）。四条一起修：消取整差（`min-height:0`）/ 隐藏滚动条（**要覆盖 html/body**，
    用户那条几乎整屏高 ⇒ 文档级）/ 隐藏站点自绘 gutter / 钉页面（`overscroll-behavior:contain` + `touch-action:pan-y`，
    **不要** `none`，否则内层滚动一起死）。已沉淀为 `§3.0-161`。
    **方法论（本轮最值钱的一条）**：凡"我们抓不到用户报的现象"，都要做**正对照**把改前条件运行期还原一次，
    证明"尺子灵"—— 本轮还原后同一扫描器立刻在 **x=1247..1269** 抓到竖条，与用户截图里的 **1248..1256** 吻合，
    装机件的"无"才站得住（否则"没抓到"可能只是"看不见"）。

**本轮的做法与产物**：设置弹层改成"手机版设置页"（全屏面板 + 标题固定 + 4 个页签等分不裁 + 圆角卡片行），
配色由 `syncSettingsColors()` 从官方弹层**实测色采样**写成内联 CSS 变量（跟随页面主题，不写死深/浅）；
改动全部落在 `DeepSeekConfig.ets`（打标 + CSS）与 `ShellScript.ets`（浮层视觉闩）。
证据：`内部验证记录`。

### 1.12 第十八轮（2026-09-17）：顶栏丢包带原生根治 / 避让通道复活 / 站点主题跟随 / 外壳统一

**（一）顶栏下方那条 16vp「点击丢包带」—— 原生侧根治（本轮最值钱的一修）**

- **现象**：网页里某个元素看得见、`clickable` 为真、坐标也对，点它就是没反应（第十七轮的设置弹层 ✕）。
- **判据**：逐点扫描量出边界 —— 丢包下沿 = `topInset`(97.7) + **`TOPBAR_FADE_H`(16)** ≈ 113.7 CSS px。
- **根因**：顶栏容器高度 = `TOP_BAR_H + topPad + TOPBAR_FADE_H`，那截渐隐带是**纯视觉**的，
  但 ArkUI **容器整块参与命中测试** ⇒ 带子里的触摸被原生层吃掉、传不到下层 Web（§3.0-159）。
- **修法**：顶栏**根容器** `.hitTestBehavior(HitTestMode.None)`。语义是**自身不吃、子节点照吃** ——
  所以顶栏主体里的三槽 `Row` 与按钮照常可点，只有装饰带子变成透明的。
- **工程专属做法（A/B 正对照，值得照抄）**：这类改动 `dumpLayout` 里 `clickable` 一律为真、构建 0 warning，
  **只有真实触摸能证伪**。做法是：临时**注释掉那一行** → 装包 → 只跑一条触摸扫描 → 拿到旧行为读数 →
  **逐字节还原**（用 md5 与改动前冻结值比对，并由第二人独立复跑 `md5sum` 确认）。本轮读数：关掉 `got=0`（8 点全丢）↔ 打开 `got=8`（8 点全到），唯一变量。
- 上一轮在**网页侧**绕（内容下移 `topInset + 20`）只是临时手段，根在原生侧。

**（二）「轻量避让通道」的双缺陷（静默失效会叠加）**

- 宿主探的入口名 `window.__dshSetInsets` **全工程从未定义**；同时宿主对回传值的 `res === 'no-channel'` 撞上
  §3.0-153（回传是**带引号的 JSON 文本**）⇒ 判据恒假。**两处都要修，只修一处仍然静默失效**：
  避让值虽然写进了 `window`，但真正的几何修正（`ensureTopSpacer()` / `applySafeArea()`）一次都没被调用过。
- 运行时对照（`__dshNativeShell.setInsets` 被删时门面必须回 `no-channel`）证明**门面**的通道存在性判据可达且正确。

**（三）侧栏开合「零跳变帧」= 几何量必须在进场之前算好**

- 旧链路：打开当拍只立一个"等定位"标记 + 900ms 兜底定时器，真正的滚动发生在 rescan 数据到达之后
  （100~300ms，正落在 350ms 的进场动画里）⇒ 用户先看到列表停在顶部、再看到它「啪」地跳到当前会话。
- 新做法：① **打开当拍**就用**手上已有的行数据**定位（面板还在屏幕外、列表早已布局，第一帧即终态）；
  ② 幂等判据从**布尔标记**换成**会话 id**（布尔分不清「已经定位好了」与「数据还没到」—— 打开当拍没有行数据时它会立刻作废，等数据真到了反而不定位）；
  ③ 补发定时器只重滚**同一个目标下标**（救「首帧布局未完成、第一次 `scrollToIndex` 被丢弃」，不产生第二次跳变）。
- **自审抓到的一个自造缺陷**：`onRowsChange` 里顺手作废了补发定时器 —— 而目标没变时 `locateIfNeeded()` 会早退，
  那次补发正是唯一的救兵，掐掉就变成「面板开出来停在列表顶部」。**改完要回头看一遍新加的"顺手清理"会不会把别的路径的保底也清掉**。
- 面板开合动画归官方 `SideBarContainer`，所以 `MOTION_SLOW` 在本工程**永远是零消费者** ⇒ 第十八轮删除（"一个零消费者、却看起来像配置项的令牌比没有更糟"）。

**（四）文字按钮的 44vp 热区配方（可直接抄）**

```ts
.responseRegion({ x: 0, y: -(HOT_MIN - BTN_H_SM) / 2, width: '100%', height: HOT_MIN })
```
看得见的胶囊仍是 `BTN_H_SM`(32)，手指的可点范围是 `HOT_MIN`(44)（iOS 导航栏「完成」的做法）。
`HOT_MIN` 只做 `ICON_BTN` 的**别名**、不另写一个 44 —— 两者一旦分开，下次只调其中一个就不同源了。

**（五）C2 站点主题跟随 + C3 不重载（工程专属）**

- 真机 `prefers-color-scheme` **恒 false**（站点用 `html.dark` 类，不用系统媒体特性）⇒ 只挂 `matchMedia` 不够。
  改为读站点**偏好**：`localStorage['__appKit_@deepseek/chat_themePreference']` → 映射 app `colorMode`；
  并做**同值早退**（否则 `setColorMode` 与 `onColorModeChange` 会自激）。只读**偏好**、不读观感 —— 读观感要遍历 DOM，成本高且会抖。
- **hilog 环形缓冲会吃掉判据**：按 `hilog -x` 全缓冲区 grep `caused by site theme` 得 0 行，**不等于没发生**
  （chromium 每秒刷几千行，等读时早被挤掉）。要「切完 2s 内立刻读」—— 本轮验收唯一那条 FAIL 就是测量假象，不是缺陷。

**（六）断言脚本自己也要做变异测试（方法论）**

- 断言脚本的假绿比产品缺陷更危险：它会**被写进交付说明**。本轮实证：`w3-check.sh` 在「把清理调用**整行注释掉**」时
  仍然 PASS —— 因为它的 `grep` 不区分注释行（会从注释掉的调用里"发现"收口函数）。
- 修法：给脚本加一个**代码视图**（把整行注释的内容清空、但**保留行号**，免得报告里的行号对不上真实文件），全部扫描对象都换成它；
  改完用三个变异体验证（注释掉清理调用 / 注释掉归一化调用 / 删掉一次性消费）都 FAIL、正相仍 PASS。
- **顺序很重要：变异测试要在别人把它当 PASS 依据之前做**。残留风险：块注释续行不以 `*` 开头时仍会漏（本项目注释风格是 ` * `，可忽略）。

**（七）两条读数纪律**

1. **产物 mtime 不能当「是否同步」的判据**：hvigor 从自己的 cache 恢复未变文件时会**保留 mtime**，
   于是「产物旧于源码」是假信号（实证：`ShellUi.ts` 比源码旧 24s，内容却已含新令牌）。判同步用**内容抽样**（grep 具体令牌）。
2. **`BUILD SUCCESSFUL` 可能是假绿**：全 `UP-TO-DATE` 的构建也这么打印。必须同时确认 `CompileArkTS` 与 `PackageHap` **都实际执行** ——
   本轮正是靠这条才发现 `PackageHap` 阶段在报 `spawn java ENOENT`（而 ArkTS 编译其实早已通过）。

**本轮产物与证据**：模拟器 Pura 90 Pro 真实触摸验收 `PASS=24 FAIL=1`（唯一 FAIL 已定性为测量假象）；
**真机 Mate70 Pro+ 复核 `PASS=28 / FAIL=0`**（同一份 HAP，见下"八"）；
证据目录 `内部验证记录`，变更史见 `CHANGELOG.md` 第十八轮。

### 1.13 真机复核（Mate70 Pro+）暴露的四条「换个平台就假失败」（第十八轮同日）

同一份产物在两台设备上跑**同一套验收脚本**：真机 `PASS=28/0`、模拟器 `27/0`。但把脚本搬到真机的过程本身
踩了四次坑，**每一条都会让"看起来通过"变成假证据**：

1. **dpr 不能写死**（真机 2.975 / 模拟器 3.5）。"顶栏丢包带"的探测 y 是按 dpr 换算的，
   写死 3.5 会让 8 个探测点整体偏下约 18% —— 落在正常可点区域里，于是报"8 点全到"，
   而真正要测的那条带**一个点都没测到**。**正解：从 CDP 读 `devicePixelRatio` 现算。**
2. **原生 `AlertDialog` 的按钮在 `dumpLayout` 里是 `clickable=false` 的 Text 节点**（两台设备一致）。
   按文本找控件若只认 `clickable`，「系统设置」永远找不到 ⇒ **整段设置链路静默跳过**，
   脚本只报一句"找不到"。**正解：优先取可点节点，取不到就退回文本节点按其中点真实触摸**；
   并先断言"弹窗真的在"（存在 `type=AlertDialog` 节点）再点，避免命中别处的同名文本。
3. **主题是持久化状态**：站点偏好写进 `localStorage`、应用 `colorMode` 也留存 ⇒ 上一轮停在深色时，
   下一轮"点深色"不产生任何变化，被记成 FAIL。**正解：用例开头归零到已知值**（写站点自己的存储键 + 重载），
   并把"归零成功"也做成一条断言。
4. **真机 hilog 淘汰更快**：同样的"读日志计数"在真机上更容易读到空。**正解：当场读**（见本节的"五"）。

⇒ 结论：**"同一把尺"不能只在同一台设备上成立**。设备无关的验收脚本三条硬要求 ——
**dpr 现算、控件按文本/描述定位而非坐标、状态先归零**。这条比任何单条修复都更值得带走。

**真机与模拟器的读数对照**（同一份 HAP）：

| 项 | 模拟器（dpr 3.5） | 真机（dpr 2.975） |
| --- | --- | --- |
| 集成验收 S0~S10（**同一套设备无关脚本**） | PASS=28 / FAIL=0 | PASS=28 / FAIL=0 |
| 顶栏渐隐带 8 点真实触摸 | got=8 | got=8（物理 y 294..336） |
| 顶栏像素 浅→深 | 242,243,245 → 23,23,25 | 242,243,245 → 23,23,25 |
| 设置页签 4 项 | 均不溢出 | 均不溢出 |

## 2. 验证方法论与脚本手册

### 2.1 脚本总清单（全部在 `内部验证记录\` 下，逐个可用）

> **注意 1**：早期排障脚本原在工程内 `verify\`（`flicker-probe.js` / `frame-truth.js` /
> `mutation-trace.js` / `regression-final.js` / `syntax-check.js` / `cdp-verify-all.js` 等），
> 该目录**已于 2026-09-11 整理时删除**（2.6GB headless profile），现只剩文件名可考。
> **注意 2**：`内部验证记录` / `-07` / `-10-blur` / `-10-real7` / `-11-sidebar-ux`
> **五个目录没有 README.md**（口径见 `CHANGELOG.md` 对应轮次）；其余**九个**目录都有
> （2026-09-15 实测：`verify-*` 共 15 个目录，9 有 / 6 无；无 README 的还有本轮新建的
> `内部验证记录`，其证据随第十六轮收尾归档后补 README）。

**通用 CDP / 断言 / 预检**

| 脚本 | 位置 | 用途与调用 |
| --- | --- | --- |
| `cdp.mjs` | `内部验证记录` | 通用 CDP 求值器：`node cdp.mjs <port> <js文件或表达式>`。后续轮次的首选 |
| `cdp-eval.mjs` | `内部验证记录{shell,real,sidebar}\` | 早期版通用 CDP 求值：`node cdp-eval.mjs <port> "<expression>"` |
| `cdp-eval-file.mjs` | `内部验证记录` | 从 `.js` 文件读表达式求值（自带 `awaitPromise`）——**避免命令行转义地狱，推荐** |
| `check-injected-js.mjs` | `内部验证记录{shell,real,sidebar}\` | **注入脚本语法预检**：把 ArkTS 模板字面量按同样转义语义还原成真实 JS，交 `node --check` 解析。装机前必跑 |
| `shell-assert-2026-09-11.mjs` | `内部验证记录` | **当前主断言脚本**：外壳不变量（`topbarHidden` / `drawerHidden` / `scrimMarked` / `scrimHidden` / `scrimPE` / `hitIsScrim` / `sessionLinks`）+ 性能 A/B，PASS/FAIL 走退出码 0/1。`node shell-assert-2026-09-11.mjs <port>` |
| `shell-assert.mjs` | `内部验证记录` | 第五轮（模拟器）版断言 + 性能 A/B；`synth-check.mjs` 是它无登录态时的合成替代 |
| `shell-assert-real.mjs` | `内部验证记录` | 第六轮真机版断言（由上一版移植并**修掉它自带的负坐标 bug**） |
| `synth-check.mjs` | `内部验证记录` | 合成抽屉替身场景：抽取链路断言 + 卡顿 A/B（无登录态时使用） |
| `cdp-smoke.mjs` | `内部验证记录` | 第三轮模拟器冒烟断言（`SMOKE-CDP: PASS`） |
| `smoke-assert.mjs` + `frame-probe.mjs` | `内部验证记录` | 第四轮 rAF 逐帧探针与冒烟断言 |
| `cdp-reload-watch.mjs` | `内部验证记录` | 重载后每 250ms 采样抽屉/遮罩状态（判定"官方抽屉默认就是打开态"）；同目录另有 `cdp-shot.mjs`（CDP 单独截网页，与原生整屏截图对照，区分"网页没渲染"与"窗口没合成"） |

**真机 UI 与像素**

| 脚本 | 位置 | 用途与调用 |
| --- | --- | --- |
| `ui.ps1` | `内部验证记录` | **真机 UI 冒烟公用工具**（dot-source：`. .\ui.ps1`）：`Hdc`（已带 `-t <sn>`）/ `Shot`（`snapshot_display` + `file recv`）/ `Dump`（`uitest dumpLayout` 扁平化成 `x1,y1,x2,y2,cx,cy,type,text,clickable`）/ `TapXY` / `TapText` / `HeaderButtons`（面板头部圆形按钮按 x 升序）/ `PanelRows`（会话行 + 行内首条 Text） |
| `smoke-real.ps1` | `内部验证记录` | **侧栏回归终验**：S1 面板已开 → S2 选择模式 → S3 勾选 → S4 原生删除确认框 → S5 取消后归零 → S6 账号菜单三项 → S7 关闭菜单；坐标全部从 `dumpLayout` 现取 |
| `px.ps1` | `内部验证记录` | 像素测量：`Measure-Region` / `Get-Px` / `Get-Row`（点源后用 `. '…\px.ps1'` 加载） |
| `analyze-sb.ps1` | `内部验证记录` | **滚动条像素剖面分析**：逐列统计深色/浅色段（判定"两条滑块"是否只剩官方那一条） |
| `kb.ps1` | `内部验证记录` | 键盘场景脚本（修复前取证：`kb1-1-before` / `kb1-2-kb`） |
| `del.ps1` / `v3.ps1` / `v9.ps1` / `vfix.ps1` / `vfinal.ps1` / `vlock.ps1` / `vsb.ps1` / `v2.ps1` / `v7.ps1` / `v8.ps1` | `内部验证记录` | 第十一轮各需求的分项验证驱动：删除链路、首页钉高（`v3`/`v9`/`vfix`）、**安全闩终验**（`vlock`）、滚动条（`vsb`）、终验（`vfinal`） |

**页面侧探针（`node cdp.mjs <port> <probe.js>`）**

| 探针 | 位置 | 用途 |
| --- | --- | --- |
| `p6.js` | `09-11-ux` | 首页/对话页几何与视口读数（`innerH` / `ta` 矩形 / `pinned` / `dock`） |
| `p42.js` | `09-11-ux` | 灌 12 行草稿并读数（长草稿场景） |
| `p31.js` / `p34.js` / `p40.js` / `p41.js` | `09-11-ux` | 会话 id/标题列表、行内「⋯」候选与其几何、抽屉归属与抽取复刻 |
| `p35.js` / `p36.js` | `09-11-ux` | 删除链路页面侧采样器（安装 80ms 采样 / 汇总，覆盖 2350ms 全链路的 31 个样本） |
| `p37.js` / `p39.js` | `09-11-ux` | 会话 id 全量快照 / 按 id 取标题（做**操作前后差集**断言） |
| `p58.js` | `09-11-ux` | 直接调 `deleteSession` 并回读"闩状态 + 返回 + 会话数前后" |
| `p50.js`~`p62.js` | `09-11-ux` | 图标/气泡/启动动画/面板头部等分项探针 |
| `p-scrim-test.js` | `内部验证记录` | 压掉遮罩 → 网页最亮 `166.67→255`（成因确认） |
| `p-drawer-state.js` / `p-topbar-tree.js` / `p-toggle-*.js` | `09-11-real` | 抽屉状态 / 顶栏结构 / 官方开关响应性（连点三次无变化） |
| `p-geom.js` / `p-a1.js` / `p-a2.js` | `09-11-real` | 视口/dpr/textarea 几何；真机触摸前后 `activeElement` |
| `p-type.js` / `p-after-send.js` | `09-11-real` | React 受控输入写 textarea → 真机点发送 → 路由 |
| `p-del3.js` / `p-clean.js` / `p-dark.js` / `p-after-fix.js` / `p-modal.js` / `p-veil.js` / `p-webstate.js` | `09-11-real` | 删除链路 / 清理 / 深色 / 修复后状态 / 弹窗 / 蒙层 / 网页状态 |
| `probe-topbar.js` / `probe-layout.js` / `probe-top-band.js` | `09-10-real` | **定位真机顶栏缺陷三件套**：复刻开关判据逐条记录候选被哪条淘汰 / 打印滚动容器祖先链与顶栏带占用 / 顶栏带扫描（隐藏成功与否的客观判据） |
| `probe-sessions.js` / `probe-deep-session.js` / `probe-hide-topbar.js` / `probe-shell-state.js` | `09-10-real` | 锚点/分组/标题质量抽检、列表中部与末尾会话 id、临时隐藏顶栏并量兄弟容器是否位移、外壳总状态 |
| `p01-arch.js` ~ `p32-step.js`（**47 个**，编号带 `23a/23b/23c`、`08/09/11/13/15/17` 等多后缀） | `09-10-blur` | 第八轮分项探针：架构/`dock`/抽屉/行菜单/页脚/账号/**占位方案 `p13`~`p17`**/安全区/删除链路 `p24`/选单 `p26`~`p31`（2026-09-15 实测：该目录 `p*.js` 共 **47** 个，无其他 `*.js`） |
| `p1-buttons.js` / `p2-page.js` / `p3-map.js` / `p4-fileinput.js` / `p5-attach-check.js` | `09-11-upload` | 第十三轮：附件按钮与输入坞几何、页面骨架、**CSS→设备坐标映射标定**、`<input type=file>` 的 accept/multiple 全量、附件是否挂上（`input.files` + `blob:` 预览 + 上传中文本） |
| `dismiss-test.ps1` | `09-11-upload` | 半模态关闭判定：点「取消」/按返回键后 `dumpLayout` 里 `选择上传` 是否消失 + 进程存活 |
| `phase-analyze.ps1` / `edge-detect.ps1` / `anim-analyze.ps1` / `make-compare.ps1` | `09-11-upload` | 第十三轮动效取证四件套：**相位扫描差分**（点按后插不同 `sleep` 各抓一帧 vs 静止帧，输出差异带首行/最大差）、面板顶边检测、连拍与静止帧逐行差、生成上/下对比图 |

**构建 / 读数留档**

| 文件 | 位置 | 用途 |
| --- | --- | --- |
| `build-*.log` | `内部验证记录`、`内部验证记录`、`内部验证记录` | 各阶段构建输出留档（用于证明 0 error / 0 warning） |
| `perf-evidence.txt` | `内部验证记录`、`内部验证记录` | 性能 A/B 与各探针的**原始终端输出**（含"假证据"对照） |
| `perf-native-sidebar.txt` | `内部验证记录` | 原生侧栏开合对网页零成本的隔离读数 |
| `perf-ab-round7.txt` | `内部验证记录` | **第六轮同日复跑**（09-10 真机"第 7 次"复跑，不是第九轮；第九轮是 09-11）外壳状态 + A/B：`fastNode 403→0`、`drawerSkip 1784→2695`、`fixedScan 658→204`，`SHELL-2026-09-10: PASS` |
| `lay*.json` / `layout*.json` / `*layout.json` | 各目录 | `uitest dumpLayout` 原始树（坐标一律从这里现取，不靠目测） |

### 2.2 设备、端口与常用命令约定

- **真机**：HUAWEI Mate 70 Pro+（`PLA-AL10`，序列号 `DEVICE_SN_REDACTED`），HarmonyOS 7.0.0.105 /
  API 26，1316×2832 px、`devicePixelRatio = 2.975`、网页 CSS 视口 **443×952**（Web 全高铺底时
  **物理坐标 = CSS 坐标 × 2.975**，原点在屏幕左上角）。
- **模拟器**：`Pura 90 Pro`（1316×2832 / density 560）。第七轮时 `dpr = 3.5` → 视口 **376×719**；
  第五轮顶栏占位时 `vh 719 = 809(屏高) − 90.86(状态栏 38.86 + 原生顶栏 52)`。
- **hdc 路径**：`D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。
- **CDP 端口**：第九轮起固定用 `9283`（历史用过 `9233` / `9240`）。取 pid：
  `hdc shell "cat /proc/net/unix | grep webview_devtools"` →
  `webview_devtools_remote_<pid>`（**主进程 pid**）→
  `hdc fport tcp:9283 localabstract:webview_devtools_remote_<pid>`。
  端口被占（`TCP Port listen failed`）就直接换一个新端口，别纠缠 `fport rm`。
- **安装与冷启动**：`hdc install -r <signed.hap>` → `aa force-stop com.example.deepseekhm` →
  `aa start -a EntryAbility -b com.example.deepseekhm`；深色/浅色 `--ps colorMode dark|light`。
- **取证三件套**：`uitest dumpLayout`（原生控件真实 bounds/text）+
  `uinput -T -c x y`（真实触摸）+ `snapshot_display -f x.jpeg`（**只接受 `.jpeg`**）；
  网页侧一律 ArkWeb DevTools CDP，不靠肉眼推断。

### 2.3 方法论（比脚本更重要）

1. **逐帧采样必须同时读"子元素 computed opacity + 设备级截屏"**：纯 opacity 动画的闪屏，
   几何（rect / padT / 圆角）逐帧采样看不见（第四轮的漏诊）。
2. **CDP `Page.startScreencast` 在 ArkWeb 上每轮只回 1 帧（不可用）**：改用
   `Page.captureScreenshot` 顺序 burst（≈100ms/张）+ rAF 时间戳对齐。
3. **负坐标判据的 bug 会同时出现在产品代码和验证脚本里**，两边都要修：
   旧 `shell-assert.mjs` 的 `findToggle` 在真机返回抽屉内 `x=-181` 的点，
   `dispatchTouchEvent` 打在屏外 → **A/B 两相皆 0 却判 PASS**（假证据）。
   本项目真的这样"通过"过一轮，所以断言脚本自己也要被审。
4. **A/B 实验的触发源必须可靠**：官方 ☰ 对合成事件完全不响应，且抽屉本就打开 →
   靠 `Input.dispatchTouchEvent` 触发 class 突变会两相都读到 0。
   第九轮起改为**直接 add/remove 抽屉的 `collapsed` 类**（这正是旧适配器观察器监听的突变源）。
5. **A/B 实验里别重建被测元素**：循环里 remove + 重新 create 会让
   `window.__dshNativeDrawer` 指向已摘除的旧节点，`contains()` 恒 false → 两轮读数一模一样（假阴性）。
   要"建一次、复用同一引用"。
6. **性能探针对象不能在注入闭包外整体替换**：探针对象在闭包里被捕获，
   外部 `window.__dshPerf = {…}` 替换对象会让写入端与读取端分家、读数恒为 0。
   正解：提供 `__deepseekHmPerfReset()` **原地清零**。
7. **注入脚本先做语法预检**（`check-injected-js.mjs`）：能在装机前拦住
   "注入脚本静默抛错、整条链路失效"这类最难查的故障。
8. **验收必须至少补一次真机真实触摸**（`uinput -T -c x y` 后回读 `document.activeElement` /
   视口高）：`dispatchEvent` 合成事件不经过命中测试，全屏遮罩挡不住它 ——
   自动化会一路"通过"而真人点不动。
9. **关键动作要加效果回读**：tap 后校验目标 class/尺寸/状态真的变了，否则"成功"可能只是
   "本来就是这个状态"（官方抽屉默认打开态就把 `prewarm()` 的空动作掩盖了很久）。
10. **自动化断言别拿"列表第一条"当"最新一条"**：列表在打开瞬间可能还没抽到最新项，
    而且会保留上次的滚动位置（第十一轮因此两次选错行/找不到行）。
    一律按**标题或 id** 定位目标，并用**操作前后的 id 差集**断言"只动了目标"。
11. **"钉住布局"类修法要用长草稿再跑一遍**（输入框会变高），否则容易修掉一个视觉问题、
    引入一个可用性问题。
12. **模拟器专用的导航限制要认清**：`/sign_in` 页顶栏是 ← 不是 ☰ 且有路由守卫
    （`history.pushState` 到 `/` 会被立刻弹回）→ 模拟器上点不到原生侧栏入口，
    需要 `--ps action openSidebar` 这类显式钩子。
13. **`onErrorReceive` 只认主框架**：子资源失败（如 `ERR_INTERNET_DISCONNECTED`）会把已加载页
    盖成错误页。涉及 `pages\Index.ets` 的 `ErrorPane` 触发条件。
14. **验证产物一律放文档镜像目录**：本工程所有截屏/脚本/读数都落在
    `内部验证记录\`，`entry\src` 保持干净（**2026-09-15 实测**：`entry\src` 共 **17 个文件**，
    其中 `main\ets\` 为 **9 个 `.ets`** —— 命令 `find entry/src -type f | wc -l`；
    旧版此处写"第七轮 16 → 17"，但第十五轮新增的 `common\ShellUi.ets` 也计在内，
    **逐轮历史数字请以 `CHANGELOG.md` 对应轮次为准**）。**历史教训**：工程内 `verify\` 曾积累 15302 个 `.cdp-*`
    headless 浏览器 profile（2.6GB）、`iconwork\.tmp1-4`，**已于 2026-09-11 整理时删除**；
    临时 profile / 截图一律放 `%TEMP%`。
15. **比截图周期更短的动效，用"相位扫描"而不是连拍**（第十三轮）：`snapshot_display`
    实测 **265ms/帧**（缩小分辨率也一样，是管线固定开销），而官方半模态进场约 300ms，
    连拍只能撞到 1 帧、根本量不出曲线。做法：同一动作重复 N 次，每次在点按后插不同
    `sleep`（0 / 0.08 / 0.16 / 0.24 / 0.32s）各抓一帧，再**与"已静止帧"逐行差分**，
    看差异带首行与最大差是否单调收敛 —— 单调收敛即"确实在播动效"，差值恒为 0 即"没有动效"
    （改造前那个系统窗就是 8 帧全同、差值恒 0）。脚本：`phase-analyze.ps1`。
16. **判定弹层开关用 `dumpLayout` 的文本节点，不靠目测**：半模态/对话框是本应用窗口内的
    原生节点，`uitest dumpLayout` 能读到标题文本（`选择上传`），出现/消失即开/关；
    而**系统**弹窗（如 ArkWeb 自带的文件选择窗）不在本应用窗口里，dump 里根本查不到 ——
    这本身就是"它是系统窗"的判据。
17. **改坐标前先重取几何**：网页输入坞的附件按钮在有附件时会下移（`(1002,1648)` →
    `(1003,1761)`，键盘弹出时又是另一套），一律先用 CDP 读矩形再换算设备坐标
    （`物理 = CSS × 2.975`），否则会把"点在输入框上"误判成"应用没反应"。

---

## 3. 注入脚本的维护要点

两个注入脚本是本工程与官方网页之间的**唯一契约面**，改它们等于改产品：

| 脚本 | 位置 | 规模（末次记录） | 触发时机 |
| --- | --- | --- | --- |
| `SHELL_JS` | `utils\ShellScript.ets`（`export const SHELL_JS`） | 第十一轮 ~1234 行源码 | `Index.injectShell()`：`onPageEnd` / 避让区变化 / 原生显式 `rescan` |
| `MOBILE_ADAPTER_JS` | `utils\DeepSeekConfig.ets` | 第十一轮 ~1742 行源码 / 注入体 1603 行 | 同上（`onPageEnd` 注入） |

维护纪律：

1. **幂等**：`SHELL_JS` 开头检查 `window.__dshNativeShell.alive`，已存在则只 `rescan(true)` 后返回；
   样式注入走固定 `STYLE_ID`（`__dsh_native_shell_style__`），重复注入不叠加。
2. **观察器实例挂 `window` 跨注入复用**（`window.__dshPanelObserver` / `__dshMainObserver`）：
   适配器每次重注入都会新建闭包，旧写法会让观察器无限累积。
3. **注入体里禁止用正则字面量处理 CSS 值**：模板字面量里的反斜杠转义极易出错 ——
   遮罩判据用 `scrimAlpha()` / `isBlankScrim()` 手写解析，不用正则。
4. **改动后必跑预检**：`node check-injected-js.mjs`（还原模板字面量转义 → `node --check`），
   通过后再构建装机。
5. **状态与诊断字段是契约的一部分**：`window.__dshNativeShell.diag()` 返回
   `drawer / topbar / toggle / sessions / taps / route / prewarm / revealOff / scrims / bridge /
   topSpacer / pinned / fullH / innerH / deleteDriving / deleteArmed / modalSeen / sbHidden`；
   新增能力时同步扩 `diag()`，否则断言脚本无从下手。
6. **原生 → 网页的接口面**：`window.__dshShellApi` =
   `openSession(id)` / `newChat()` / `back()` / `rescan()` / `diag()` / `setInsets(top,bottom)` /
   `account()` / `openAccountMenu()` / `pickAccountOption(label)` / `closeAccountMenu()` /
   `deleteSession(id, token)` / `setDeleteToken(token)` / `clearDeleteToken()` / `reveal()`。
   **第十四轮变更**：`armDelete(on)` **已从页面对象上删除**（它等于把开闸能力交给页面）；
   删除改为一次性密钥模型：native 生成密钥 → 写 `window.__dshArm`（交接用，读走即删）
   → 同一次求值里调 `setDeleteToken` 校验并入库 → `deleteSession(id, token)` 比对。
   新增的 `setInsets(top,bottom)` 是避让区变化的**轻量通道**（不重跑脚本）。
   网页 → 原生：`window.dshBridge.post(json)`（`javaScriptProxy` 注册名 `dshBridge`），
   消息体 `ShellMessage`（`t` = `sessions` / `route` / `ready` / `log` / `account` / `deleted`）。
7. **新增"接管官方 UI"的能力时，三处必须一起改**：`markShell()` 里接管、
   `reveal()` 里摘标记（兜底把外壳交还用户）、`diag()` 里加可断言的字段。
   另：`diag()` 是**任何人都能调**的诊断口，安全相关的秘密（如删除密钥）**不得**进入它的返回值，只能暴露布尔状态。
8. **性能红线**：任何新增的热路径都要先过 `inNativeDrawer(el)` 短路 + `__dshShellOwnsChrome` 门控，
   并避免在新代码里出现 `querySelectorAll('body *')` 或逐节点 `getComputedStyle()` /
   `getBoundingClientRect()` 的组合（那是第五轮卡顿的根因）。
9. **避让区变化的轻量通道（第十四轮已做）**：`window.__dshSetInsets(t,b)` 只推两个数值 + 重跑两处几何修正，
   不再重跑整脚本；通道不存在（脚本未就绪 / 整页刷新清掉）时自动回退整注入。
   同批还把三次 `runJavaScript` 合并为一次、下发前剥离整行注释。
   **注意**：脚本逐行注释里不得出现反引号与 `${`（`§3.0-133`）。

---

## 4. 破坏性接口的"用户在场"安全闩

**背景**：第十一轮验证期间发生过一次**误删用户真实会话** —— 原因是我自己的 CDP 探针在官方隐藏
抽屉里留下一个展开着的「⋯」菜单，而当时的删除链路按文案点菜单项时命中了那一份
（详见 §1.3 第 31 条）。为杜绝"任何调试/自动化脚本顺手调一下接口就把用户数据删掉"：

- **网页侧**（`ShellScript.ets`）：**第十四轮重做**。密钥存在脚本闭包里（`ARM_SECRET`，
  由 native 经一次性交接变量搬进去，页面上读不到）；`deleteSession(id, token)` 的判据是
  `deleteTokenAssigned && state.deleteToken !== '' && token === state.deleteToken`，
  不满足则 `reportDelete(id,'locked')` **并回报**（旧实现静默返回，用户以为已删）。
  页面对象上**已无 `armDelete`**；`setDeleteToken` 只认与闭包密钥一致的值（否则 `rejected`）。
- **原生侧**（`Index.ets` + `SidePane.ets`）：**只有用户点了面板里的「选择」进入选择模式**，
  原生侧才 `rotateDeleteNonce()` 下发密钥；**唯一落门点是 `pumpDelete` 队列收尾**，
  退出选择模式 / 关面板时**若删除队列仍在跑则不落门**；
  `pumpDelete` 里必须**先下发删除、再换密钥**（调换顺序即整批失效，见 `§3.0-131`）。
- **验证方法**（第十四轮起用 `内部验证记录`）：三个攻击面各试一次 →
  不带密钥 / 自造密钥 均 `locked`，自造值与空串开闸均 `rejected`，
  **会话数与 id 差集均为 0**；顺带断言 `diag()` 里**不出现密钥本身**。
- **约定**：本工程任何新增的破坏性接口（删除、发送、清空、覆盖 user 数据）都**必须**照此加闩，
  并把"未开闸返回 `locked` 且数据不变"写成断言。
- **配套纪律**：按文案操作官方菜单的链路，动手前先要求"场上无残留菜单/弹窗"，
  收不掉就**中止**；每次破坏性操作都用**操作前后 id 差集**证明只动了目标。

---

## 5. 已知残留与未闭环问题（如实记录）

| # | 问题 | 现状 |
| --- | --- | --- |
| 1 | **网页侧 backdrop 不覆盖原生顶栏**：官方设置弹层打开时只压暗网页内容，原生顶栏仍为亮色 | 架构固有取舍（原生层在 Web 之上），未处理。**第十六轮进一步收窄**：用户要求侧栏账号菜单**只留「退出登录」**，「系统设置」「帮助与反馈」入口直接去除（点了不生效的死入口），本条的触发路径随之消失，优先级下降（见 `PROJECT.md` §4 与 `CHANGELOG.md` 第十六轮） |
| 2 | ~~`injectShell()` 重跑成本未实测~~ | **第十四轮已改**：避让区变化改走 `window.__dshSetInsets` 轻量通道（只推两个数值 + 重跑两处几何修正），且三次 `runJavaScript` 合并为一次、下发前剥离整行注释；真机读数见 `内部验证记录` §2.4。**⚠️ 第十八轮修正**：该通道此前**从未真的通** —— 宿主探的入口名 `window.__dshSetInsets` 全工程零定义，且回传值判据撞上 §3.0-153（带引号的 JSON 文本）恒假；本轮两处一起修好（见 §1.12 二），并做了三入口 + 负对照的运行时验证 |
| 3 | **真机与模拟器观感差异**：dpr 2.975 vs 3.5，圆角与磨砂观感可能有差 | **第十八轮已双机验收**（同一份 HAP）：模拟器 `27/0`、真机 `28/0`，四条 platform 差异见 §1.12 八。模拟器仍只用于快速迭代 |
| 4 | **第十一轮无法归因的会话减少**：滚动条排查期间会话数由 51 → 50（少了「现代城市水岸景观」） | 安全闩装好后复核：直接调 `deleteSession` 返回 `locked`、会话数不变，此后稳定在 50 未再变化 |
| 5 | **设备侧历史临时文件**：真机 `/data/local/tmp` 里若干早前轮次的 `burst*/cc.*/dsh_*` 文件 | 待用户确认后清理（工程目录内的 `verify\` 残留已于 2026-09-11 整理时删除） |
| 6 | ~~四个死资源~~：`shell_topbar_bg` / `shell_sidebar_bg` / `shell_scrim` / `shell_select_bar_bg`（base+dark 共 8 条）零引用 | **第十五轮已删除**（收口记录在第十四轮，实际执行在第十五轮）；2026-09-15 实测：四个名字在 `base`/`dark` 的 `color.json` 里各 **0 命中**、源码里也 0 引用，两份 `color.json` 现各 **16 条**（删 4 个 + 新增 `on_accent`） |
| 7 | **登录态依赖**：真实登录态是验证"从官方 DOM 抽取数据"类功能的前提 | 覆盖安装一律 `install -r`；确需 `uninstall` 前先确认登录态可弃 |
| 8 | **官方网页改版风险**：所有 DOM 选择器与几何判据都可能失效 | 已备通道：UUID 属性兜底 `extractByAttr`、`reveal()` 交还官方外壳、`diag()` 可断言；改版后按 §3 流程更新两个注入脚本 |

---

## 6. 一分钟速查（遇到问题先看这里）

| 症状 | 先看哪里 |
| --- | --- |
| 侧栏打开「闪一下」 | 先分清是**几何跳变**（CSS 首帧规则 §1.2-7）、**透底叠影**（`syncDrawerBackdrop()` + `::before` §1.2-8）还是**卡顿**（`inNativeDrawer()` 短路 §1.2-10）—— 混一起查必返工 |
| 侧栏打开「卡」 | `window.__dshPerf.fastNode` 应为 **0**；不为 0 说明有热路径漏了 `inNativeDrawer()` 短路或 `__dshShellOwnsChrome` 门控 |
| 整页发灰 / 面板与页面有色差线 | 先量三个值（面板 / 内容侧 / 参照物本色），再查官方抽屉的**兄弟遮罩**有没有一起接管（§1.3-29），最后才怀疑 tint（§1.2-17） |
| 「看得见却点不动」 | 查 Stack 层序（§1.2-23）、`SideBarContainer` 面板全高（§1.2-23）、全屏遮罩 `pointer-events`（§1.3-29），以及命令打在了哪台设备（§1.6-49） |
| 输入框位置不对 | `diag().pinned` + `innerHeight` + `ta` 矩形（§1.4-35/36） |
| 出现两条滑块 | `diag().sbHidden` 应为 2；用 `analyze-sb.ps1` 看深色像素是否为 0（§1.4-38） |
| 点附件没反应 / 弹层没动效 | 先看 hilog 有没有 `picker <kind>: …`（§1.7-61），再看是不是又回到「自绘覆盖层」（§1.7-58，应走官方 `bindSheet`）；选完没上传 → 查 `cacheDir` 有没有 `dsh-upload-*` 沙箱副本（§1.7-59） |
| 自动化「全绿」但真人点不动 | 补一次 `uinput -T -c x y` **真实触摸** + 效果回读（§2.3-8 / §3.0-81/82） |
| 官方 UI 又冒出来了 | 检查「本体 + 兄弟遮罩」是否成对处理、文档级 portal 是否需要 `data-dsh-delete-driving` 标记、`reveal()` 是否漏摘标记（§1.3-29/30、§3-7） |
| 顶栏下方一条带里点不动 | 先算 `topInset + TOPBAR_FADE_H(16)`：顶栏**容器**的命中面含那截装饰渐隐带。**第十八轮已根治**（根容器 `HitTestMode.None`，A/B 正对照 `got=0 ↔ got=8`）；复发先看该属性在不在（§1.12 一 / §3.0-159） |
| 在站点里切主题，原生外壳不跟 | 真机 `prefers-color-scheme` **恒 false**（站点用 `html.dark` 类）⇒ 要读站点**偏好**（`localStorage`）+ 映射 app `colorMode`，而不是只挂 `matchMedia`；另注意 hilog 是环形缓冲，判据要「切完 2s 内立刻读」（§1.12 五） |
| 改了代码但读数没变 | 先确认构建不是全 `UP-TO-DATE` 的假绿（要看到 `CompileArkTS` + `PackageHap` **都实际执行**，§3.0-163），再确认产物同步用**内容抽样**而不是 mtime（§1.12 七） |

## 7. 本工程条目 ↔ 通用坑表对照

本工程是下列通用坑的**首次实证项目**（原文已抽到 `内部踩坑表`，
锚点 `#3.0-N` 永久稳定；`AGENTS.md` §4 是其中最高频的摘要）。
本节只做定位，不复制原文：

| 本文件条目 | 通用坑 | 一句话 |
| --- | --- | --- |
| §1.2-8 | `#3.0-18` | 纯 opacity 动画的闪屏，几何逐帧采样看不见 |
| §1.2-12 | `#3.0-67` | `getBoundingClientRect()` 的 `left` 判据必须两侧都挡（负坐标最易漏） |
| §1.2-13 | `#3.0-68` | "隐藏一个容器"要取最外层匹配祖先，别在第一个匹配处早退 |
| §1.1-2 | `#3.0-70` | `body { padding-top }` 很可能无效，决定纵向起点的是 Web 组件位置 |
| §1.2-19 | `#3.0-74` | `backgroundBlurStyle` 是"材质"不是"模糊" |
| §1.2-20 | `#3.0-75` | `Stack` 默认 `alignContent: Center` |
| §1.2-21 | `#3.0-76` | Web 铺到屏幕顶会让 `env(safe-area-inset-top)` 变成状态栏高 |
| §1.2-22 | `#3.0-77` | 虚拟列表"内容顶部留白"不能用 `padding-top` |
| §1.3-31（旧版） | `#3.0-78` | "从子元素向上找行容器、再取第一个按钮"会打错目标 |
| §1.2-28 | `#3.0-79` | 遮罩压暗会把"本来同色的两个面"变成"有细线的两个面" |
| §1.5-41 | `#3.0-80` | `AlertDialogParamWithOptions` 的 `message` 是必填 |
| §1.3-29、§2.3-8 | `#3.0-81` | 全屏遮罩常是"本体的兄弟节点"，只隐藏本体等于没隐藏 |
| §1.3-33 | `#3.0-82` | "当前状态恰好正确"会掩盖"动作其实无效" |
| §1.2-17 | `#3.0-83` | 色差只有"tint 亮度贴近底色 + 低 alpha"一条路 |
| §1.2-18 | `#3.0-84` | 模糊半径会溢出组件边界 |
| §1.2-23 | `#3.0-85` | `Stack` 里覆盖层的先后就是命中顺序 |
| §1.6-49 | `#3.0-86` | `hdc` 多设备并存时命令会落到"另一台"设备上 |
| §1.4-35/36 | `#3.0-87` | ArkWeb 软键盘避让默认 `RESIZE_CONTENT`，布局视口真的会缩 |
| §1.3-30 | `#3.0-88` | 官方模态/下拉是"文档级 portal"，不属于被隐藏的抽屉 |
| §1.3-31 | `#3.0-89` | 官方下拉菜单单例复用且无归属信息 → 残留菜单会点错行 |
| §1.3-32 | `#3.0-90` | 隐藏容器里元素的 `getBoundingClientRect()` 可能是全 0 |
| §2.3-10 | `#3.0-91` | 自动化验证别拿"列表第一条"当"最新一条" |
| §1.4-38 | `#3.0-92` | 输入框"两条滑块"= 官方自绘滚动条 + 引擎 overlay 滚动条 |
| §4 | `#3.0-93` | 破坏性接口必须加"用户在场"安全闩 |
| §1.7-57/58 | `#3.0-98` | 不实现 `onShowFileSelector` 时 ArkWeb 的系统「选择上传」窗无进场动效；接管后要用官方 `bindSheet`，别自绘 |
| §1.7-59 | `#3.0-99` | 选择器 URI 是跨应用临时授权，必须落沙箱副本再 `handleFileList` |
| §1.7-60 | `#3.0-100` | `cameraPicker.PickerProfile` 字段运行期只读，必须对象字面量构造 |
| §1.6-46/50 | `#3.0-71`、`#3.0-73` | `uninstall` 会清 Cookie；真机 `USB Offline` 用 `hdc kill -r` |
| §1.1-5 | `#3.0-69` | `sys.symbol.*` 名字有 SDK 权威清单（`id_defined.json`） |
| §1.6-51 | `#3.0-10` | 真机与模拟器渲染可能有差异，容器渲染路径必须真机验证 |
| §1.1-3 | `#3.0-3` | 容器类网页适配用 `MOBILE_ADAPTER_JS` 兜底（本工程亦有实证） |
| §3 第 8 条 + §1.6-51 | `#3.0-10` | 真机与模拟器渲染有差异，容器渲染路径必须真机复核（**首次实证项目：DeepSeekHm**） |
| §2.2 | `#3.0-71`、`#3.0-72`、`#3.0-73` | `uninstall` 会清 Cookie / `fport rm` 对死 pid 无效 / `USB Offline` 用 `hdc kill -r` |
| §3 第 1/7 条 | `#3.0-130`、`#3.0-133` | 模板字面量里的单反斜杠会被静默吃掉；注入脚本要按"运行时字符串"断言、注释里不许有反引号与 `${` |
| §4 第 2/5 条 | `#3.0-131` | "先退模式、再抛请求"会把异步接口的安全闩提前落闩 |
| §3 第 5 条 | `#3.0-132` | 容器适配脚本必须做**顶层单例守卫**（多实例会叠加巡检） |
| §1.9、`PROJECT.md` §4/§12 | `#3.0-151` | 重叠布局里"铺满的兄弟容器"照样吃掉下层点击 —— 重写布局前先确认命中面等价（第十六轮真机 P0） |
| §1.9、`CHANGELOG.md` 第十六轮 §7 | `#3.0-152` | `ForEach` 里"数据字段"（必须进 key）与"`@State` 标记"（绝不要进 key）是**两条相反的刷新路径**；且 **`dumpLayout` 只导可见节点，"读不到"≠"没更新"**；无障碍字段**不是稳定判据**（第十六轮 B8） |
| §1.9、`CHANGELOG.md` 第十六轮 §9.3 | `#3.0-153` | `runJavaScript()` 回传的是**表达式结果的 JSON 文本**（字符串带引号）⇒ 全等比较恒假、**静默断链**（第十六轮第三批：账号菜单驱动链路 + 主题探测每次切深色整页重载） |
| §1.12-一、`CHANGELOG.md` 第十八轮 §3 | `#3.0-159` | 装饰性渐隐带算进容器高度 ⇒ 容器替它吃掉那一整条带里的点击；**第十八轮在原生侧根治**（顶栏根容器 `HitTestMode.None`）并做了 A/B 正对照（`got=0` ↔ `got=8`） |

**本工程未主张首次实证、但同样适用的条目**（原文见通用坑表，仅列编号避免重复）：
§3.0-1（`signingConfig` 必须被 `products[0]` 引用）、§3.0-2（材质 metadata 值必须小写 —— 首次实证
是 PrismAgent，本工程保持 `disable` 与本条无关，见文首"材质状态说明"）、§3.0-4~9、
§3.0-24（`@Watch` 初始化不触发 —— 首次实证是 PrismAgent；本工程在第七/十轮各复发一次，见 §1.2-25）、
§3.0-69（符号名查 SDK 清单）。

> 归属说明：本工程是 §3.0-10 / 18 / 67~93 / 98~100 / **130~133 / 151~153** 中最上面列出各条的首次实证项目；
> 同一条通用坑可能另有其他工程的实证，以 `内部踩坑表` 正文为准。
> 本工程**不修改** `内部踩坑表` 与 `AGENTS.md`（第十六轮例外：本轮由本工程文档负责人在
> Lead 授权下新增 `§3.0-151` 并同步 `AGENTS.md` §4 第 29 条）。
> **第十九轮再次例外**：由 Lead 授权新增 `§3.0-183 ~ §3.0-186` 四条并同步 `AGENTS.md` §4 计数与 §5 索引。

---

## 8. 第十九轮（2026-09-18 ~ 09-19）：Agent Teams 协作下的精简提速与 iOS 对齐

> 本轮的组织方式与历轮不同：**1 Lead + 4 teammate**，写作用域互斥（注入层 / 原生 UI / 主页面 / 只读审计），
> Lead 独占设备与构建。验收读数见 `内部验证记录`，
> 逐域改动见同目录 `W1-inject.md` / `W2-native-ui.md` / `W3-shell-core.md`，审计见 `tmp/r19-audit/REPORT.md`。

### 8.1 本工程首次实证的新通用坑（已沉淀）

| 编号 | 一句话 | 本工程实证点 |
| --- | --- | --- |
| `§3.0-183` | 注入脚本语法预检必须对**渲染后的文本**做（原文模型下 `/[\\s]+/` 与 `/[\s]+/` 都 PASS） | W4 的预检 v1 用模板原文 ⇒ 抓不到"转义被吃掉"；`原文−渲染` 差值恰等于模板内成对反斜杠处数（SHELL_JS 差 3、适配器差 18），可当转义指纹 |
| `§3.0-184` | 改一个布尔参数的传参时，必须列出它在**全部被调用者**里的分支 | `rescan(true)→(false)` 会顺带丢掉 `markShell` 的 `revealOff` 重置与 `reportRoute` 的强制补报；改 `collect()` 内部发送条件才语义最小 |
| `§3.0-185` | 静态体检的"无未使用 import"**≠**"可编译" | `pages/Index.ets` 整理 import 时误删仍在使用的 `GAP_XS`/`FS_BODY` ⇒ `COMPILE RESULT:FAIL{ERROR:3}`，只有真构建才暴露 |
| `§3.0-186` | 报体积必须写**口径**（`String.length` 是 UTF-16 码元数，不是字节） | PROJECT.md §10 旧行写 "46,013 B"；权威口径是"渲染后+剥注释"文本（43,914 字符 / 44,362 UTF-8 B） |

### 8.2 工程专属经验（本轮新增）

1. **跨写域接口变更会产生"编译不过的中间态"**：本轮删顶栏 `onShare` 时，`view/TopBar.ets`（W2 域）
   与 `pages/Index.ets`（W3 域）必须**按序**改 —— 先由接口方宣布变更、调用方再跟。**改完必须重跑完整构建**，
   否则"两边都报完成、实际编译不过"。
2. **`routeKind` 是桥消息 `route` 内部的字段、原样接收无白名单**（`Index.ets` 里 `typeof msg.kind === 'string' ? msg.kind : 'home'`）
   ⇒ **新增路由类别（如 `'settings'`）不需要改 `isKnownShellKind()`**。这条在派活时曾被 Lead 误判为"需要 W3 配合"，
   由 W1 查证纠正 —— **派活前先把"跨域影响面"查实，别凭直觉扩任务**。
3. **深色玻璃 alpha 9% 与"网页浅色"必然分裂**：W2 算式 —— `shell_panel_glass` dark `#1728282A`
   （alpha 23/255）+ 浅色网页 ⇒ 白字贴 `#ECECEC`，对比度 **1.16:1**（远低于 4.5:1）。
   **正解是让主题一致，不是改 alpha**（改 alpha 会推翻第十轮的逐像素定标）。
4. **iOS 对齐要拿第一手证据**：本轮不靠二手资料，而是抓 App Store 商品页 HTML → 下载官方截图原图 →
   逐张看图 + 放大裁剪。由此确认：iOS 顶栏**任何路由下左右各只有 1 个按钮**、会话页**没有分享**、
   首页**无标题**、附件是**三宫格**、**没有底部 tab**、iPad 截图**未呈现双栏**。
   ⇒ "参考 iOS"的正确姿势是**看原图**，不是凭印象或搜摘要。
5. **验收要按"每块各真实触摸一次"**：三宫格改完后，Lead 用 `uinput -T -c` 依次点三块，
   确认分别拉起**系统图库 / 文件选择器 / 相机** —— 合成事件或"看着像"都不算（§3.0-81）。

### 8.3 本轮未闭环（勿当成已闭环）

见 [`PROJECT.md` §13-B 第 0 条](PROJECT.md)：相机媒体类型偏差（刻意保留）、设置浮层关闭方向最多晚 200ms、
`onBackPress()` 留到下一单、P2-9 `boundedText`（已遏制未修）、首屏主题窗口期缺毫秒 A/B 读数、
深色 alpha 的边界分支、平板双栏未实测。

---

## 9. 第二十轮（2026-09-25 ~ 09-26）：顶栏改由官方 `Navigation` 标题栏承载 + 官方沉浸光感

> 用户诉求（原文）：「**标题栏和页面有明显分界线，不好看，改为沉浸式**」＋ 先前定的「以后 UI 优化默认使用官方材质、优先查官方文档」。
> 组织方式：1 Lead + 4 teammate（基础设施 / 顶栏改造 / 真机验证 / 文档），Lead 独占设备与构建。
> 交付口径：[`specs/UI-DESIGN.md`](specs/UI-DESIGN.md) §2.1；逐点裁决：[`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md)；
> 真机基线与工具链：`内部验证记录`（**证据力按该文件自己的标注，不升格**）。

### 9.1 本工程首次实证的新通用坑（已沉淀）

| 编号 | 一句话 | 本工程实证点 |
| --- | --- | --- |
| `§3.0-254` | `uitest dumpLayout` 把节点**顶边钳在状态栏下沿**（137px）—— 拿转储顶边当几何会系统性少算一整条状态栏 | 本轮标定顶栏时**第一次误判就栽在这里**：`Web` 铺满整屏（`innerHeight`=2832=整屏）却报 `[0,137]`。三条独立判据（网页自证 / 源码高度自证 / WMS 窗口全屏）才把它钉死 |
| `§3.0-255` | `Navigation` 标题栏**可用高 = 112 − 状态栏**（46vp 机上 = 56vp），请求更高会被钳成同一个 166px ⇒ **网页让位量不能按自己那行的高算** | 构造器请求 66vp 与 56vp 落点完全相同；让位量最终按 `112−46=66` 算（`topInset + NAV_TITLE_SLOT_VP`） |
| `§3.0-256` | 应用级 `UIMaterial.state=enable` **不是空闸门**：它把「默认开启清单」（**含 `bindSheet`**）一起翻到材质档，且材质**优先于**这些组件自身的 bg/blur/shadow/border | 改 `enable` 前按 SDK 原文核对出 `bindSheet` 在清单里 ⇒ 上传半模态的观感变化被登记为**必须真机复核**的接入点 |

> **追加（2026-09-25，verify 独立核出 → `REPORT.md` §8）**：`§3.0-256` 的「同名不同入口」小节已按 verify 的行号级核对订正 ——
> aa-hm 清单 §0-J 把「`undefined` = 恢复组件默认材质」挂在 `common.d.ts:22632-22633` 上，**该行原文与它相反**；
> 它的**结论**（隐藏态须显式 `Material.empty`）作用的是 `Tabs` 那个**可选字段**入口，可以并存，**但引用挂错了行**。

### 9.2 工程专属经验（本轮新增）

1. **开关名要写「我这档用什么」，不要写「我正在切换的那个东西」** —— R20 踩到的实例：
   `view/TopBar.ets` 的 file-local const 原名 `TOPBAR_BAR_MATERIAL`，而它 `true` 的实际含义是
   「**框架栏**供给模糊、**我们自己的 Row 不挂任何材质**」（`topBarTitleOptions()` 走 `backgroundEffect` 分支、
   `OfficialBar()` 里 `.systemMaterial(...)` 传 `undefined`），`false` 才是「Row 挂节点级材质」。
   ⇒ **名字与语义相反**（旧语义是 true=Row 挂材质）。R20 已改名 **`TOPBAR_FRAMEWORK_BLUR`**（只动本文件 4 处）。
   **教训保留**：这类开关读错一次就会把 A/B 的两臂搞反，而**源码仍然自洽、能编译、能跑** —— 只有把三处引用
   （常量定义 / 选项分支 / `.systemMaterial` 的实参）**放在一起读**才发现。
2. **节点级材质「给整条栏上材质」这条路在本工程被真机否决**：它画出的是**有确定边界的圆角材质带**
   （自带顶/底缘高光），下缘就是一条可见接缝 —— 用户原话「标题栏和页面有明显分界线，不好看」。
   要「一片连续的糊化」就用**框架栏的 `backgroundEffect`**（纯模糊）；同型真机的逐像素剖面见
   `§3.0-250`（y=167 顶缘 255 / y=356 底缘 254）。
   ⇒ 本轮最终是「**框架栏供模糊 + 自建 Row 零自绘层 + 3 个按钮挂官方沉浸光感**」三段各管一段，
   **不是**「进栏就自动有材质」。
3. **「自绘栏 → 框架栏」迁移的几何标定方法（可复用）**：
   ① 判 `dumpLayout` 几何必须三判据合验（网页 `innerHeight` 自证 / 源码高度拼底边自证 / `hidumper -s WindowManagerService` 看窗口是否全屏）—— 见 §3.0-254；
   ② 让位量按「框架栏高 − 状态栏」（112−46=66）算，**不要**按自己那行的高（52）算，否则正文首行落进模糊区 —— 见 §3.0-255；
   ③ 「覆盖高度有没有变多」用**屏幕绝对 px** 比，且**先把改前基线的绝对区间量出来**（本轮：改前覆盖 0..338px）；
   ④ 命中丢包带用**网页侧探针 + `uitest uiInput click` 逐点点击、读回 `clientY`** 量，不要用「看着能点」；
   ⑤ 标定结论要**写进源码注释**（数值 + 实测命令 + 判据），否则下一个人会凭想象调常量。
4. **栏覆盖区是否吃网页点击 —— 结论要按 verify 的口径写，别写成「无回归」**：
   · **可断言（强）**：栏下缘之下 **y=350 穿透成功**（系统级点击 + 网页内 click 探针回读 `probe=1`，落点 CSS 221,117 = 物理 657,348）；y330..400 **无任何原生可点节点**（`REPORT.md` §2.5(c)/§2.5(d)）。
   · **可断言（中）**：栏覆盖区 0..332 **整体不吃给网页**（同法实测 `probe=0`）。
   · ⚠️ **不可断言**：「这是不是回归」—— verify **未做同口径的改前对照**（设备按要求已装回默认包，未再装旧包/对照臂）⇒ `REPORT.md` §7-1 明写「不可断言是否为回归」。
   ⇒ T2 自述的「改前 y≤335 丢包 / 改后 y≤332 丢包 ⇒ 332<335 无回归」**只能作 T2 自述**，
   它当时的原始产物在 `%TEMP%`（**未进 `verify-*`**）⇒ **不要把「无回归」当成本轮结论**。
5. **「判材质有没有画出像素」的方法论（本轮 verify 的关键贡献，判据必须这样写）**：
   ① **ROI 必须排除左右按钮**：同一构建两次冷启动，含按钮的整条噪声底是 **MAE 5.24 / max 249**
   （按钮图标抗锯齿的 ±1px 抖动），而**中段** `200,137,900,201` 只有 **MAE 2.68 / max 5 / 0 个超阈值像素**；
   ② ⇒ 改后中段 MAE **明显 > 5** 才算材质真的改变像素，2.68 以下不算；
   ③ 跨包对比必须固定**路由 + 页面态 + 滚动位次**（实测两次冷启动连网页问候语都不同）；
   ④ 别用 `uiInput click` 的返回码当「点中了」的判据（用 dump 节点数变化回读：94→167）。
   读数与脚本：`内部验证记录` §4.3 + `tools/roi-mae.mjs` / `tools/tap.mjs`。
   ⚠️ 该目录自己标注的证据力弱点**照抄**：「设备上 `entry.hap` 的 md5 取不到（`Permission denied`）⇒ 只有时间戳对应，非内容同一性（证据力：中）」。
6. **「材质画没画出来」的判据必须能被单变量回答 —— 原定臂被证伪后换臂的完整过程**（本轮最有价值的一课）：
   ① **原定臂无效**：「IMM vs OFF 顶栏中段 MAE」**不能**回答本问题 —— OFF 臂的 `DrawnBar` **同样带 `backgroundEffect`**，
   两臂中段本来就都模糊。实测 IMM vs OFF = **0.26**、IMM vs 改前基线 = **0.26**，离群的反而是 SEAM 臂（light 2.25 / dark 10.22）。
   ⇒ **先问「这个对比里唯一变量是什么」**；两臂都有同一个绘制层时，中段 MAE 结构性地接近 0。
   ② **「有没有滚动」必须回读**：`uitest uiInput swipe` 两次都没让网页滚动（CDP scroll 事件 = 0）⇒ 取到的其实是静止图；
   正解是**用 CDP 直接设 `scrollTop`** 把正文滚到栏背后（`tools/scroll-capture.mjs`）。
   ③ **换臂后成立的判据 = 同一帧内「栏内 vs 栏外」+ 跨臂单变量**：同一行网页正文的横向梯度 `gradX`，
   OFF 臂 **8.523**（未模糊）vs IMM 臂 **0.374**（被糊）⇒ **22.8×**（dark 23.8×）；**同帧对照区** y340:360 三臂 `gradX` 完全相等
   ⇒ 内容与滚动位次一致，差异只能归因于栏。另有跨臂栏外整体校验 **MAE = 0.0022**（max 10 / 15 px >8）。
   ④ **噪声底要分档**：同页面态（同会话页同滚动位次）**0.26 / max 3~4**；跨冷启动（站点问候语不同）**2.68 / max 5** ——
   早期那个 2.68 里其实混进了页面态变化 ⇒ 「MAE > 5 才算画出像素」只对跨冷启动比较成立。
   ⑤ **固定阈值单列剖面不敏感**：`--jump 12` 在四臂上全 0 hit，而 SEAM-dark 实有 **68 级**硬边 ⇒
   行级特征必须**按行平均**（宽 ROI 逐行均值 + 最大一阶差分 + residual 带，见 `§3.0-250` 的判据族）。
7. **同一轮里「用户拍板」可以覆盖派活时写死的硬约束 —— 但因果链必须写进文档**：
   本轮原硬约束是「网页可读区上方被原生覆盖的高度**不得超过改前**」，最终落地是 **+14vp**（97.71vp → 111.71vp）。
   正确写法是「用户真机反馈 → 形态取舍 → 代价 +14vp」，**不是**「实现需要所以扩了」；
   原硬约束的记录**保留**（标明被本轮覆盖及原因），不静默删除。

### 9.3 T3 真机独立验证结论（**原文引用**，证据力照抄 `REPORT.md` §0/§3）

验证人 = **verify**（独立于执行人 topbar）；三臂 = **IMM**（交付默认）/ **SEAM**（有接缝，用户已否决）/ **OFF**（回退），
三臂为**干净单变量 A/B**（HAP 解包 14/16 条目逐字节相同；源码侧 IMM vs SEAM 只差 `TopBar.ets`、IMM vs OFF 只差 `ShellUi.ets`），
且三个常量臂**都真机构建装机**过（不是静态审查）。

| 结论 | 证据力 |
| --- | --- |
| 应用级开关生效：构建产物 `module.json` 里 `UIMaterial.state` = `"enable"`（改前包 = `"disable"`） | **可断言（强）** |
| **交付默认臂无新增分界**：IMM-dark 逐行均值最大一阶差分 **5.26 @ y=77**（状态栏图标行），与改前基线 **5.25 同位置同量级**；y=332 处仅 2 级 | **可断言（强）** |
| **被否决的 SEAM 臂复现用户描述**：SEAM-dark **68.37 @ y=167** + 次峰 **52.00 @ y=322**，residual 带 49 行覆盖 y150..331 = 全宽硬边亮带 | **可断言（强）** |
| **框架栏模糊真的糊住正文**：同一行 gradX OFF **8.523** / IMM **0.374** = **22.8×**（dark 23.8×）；同帧对照区三臂 gradX 完全相等；栏外 MAE **0.0022** | **可断言（强）** |
| 几何：`window.__dshTopInsetPx` = **111.714287**（×dpr = **332px**），转储网页首个容器顶边 **333px**（改前 **291px**） | **可断言（强）** |
| 交互：侧栏钮真实点击 + 效果回读（节点 **97→170**）；「新建对话」整屏 MAE **16.84** / 15.06% 像素变化 | **中-强** |
| 栏下沿触摸穿透：y=350（栏下缘之下 18px）被网页收到（probe=1）；y330..400 无原生可点节点 | **可断言（强）** |
| 崩溃：hilog **无本应用** jscrash/CppCrash/FaultLogger 命中（全是 `com.huawei.hmos.aidataservice` 噪声） | **可断言（中）**（环形缓冲） |
| 用户第二次反馈「又出现很明显的分界线了」的归属 | **可断言（时间线）**：对照臂在机窗口 **15:25:56.831 → 15:30:32.705** ⇒ 他看到的是 **SEAM 臂** |
| 改后与改前「观感等价」 | ❌ **不可断言**（只有中段数值等价 MAE 0.26，无用户观感样本） |

### 9.4 本轮未闭环（勿当成已闭环）

- ~~材质在真机上是否画出像素 / 是否出现硬边~~ —— **已由 T3 验证**（见 §9.3 前两行，均「可断言（强）」）；
- **顶栏覆盖区（0..332px）内的网页元素是否可点 / 是否回归**：**不可断言** —— verify 实测该区整体不吃给网页（probe=0，证据力**中**），但**未做同口径改前对照** ⇒ `REPORT.md` §7-1 明写「不可断言是否为回归」；
- **`other` 路由（子页/设置浮层）的返回键**：本轮未能稳定进入 `other` 路由（抽屉头部三钮未定位到设置入口）⇒ **未验证**（`REPORT.md` §7-2）；
- **观感裁定**：「是否好看 / 是否达成用户要的沉浸」**需用户本人看图裁定**（材料 `compare/*.png`，含 plain/enhanced 两版 + 3 臂 2× + 4×/8× zoom）；数值只能证到「默认臂无新增分界、对照臂复现用户描述」；
- **`lightEffect: { color: Color.White }` 是否在玻璃顶缘合成亮线**：未单独排除 —— 反例 `§3.0-13`（DshMobile 实测「锐利贯穿亮线」）；
- **按钮挂官方材质的可读性（洗白）风险**：未单独排除 —— 反例 `§3.0-58`。本工程按钮是 `TEXTUAL` 无实色底、`materialColor` 带 alpha，**情景不同但风险未消除**；
- **上传半模态（`bindSheet`）在 `enable` 档下的宫格观感变化**：真机未验证（`§3.0-256`）；
- **`TOPBAR_FADE_GUARD`「无需改动」是算式推断、非实测**：`让位量 + 20 = 131.71 CSS px = 392px > 丢包带下界 332px`，但**未真机打开设置面板**复核面板内交互件不被吃点击；
- **崩溃扫描证据力受 hilog 环形缓冲限制**（只覆盖本轮时间窗）；**模拟器未参与**（本轮全部结论仅基于真机）。

---

## 10. 第二十一轮（2026-09-28）：设置页底部功能栏改原生组件（参考 aa-hm）

### 10.1 为什么走自绘、不走官方 `Tabs` 底栏（两工程结论一致）

用户要求「参考 aa-hm 的底部功能栏，重新写设置页的功能栏」。aa-hm 的 `ui/BottomNav.ets` 文件头有一张三臂表：
官方 `Tabs` + `FloatingTabBarStyle.systemMaterial` 在本机型本位置 **Δ+0.0**、`barFloatingStyle` **未生效**，
而它**自绘的悬浮胶囊 Δ+16.0** ⇒ 它最终交付的就是自绘那条路径。

本工程还多一条更硬的理由：**设置页的内容在网页里**（chat.deepseek.com 的系统设置弹层）。
官方 `Tabs` 的 `TabContent` 是**原生页面容器**，挂不上网页内容 —— 页签只能用原生画、再反过来驱动网页。

### 10.2 隐藏网页元素供派发：**只有 `opacity: 0` 是安全的**

原生底栏点击要驱动网页切页签，就得对网页那一行页签派发 `dispatchEvent`。
三种隐藏方式的实测结论（本轮再次验证了 R17 的结论，见 §1.11-80）：

| 写法 | rect | `dispatchEvent` 命中 | 结论 |
| --- | --- | --- | --- |
| `display: none` | **全 0** | ✗（`tap()` 会退到祖先取坐标 ⇒ 点错元素） | 不可用 |
| `visibility: hidden` / `pointer-events: none` | 正常 | **✗** | 不可用 |
| **`opacity: 0`** | 正常 | **✓** | **唯一可用** |

位置：`utils/DeepSeekConfig.ets` 的 `[data-dsh-settings-tabs="1"]` 规则；
派发链路：`pages/Index.ets` `onSettingsTabSelect` → 桥 `setSettingsTab(i)` → `utils/ShellScript.ets` 的 `tap()`。

### 10.3 网页侧的「选中态」不可信 —— **以内容为准**

真机实测（2026-09-28）：网页设置弹层**每次打开渲染的都是第 1 项的内容**，
而它自己的选中 hash 类会**残留上次的值** —— 一次读数就是「内容 = 通用设置、hash = 服务协议」，
**网页自身就不一致**。第一版底栏跟着那个残留态高亮（`syncSettingsTabFromWeb`），
用户看到的是「高亮服务协议、内容却是通用设置」（证据 `内部验证记录`）。

修法：**以内容为准** —— 进入设置页时归 0 并**幂等派发**一次点击（React 对同一页签重复点击不重渲染）。
于是「高亮 = 内容」这条不变量成立，且不依赖网页侧那个会漂移的残留态。
位置：`pages/Index.ets` 的 `onSettingsOpened()`（取代原 `syncSettingsTabFromWeb()`）。

> **可复用判据**：凡「原生状态要跟随网页状态」的链路，先确认网页那个状态**是不是显示真相**。
> 本工程已经踩过两次同族问题：§1.11-80（浮层逃出祖先链）与本条（选中类与内容不一致）。
> 网页的「记录态」和「显示态」是两件事，能读显示态就别读记录态。

### 10.4 底栏令牌与色值（为什么不能复用面板玻璃）

- 令牌 `TABBAR_*` 在 `common/ShellUi.ets` §9：高 54 / 图标 22 / 文字 11fp / 留边 12% / 磨砂 18 / 全圆角；
- **`TABBAR_BLUR`(18) 与 `TOP_BAR_BLUR`(6) / `PANEL_BLUR`(24) 分开**：aa-hm 的教训是「共用的 6 对 54vp 的底栏太轻」；
- **不复用 `shell_panel_glass`**：它的 alpha 25% 是为「与页面底色配平」定标的（R10），
  叠在设置页底色上会几乎不可见 —— aa-hm 踩过同款（它家 `glassSurface` 25% 近白在近白页面上 Δ=0，故单开了 `glassNavSurface`）；
- 新增 4 色 `shell_tabbar_glass` / `_rim` / `_sheen` / `_sheen_clear`（深浅逐键成对）；
  **`_sheen_clear` 必须同 RGB、alpha=0**，用 `Color.Transparent` 会让渐变插值发灰（同 `shell_topbar_fade` 的教训）。

### 10.5 承载位置的最终结论：**ArkWeb 是独立合成图层，浮层挡不住它，必须走框架层**

（本节修正 §10.1-10.4 里那版「自绘悬浮胶囊」的承载判断 —— 形态与令牌仍然有效，**承载位置**变了。）

## 现象与三次试错

用户连续三条反馈：「底栏晃动时还是会被遮挡」→「将其置于最顶层」→「还是有问题」（附截图：底栏图标上半被裁）。

| # | 承载 | 结果 |
| --- | --- | --- |
| ① | 自绘悬浮胶囊（根 `Stack` 浮层，`justifyContent(End)`） | 图标被裁、晃动时被盖 |
| ② | 官方 `Tabs` 悬浮底栏（`barFloatingStyle.systemMaterial`） | 胶囊上半被裁（Tabs 高度装不下 `barBottomMargin`）；补高度后仍被盖 |
| ③ | **官方 `Navigation` 工具条**（`toolbarConfiguration`） | ✅ 完整、稳定 |

## 根因（本轮最有价值的一条）

`ArkWeb` 承载的是**独立合成图层**的内容。`Stack` 里的普通原生浮层与它重叠时，
**图层关系在页面滚动 / 内容切换这些时刻不稳定** —— Web 的图层会翻到原生浮层之上，
表现就是「底栏被裁一半 / 被盖住」。

⚠️ **纯 `Stack` 顺序解决不了**：把它移到根 `Stack` 的最后一个子节点（= 最顶层，见 §1.2-23 的层序规则）
**依然被盖** —— 因为那条规则管的是**原生层之间**的先后，管不到 Web 的独立图层。

**正解 = 挂到框架层**。本工程顶栏从 R20 起用 `Navigation` 的**标题栏**承载，从未被 Web 遮挡过 ——
这是同一套机制的现成旁证。底栏对应的是 `Navigation` 的**工具条**：

```ts
.toolbarConfiguration(this.SettingsToolbar(), settingsToolbarOptions())
.hideToolBar(this.routeKind !== 'settings')
```

**可复用判据**：某原生 UI 要被 Web 盖住时，**先看它是不是在框架层**（`Navigation` 标题栏 / 工具条、
`SideBarContainer` 的面板）；不在就搬进去，而不是去调 `zIndex` 或 Stack 顺序。

## 两条配套细节（都是真机量出来的）

1. **工具条自身不避让底部安全区**：实测底栏文字 `y 2780~2818` 与系统手势条 `y 约 2734~2832` **叠在一起**。
   修法：builder 的高度与内边距都算上 `bottomPad`（EntryAbility 下发的底部避让），框架按内容撑高工具条。
2. **工具条整条铺底色 + 栏内胶囊 = 两层**：胶囊的圆角边界在底色带上几乎看不出来。
   ⇒ 工具条设 `Color.Transparent`，可见表面交给栏内的悬浮胶囊（`backgroundEffect`，
   与顶栏自绘回退档同一套四参数）。**保留 aa-hm 的悬浮胶囊形态，只换承载位置**。

## 工具条上的两个实测坑

3. **`TabContent` 里不能直接放 `Blank()`**：编译报 `10905201`（Blank 只能嵌在 `Row`/`Column`/`Flex` 里）；
   也不能写空的块容器（`§1.10-77`）。用「带属性的 `Column()`」这种合法空容器。
4. **`@Builder` 的值参数不重建**（`§3.0-38`）在工具条上同样成立：选中态**不能**由父级当参数传下去
   （工具条内容是 `@Builder`，参数变了子项也不重建）。用 `@StorageLink` 同一个键，两端各自订阅。

### 10.6 工具条承载的两条真机实测（都是「设了不生效」型）

用户反馈「底栏没有沉浸，页面底部颜色要统一」——两个问题各自的根因：

**① `NavigationToolbarOptions.backgroundColor` 在 CustomBuilder 模式下不生效。**
工具条是**占位式**的（Web 视口被它压短），设透明就会在它下面露出原生 `Stack` 的 `bg_page`
（浅色下**纯白 255**），而设置页底色是浅灰 **241** ⇒ 胶囊一圈与最底部那条明显更白。
⚠️ 给 `toolbarConfiguration(builder, options)` 的 `options.backgroundColor` 赋值**没用**
（实测那一条仍是 255）⇒ **底色要在 builder 的根容器上自己铺**。
修后读数（浅色）：页面底 / 胶囊带外 / 最底部**三点全是 242,243,245**，完全一致。

**② `systemMaterial`（官方沉浸材质）在本位置会「接管背景却画不出材质」。**
给胶囊挂上 `officialImmersiveMaterial(...)` 之后，胶囊的像素差只剩 **Δ+1.8**（与底色几乎同色、**胶囊等于消失**）
—— 因为材质接管了 `backgroundColor` 却没在这个位置画出表面。
与 aa-hm「官方材质在本机型底部位置 **Δ+0.0**」的记录一致（`§3.0-245`：材质不在这个位置的生效范围内）。
⇒ 表面用 `backgroundEffect`（官方 API 口径，与顶栏自绘回退档同一套四参数）；
玻璃色 alpha 由 90% 降到 **70%**（`#B3FFFFFF` / `#B3202023`）⇒ 半透明磨砂 + 18vp 模糊 + 发丝亮边。
修后读数：胶囊内 **251** vs 底色 **242** = **Δ+9**（可见的玻璃面）。

**③ 一条能力边界（如实记）**：工具条是占位式的 ⇒ 页面内容不会从底栏背后穿过，
那层 18vp 模糊**在纯色背景上没有可糊的内容**，观感上主要表现为「半透明白 + 亮边」。
这是位置决定的（浮层能从背后穿过，但浮层会被 ArkWeb 独立图层遮挡 —— 见 §10.5），不是参数没生效。

### 10.7 「零消费者令牌」是丢功能的探测器（底栏光效）+ 一次多余的点击派发（转圈）

**① 零消费者令牌 = 功能丢失的信号。**
用户报「底栏没有光效」。查下来是**我改承载时丢的**：aa-hm 悬浮胶囊的四要素
（全圆角 / 磨砂 / **同源渐变光层** / 亮边）里，我把承载从自绘换成官方工具条时只留了后两条，
而 `TABBAR_SHEEN_ANGLE` / `TABBAR_SHEEN_MID_STOP` / `shell_tabbar_sheen*` **一直是零消费者**。

> **可复用判据**：改造一处组件后，**扫一遍新引入的令牌有没有消费者**。
> 本工程一直有「零消费者常量要删」的纪律（第十七轮删 `SHADOW_DY_MD`、第十八轮删 `PRESS_SCALE`），
> 但那条纪律的**反向用法**同样重要 —— 一个刚加过、改完就没人用的令牌，往往意味着**功能被改丢了**，
> 不是「该删的冗余」。本轮若早扫一眼，这条反馈根本不会产生。

**② 一次「幂等派发」引发的每次转圈。**
用户报「系统设置里有些界面每次打开都会刷新一下，转个圈再显示」。
元凶是 `onSettingsOpened()` 里那句 `callApi('setSettingsTab(0)')` ——
写它的本意是「对齐高亮」，但它是给官方页签的一整套**真实点击序列**，
官方 tab 收到后会**重新挂载内容页**，需要拉数据的页签于是每次打开都转圈。

> **可复用判据**：**「幂等」不等于「无副作用」**。
> React 对同一 tab 的重复点击确实不会重渲染**同一份**内容，但**重新挂载**是另一回事；
> 而且在容器工程里，「我们派发一次试试」这类动作的成本往往落在**官方组件的生命周期**上，
> 不是落在我们自己的 DOM 上。凡是「为了让状态对齐」而派发的事件，先问：**不派发会怎样？**
> 本轮答案是 —— 目的本来就已满足（网页每次打开都渲染第 1 项），派发纯属多余。

**③ 验证手法：MutationObserver 抓「有没有重挂载」，并**必须带对照组**。**
阅读数：打开设置页 `added:0, removed:0, runs:0`；点页签切内容 `added:5, removed:4, runs:2`。
对照组是必需的 —— 没有它，「零变动」既可能是真结论，也可能是**观察器没生效**的假读数
（同族教训：判据恒真的源码闸门）。

### 10.8 「界面每次打开都转圈」的正确查法：**抓请求**，而不是猜 DOM

用户反馈「系统设置里有些界面每次打开都会刷新一下，转个圈再显示」。

**第一轮我猜错了**：怀疑是自己那次多余的点击派发（`setSettingsTab(0)`），删掉后回「都没解决」。
复查才发现：打开设置页时**DOM 零变动**（`added:0, removed:0, runs:0`）—— 那只说明「没有重挂载」，
**不能推出「没有重新取数」**。转圈是**网络往返**造成的，DOM 观测看不见它。

**正确查法（本轮）**：hook `XMLHttpRequest.prototype.open/send` 记录 URL + 方法。
一次就抓到真凶：官方每次打开设置页都要重新拉
`/api/v0/users/settings`、`/api/v0/chat/tts/voices`、`/api/v0/users/get_birthday`（三个 XHR GET）。

> **可复用判据**：用户描述「闪一下 / 刷新一下 / 转个圈」时，先分清楚它属于哪一类：
> ① **重挂载**（DOM 观测）② **取数**（hook XHR/fetch）③ **重绘**（看 style/class 变动）。
> 三类的观测手段**完全不同**，拿 ① 的「零变动」去否证 ② 是本轮最贵的那个错。

**修法**：白名单（三个 URL）+ 短 TTL（90 秒）的内存缓存，命中时**伪造 XHR 响应**、不发起真实请求。
读数：第 2 次打开 `hits:3`（全命中），改设置后 `keys:[]`（安全阀）。

**安全阀的坑（同一轮踩到）**：第一版判据写成「设置面板内任何点击都清缓存」——
而**关闭设置页要点面板头部的 ✕**（也在面板内）⇒ 每次关闭都清一次 ⇒ 缓存永远命中不了
（实测：关闭后 `keys=[]`、第二次打开 miss 3→6、hits 恒 0）。
⇒ 判据必须收紧到**「改设置值」的那类控件**（`data-dsh-settings-row/seg/group`），
页签与关闭钮都不清。**「清缓存」这种安全阀，判据越宽越容易把自己废掉。**

### 10.9 「没有光效」的正确排查顺序：**先查生效范围，再查绘制层序**

用户连续三轮反馈「底栏没有光效」，我前两轮都在**自绘参数上试**（换 alpha、加投影、加渐变），全是白费。
第三轮用户直接点破：「仔细查阅官方文档，不要费功夫写一些没用的代码」。

**第一步：查生效范围（`§3.0-245` 引的官方原文）**

沉浸光感只有四类位置生效：①弹窗类 ②`Slider`/`Toggle`/`Select` ③`Navigation`/`NavDestination` **标题栏**
④横向 `Tabs` 且 `barPosition = End` 的**底部 TabBar**。**其他区域一律不生效（静默）。**

⇒ 底栏挂在 `Navigation` **工具条**里 —— 工具条**不在四类中**。先前实测「挂 `systemMaterial` 后胶囊 Δ+1.8」
**不是 API 用错、也不是材质坏了**，而是它根本不在生效范围。**这一条一查就能下结论，不必做实验。**

> **可复用判据**：一个「官方效果没出来」的问题，**第一问是「这个组件在不在官方给的生效位置上」**，
> 第二问才是「参数对不对」。本工程 `specs/MATERIAL-ACCESS-POINTS.md` 已经把这份清单整理成表（含 SDK 一手行号），
> 动手前先读它 —— 它存在的意义就是让后来者不必重做这三轮。

⚠️ 同条还有一条容易漏的：材质**不要与 `backgroundColor` / `borderColor` / `borderWidth` / `shadow` 同用**
（材质会把它们接管）。我先前给胶囊挂材质时**同时还画着发丝亮边**，两套语义在打架 —— 这也是「材质没效果」的候选原因之一。

**第二步（确认走自绘后）：查绘制层序，而不是继续调色值**

照搬 aa-hm 的三层渐变后光效仍不可见，量竖直剖面才找到真因：

| 写法 | 胶囊内竖直梯度 |
| --- | --- |
| 渐变与 `backgroundEffect` **同节点**（aa-hm 的写法） | **2 级**（223→225，方向还反了） |
| **独立高光层**（`Stack` 内装饰层 + `HitTestMode.None`） | **5 级**（229→226→224，顶部亮向下衰减） |

> **可复用判据**：`linearGradient` 与 `backgroundEffect` 挂在**同一节点**时，前者几乎不出效果。
> 要让光带可见，就把它做成**独立层**（这也是 aa-hm 在 `GlassIcon.ets` 里对光弧的处理方式 ——
> 它在底栏上用了同节点写法，那条观感本来就含蓄）。

**第三步：注意「照抄数值 ≠ 照抄效果」的两个耦合项**

1. **alpha 要按对方的实证读数取，不是按 color.json 的现值**：aa-hm 的 `glassNavSurface` 现值是 2.4% 黑（Δ-6，几乎不可见），
   而它 `Design.ets` 注释里记的定点依据是 **7.8% 黑 ⇒ Δ-19.7** ⇒ 取依据档 `#14000000`，实测 Δ-16 ✓；
2. **渐变角度与元素宽高比耦合**：`SHEEN_ANGLE = 145` 是给满屏宽胶囊的；本工程胶囊 851×161px（5.3:1），
   145° 会让渐变近乎水平 ⇒ 竖向零梯度。改 0°（自上而下）。

**能力边界（记死，别再试）**：工具条占位 ⇒ 内容不从底栏背后穿过 ⇒ 磨砂**没有可糊的内容**。
在本工程底栏这个位置，光效上限就是「纱 + 光带 + 亮环」这套自绘配方；
想要「玻璃折射背后内容」的效果，必须先解决 ArkWeb 图层与浮层的矛盾（见 §10.5），那是结构问题不是参数问题。

### 10.10 底部 TabBar 的两个「静默失效」：受控 `index` 与脱离文档流的派发目标

底栏最终落在官方 `Tabs` 底部 TabBar（材质生效的第 ④ 类位置）。此前两次没走通，
原因都在实现层，且**都不报错**——记录如下，避免重蹈：

**① `Tabs` 的高度必须 = `barHeight` + `barBottomMargin`。**
`barHeight` 只表达胶囊自身高度；`barBottomMargin`（离底间隙）**也在 bar 带内**。
只给 `barHeight` ⇒ 胶囊上半被裁（实测图标整条不可见）。

**② 派发目标不能脱离文档流。**
网页侧那行页签（`opacity:0` 的派发目标）一度被改成 `position:fixed`（配合占位式工具条），
结果**桥调用返回 `ok` 但内容不切**。CDP 量 rect 才发现：`fixed` 后页签行落在视口底、
rect 看似有效，但**派发的 click 不再被官方 React 处理**（成因未深究，现象可稳定复现）；
改回**文档流占位**（`order:2`）后立刻恢复。

> **可复用判据**：给「藏在 opacity:0 里的元素」派发事件前，先用 CDP 量一次它的 `rect` 与
> `position`——**脱离文档流的元素，事件派发可能静默失效**；文档流里的才是已验证路径。

**③ 材质生效的最终确认（浅色）**：胶囊内 231.8（Δ-10），且带**上暗下亮的官方折射渐变**
（231.8 → 240.9）—— 这正是 `FloatingTabBarStyle.systemMaterial` 的玻璃质感，
自绘渐变（上一版 223→225 的 2 级梯度）做不出来。
