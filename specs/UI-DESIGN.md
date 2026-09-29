# DeepSeek 鸿蒙端 · UI 设计规范（iOS 参考）

> 第十六轮（2026-09-15）建立。本文件是**原生外壳**的 UI 契约：所有原生页面的视觉与交互
> 都按这里写的执行，数值一律取自 [`common/ShellUi.ets`](../entry/src/main/ets/common/ShellUi.ets)。
> 现状见 [`PROJECT.md`](../PROJECT.md)，踩坑见 [`EXPERIENCE.md`](../EXPERIENCE.md)。

---

## 0. 适用范围与前提

本工程是 **ArkWeb 容器 + 原生外壳**：

| 层 | 归谁渲染 | 本规范是否覆盖 |
| --- | --- | --- |
| 聊天区（会话内容、输入框、官方弹层） | `chat.deepseek.com` 网页 | ❌ 不覆盖（只通过注入脚本做移动端适配，见 `utils/DeepSeekConfig.ets`） |
| 原生顶栏、侧栏、启动页、错误页、上传半模态、轻提示 | 本工程 ArkUI | ✅ 全部覆盖 |

**设备尺度前提**：目标机 1316×2832 / density 560 ⇒ **1vp = pt**（有效宽 376vp ≈ iPhone 12 mini 的
375pt）。所以 iOS HIG 的 pt 数值可以**一对一**搬进 vp，无需换算。

---

## 1. 总原则

1. **能用官方组件就不自绘。** 自绘意味着自己承担无障碍、按压反馈、动效、深浅色、
   焦点与热区全部细节，历史缺陷几乎都出自"手搓了一个本可以用官方组件的控件"。
2. **一切数值来自令牌。** 不写裸魔数；需要新语义时先在 `ShellUi.ets` 加常量并注明依据。
3. **动效服务于层级，不服务于炫技。** 每个动效回答一个具体问题（"它从哪来""我刚按到了吗"
   "我在等什么"），答不上来就不要加。
4. **深浅色必须双值成对。** `resources/base/element/color.json` 与
   `resources/dark/element/color.json` 的 key 集合必须**逐键一致**，颜色一律走 `$r('app.color.*')`。
5. **改动必须可验证。** 视觉类改动附截图（浅色 + 深色），交互类改动附真实触摸的效果回读。

---

## 2. 导航栏（顶栏）

| 项 | 值 | 依据 |
| --- | --- | --- |
| 高度 | `TOP_BAR_H` = 52vp（不含状态栏避让） | iOS 导航栏 44pt + 8vp 呼吸；与官方网页顶栏 60px 尺度对齐（第六轮真机实测） |
| 左右内边距 | 左 `GAP_SM`(8) / 右 `GAP_SM`(8) | 让 44 的圆形按钮的视觉边缘与屏幕边缘留出呼吸 |
| 标题 | `FS_TITLE`(16) / `FontWeight.Medium` / 单行省略；**首页不显示标题** | iOS 导航栏标题 17pt semibold 的中文等价档；iOS 首页顶栏中间整条留空（官方截图实证，R19） |
| 图标按钮（可点） | `ICON_BTN` = 44×44、`ButtonType.Circle` + `ButtonStyleMode.TEXTUAL`，底色透明 | iOS HIG 最小触控 44×44 |
| 图标按钮（可见圆） | `ICON_BTN_VISUAL` = 40vp，色 `icon_btn_bg`（浅 `#F2F2F3` / 深 `#2A2A2C`），圆内图标 `FS_ICON_BTN`(18)；**按下整圆变暗**为 `icon_btn_bg_pressed`（浅 `#E4E5E8` / 深 `#3A3A3D`），`MOTION_FAST`(150ms) 过渡 | R19：iOS 顶栏按钮是「**圆形浅底 + 图标居中**」，可见圆约 40pt 而可点区仍 44pt ⇒ **观感与触控分成两档**（`ShellIconButton(…, raised=true)` + `ShellIconHotRegion` 把热区补回 44）。按压语义是 **iOS 的"整个圆变暗"**（不是缩放、也不是只有图标变淡），故圆必须是按钮**自己的底色**（画成子节点就收不到 pressed 状态），且 `stateEffect` **必须取 `false`**（**不要顺手改回 true**）。依据是 SDK 原文（`component/button.d.ts:320-324` 的 `stateEffect` NOTE）："When the pressed state effect is enabled and a custom pressed state style is configured, the resulting color displayed after pressing is a **composite blend** of the original background color and the newly defined pressed state color." ⇒ 开着它看到的是"原底色 ⊕ 按下色"的**混合**结果，拿不到精确的 `icon_btn_bg_pressed`，深浅两态观感不再可控。**可见圆只用在顶栏**（侧栏头部无 iOS 抽屉参考素材 ⇒ 保持裸图标），但**按压语义两者相同**（见 §3.2 第 1 条）。 |
| 底边线 | **无**（不画） | 第十六轮第三批已删除；**R20 起官方档连渐变过渡带（`TopBarFadeBand()`）也不再使用** —— 官方模糊的边缘已接替「抹平磨砂方块下缘」这个职责，留着它会在自己的边缘再产生**第二条分界**（见 §2.1） |
| 背景 | **官方沉浸档（默认）** = 框架标题栏的 `NavigationTitleOptions.backgroundEffect`；**自绘回退档** = 悬浮 `backgroundEffect({radius: TOP_BAR_BLUR, color: $r('app.color.shell_topbar_glass')})` | 两档与回退开关见 §2.1；两种都**禁止**用 `backgroundBlurStyle`（那是「材质」会接管 `backgroundColor`，见 §7 第 1 条） |

**接缝纪律（最容易出事的地方）**：`TOP_BAR_H` 同时决定 ①原生顶栏高度 ②下发给网页的
`topInset + TOP_BAR_H` 下移量。两侧**必须同源**，单独改一处会在顶栏下沿露出网页底色。
同类接缝还有侧栏上沿（= 顶栏下沿），见 §3。

**标题：居中优先，长标题也不再早截断（R19 收敛）**。
iOS 导航栏标题居中，本工程照做：单层 `Row` 三槽，左右槽**等宽且固定**
（`SLOT_W = ICON_BTN + GAP_SM = 52`），标题槽 `layoutWeight(1)` 居中 —— 因为左右槽等宽，
剩余空间的中心就是屏幕中心，标题严格居中且**不随路由漂移**。

**`SLOT_W` 96 → 52（R19）**：旧值 `ICON_BTN*2 + GAP_SM`(96) 是按"右槽最多两个按钮
（新建 + 分享）"定的。R19 按 iOS 去掉分享后右槽**恒为 1 个按钮**，槽宽随之收敛，收益直接落在
标题上：标题可用宽度 `376 − 52×2 − 16 ≈ **256vp**`（原 ≈ 168vp，≈ 10~11 个汉字 @ `FS_TITLE`），
与 iOS 实测标题槽 250~290pt 同档 —— **iOS 三张会话页官方截图里的长标题都不截断**，旧值则会截断。
槽宽取 52 而非 44：仍留 8vp 安全垫，不做"零余量精确贴合"（零余量时任何尺寸微调都会静默溢出被裁，
§3.0-141）。

**不要试图用"左槽只放 1 个按钮就收窄左槽"这类办法兼得** —— 左右槽一旦不等宽，居中立刻失效。
`other` 路由下左槽只放 1 个按钮、却仍占满 `SLOT_W`，这是**刻意留白**（换来标题位置恒定），
不是"布局没收拾干净"。**左右槽必须同时改**（两处都引用同一常量 `SLOT_W`）。

**按钮语义**（路由 → 左右槽）：

| `routeKind` | 左槽（固定 `SLOT_W`） | 右槽（固定 `SLOT_W`） | 标题槽 |
| --- | --- | --- | --- |
| `home` | 侧栏开关（自绘双横杠） | 「新建对话」`plus_circle` | **不渲染**（iOS 首页顶栏留空） |
| `chat` | 侧栏开关 | 「新建对话」`plus_circle` | 会话标题 |
| `other`（登录/条款等子页） | 返回 `chevron_left` | **不渲染**（刻意留白） | 文档标题 |
| `settings`（设置页浮层，R19 新增） | **不渲染**（刻意留白） | **不渲染**（刻意留白） | 文档标题（网页侧发 `title:'系统设置'`） |

**"不渲染但仍占满 `SLOT_W`"是刻意留白**：左右槽等宽才能让标题槽的中心等于屏幕中心，
所以某个路由少一个按钮时**不能**把槽改窄（那会让标题随路由漂移）。
`settings` 下左槽刻意不放"关闭"——设置页浮层自带 × 关闭入口（网页侧渲染），
顶栏再放一个会出现两个语义相同的关闭控件。
**「分享会话链接」已于 R19 从顶栏移除**（iOS 官方截图实证：首页与会话页顶栏右槽都只有 1 个按钮、
会话页右槽就是「新建对话」，没有分享；用户已拍板按 iOS 走）——分享入口此后只在网页区的消息操作条里。

**首页不显示标题**（R19）：iOS 首页顶栏中间整条留空。标题槽仍然占位（`layoutWeight(1)`），
所以"留空"不影响居中，也不影响会话页/子页的标题。

### 2.1 承载结构与材质档位（R20 起：官方沉浸档为交付口径）

**承载结构（官方档）**：`MainPane.build()` 用 `Navigation() { <内容层> }`
+ `.title(this.TopBarTitle(), topBarTitleOptions())` + `.hideToolBar(true)` + `.mode(NavigationMode.Stack)`
+ `.titleMode(NavigationTitleMode.Full)` + `.backgroundColor(Color.Transparent)`；顶栏那一行是 `TopBar(official: true)`。
**为什么必须"进栏"**：官方沉浸光感**只在 `Navigation`/`NavDestination` 标题栏（或横向 Tabs 底部 TabBar、弹窗类接口）里生效**，
挂在页面正文里的普通容器上是**静默无效** → `§3.0-245`。

**两个 `systemMaterial` 入口不是一回事**（别混用）：`NavigationTitleOptions.systemMaterial` 的作用面是**标题栏**那一组视觉属性；
`CommonMethod.systemMaterial` 才是「挂在哪一行就作用于哪一行」。本工程顶栏两条路各用一个入口（见下表），口径来源见
[`MATERIAL-ACCESS-POINTS.md`](MATERIAL-ACCESS-POINTS.md) §0-E/E2。

| 档 | 开关 | 栏本体 | 栏内按钮 | 状态 |
| --- | --- | --- | --- | --- |
| **官方沉浸档**（默认交付口径） | `OFFICIAL_MATERIAL = true` ＋ 调用点 `official: true` | 模糊由**框架标题栏**供给：`topBarTitleOptions()` 里的 `NavigationTitleOptions.backgroundEffect`（`radius` / `saturation` / `brightness` 与改前同值 + 同一个 `shell_topbar_glass` 令牌）；自建 `Row` **零自绘层** | 3 个按钮走 `ShellIconButton(..., official: true)` / `MenuButton` 官方分支 ⇒ `.systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))`（`style: THIN` / `interactive: true` / `lightEffect` 白） | 交付 |
| **节点级材质档**（A/B 对照，**已被用户否决**） | `TOPBAR_FRAMEWORK_BLUR = false` | 框架栏不画；材质挂**自建 `Row`** 的 `CommonMethod.systemMaterial` | 同上（按钮仍走官方材质） | 仅作 A/B 对照与一行回退 |
| **自绘回退档** | `OFFICIAL_MATERIAL = false`，或调用点 `official: false` | `TopBar.DrawnBar()`：自绘 `backgroundEffect` 磨砂 ＋ `TopBarFadeBand()` 渐变过渡带（与 R19 逐字相同） | `ShellIconButtonDrawn`（底色 ＋ `stateStyles` 按压） | 回退路线，**始终留在树上** |

**「谁在画底」的可机械核验口径**：默认档在自建 `Row` 上**显式**写 `.systemMaterial(undefined)`
（`CommonMethod` 上 `undefined` 的原文语义 = **no-material effect**，`common.d.ts:22632-22633` / `:22642`）——
这是「**显式声明本行不挂材质**」，**不是**「忘了写这一行」；`grep -n "systemMaterial(TOPBAR_FRAMEWORK_BLUR" view/TopBar.ets`
能同时看到两档的实参（true ⇒ `undefined`；false ⇒ `officialImmersiveMaterial(...)`）。
⚠️ **同名不同入口**：`Tabs` 的 `FloatingTabBarStyle.systemMaterial`（`tabs.d.ts:895`）是**另一个入口**，
它的 `undefined` 语义是「恢复默认材质」、要关闭必须用 `Material.empty` —— **不要把两处结论互套**（详见 `内部踩坑表` §3.0-256`）。

⚠️ **为什么默认档不用节点级材质**（用户真机反馈，R20）：节点级 `systemMaterial` 会画出**有确定边界的圆角材质带**，
下缘就是一条可见接缝（用户原话「**标题栏和页面有明显分界线**」）；同型真机的逐像素剖面见
`§3.0-250`（顶/底缘高光 255 / 254）。⇒ 取「框架栏连续模糊」，代价见下条。

**几何契约（R20 变更，用户真机拍板）**

- 框架栏在 `.titleMode(Full)` 下 = 窗口顶 **0..112vp（含状态栏那 46vp）** ⇒ 网页侧让位量改为
  **`topInset + NAV_TITLE_SLOT_VP`（66vp = 112 − 46）**：`pages/Index.ets` 的 `injectShell()` / `pushInsets()`
  与 `ErrorPane` / `NewChatTipLayer` **四处同一个常量、同一个算式**；
- **因果链（如实记录，不许写成"实现需要所以扩了"）**：用户真机反馈「标题栏和页面有明显分界线，不好看，改为沉浸式」
  → 形态取舍（框架栏连续模糊，正文首行不落进模糊区）→ **代价**：让位量 97.71vp(291px) → 111.71vp(332px)，**+14vp**；
- ⚠️ **原硬约束「网页可读区上方被原生覆盖的高度不得超过改前」已被本轮用户拍板覆盖** —— 记录保留，不静默删除；
- 框架给标题栏构造器的**可用高只有 56vp**（顶边被框架锚在 166px）：见 `§3.0-251`、
  `§3.0-255`；
- 承载容器（`TopBar.OfficialBar()` 的 `Column`）**必须保留** `.hitTestBehavior(HitTestMode.None)`（自身不吃、子节点照吃）→ `§3.0-159`；
- ⛔ `Mini` / `Free` 都不可用（`§3.0-247`）；⛔ 不要给那条 `Row` 挂节点级 `systemMaterial`（`§3.0-250`）；
  ⛔ 不要再补自绘渐变过渡带（会在自己的边缘产生第二条分界）。

**真机结论（R20，T3 独立验证，证据力照抄）**：默认臂**无新增分界**（逐行均值最大一阶差分 **5.26 @ y=77** ↔ 改前 **5.25**）；
被否决臂复现用户描述（SEAM-dark **68.37 @ y=167** + **52.00 @ y=322**）；框架栏模糊**真的糊住正文**（同一行 `gradX` **22.8×**，栏外 MAE **0.0022**）；
两个对照臂**都真机构建装机**过（回退路线可用）。原文与复跑命令：`内部验证记录`。

---

## 3. 侧栏（原生抽屉）

形态：**贴左、上避让状态栏、下避让手势条与输入法、右侧两角 `PANEL_RADIUS`(22) 圆角 + 右投影像素定标**。
避让在面板**外层容器**用一次 padding 完成，内部不再各自补 inset。

### 3.1 列表（inset grouped）

| 项 | 值 |
| --- | --- |
| 列表左右内缩 | `LIST_INSET` = 8vp（面板约 308vp 宽，取 iOS 16pt 的等比例收窄值） |
| 行高 | `LIST_ROW_H` = 44vp（iOS 列表行标准，同时满足最小触控） |
| 行圆角 | `RADIUS_SM` = 10vp |
| 分组标题 | `FS_CAPTION`(12) / `shell_group_text` / 高 `GROUP_ROW_H`(30) |
| 分隔线 | `HAIRLINE` + 左内缩 `SEP_INSET`(16)：**不从边缘起画**，从内容起始处起画 |
| 激活行 | 文字 `accent` + `FontWeight.Medium`，底色 `shell_item_active_bg` |
| 按压态 | 底色过渡到 `shell_item_active_bg`，时长 `MOTION_FAST`(150ms) |
| 搜索字段底色 | `field_bg`（浅 `#E5E5EA` / 深 `#1C1C1E`）= iOS 中性灰 systemGray5/6 |

**为什么按压态用底色不用缩放**：这是 iOS 的语义（UIKit 的 `highlighted` 是变暗/变底色），
缩放会让列表在手指下"抖动"，且缩放的锚点问题会让长标题行视觉跳动。

### 3.2 面板结构（自上而下）

1. **头部** `ROW_H`(52)：品牌名（`FS_BRAND` 19/Bold）或选择模式计数（`FS_TITLE`）+ 图标按钮组。
   图标按钮组**不带可见圆**（无 iOS 抽屉参考素材，见 §2），但**按压语义与顶栏完全一致**：
   按下变 `shell_item_active_bg` 底色 + `MOTION_FAST`(150ms) 过渡。**这是有意的统一，不是待定项** ——
   顶栏按钮既然"可见圆 + 按下变底色"，侧栏头部保持同一套按压语义才不出现"同类控件两套反馈"
   （本工程一直在消灭的东西）。两处共用同一个 `ShellIconButton` 配方（第 4 实参 `raised` 区分观感）。
2. **发丝线**（左右内缩 `SEP_INSET`）；
3. **搜索**（非选择模式）：官方 `Search` 组件，高 36、`RADIUS_SM` 圆角；
4. **列表 / 空态**：空态用 `LoadingProgress` + `FS_LABEL` 文案 + 兜底按钮；
5. **底部条**：普通态是计数（`FS_FOOTNOTE`，行高 `GROUP_ROW_H`(30) —— 它只做语义、不是按钮行；
   R19 由 `BTN_H_MD`(44) 收敛到 30，计数因此紧贴列表下沿、账号行上移 14vp），选择态换成 `SelectBar`
   （`BTN_H_MD`(44)，装 32vp 按钮 + `responseRegion` 热区）。**代价**：两态高度不同 ⇒ 进入选择模式时
   账号行下移 14vp（与"搜索行消失 + 底部条换内容"同一次重排，已判定可接受）；
6. **发丝线**；
7. **账号行** `ROW_H`：头像 28 + 昵称（`FS_LABEL`）+ 尾图标 `sys.symbol.ellipsis_circle`（圆圈三点，
   通用的"更多操作"）。**不要用 `sys.symbol.more`** —— 它在 SDK 里是 2×2 方块网格（读作"应用/网格"），
   R19 用 SDK 自带符号字体逐个渲染核对后订正。

### 3.3 账号菜单（第十六轮收口）

账号行点击弹出**官方动作菜单** `UIContext.getPromptAction().showActionMenu()`（R19 由居中
`AlertDialogParamWithOptions` 改来）：手机上它渲染为**底部弹出的动作菜单**，正是 iOS 的 action sheet 形态；
标题 = 用户名，**没有副标题**（旧实现那句"这些操作会直接在 DeepSeek 官方页面上执行"是写给实现者看的，
iOS action sheet 也没有副标题，R19 删除）。取消（点菜单外/返回键）必须同样收起官方网页菜单 ——
回传形态不唯一（`index < 0` 与 Promise reject 两种），**两条路都要兜**。

按钮为**白名单两项**：「系统设置」+「退出登录」（`shell_danger` 色）。两项都**不是自由入参**：
原生侧（`Index.onPickAccountOption`）与桥侧（`ShellScript.pickAccountOption`）各有一道**同一份白名单**，
只有这两个字面量能下发，保证可驱动面是封闭集合（§3.0-93 同源）。
「帮助与反馈」**维持移除**：它同样要驱动隐藏抽屉里的官方菜单项（多一层异步渲染 + 文案匹配，
命中率不稳定），用户实测"点击后不生效"。
两项都走同一条链路，并保留 140ms×8 的重试与失败 toast。

---

## 4. 动效

| 场景 | 时长 | 曲线 | 说明 |
| --- | --- | --- | --- |
| 按压 / 勾选 / 选中 | `MOTION_FAST`(150) | `CURVE_STD` | 只回答"我按到了吗" |
| 淡入淡出、元素进出、气泡 | `MOTION_NORMAL`(250) | `CURVE_STD` | iOS 默认转场时长 |
| ~~面板 / 整屏转场~~ | ~~`MOTION_SLOW`(350)~~ | — | **第十八轮删除**（零消费者）：面板开合由官方 `SideBarContainer` 自己的动画负责（见本节末条）。将来若真需要整屏级转场，按"同一语义一个值"重新引入 |
| 启动页编排 | `MOTION_SPLASH`(420) | `CURVE_STD` | 鲸鱼放大+淡入，配合逐字跳出（200ms/字） |
| 会话列表行进/出场 | `MOTION_NORMAL`(250) | `CURVE_STD` | **第二十一轮新增**：官方 `TransitionEffect`（`listItemTransition()`）——进场"从底缘滑入+淡入"、退场"淡出"（位移会与补位行对穿）。只作用于 ForEach key 变化触发的插入/删除，不影响行内按压/选中过渡（那条仍走 `.animation()`） |

**硬性要求**：

- 曲线一律 `CURVE_STD`；**不要 `Curve.Linear`**（线性运动在 UI 里显得机械）。
- 动画只能改**不参与排版**的属性（`opacity`/`scale`/`translate`/`backgroundColor`）；
  改 `width/height/padding` 的动画会每帧重排，是掉帧的主因。
- 条件渲染（`if`）没有可播的过渡（挂载即终值）。要过渡就用**常驻 + opacity/translate**，
  并给该层 `hitTestBehavior(HitTestMode.None)` 保证它不吃点击（首页「已是新对话」气泡即此配方）。
  ⚠️ **但这句只对"该层里全是纯展示内容"成立**：`HitTestMode.None` 的语义是"**自身**不参与
  命中测试、**子节点仍然参与**"，因此它**不能**让"内部装着可点元素"的覆盖层整体穿透。叠层
  里**每一个铺满的兄弟容器**都要各自处理，漏掉一个就整片区域失效 —— 第十六轮顶栏 P0 就是
  只给了标题层、漏掉两个同样铺满的按钮组（详见 §7 第 9 条）。
- 面板开合由 `SideBarContainer` 官方动画负责，**不要**自己在面板上再套一层 transform 动画。
- **装饰性区域不要计入可交互容器的命中面**：顶栏的 `TOPBAR_FADE_H` 渐隐带是纯视觉层，但它的父容器（顶栏根 `Column`）
  高度含它 ⇒ 整块参与命中测试、把带子里送往下层的点击吃掉（第十八轮已用 `.hitTestBehavior(HitTestMode.None)` 根治；
  `None` = 自身不吃、子节点照吃）。新增任何"容器高度含装饰段"的层，都要问一句：**它的命中面该不该等于它的视觉范围**。
  判定只能用真实触摸 + A/B（`dumpLayout` 里 `clickable` 一律为真、构建 0 warning），见 §3.0-159。

---

## 5. 官方组件清单（该用哪个）

| 需求 | 用官方 | 不要 |
| --- | --- | --- |
| 搜索框 | `Search`（自带 `searchIcon`/`cancelButton`/`$$` 双向绑定、≥40vp 清除热区、`searchButton` 提交键 **第二十一轮新增**） | `Row{ SymbolGlyph + TextInput + 自绘 × }` |
| 会话列表 | `List` + `ListItem`（可选 `ListItemGroup` + `.sticky(StickyStyle.Header)`）；行进/出场挂官方 `TransitionEffect`（`listItemTransition()`，**第二十一轮新增**） | `Column` + 手动滚动 |
| 底部半模态（上传来源） | `bindSheet` + `$$` 双向绑定 + `SheetSize.FIT_CONTENT`；内容为 iOS 式**三宫格**（拍照 / 相册 / 文件，等宽 `Column` + `RADIUS_LG`(16) 圆角 + `TILE_H`(76) 高 + `TILE_ICON`(26) 图标在上、文字在下） | 自绘全屏覆盖层、"三行列表"式半模态 |
| 确认对话框 | `UIContext.showAlertDialog`（`AlertDialogParamWithButtons`/`WithOptions`） | 自绘对话框、已废弃的 `AlertDialog.show` |
| 动作菜单（账号操作等"选一项"） | `UIContext.getPromptAction().showActionMenu()`（`promptAction.ActionMenuOptions`） | 居中 `AlertDialog`（iOS 用底部 action sheet，不用居中弹窗） |
| 轻提示 | `getPromptAction().showToast()` | 自绘气泡（除非需要锚点定位，那用 `bindPopup`） |
| 图标 | `SymbolGlyph($r('sys.symbol.*'))`，符号名必须查 SDK `id_defined.json` 实证 | 文本字符当图标（如 `'⋯'`）、自绘图形 |
| 设置页底部功能栏 | **官方 `Navigation` 工具条承载 + 栏内悬浮胶囊**（`view/SettingsTabBar.ets` 提供数据/图标/工具条选项，`pages/Index.ets` 的 `SettingsToolbar()` 画胶囊）。**第二十一轮最终档**。承载位置的定论见 [`EXPERIENCE.md`](../EXPERIENCE.md) §10.5：`ArkWeb` 是**独立合成图层**，`Stack` 浮层（哪怕放最顶层）会被它盖住/裁切，**必须搬进框架层** —— 工具条与本工程顶栏（`Navigation` 标题栏）同级。形态仍是 aa-hm 的悬浮胶囊（全圆角 = 高/2 + `backgroundEffect` 磨砂 + 亮边，令牌 `TABBAR_*`），但**工具条自身设 `Color.Transparent`**（整条铺底色会与胶囊叠成两层），并用 `bottomPad` 避让系统手势条 |
| 加载中 | `LoadingProgress` | 自绘转圈 |

**图标唯一例外**：顶栏菜单的"**两条**横杠、上长下短、左端对齐"自绘（`MenuGlyph`）。
R19 重新穷举了 SDK 全部 4042 个符号名并**逐个渲染核对造型**：`line_2_horizontal` 是两条**等长**、
`line_3_horizontal` 是三条等长、`text_alignleft` 是**四条**、`align_left` 是"竖线 + 两条粗杠"、
`line_text_alignleft` 是"竖线 + 四条" ⇒ **没有"两条、上长下短、左对齐"的符号**，做不出来，只能自绘。
（该按钮同样要带无障碍三件套。）

> **旧定标为何被推翻（写清楚，免得后来者再翻烧饼）**：第十六轮这里自绘的是**三条**横杠
> （19/16/13，居中错落），理由写作"系统符号 `line_3_horizontal` 等都是等长造型，做不出 iOS 那种长短款"。
> 但那时工程**没有任何 iOS 对照素材**，三条是**自定值**。R19 拿到 iOS 官方 App Store 截图原图
> （`tmp/r19-audit/ios-shots/crop-topbar.png` / `crop-topbar-chat.png`，首页与会话页一致），
> 4 倍放大后**明确是两条**（上长下短、两条**左端对齐**）⇒ **有第一手素材时证据优先**，
> 三条改两条、居中改左对齐（Lead 定夺）。
> `MENU_BAR_W_MID` 作为**已导出常量保留不删**（RULES §1.5），但**已不参与绘制**；
> `MENU_GLYPH_W` 由 24 收敛为 `MENU_BAR_W_LONG`(19)（容器与长杠同宽 ⇒ 长杠在圆内居中、短杠左端对齐）。

---

## 6. 无障碍

每个**可点**的纯图标控件必须给三件套（缺一不可，实测口径见 `EXPERIENCE.md`）：

```ts
.accessibilityText(label)          // 读屏取名字的正式属性
.accessibilityDescription(label)   // uitest dumpLayout 里唯一读得出来的字段（自动化断言用）
.accessibilityLevel('yes')         // 保证能被读屏聚焦（默认 auto 会跳过纯图标按钮）
```

列表行给 `accessibilityText(row.text)` + `accessibilityDescription('当前会话' | '会话')`。
**新增任何可点组件都要补**：audit 曾测出全工程无障碍覆盖为 0。

---

## 7. 禁止事项（违反会造成静默故障或返工）

1. **`backgroundBlurStyle` 不是"模糊"而是"材质"**：它自带近乎不透明的遮罩并接管
   `backgroundColor`（alpha 调到 0 都无效），会把背后的网页内容整片盖掉。纯模糊用
   `backgroundEffect` / `backdropBlur`。→ `§3.0-74`
2. **材质 metadata 值必须小写**：`module.json5` 的 `ohos.arkui.UIMaterial.state` 写大写
   会被系统**静默忽略**（探针读到的 `state` 仍是 `DEFAULT=0`）。**本工程 R20 起为 `enable`**
   （此前刻意 `disable`；打开它的**代价**见第 10 条与 `§3.0-256`）。
   → `§3.0-2`
3. **不要给"按内容撑开"的容器里的子节点写 `width('100%')`**：百分比按父 content-box 解析，
   会比父更宽，末个子项被挤出裁剪区（`dumpLayout` 里连节点都查不到）。
   → `§3.0-141`
4. **`ForEach` 的 key 必须包含所有会变的字段**（标题、激活态、勾选态）：key 相同就复用组件，
   只改标题的变化不会重建（侧栏标题停在旧值就是这么来的）。勾选态进 key 会导致全表重建，
   两者要平衡：**内容字段进 key，勾选态由行内自更新**。
   → `§3.0-138`
5. **`bindSheet` 的 `isShow` 必须是 `boolean`**，且只挂在页面根节点一个。
   → `§3.0-137`
6. **`@State` 只在 `build()` 读到它时才登记依赖**：靠"自增一个 tick"是无效写法。
   → `§3.0-134`
7. **`systemMaterial` 只许挂在生效范围内的位置**：`Navigation`/`NavDestination` **标题栏**、横向 Tabs 且
   `barPosition = BarPosition.End` 的**底部 TabBar**、以及**弹窗类组件/接口**（`bindSheet` / `bindPopup` / 各 Dialog /
   `Select` / `Toggle` / `Slider`）。**页面正文里挂是静默无效**（不报错、不告警），而官方档不画自绘层 ⇒ 会变成透明空壳。
   模拟器不受这条范围限制，只跑模拟器会漏掉。
   → `§3.0-58`、`§3.0-245`
8. **不要在 UI 线程上做全量遍历/测量**（网页侧注入脚本同理）：`querySelectorAll('body *')` +
   逐节点 `getComputedStyle` 是历史卡顿主源。
9. **能用"不重叠的排布"解决，就不要用"覆盖层 + `hitTestBehavior` 特判"**（第十六轮 P0 实证）。
   重叠布局里**每一个铺满的兄弟容器都参与命中测试、并阻断下层的兄弟** —— 只要有一个漏配，
   它覆盖的整片区域就失效。本工程真的踩过：顶栏为做"标题居中"改用 `Stack` 三层，只给铺满的
   **标题层**加了 `HitTestMode.None`，漏掉两个同样铺满的**按钮组** `Row` ⇒ 最上层的右按钮组
   吃掉整条顶栏的点击 ⇒ **侧栏完全打不开**（汉堡按钮 6 个点位真实触摸 + 连拍 5 帧全无反应，
   而同排的「新建对话」正常 —— 因为它就在覆盖层内部）；构建期 `0 error / 0 warning`
   **完全无感**。
   两条规则：
   - **首选不重叠的排布**：顶栏用"左槽 / 标题槽 / 右槽"的**单层 `Row`**，左右槽**等宽且固定**
     即可让标题严格居中 —— 命中面天然就是按钮本身，不需要任何 `hitTestBehavior`；
   - 确实必须用覆盖层时：**每一个铺满的兄弟容器都显式给出 `hitTestBehavior`**，并在写完后
     **对每个可点元素重跑真实触摸**（§3.0-81）。
   附一条本轮实证的语义细节：`HitTestMode.None` 是"**自身**不参与命中测试、**子节点仍然参与**"，
   所以它无法让"内部装着可点元素"的覆盖层整体穿透，只在"覆盖层里全是纯展示内容"时才够用。
10. **不要用节点级 `systemMaterial` 去"给整条栏上材质"**：它画出来是**有确定边界的圆角材质带**（自带顶 / 底缘高光），
   相邻两块各挂一层就是肉眼可见的分界（用户原话「标题栏和页面有明显分界线」，R20 据此否掉了默认档）。
   要"一片连续的糊化"就用 `backgroundEffect`（纯模糊），且相邻两块的 `radius` / `saturation` / `brightness` / `color` 必须逐字同值。
   → `§3.0-250`

---

## 8. 验证要求

| 改动类型 | 必须有 |
| --- | --- |
| 纯视觉（圆角/间距/字号/颜色） | 浅色 + 深色截图各一张 |
| 交互（点击/勾选/展开） | **真实触摸**（`hdc shell uinput -T -c x y`，坐标用 `uitest dumpLayout` 现取）的效果回读；合成事件（`dispatchEvent`）不经过命中测试会假 PASS → `§3.0-81` |
| 动效 | 连拍帧或录屏，读出动效确实在播 |
| 材质 / 安全区 / 键盘避让 | **必须真机**（模拟器有已知合成故障与生效范围差异）→ `§3.0-10`、`§3.0-58` |
| 材质「**是否真的画出像素**」 | ⚠️ **本轮把这条判据换过臂，写判据时别再走原方案**：① **原定臂无效** —— 「新臂 vs 回退臂的中段 MAE」不能回答本问题（回退臂的 `DrawnBar` **同样带 `backgroundEffect`**，两臂中段本来就都模糊；实测 0.26）；② **成立的口径** = **同一帧内「栏内 vs 栏外」+ 跨臂单变量**：同一行正文横向梯度 `gradX`（本工程 OFF 8.523 / IMM 0.374 = **22.8×**，dark 23.8×）+ **栏外整体 MAE 0.0022**；③ 另一条独立通路 = **宽 ROI 逐行均值 + 最大一阶差分**（交付臂 5.26 ≈ 改前 5.25，被否决臂 68.37）；④ 噪声底分档：**同页面态 0.26 / max 3~4**、**跨冷启动 2.68 / max 5**（早期那个 2.68 混进了页面态变化）⇒ 「MAE > 5 才算画出像素」只对跨冷启动比较成立；⑤ **按钮区不能作 ROI**（图标抗锯齿抖动 max 249）；⑥ 取图前必须**回读「网页真的滚了」**（`uiInput swipe` 会静默无效，改用 CDP 设 `scrollTop`）。读数与脚本见 `内部验证记录` §2.3/§4 与 `tools/{blur-index,row-profile,roi-mae,scroll-capture}.mjs` |
| 性能/内存 | 改造前后同口径读数（PSS / 启动耗时 / 计数器），见 `内部验证记录` |

---

## 9. 相关文档

| 文档 | 内容 |
| --- | --- |
| [`common/ShellUi.ets`](../entry/src/main/ets/common/ShellUi.ets) | 设计令牌（数值的唯一来源）＋ 官方材质工厂 `officialImmersiveMaterial()` / 回退开关 `OFFICIAL_MATERIAL` / 列表行进出场转场工厂 `listItemTransition()`（第二十一轮新增） |
| [`view/SettingsTabBar.ets`](../entry/src/main/ets/view/SettingsTabBar.ets) | **设置页底部功能栏**（第二十一轮新增，原生自绘悬浮胶囊，形态参考 `aa-hm` 的 `ui/BottomNav.ets`）；令牌全部来自 `TABBAR_*`，组件内零裸魔数 |
| [`specs/MATERIAL-ACCESS-POINTS.md`](MATERIAL-ACCESS-POINTS.md) | **材质接入点清单**（逐点裁决 + 官方依据「文件:行号」一手出处） |
| [`PROJECT.md`](../PROJECT.md) | 工程现状（架构 / 权限 / 构建 / 配置项清单） |
| [`EXPERIENCE.md`](../EXPERIENCE.md) | 本工程专属踩坑与实测结论 |
| [`CHANGELOG.md`](../CHANGELOG.md) | 逐轮变更史与证据路径 |
| `内部验证记录` | 第十五轮只读全量审查（UI 统一性问题清单 U-1~U-17） |
| `内部验证记录` | 第十四—十五轮修复口径与真机读数 |
| `AGENTS.md` | 工作区总纲（目录纪律 / 环境 / 高频致命坑） |
| `内部踩坑表` | 跨工程通用踩坑全表（`§3.0-N` 锚点稳定） |
