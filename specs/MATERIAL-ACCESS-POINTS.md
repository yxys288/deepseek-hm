# deepseek-hm 材质接入点清单（第二十轮 · task-3）

> **目标**：把原生外壳里**仍在自绘**的材质，在**官方生效范围允许的位置**改用官方沉浸材质
> （`uiMaterial.ImmersiveMaterial` / `CommonMethod.systemMaterial` / `NavigationTitleOptions.systemMaterial`）；
> **范围外的位置一律留自绘**（挂了不报错、不告警，只是静默无效）。
>
> **本文件的定位**：先查官方依据再动手（用户诉求「优先查询官方文档再决定怎样优化」），
> 产出的判据供 T2（`view/TopBar.ets` + `pages/Index.ets` 改造）与 T3（真机验证）使用。
> 体例与 §0 的引用深度对齐参考工程 `aa-hm`（纯 ArkUI，已有完整实测与裁决记录）。
>
> **快照**：§1 全部行号/实现对着 **T2 落地前** 的源码树（各文件 md5 见 §6）。
> T2 进行中：本文**不改写 T2 的结论**，T2 落地后以它的实际源码为准（差异由 T3/T4 复核）。

---

## 勘误 · 更新（2026-09-25，对着 T2 落地后的源码；由 Lead 授权，原描述**保留**不删）

⚠️ 下面 §1 的 **T1/T2/T3** 三行写的是**派活时的方案**（「顶栏本体挂官方沉浸材质」）。
T2 落地后**结论变了** —— 这里保留原描述并给出更新，**不要只看 §1 就以为栏本体挂的是节点级材质**。

| 项 | §1 的旧描述（保留；已标明被取代） | 落地后的实际（**以源码为准**） |
| --- | --- | --- |
| 顶栏栏本体 | 「把承载结构换成 `Navigation` + `.title(...)`，顶栏本体挂官方沉浸材质」 —— **已被源码取代** | **模糊由框架标题栏供给**：`topBarTitleOptions()` 里的 `NavigationTitleOptions.backgroundEffect`（`radius`/`saturation`/`brightness` 与改前同值 ＋ 同一个 `shell_topbar_glass` 令牌），自建 `Row` **零自绘层**；节点级 `systemMaterial` 降级为 **A/B 对照档**（`TOPBAR_FRAMEWORK_BLUR = false`，**已被用户真机否决**：它画出来是「**有确定边界的圆角材质带**」，下缘即接缝，用户原话「标题栏和页面有明显分界线」；同型逐像素剖面见 `§3.0-250`） |
| 栏内 3 个按钮 | 「调用点补第 5 实参 `official: true`」 | **照旧成立**：走 `ShellIconButtonOfficial` 的 `.systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))`；自绘 `MenuGlyph` 的菜单按钮也补了官方分支（零自绘层） |
| 几何契约（原 T4） | 「网页可读区上方被原生覆盖的高度**不得超过改前**」 | ⚠️ **这条硬约束被用户真机拍板覆盖**：让位量 97.71vp(291px) → 111.71vp(332px)，**+14vp**。**因果链** = 用户反馈「标题栏和页面有明显分界线，不好看，改为沉浸式」→ 形态取舍（框架栏连续模糊、正文首行不落进模糊区）→ 代价 +14vp。**不是**「实现需要所以扩了」 |
| 自绘渐变过渡带 | §1 未单列（当时作为顶栏一部分） | **官方档删除**：官方模糊的边缘已接替「抹平磨砂方块下缘」这一职责，留着会在自己的边缘再产生**第二条分界**；仅自绘回退档（`OFFICIAL_MATERIAL = false`）仍在用 |

**本轮新增的一手依据 / 实测（补进 §0 的判据集）**：

- 新沉淀的通用坑：`§3.0-254`（`uitest dumpLayout` 把节点**顶边钳在状态栏下沿** 137px）、
  `§3.0-255`（标题栏**可用高 = 112 − 状态栏** = 56vp；让位量不能按自己那行的高算）、
  `§3.0-256`（`UIMaterial.state=enable` **不是空闸门**：`bindSheet` 在默认开启清单里）；
- 真实框架栏几何（真机 `dumpLayout`）：`TitleBar [0,137][1316,332]`（= 112vp，**含状态栏那 46vp**）；
  构造器顶边被框架锚在 **166px**、可用高 **166px = 56vp**（请求 66vp 与 56vp 落点相同）；
- 栏覆盖区是否吃网页点击（**结论按 verify 的口径**）：**可断言（强）** y=350（栏下缘之下 18px）穿透成功（系统点击 + 网页内 click 探针 `probe=1`）；
  y330..400 无任何原生可点节点。⚠️ **不可断言「是否回归」** —— 该区整体不吃给网页（probe=0，证据力**中**）实测成立，但 verify **未做同口径的改前对照**
  ⇒ T2 自述的「改前 y≤335 / 改后 y≤332 ⇒ 332<335 无回归」**只作 T2 自述，不是本轮结论**（`REPORT.md` §2.5(c)/§7-1）。

> 以上三条实测来自 T2 的真机工作（原始产物在 `%TEMP%` 中间产物区，**未进 `verify-*`**）；
> **正式真机判据以 `./内部验证记录`（T3）为准**，本文不替它下结论。

**行号漂移对照（T2 落地后，2026-09-25 07:1x 复核；快照 md5 见下）**：本文 §1 的 `pages/Index.ets` 行号是**改前**的，
T2 落地后整体后移，下面是四个「网页让位同源点」的**新行号**（其余 `Index.ets` 引用同理，请以 `grep NAV_TITLE_SLOT_VP` / `grep OFFICIAL_MATERIAL` 现取为准）：

| 位置 | 改前（本文 §1） | T2 落地后（新行号） |
| --- | --- | --- |
| `injectShell()` 的 `window.__dshTopInsetPx` | `:1150` | **`:1150-1152`**（算式在 `:1152`） |
| `pushInsets()` 的 `let top` | `:1316-1317` | **`:1320`**（`:1336` 写回全局） |
| `ErrorPane` 的顶部让位 | `:2605` | **`:2689`** |
| `NewChatTipLayer` 的落点让位 | `:2776` | **`:2861`** |
| 官方/回退两档的入口 | —（改前无） | `Index.ets:2398`（`if (OFFICIAL_MATERIAL)`）/ `:2414`（`Navigation()`）/ `:2426`（`.title(this.TopBarTitle(), topBarTitleOptions())`）/ `:2470`（`TopBarTitle()` 构造器） |

**复核时点的源码 md5**（用于判断本文是否还对得上树）：

| 文件 | md5 |
| --- | --- |
| `entry/src/main/ets/view/TopBar.ets` | `4752C26203A1BB0FD03E84664BBFA2BB` |
| `entry/src/main/ets/pages/Index.ets` | `C26ECF69DE70C5738FBB82B617BFD591` |
| `entry/src/main/ets/common/ShellUi.ets` | `1A6AEB3A0867793E18311B014DE4BDCF` |
| `entry/src/main/module.json5` | `7B2B28D25219AD0330382B6967C5BA18` |

**改名已落地复核**：`grep TOPBAR_BAR_MATERIAL|TOPBAR_FRAMEWORK_BLUR` ⇒ 现树只剩新名（`TopBar.ets:167` 定义、`:179` 分支、`:321` 注释、`:322` 实参），旧名只出现在 `:163` 的「曾用名」说明里 ⇒ 本清单与 UI-DESIGN 用新名**正确**。

---

## 0 · 官方依据（一手来源逐条带「文件:行号」）

> 路径写法说明：本文件里所有 Windows 路径**统一用正斜杠**书写（`D:/DevEco Studio/...`）。
> 这是 AGENTS.md §1.5 允许的「不用转义的写法」—— 反斜杠写在 Markdown 里一旦被当转义符落盘，
> 整段命令会变成控制字符垃圾（`node scripts/check-docs.mjs` 会把 `0x09` 判为致命）。

| # | 依据 | 一手出处（文件:行号 + 原文要点） |
| --- | --- | --- |
| **A** | **应用级三档状态**：`DEFAULT=0`（部分组件默认开）/ `ENABLE=1`（默认开清单**含 `bindSheet`**，且「材质样式**优先于**组件自身设置的 background color / blur / shadow / border style」）/ `DISABLE=2`（「即使给组件设了材质参数也不生效」）；metadata 的 `state` 就来自 `module.json5` | 本机 SDK `D:/DevEco Studio/sdk/default/openharmony/ets/api/@ohos.arkui.uiMaterial.d.ts`：`DEFAULT` **:69-83**、`ENABLE` **:85-103**（:91 列出 `bindSheet`）、`DISABLE` **:104-114**；`getMaterialInfo()` **:150-163**。工程侧：`entry/src/main/module.json5` 的 `metadata` |
| **B** | 材质**会接管** `backgroundColor` / `borderColor` / `borderWidth` / `shadow`，官方原文 **「You are advised not to use this API together with the aforementioned APIs」**（不建议同用） | `ets/component/common.d.ts:22624-22642`（`CommonMethod.systemMaterial` 的 NOTE）；模块头同义复述 `@ohos.arkui.uiMaterial.d.ts:19-24` |
| **C** | `ImmersiveOptions` 六字段与默认值；**`materialColor` 必须带透明度**（原文：*cannot be completely opaque. Otherwise, the material filter effect will be completely blocked*）；`applyShadow=true` 时材质投影**优先于**通用 `shadow` | `@ohos.arkui.uiMaterial.d.ts:306-429`（`style` :307-323、`materialColor` :324-341、`colorInvert` :342-380、`applyShadow` :381-399、`interactive` :400-413、`lightEffect` :414-428）；构造器默认值 **:503-517**（原文 `{style:ImmersiveStyle.REGULAR, materialColor:Color.Transparent, colorInvert:false, applyShadow:true, interactive:false, lightEffect:undefined}`） |
| **D** | `ImmersiveStyle` 五档：`ULTRA_THIN=0` / **`THIN=1`** / `REGULAR=2` / `THICK=3` / `ULTRA_THICK=4` | `@ohos.arkui.uiMaterial.d.ts:174-225` |
| **E** | **标题栏专属入口**：`NavigationTitleOptions.systemMaterial?: Material`（@since 26.0.0），原文「Set system-styled materials for the **TitleBar** … can **influence the backgroundColor, border, shadow**, and other visual attributes of the titleBar」；其 `Material` 类型 = `uiMaterial.Material`（基类） | `ets/component/navigation.d.ts:1880-1891`；类型别名 `navigation.d.ts:27` |
| **E2** | **通用属性入口**：`CommonMethod.systemMaterial(material: SystemUiMaterial \| undefined): T`（@since 26.0.0），传 **`undefined` = 显式无材质**（SDK 原文：*Setting it to `undefined` will make the component return to the **no-material effect***，`:22632-22633`）—— ⚠️ **不是**「恢复默认材质」；`SystemUiMaterial` = `uiMaterial.Material`（`common.d.ts:16964`）。⚠️ 与 E 是**两个不同入口**：E 的作用面是「标题栏」这一组视觉属性，E2 才是「挂在哪一行就作用于哪一行」的通用口子 | `ets/component/common.d.ts:22624-22642`（`undefined` 语义 :22632-22633）；类型声明 `common.d.ts:16964`（原文注释「Base class for system material objects」） |
| **F** | 标题栏另有**框架级模糊**入口 `NavigationTitleOptions.backgroundEffect`（@since 19），SDK 明确「**Avoid using this API in conjunction with `backgroundBlurStyleOptions`**」 | `ets/component/navigation.d.ts:1745-1758`（`backgroundBlurStyleOptions` :1744） |
| **G** | **「弹窗类接口在生效范围内」在 SDK 层可核对**：以下弹窗类 options 各自带 `systemMaterial?: SystemUiMaterial` —— `SheetOptions` / `PopupCommonOptions` / `TipsOptions` / `PopupOptions` / `CustomPopupOptions` / `ContextMenuOptions`；对话框族另有 `AlertDialog` / `ActionSheet` / `CustomDialogController` / 各 Picker | `ets/component/common.d.ts`：`SheetOptions` **:12155**、`PopupCommonOptions` **:12966**、`TipsOptions` **:13167**、`PopupOptions` **:13824**、`CustomPopupOptions` **:14406**、`ContextMenuOptions` **:15594**；`alert_dialog.d.ts:894`、`action_sheet.d.ts:834`、`custom_dialog_controller.d.ts:681`、`date_picker.d.ts:1075`、`calendar_picker.d.ts:590` |
| **H** | **生效范围（HarmonyOS 7 起，仅对 `targetSdkVersion >= 26.0.0` 生效）**：变更后，弹窗类组件/接口与 `Slider`/`Toggle`/`Select` **仍可在页面内全部区域生效**；**其他组件仅在 `Navigation`/`NavDestination` 标题栏、或横向 Tabs 且 `barPosition = BarPosition.End` 的底部 TabBar 中生效；在其他区域设置沉浸光感不生效**（不报错、不告警）。⚠️ **这层「范围」约束在 SDK 类型定义里没有原文** —— SDK 只写 API 与语义，范围是 OS 平台行为 ⇒ 本条由「官方 OS 平台行为变更说明 + 本工作区实测」支撑 | 复述与实测见 `内部踩坑表` §3.0-245`、`§3.0-58`；工程侧前置条件：`build-profile.json5` 的 `targetSdkVersion: "26.0.0"`；检索方式见 §0-I |
| **I** | ⚠️ **官方来源的检索方式（如实注明，勿写成「直接抓取了官网原文」）**：华为开发者官网是 **SPA**。本轮**实测**：对 `https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial` 与 `https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/changelogs-for-all-apps-7003` 各 `web_fetch` 一次，两次都是 `statusCode=200`、`body.kind=html`、**正文长度 1731 B 且内容逐字相同**（`<title>文档中心</title>` + `<base href="/consumer/cn/doc/">` + 脚本标签）⇒ **只能拿到外壳，正文取不到**。因此本文的官方原文只有**两个来源**：① **本机 SDK 类型定义**（一手，逐行可核对，见 A~G/J/K）；② **`web_search` 返回的第三方转述**（用于 H 的交叉验证）：IT之家系报道「华为开发者官网 OS 平台行为变更说明今日更新，宣布沉浸光感新增生效约束」，含「变更前 `Column` 挂 `systemMaterial` 生效、变更后同一写法不生效」的官方示例，转载见 <https://www.sohu.com/a/1071566474_114760>、<https://m.sohu.com/a/1071567297_122066678>、<https://www.ihonker.com/forum.php?mod=viewthread&tid=36216>。**这些是转述，不是一手原文** —— 请勿在别处升级成「已核对官方网页」 |
| **J** | `Material.empty` 的语义是「**disable**」（原文：*used to disable the immersive system material effect for a component*）。⚠️ **`systemMaterial` 有两个同名入口，`undefined` 的语义按各自 SDK 原文分别成立**：① `CommonMethod.systemMaterial`（`common.d.ts:22642`）⇒ `undefined` = **显式无材质**（原文 `:22632-22633`）；② `Tabs` 的 `FloatingTabBarStyle.systemMaterial`（`tabs.d.ts:886-895`）是**可选字段**（类型 `UIMaterial.ImmersiveMaterial`）⇒ `undefined` = 「**未配置**」，关闭须显式 `Material.empty`。⚠️ **勘误（2026-09-25，verify 独立核出，见 `REPORT.md` §8）**：aa-hm 清单 §0-J 把「`undefined` = 恢复组件默认材质」挂在 `common.d.ts:22632-22633` 上，**而该行原文与它相反** ⇒ 其**结论**（隐藏态须显式 `Material.empty`）**可并存，但引用挂错了行**；两处结论**不要互套**（详见下方 §0-J 补注） | `@ohos.arkui.uiMaterial.d.ts:465-482`（`:467-472` 为原文）；`common.d.ts:22632-22633`、`:22642`；`tabs.d.ts:886-895` |
| **K** | 标题栏高度常量（本工程几何标定必须知道量级）：`NavigationTitleMode.Full` = **112 vp**（只有主标题时）、`Mini` = **56 vp**、`Free` 随滚动收缩 | `ets/component/navigation.d.ts:244-255`（Full）、`:256-271`（Mini）、`:222-243`（Free）；赋值口 `titleMode(value)` :2392；真机标定口径与 `Mini` 被证伪的实测见 `内部踩坑表` §3.0-247` |

**§0-J 补注 · `systemMaterial` 的两个同名入口（2026-09-25 verify 独立核出后订正）**

| 入口 | 形参 / 字段类型 | `undefined` 的语义（**各自 SDK 原文**） | 怎么关材质 | 本工程是否使用 |
| --- | --- | --- | --- | --- |
| `CommonMethod.systemMaterial`（`common.d.ts:22642`，@since 26.0.0） | `SystemUiMaterial \| undefined`（别名 = `uiMaterial.Material`，`common.d.ts:16964`） | **no-material effect** —— 原文「Setting it to **undefined** will make the component return to the **no-material effect**」（`:22632-22633`） | 直接传 `undefined` 即**显式无材质** | ✅ 用（顶栏 `Row` 的 `.systemMaterial(TOPBAR_FRAMEWORK_BLUR ? undefined : …)`） |
| `Tabs` 的 `FloatingTabBarStyle.systemMaterial`（`tabs.d.ts:886-895`） | **可选字段**，类型 `UIMaterial.ImmersiveMaterial`（**不含** `undefined` 语义） | 「**未配置**」⇒ 行为由框架缺省决定（ENABLE 档下悬浮 TabBar 默认 THIN） | **必须** `uiMaterial.Material.empty`（`uiMaterial.d.ts:465-482`，语义 = **disable**） | ❌ 未使用（本工程无底部 TabBar） |

⚠️ **勘误留痕（不静默抹掉）**：参考工程 aa-hm 的 `MATERIAL-ACCESS-POINTS.md` §0-J`
把「`undefined` = 恢复组件默认材质」挂在 `common.d.ts:22632-22633` 上，**而该行原文与它相反**（no-material effect）。
⇒ **aa-hm 那条的结论（隐藏态必须显式 `Material.empty`）可以并存**（它作用的是 Tabs 那个**可选字段**入口），
**但它引用的行是错的**；对照证据见 `内部验证记录` §8（verify 在本机 SDK 逐行读过）。
结论：**同名不同入口，`undefined` 的语义按各自 SDK 原文分别成立**，引用时必须写清入口 + 行号（同步沉淀为 `内部踩坑表` §3.0-256`）。

**由 A/B/H/J 推出的三条硬约束（本清单的唯一判据）：**

1. **不在生效范围内的位置，一律不许挂材质** —— 挂了只会静默无效，而官方档**不画任何自绘层**，
   结果是「把回退层删掉、换来一个透明空壳」，比不改更糟（依据 H + B）。
2. **同一节点上官方材质与自绘层不共存** —— 官方分支里 `backgroundEffect` / 渐变 / `backgroundColor` /
   `border*` / `shadow` **一个都不留**（依据 B）。
3. **应用级 `enable` 不是一个「空闸门」** —— 它按 A 把「默认开启清单」（含 `bindSheet`）一起翻到材质档，
   并且材质**优先于**这些组件自身设的 background/blur/shadow/border ⇒ 打开它**本身就有改动面**，
   见 §1 的 **I1**。

---

## 1 · 材质接入点清单（逐点裁决）

判定列含义：**范围内** = 命中 §0-H 的四类位置（弹窗类 / `Slider`·`Toggle`·`Select` / `Navigation`·`NavDestination` 标题栏 / 横向 Tabs 底部 `barPosition=End`）；
**范围外** = 页面正文（`Stack`/`Column`/`Row` 里的普通容器）。

### 1.1 应用级闸门与顶栏（功能栏 · 顶）

| # | 位置（文件:符号/锚文） | 当前实现（快照 = T2 落地前） | 在官方生效范围 | 处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **M1** | `entry/src/main/module.json5` 的 `module.metadata` → `"name": "ohos.arkui.UIMaterial.state"` | 本轮由 `disable` 改 **`"value": "enable"`**（**值必须小写**） | —（应用级闸门，不是挂载点） | **保持 `enable`**；`OFFICIAL_MATERIAL` 负责回退，不回退这一行 | §0-A、`§3.0-2` |
| **T1** | `view/TopBar.ets` → `build()` 顶栏根 `Column`（`.backgroundEffect({ radius: TOP_BAR_BLUR, saturation, brightness, color: $r('app.color.shell_topbar_glass') })` **:185-194**）＋ `Blank().linearGradient({...})` 渐变过渡带 **:206-217** | 自绘高斯模糊 + 自绘渐变过渡带（**零官方材质**） | ❌ **改前不在** —— 全工程 `Navigation(`/`NavDestination(` **命中 0 处**（grep 见 §5），`TopBar` 是 `MainPane` 的 `Stack` 里一个普通节点，属页面正文 | **改（T2）**：把承载结构换成 `Navigation` + `.title(...)`，顶栏本体挂官方沉浸材质；`:185` 的 `backgroundEffect` 与 `:209` 的 `linearGradient` **整组删除**（依据 B） | §0-B、§0-H、§0-K |
| **T2** | `view/TopBar.ets` → `MenuButton()` **:271-295**：自绘 `MenuGlyph` 双横杠 + `.stateStyles({normal/pressed: backgroundColor(icon_btn_bg / icon_btn_bg_pressed)})` **:280-287** | 图标**自绘**（SDK 无「两条、上长下短、左对齐」的符号，见 `specs/UI-DESIGN.md` §5）＋ 底色/按压**自绘** | 同 T1（改后在标题栏内 ✅） | **改（T2）**：`MenuGlyph` **保留自绘**（造型在 SDK 里确实做不出来，不是漏换），底色改为挂 `systemMaterial`、删掉自绘 `stateStyles` 底色 | §0-B、`specs/UI-DESIGN.md` §5 |
| **T3** | `view/TopBar.ets` → 左槽 `ShellIconButton($r('sys.symbol.chevron_left'), '返回', this.onBack, true)` **:111**；右槽 `ShellIconButton($r('sys.symbol.plus_circle'), '新建对话', this.onNewChat, true)` **:164** | 两者都走 `ShellIconButton` 的**自绘档**（第 5 实参 `official` 缺省 `false`），可见圆 = `Button` 自身底色 + 显式 `stateStyles` | 同 T1 | **改（T2）**：调用点补第 5 实参 `official: true`，改由 `ShellIconButtonOfficial` 的 `.systemMaterial(...)` 画底与按压/光感 | §0-B、§0-H |
| **T4** | 顶栏**几何契约**（不是材质接入点，但改动必须不破它）：根 `Column.height(TOP_BAR_H + topPad + TOPBAR_FADE_H)` **:220**；`.hitTestBehavior(HitTestMode.None)` **:231**；网页侧下移量 `window.__dshTopInsetPx = topInset + TOP_BAR_H`（`pages/Index.ets` **:1150**、**:1316-1317**、**:1332**） | 原生顶栏实际覆盖高度 = `TOP_BAR_H(52) + topPad + TOPBAR_FADE_H(16)`；两侧同源 | —（与材质无关的硬约束） | **保持**：① 网页可读区**上方被原生覆盖的高度不得超过改前**；② `hitTestBehavior(HitTestMode.None)` **不得去掉**（§3.0-159 的历史 P0）；③ 框架标题栏高度 ≠ 本工程 52vp ⇒ 换结构后必须**真机 `dumpLayout` 实测标定**并写进代码注释（依据 K 给量级：`Full` 112vp / `Mini` 56vp） | §0-K、`§3.0-159`、`§3.0-247` |

### 1.2 侧栏面板（`SideBarContainer` 内容槽 = 页面正文）

| # | 位置（文件:符号/锚文） | 当前实现 | 在官方生效范围 | 处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **S1** | `view/SidePane.ets` → `build()` 面板本体 `Column`：`.backgroundEffect({ radius: PANEL_BLUR, saturation, brightness, color: $r('app.color.shell_panel_glass') })` **:1166-1171**、`.clip(true)` **:1185**、`.shadow({...})` 对称淡晕 **:1205-1210** | 自绘高斯模糊 + 自绘投影（真机逐像素定标过：alpha≈20%、投影 `offsetX/Y = 0`） | ❌ **不在**（`SidePane` 挂在 `SideBarContainer` 的**内容槽**，是页面正文里的普通容器） | **保持自绘**（理由见 §2-S1） | §0-H |
| **S2** | `view/SidePane.ets` → `PanelHeader()` 里三个 `ShellIconButton(..., false)`：`:688`（选择对话）/ `:693`（新建对话）/ `:698`（关闭侧栏） | 自绘档（`raised=false`：裸图标 + 按下换 `shell_item_active_bg` 底色） | ❌ 同上 | **保持自绘** —— 调用点就在正文里，改 `official: true` 会**静默无效并丢掉可见圆/按压反馈**（理由见 §2-S2） | §0-H、§0-B |
| **S3** | `view/SidePane.ets` → 列表行 / 账号行 / 空态：`Search({ value, placeholder: '搜索会话' })` **:729**、行底色 `shell_item_active_bg` / `field_bg` 等 | 官方 `Search` + 令牌底色 | ❌（`Search` 不在 §0-H 四类位置里；`Slider`/`Toggle`/`Select` 才豁免，`Search` **不在豁免清单**） | **保持**（不挂材质） | §0-H |

### 1.3 根层浮层 / 半模态（`pages/Index.ets`）

| # | 位置（文件:符号/锚文） | 当前实现 | 在官方生效范围 | 处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **I1** | `pages/Index.ets` → 根节点 `.bindSheet($$this.pickerSheetShown, this.PickerSheetContent(), { height: SheetSize.FIT_CONTENT, dragBar: false, showClose: false, title: ... })` **:2205-2210**；内容 `PickerSheetContent()` **:2287-2333**，内含三宫格 `PickerTile(...)` **:2238-2272**（`.backgroundColor($r('app.color.icon_btn_bg'))` **:2255** + `stateStyles` 按压换底色） | 官方半模态承载；**内容自绘**（宫格实底 + 按压换底） | ✅ **在**（半模态转场属**弹窗类接口**；SDK 侧入口即 `SheetOptions.systemMaterial` **:12155**）。⚠️ 而且按 **A**，`ENABLE` 档下 `bindSheet` 属**默认开启**清单且「材质优先于组件自身的 background/blur/shadow/border」 | **本清单不改它的代码，但登记为「被应用级开关连带改变的接入点」**：`M1` 一改，这个半模态的默认观感就变了 ⇒ 必须**真机复核宫格是否被材质洗白**（理由与风险见 §2-I1 / §4） | §0-A、§0-G |
| **I2** | `pages/Index.ets` → `MainPane.ErrorPane()` 卡片 **:2551-2609**：`.backgroundColor($r('app.color.card_bg'))` **:2593** + `.shadow({...})` **:2595-2600**，容器 `.backgroundColor($r('app.color.bg_page'))` **:2607** | 自绘卡片：实底 + 投影 | ❌ **不在**（错误页是 `MainPane` 的 `Stack` 里铺满整屏的普通容器，属页面正文） | **保持自绘**（理由见 §2-I2） | §0-H、§0-B |
| **I3** | `pages/Index.ets` → `SplashOverlay` **:2624-2726**：整屏 `.backgroundColor($r('app.color.bg_page'))` **:2720** | 不透明整屏覆盖层（鲸鱼 + 逐字标语） | ❌ 不在 | **保持自绘**（理由见 §2-I3） | §0-H |
| **I4** | `pages/Index.ets` → `NewChatTipLayer` **:2747-2784**：`shell_item_active_bg` 底 **:2759** + `line_color` 发丝描边 **:2761** + `.shadow({...})` **:2762-2767**；靠常驻 + `opacity/translate` 显隐 | 自绘气泡 | ⚠️ **语义上是「轻提示」**，但本工程**没有**用 `bindPopup` / `showToast` —— 它是自绘常驻层（原因：其锚点在面板之下，`bindPopup` 会被抽屉裁掉，见 `:2731-2736`）。SDK 侧 `TipsOptions.systemMaterial`（**:13167**）**不作用于它** | **保持自绘**（理由见 §2-I4） | §0-G、§0-H |
| **I5** | `pages/Index.ets` → `MainPane` 的点击接管层：`Column().backgroundColor(Color.Transparent)` **:2510-2513** | 全透明整屏可点层（只负责「点面板外关侧栏」） | —（无材质、无底色，不构成接入点） | **保持**（它必须全透明，任何底色都会让「遮罩压暗」的旧缺陷回归） | `specs/UI-DESIGN.md` §7-9 |

### 1.4 共享配方（`common/ShellUi.ets`，本轮 T1 已落地）

| # | 位置（文件:符号/锚文） | 当前实现 | 在官方生效范围 | 处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **U1** | `common/ShellUi.ets` → `OFFICIAL_MATERIAL` **:371**（`true`）＋ `officialImmersiveMaterial(color)` **:399-408**（`style: THIN` / `colorInvert: false` / `applyShadow: true` / `interactive: true` / `lightEffect: { color: Color.White }`）＋ `ShellIconButtonOfficial()` 的 `.systemMaterial(officialImmersiveMaterial($r('app.color.icon_btn_material')))` **:534** | **本轮新增的官方档**（零自绘层：无 `backgroundColor` / `stateStyles` / `.shadow(` / 渐变 / 边框） | **取决于挂载点**：标题栏内 ✅ / 正文 ❌ | **保持**；调用点的前提是「必须在 `Navigation`/`NavDestination` 标题栏里」，否则退化成**看不见的透明空壳**（理由见 §2-U1） | §0-B、§0-H、§0-C |
| **U2** | `common/ShellUi.ets` → `ShellIconButtonDrawn()` **:547-586**：`.stateStyles({normal/pressed: backgroundColor(...)})` **:569-576** + `.animation({duration: MOTION_FAST, curve: CURVE_STD})` **:579** | 自绘回退档（**本轮之前的口径**） | 视挂载点 | **保持**（回退路线：`OFFICIAL_MATERIAL = false`，或调用点省略 `official`） | §0-B |

### 1.5 网页侧 CSS 玻璃（**不属于 ArkUI 材质管线**）

| # | 位置（文件:符号/锚文） | 当前实现 | 是否走官方材质 | 处置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **W1** | `utils/DeepSeekConfig.ets` 注入的网页样式：`[data-dsh-floatbtn="1"]::after { ... -webkit-backdrop-filter: blur(10px) saturate(1.4); backdrop-filter: blur(10px) saturate(1.4); }` **:272-276**（打标函数 `markSidebarToggleButtons()` **:897**，运行时按几何给官方侧栏开关按钮加 `data-dsh-floatbtn="1"`） | **网页侧** CSS 玻璃圆框（半透明底 + backdrop 模糊 + 1px 环 + 柔影） | ❌ **完全不适用**：这是 Chromium 合成层的 CSS `backdrop-filter`，**不经过 ArkUI 材质管线**；`module.json5` 的 `UIMaterial.state` 与任何 `systemMaterial` 对它**零影响** | **保持**；登记口径：它**属于网页侧**，不要指望官方沉浸材质能接管它（理由见 §2-W1） | §0-H（H 约束的是 **ArkUI 组件**，管不到网页 CSS） |

**§1 读数**：**范围内且本轮处置** = `T1`/`T2`/`T3`（顶栏三项）；
**范围内但被应用级开关连带改变** = `I1`（上传半模态）；
**范围外、保留自绘** = `S1`/`S2`/`S3`/`I2`/`I3`/`I4`；
**不是接入点但改动必须不破** = `T4`/`I5`；
**已落地的共享档** = `U1`（官方）/ `U2`（回退）；**与材质无关** = `W1`。

---

## 2 · 「保留自绘」的逐条理由（不许简化成「不在范围内」一句话）

**§2-S1（侧栏面板本体）**：它的位置是 `SideBarContainer` 的**内容槽**，属 §0-H 的「其他区域」
⇒ 挂 `systemMaterial` **不生效**（不报错、不告警）。而它当前的自绘层不是「随手画的」：
`shell_panel_glass` 的 alpha≈20% 与投影 `offsetX/offsetY = 0` 都是**真机逐像素定标**的结果
（alpha 高 5 级就出现面板右缘竖线；投影横向偏移就在上下圆角处留硬边，见 `SidePane.ets:1152-1204`）。
把它换成官方材质 = **删掉定标过的回退层去换一个静默无效的空壳**，是双重损失。

**§2-S2（侧栏头部 3 个图标按钮）**：它们与 `T3` 走的是**同一个** `ShellIconButton` 配方，
差别只在第 5 实参。**不在范围内** ⇒ 若传 `official: true`，`ShellIconButtonOfficial` **不画任何自绘层**，
按钮会变成「没有可见形态的透明区域」，而 `ShellIconButtonDrawn` 的「按下变 `shell_item_active_bg`」
正是侧栏按压语义的一部分（`specs/UI-DESIGN.md` §3.2 第 1 条：与顶栏**有意统一**）。
⇒ 这一档**必须**继续走自绘；将来若把侧栏改成 `NavDestination` 标题栏，这两处再一起改。

**§2-I1（上传半模态：不改代码，但必须复核）**：按 §0-A，`ENABLE` 档下 `bindSheet` **默认带材质**，
并且「材质样式**优先于**组件自身设置的 background color / blur / shadow / border style」。
本工程 `.bindSheet(...)` 的 options（`:2205-2210`）**没有**传 `systemMaterial` ⇒ 本轮**不改它的代码**；
但应用级开关一开，它的默认观感就与改前不同（这是「打开 `enable`」的**真实代价**，不是零成本）。
**风险点**：三宫格 `PickerTile` 用 `icon_btn_bg` 实底（`:2255`）—— 若平台的「材质优先」作用到了宫格这类**子组件**，
会重演 `§3.0-58` 记录的「材质把实色洗白」。
**这一条只能真机定论**（见 §4 的 I1 项），本清单不下结论、也不替 T3 下结论。

**§2-I2（错误页卡片）**：位置是 `MainPane` 的 `Stack` 里的普通容器（页面正文）⇒ 不在范围。
它承载的是**可读性**目标（错误文案 + 「重新加载」CTA 必须在任何背景上可读），
实底 `card_bg` + 投影正是为此；换成透明材质会让错误页在网页内容上「糊着读」。**保持自绘**。

**§2-I3（启动页）**：它是**全屏不透明**覆盖层，材质（半透明 + 折射）在这里没有任何语义；
而且它在**冷启动最初一帧**就要完整遮住 Web（改前 Web 组件的 `backgroundColor(bg_page)` 与它同色，
正是为了「首帧不闪」）。**保持不透明自绘**。

**§2-I4（「已是新对话」轻提示）**：形态上它属于「轻提示」，但本工程**刻意没用** `bindPopup`/`showToast`：
它的锚点（顶栏 ⊕）在侧栏面板之下，`bindPopup` 会被抽屉裁掉（`Index.ets:2731-2736` 的原话），
而 `showToast` 无法贴着顶栏右下角定位。⇒ 它是自绘常驻层，
SDK 的 `TipsOptions.systemMaterial`（`common.d.ts:13167`）**作用不到它**（它不是 Tips）。
另有一条独立的历史结论必须保留：该层在 `opacity(0)` 时仍可命中，
实测在物理 `[1030,290]-[1281,380]` 吃掉了设置弹层右上角 ✕ 的全部触摸（`§3.0-159`），
故内外两层都显式 `hitTestBehavior(HitTestMode.None)`（`:2771`/`:2779`）。**保持自绘**。

**§2-U1（`ShellIconButtonOfficial` 的挂载前提）**：该档**零自绘层**是有意设计（依据 B），
代价是**它自己不会画出任何东西** —— 形状、底色、按压反馈全部由材质提供。
⇒ 一旦被挂在范围外（本次 T2 之前的顶栏、以及现在的侧栏头部若误传 `official: true`），
正确行为是「什么都不显示」，而不是「退化成自绘」（两个分支是**互斥**的 `if/else`，见 `:507-511`）。
这也是为什么本清单要求：**`official: true` 只许出现在标题栏内**。

**§2-W1（网页侧 CSS 玻璃）**：`backdrop-filter` 是**网页自己**的合成层效果（Chromium 实现），
与 ArkUI 的 `uiMaterial` 是两套完全独立的管线：前者由网站 CSS 决定，后者由 `module.json5` 的 `UIMaterial.state` + 挂载点决定。
⇒ 本文把它单列一节，就是为了避免「我开了官方材质，所以网页那圈玻璃也变成官方材质了」这类误判。
（同源教训：模糊 API 的选择见 `§3.0-74`。）

---

## 3 · 官方分支的零自绘层（本轮判据）

对 `T1`/`T2`/`T3` 改完后的源码，必须能机械核验下面两条（依据 B）：

1. 官方材质所在的那一行/那一层，**不含** `backgroundEffect(` / `.shadow(` / `linearGradient(` /
   `radialGradient(` / `.borderColor(` / `.borderWidth(` / 自绘 `.backgroundColor(`；
2. `ShellIconButton` 的两个分支**几何逐字相同**（`ICON_BTN_VISUAL` / `FS_ICON_BTN` / `ShellIconHotRegion`），
   这样「自绘 ↔ 官方」的 A/B 只差「哪一层在画底」，逐像素差值才可归因（`:501-503` 的原话）。

**本清单给出的复跑命令**（§5 有实测输出）：

```text
node scripts/check-docs.mjs（文档控制字符/链接检查脚本，属开发工作区工具，未随本仓库发布）
grep -n "backgroundEffect(\|\.shadow(\|linearGradient(\|systemMaterial(" entry/src/main/ets/view/TopBar.ets
grep -rn "Navigation(\|NavDestination(" entry/src/main/ets
```

---

## 4 · 未验证 / 未完成（如实登记，真机结论一律标注证据力）

| 项 | 状态 | 证据力 |
| --- | --- | --- |
| 顶栏官方材质 / 框架栏模糊**是否真的画出像素** | **T3 已验证**（`REPORT.md`）：**框架栏模糊真的糊住正文** = 同一行 `gradX` OFF **8.523** / IMM **0.374** = **22.8×**（dark 23.8×）+ 栏外 MAE **0.0022** ⇒ **可断言（强）**；**交付默认臂无新增分界** = 逐行均值最大一阶差分 **5.26 @ y=77** ↔ 改前 **5.25** ⇒ **可断言（强）**。⚠️「原定臂（IMM vs OFF 中段 MAE）被证伪为无效、已换臂」的过程见 [`EXPERIENCE.md` §9.2-6](../EXPERIENCE.md) | 已验证（强） |
| 换 `Navigation` 标题栏后的**几何** | **T3 已验证（强）**：`window.__dshTopInsetPx` = **111.714287**（×dpr = **332px**）与转储网页首个容器顶边 **333px** **双来源吻合**（改前 291px）。⚠️ 原 T4 判据「**不得超过改前**」已被**用户真机拍板覆盖**（实际 **+14vp**，因果链见 §勘误节）⇒ 该判据**本轮不适用**；替代判据 = ① 让位量落地准确（已验）② 正文首行不落进模糊区（逐行曲线 y=332 处仅 2 级，已验） | 已验证（强） |
| `lightEffect: { color: Color.White }` 是否会在玻璃顶缘合成一条**亮线** | **真机未验证** ⚠️ —— 本工作区**有反例**：`§3.0-13` 记录 DshMobile 上「`ImmersiveMaterial` 开 `lightEffect` … 会在玻璃胶囊顶缘合成一条**锐利贯穿亮线**」，那里的处置是「不用 `lightEffect`」。本工程按用户诉求「按钮走官方沉浸光感」选了 `lightEffect` + `interactive` ⇒ **必须取证**：顶栏 ROI 的竖直剖面里出现单像素级高亮带即为命中的形态 | 未验证（已知反例） |
| 按钮挂 `systemMaterial` 是否会把图标/文字**洗白**（可读性） | **真机未验证** ⚠️ —— `§3.0-58` 记录 PrismAgent 上「材质会把实色洗白（`#E600A3B4` → `(150,247,253)`，白字不可读）」，其结论是「**按钮不要用 systemMaterial**」。本工程的差异：`ShellIconButtonOfficial` 是 `ButtonStyleMode.TEXTUAL`、**无实色底**，`materialColor` 走带 alpha 的 `icon_btn_material`（`:33F2F2F3` / `#242A2A2C`）⇒ 与那处的场景不同，但**不能据此断定安全** | 未验证（情景不同，风险未消除） |
| 上传半模态（`I1`）在 `ENABLE` 档下宫格是否被材质改变观感 | **真机未验证** —— 见 §2-I1；判据 = 半模态打开态截图与改前基线比对（同页、同深浅色） | 未验证 |
| 顶栏按钮与栏下沿的**真实触摸穿透** | **T3 已验证**：侧栏钮真实点击 + 效果回读（节点 97→170）**可断言（强）**；栏下缘 y=350 穿透成功（probe=1）**可断言（强）**；⚠️ **栏覆盖区（0..332）内网页元素是否可点 / 是否回归** = **不可断言**（缺同口径改前对照，`REPORT.md` §7-1） | 见左 |
| 改后顶栏的**深浅色两态**观感 | **真机未验证** —— 双值资源 `shell_topbar_glass` / `icon_btn_material` 已存在（§6），但材质与双值色的叠加结果只能真机看 | 未验证 |

> ⚠️ **本清单的「范围内」判定是源码级 + SDK 原文级结论（可断言）**；
> **「真机上是否画出像素 / 是否出现硬边」一律未验证**，以 `./内部验证记录` 为准。

---

## 5 · 本轮实际执行的核验命令与输出摘要

全部命令在仓库根目录执行；`grep` 用 ripgrep 语法，`path` 为 `./entry/src/main/ets`。

```text
1) 全工程找现存的官方材质接入点
   pattern: systemMaterial   → 3 处全部命中 common/ShellUi.ets（:363 注释、:496 注释、:534 真实调用）
   pattern: backgroundEffect\( → 2 处：view/SidePane.ets:1166、view/TopBar.ets:185
   pattern: linearGradient\( → 1 处：view/TopBar.ets:209
   pattern: \.shadow\(       → 6 处（其中 2 处是注释）：pages/Index.ets:2595、:2762、view/SidePane.ets:1205
   pattern: backgroundBlurStyle → 3 处**全部是注释**（SidePane:1158、TopBar:16、TopBar:180）⇒ 工程内零实际使用
   pattern: backdropBlur     → 2 处**全部是注释**（SidePane:1146、TopBar:178）
   pattern: bindSheet        → 9 处（真实挂载点只有 pages/Index.ets:2205 一个，符合 §3.0-137）
   pattern: bindPopup        → 1 处，且是注释（pages/Index.ets:2733）⇒ 工程内零 bindPopup 调用
   pattern: blur\(           → 1 处，网页侧 CSS：utils/DeepSeekConfig.ets:275
2) 承载结构：pattern: Navigation\(|NavDestination\( → **0 处** ⇒ 改前全工程没有任何官方标题栏
3) 几何契约：pattern: TOP_BAR_H → 16 处；网页侧下移量见 pages/Index.ets:1150 / :1316-1317 / :1332
4) 应用级前置：build-profile.json5 的 targetSdkVersion = "26.0.0"（§0-H 的生效前提）
5) 官方来源：web_fetch 两个华为 URL 各 1 次 → statusCode=200 / 正文 1731 B / 两次内容逐字相同（SPA 外壳，见 §0-I）
   web_search 2 条 query → 取到第三方转述 3 条（sohu / m.sohu / ihonker），见 §0-I
```

本文件所引 SDK 行号全部来自 **本机** SDK 副本的**逐行阅读**（不是印象）：
`ets/api/@ohos.arkui.uiMaterial.d.ts`（531 行）、`ets/component/navigation.d.ts`（3127 行）、
`ets/component/common.d.ts`（27233 行）、`ets/component/tabs.d.ts`（1831 行）。

---

## 6 · 快照与基线（可复核 / 可回退）

**本文件对着的快照 = T2 落地前**（`view/TopBar.ets` / `pages/Index.ets` 的 mtime 仍是 2026-09-18，
即 T2 尚未写入这两个文件）：

| 文件 | md5（第二十轮动手前快照） |
| --- | --- |
| `entry/src/main/module.json5` | `7B2B28D25219AD0330382B6967C5BA18` |
| `entry/src/main/ets/common/ShellUi.ets` | `1A6AEB3A0867793E18311B014DE4BDCF` |
| `entry/src/main/ets/view/TopBar.ets` | `88DCF67FAD2DBD7C7A7D6E60B9007C9C` |
| `entry/src/main/ets/view/SidePane.ets` | `4A80FD6B28DF79E4E7168D66792BC491` |
| `entry/src/main/ets/pages/Index.ets` | `2F30C51F66C404D4C6C1761C13C395B9` |
| `entry/src/main/ets/utils/DeepSeekConfig.ets` | `E9A4C0B59DBE6C298C01E8A3A464A9EE` |
| `entry/src/main/resources/base/element/color.json` | `1764D7F52608D4ED34AED93EC67337CD` |
| `entry/src/main/resources/dark/element/color.json` | `C085690E18929862C19B2900087E83FE` |

> 说明：`module.json5` / `ShellUi.ets` / 两个 `color.json` 的 md5 是**T1 落地后**的值（它们已被 T1 改过）；
> `TopBar.ets` / `Index.ets` / `SidePane.ets` / `DeepSeekConfig.ets` 是**本轮之前**的值。
> 本工程**已被 git 跟踪**（`git ls-files -- .` = 974 个文件），
> 但工作区当前存在**未提交改动**（`git status --porcelain` 里这些文件都是 ` M`）
> ⇒ **回退基线以本表的 md5 为准，不要假设 `git checkout` 能回到「改前」。**

**本轮新增的资源令牌**（T1 落地，供材质用；**都带 alpha**，依据 §0-C）：

| 令牌 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `shell_topbar_glass` | `#40F2F2F3` | `#1728282A` | 顶栏材质色（改前是 `backgroundEffect` 的 `color`） |
| `shell_topbar_fade` | `#00F2F2F3` | `#0028282A` | 渐变过渡带终点（同 RGB、alpha=0） |
| `shell_panel_glass` | `#40F2F2F3` | `#1728282A` | 侧栏面板玻璃色（**保留自绘**，见 §2-S1） |
| `icon_btn_material` | `#33F2F2F3` | `#242A2A2C` | **按钮材质色**（`ShellIconButtonOfficial` 的 `materialColor`） |

---

## 7 · 相关文档

| 文档 | 内容 |
| --- | --- |
| [`specs/UI-DESIGN.md`](UI-DESIGN.md) | 顶栏 / 侧栏 / 材质口径的设计契约（§2 顶栏、§7 禁止事项） |
| [`PROJECT.md`](../PROJECT.md) | 工程现状（架构 / 配置项清单） |
| [`EXPERIENCE.md`](../EXPERIENCE.md) | 本工程专属踩坑与实测结论 |
| [`CHANGELOG.md`](../CHANGELOG.md) | 逐轮变更史（第二十轮条目） |
| [`common/ShellUi.ets`](../entry/src/main/ets/common/ShellUi.ets) | 设计令牌 + `OFFICIAL_MATERIAL` + `officialImmersiveMaterial()` |
| [`entry/src/main/module.json5`](../entry/src/main/module.json5) | 应用级开关 `ohos.arkui.UIMaterial.state` |
| 参考工程 `aa-hm` 的同类清单 | 本文体例来源（该工程未随本仓库发布） |
| 参考工程 `aa-hm` 的验证报告 | 证据力分级体例来源（§5） |
| 内部踩坑表 | 开发工作区跨工程通用踩坑全表（**未随本仓库发布**，`§3.0-N` 编号保留对照） |
| 开发工作区 `AGENTS.md` | 工作区总纲（目录纪律 / 环境 / 高频致命坑，未随本仓库发布） |
