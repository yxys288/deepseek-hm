# DeepSeek 鸿蒙端（deepseek-hm）· 项目现状

> 本文件只写**现状**；变更史见 `CHANGELOG.md`，踩坑与脚本手册见 `EXPERIENCE.md`。

> ⚠️ **开源发布说明**：本文件由工程内部文档整理而来。「内部验证记录」= 开发期的验证证据目录
> （整机截屏 / CDP 探针 / `dumpLayout` 读数，**未随本仓库发布**）；「内部踩坑表 `§3.0-N`」=
> 开发工作区的跨工程通用踩坑表编号（同样未随本仓库发布），编号保留以便与本项目内部记录对照。

## 1. 概述

- **一句话**：把 DeepSeek 官方网页端（`chat.deepseek.com`）封装成 HarmonyOS 应用——
  **原生 ArkUI 外壳 + ArkWeb 聊天区**：侧栏与顶栏由原生组件渲染，网页只承载聊天区
  （因此登录态与云端历史完整保留）。
- **形态**：Stage 模型单模块（`entry`）+ 服务卡片 ExtensionAbility；启动**沉浸全屏直入**
  聊天页，无独立软件首页（与安卓版观感一致）。
- **bundleName**：`com.example.deepseekhm`；`deviceTypes`：`phone` / `tablet`。
- **源码位置**：本仓库根目录。

## 2. 技术栈与基线

| 项 | 值 |
| --- | --- |
| SDK | `compatibleSdkVersion` / `targetSdkVersion` = `26.0.0`，`runtimeOS: HarmonyOS`（HarmonyOS 7 / API 26） |
| 签名 | **需自行生成**：DevEco Studio → File → Project Structure → Signing Configs → 勾选 Automatically generate signature（登录华为账号）；`products[0]` 必须引用签名配置（默认名 `default`），否则报 `No signingConfig found for product default`。开源版本的 `build-profile.json5` 已移除 `signingConfigs`（原含本机密钥库路径与口令） |
| 权限 | 仅 `ohos.permission.INTERNET` |
| 导航安全 | `onLoadIntercept` 只放行官方主域主框架；不放宽 `mixedMode` |
| 登录态 | 由 ArkWeb 内核管理（Cookie / domStorage / database）；覆盖安装必须 `hdc install -r` |
| 沉浸配置 | `loadContent('pages/Index')` 直入主页面；`setWindowLayoutFullScreen(true)` + 透明系统栏 + 随深浅色反白；避让区经 `avoidAreaChange` 落 `AppStorage`（`topHeightPx` / `bottomHeightPx` / `keyboardHeightPx`） |
| 沉浸材质 / 图标 | `UIMaterial.state` = **`enable`**（**第二十轮由 `disable` 改**；值必须小写）+ 顶栏走**官方 `Navigation` 标题栏**；分层图标 `layered_image`（主 logo 占 ~62% 安全区）；`startIcon.png` 为透明底蓝鲸鱼 |
| 资源 | 深浅双值 `color.json`（`shell_panel_glass` / `shell_topbar_glass` 浅 `#40F2F2F3` / 深 `#1728282A`；`icon_btn_material` 按钮材质色 浅 `#33F2F2F3` / 深 `#242A2A2C`） |

> **材质口径（第二十轮改写）**：`disable` 与 2026-09-11 那次修复**不是一回事** —— 另四个容器工程曾把该值误写成大写
> `"ENABLE"`（被静默忽略），当天已改为小写 `"enable"` 并重建通过；本工程当时**从未用该材质**，故保持 `disable`。
> 第二十轮改成 `enable` 的原因与代价：① 官方沉浸光感**只在 `Navigation`/`NavDestination` 标题栏等位置生效**，
> 顶栏因此先进栏（`§3.0-245`）；② 打开它会把「默认开启清单」（**含 `bindSheet`**）
> 一起翻到材质档（`§3.0-256`）；③ 回退开关是 `common\ShellUi.ets` 的 `OFFICIAL_MATERIAL`
> 与 `view\TopBar.ets` 的 `TOPBAR_FRAMEWORK_BLUR`（**一行**）。逐点裁决见 [`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md)。

## 3. 目录结构（源码关键文件职责）

`entry\src\main\ets\`（11 个 `.ets`）：

| 文件 | 职责 |
| --- | --- |
| `pages\Index.ets` | **原生外壳主页面**：`SideBarContainer(Overlay)` + 全窗口 `Web`；**第二十轮起 `MainPane` 用 `Navigation` 承载顶栏**（官方沉浸档；`OFFICIAL_MATERIAL=false` 时退回 R19 的 `Stack` + 悬浮 `TopBar`）；桥回调分发、层序契约、`SplashOverlay` / `ErrorPane` / `NewChatTipLayer` 覆盖层、删除队列串行驱动（第十六轮把 17 个 `@State` 拆成四个子组件） |
| `view\TopBar.ets` | **原生顶栏**（第十六轮新增）：单层三槽 `Row`（左槽 / 标题槽 `layoutWeight(1)` / 右槽，**左右槽等宽固定 `SLOT_W` = `ICON_BTN + GAP_SM` = 52**，R19 由 96 收敛）⇒ 标题严格居中且不随按钮数漂移，**命中面天然就是按钮本身**；**第二十轮起本组件是 `Navigation.title(...)` 的标题栏构造器**（`official: true`）：栏本体模糊走框架栏 `backgroundEffect`、3 个按钮走官方沉浸光感；改名前叫 `TOPBAR_BAR_MATERIAL` 的开关现名 `TOPBAR_FRAMEWORK_BLUR`（语义与旧名相反，见 `EXPERIENCE.md` §9）、几何常量 `NAV_TITLE_SLOT_VP`(66) 与网页让位同源；教训见 `specs\UI-DESIGN.md` §7-9（`Stack` 三层 + `hitTestBehavior` 会吃掉整条顶栏点击） |
| `view\SidePane.ets` | **原生侧栏面板**：面板头（☰ / 选择 / ⊕ / ×）、搜索、分组会话列表（inset grouped：行高 44 / 分隔线内缩 / 分组头 / 按压底色过渡）、账号页脚、批量选择栏；三重避让、22vp 圆角、`backgroundEffect` 磨砂集中在此 |
| `view\SettingsTabBar.ets` | **设置页底部功能栏**（第二十一轮新增）：**原生自绘悬浮胶囊**，形态参考 `aa-hm` 的 `ui/BottomNav.ets` 那条自绘路径（全圆角 + `backgroundEffect` 磨砂 + 同源渐变光层 + 亮边），四项「图标上、文字下」、选中走 `accent`；页签语义由原生承载，点击经桥 `setSettingsTab(i)` 驱动网页切页签。令牌全部来自 `ShellUi` 的 `TABBAR_*`，组件内零裸魔数 |
| `utils\ShellScript.ets` | **网页侧桥脚本** `SHELL_JS`：会话抽取（`TreeWalker` 零几何）/ 路由上报 / 官方顶栏与抽屉让位 / 遮罩与弹窗接管 / 首页钉高 / 输入框滚动条治理；暴露 `window.__dshShellApi`；巡检 ticker 第十六轮由 3s 放宽到 **5s**（+ `visibilityState` 门控 + 路由脏标记，强制全查安全网仍 ~30s） |
| `utils\DeepSeekConfig.ets` | 常量 + **移动端兜底适配** `MOBILE_ADAPTER_JS`（安全区、横向溢出、弹层限宽高、代码换行、入口隐藏、巡检门控） |
| `common\ShellUi.ets` | **设计令牌表**（第十五轮建立，第十六轮扩为完整令牌表）：尺寸（`TOP_BAR_H` 52 / `ICON_BTN` 44 / `BTN_H_MD` 44 / `BTN_H_SM` 32 / `ROW_H` 52 / `LIST_ROW_H` 44 / `GROUP_ROW_H` 30）、间距 `GAP_*`、内缩 `LIST_INSET`/`SEP_INSET`、圆角 `RADIUS_*`/`PANEL_RADIUS`、发丝线 `HAIRLINE`、阴影 `SHADOW_*`、动效 `MOTION_*`/`CURVE_STD`、按压 `PRESS_OPACITY`（`PRESS_SCALE` 第十八轮已删除）、模糊/亮度 `PANEL_BLUR`/`TOP_BAR_BLUR`/`DARK_BRIGHTNESS`、**官方沉浸材质入口 `officialImmersiveMaterial()` 与回退开关 `OFFICIAL_MATERIAL`（第二十轮新增）** —— **全工程唯一数值来源**，规范见 `specs\UI-DESIGN.md` |
| `model\ShellTypes.ets` | 原生↔网页数据契约：`ChatSessionItem` / `SideRow` / `ShellMessage`（`sessions` / `route` / `ready` / `account` / `deleted`） |
| `entryability\EntryAbility.ets` | 沉浸式窗口与系统栏配色、`loadContent('pages/Index')`、避让区桥接、卡片拉起参数、`--ps colorMode` 调试钩子、`onMemoryLevel` → `trimMemoryByPressureLevel`、`initializeWebEngine` 预热 |
| `entryformability\EntryFormAbility.ets`、`widget\pages\WidgetCard.ets` | 服务卡片（2x2/2x4/4x4），点击 `postCardAction` 拉起并新建对话；周期刷新第十六轮关闭 |

其余：`AppScope/`、`hvigor/`、`build-profile.json5`、`hvigorfile.ts`、`oh-package.json5`、`.gitignore`、
`specs/`（**设计文档**：`UI-DESIGN.md` = iOS 参考的 UI 规范与设计令牌定标）、
`iconwork/`（图标制作源）。

> **开源版移除的内容（不影响构建与运行）**：
> - `verify-*/`：开发期的验证证据目录（整机截屏、CDP 探针、`dumpLayout` 读数）；
> - `.workbuddy/`：协作工具的工作目录；
> - `README-source.md`：迁入本仓库前的旧版 README（其中描述的 `pages/WebPage.ets` 等文件已删除）。
>
> 下文凡提到这三个目录的地方，均指开发期工作区。

## 4. 关键实现（需求 → 实现）

| 需求 | 实现 |
| --- | --- |
| 沉浸全屏直入 | 启动即 `loadContent('pages/Index')`（旧 `pages/WebPage` 已删除）；`setWindowLayoutFullScreen(true)` + 透明系统栏 + 网页安全区避让 |
| 原生外壳 + ArkWeb 聊天区 | `SideBarContainer(Overlay, sideBarWidth '82%', maxSideBarWidth 352)` 包 `SidePane` + `MainPane`；层序固定 **内容 → 接管层 → 顶栏 → Splash/Error 覆盖层**（层序即命中顺序） |
| 侧栏原生渲染 | 会话由 `SHELL_JS` 抽取后经 `javaScriptProxy('dshBridge')` 上报，`SideRow` 拍平成一维 `List`；搜索纯内存过滤，打开即定位当前会话 |
| 官方抽屉只作数据源 | 抽屉 `visibility:hidden`（**不能 `display:none`**，要保住 DOM 与布局），**连兄弟遮罩一起接管**；抽不到会话时 `reveal()` 把官方外壳交还用户 |
| 深浅色跟随 | `WebDarkMode.Auto` + 双值资源；`onConfigurationUpdate` → 系统栏换色 + `AppStorage.currentColorMode` → `Index.onColorModeChange` 校验网页 `prefers-color-scheme`（不一致 `refresh()`，一致则重注入）；钩子 `--ps colorMode dark|light` |
| 磨砂 / 材质 | **第二十轮起分两档**：① **顶栏（官方沉浸档）** = 官方 `Navigation` 标题栏，模糊由框架栏的 `NavigationTitleOptions.backgroundEffect` 供给（同 `radius`/`saturation`/`brightness` + 同一个 `shell_topbar_glass` 令牌），栏内 3 个按钮走官方沉浸光感 `.systemMaterial()`；② **侧栏面板** = 仍自绘 `backgroundEffect({radius: PANEL_BLUR, saturation:1.0, brightness:1.0, color: $r('app.color.shell_panel_glass')})`（面板在 `SideBarContainer` 内容槽里，**不在**官方生效范围，见 `specs\MATERIAL-ACCESS-POINTS.md` §2-S1）；两种都**不用** `backgroundBlurStyle`（那是材质、会接管背景填充）。逐点裁决与依据见 `specs\MATERIAL-ACCESS-POINTS.md` |
| 键盘"原地不动" | 首页把应用根高度钉在键盘未弹出时的高度（`pinHomeLayout`），长草稿按"底边不越过键盘上沿"回推高度；**只对首页生效**（对话页输入坞是贴底 sticky） |
| 批量删除 | 侧栏「选择」模式 → 串行驱动官方 DOM（行内 ⋯ → 菜单「删除」→ 确认「删除该对话」），每步等网页 `{t:'deleted'}` 回报，8s 看门狗；带"用户在场"安全闩（未进选择模式返回 `locked`） |
| 服务卡片 / 图标 / 启动动画 | Form 2x2/2x4/4x4 点击拉起并新建对话；分层图标由系统超椭圆遮罩裁切；启动动画只留透明底蓝鲸鱼（`startIcon`，无圆角）+「探索未至之境」逐字跳出（200ms/字），`start_window_background` 与 `bg_page` 对齐消除跳色 |
| 移动适配兜底 | `MOBILE_ADAPTER_JS`（`onPageEnd` 注入）：禁横向溢出 / 弹层限宽高 / 代码换行 / `viewport-fit=cover` / 入口隐藏 + SPA 路由监听；**不设**全局 `button{min-height:40px}`（会把官方圆形按钮拉成椭圆） |
| 设置页底部功能栏（**第二十一轮**） | **官方 `Navigation` 工具条承载 + 栏内悬浮胶囊**（最终档）：`pages\Index.ets` 的 `MainPane` 挂 `.toolbarConfiguration(this.SettingsToolbar(), settingsToolbarOptions())` + `.hideToolBar(routeKind !== 'settings')`；胶囊形态仍按 `aa-hm` 的底部功能栏做（全圆角 = 高/2 + `backgroundEffect` 磨砂 + 亮边，令牌 `TABBAR_*`）。**为什么必须走框架层**：`ArkWeb` 是**独立合成图层**，`Stack` 里的普通原生浮层（哪怕放根 `Stack` 最顶层）在滚动/内容切换时会被它盖住或裁切 —— 工具条与本工程顶栏（同一 `Navigation` 的标题栏）同级，才拿到同一份「不被 Web 遮挡」的保证（详见 `EXPERIENCE.md` §10.5）。配套两条：工具条本身设 `Color.Transparent`（否则整条底色与胶囊叠成两层）、builder 用 `bottomPad` 避让系统手势条。**网页那一行页签改 `position:fixed` 不占位**（工具条已占位，避免双重留白）+ `opacity:0` 保留几何供派发；点胶囊 → 桥 `setSettingsTab(i)` → `tap()` 派发给官方页签；标题栏的 `<` → 桥 `closeSettings()`（配置浮层不改 URL，**不能**用 `history.back()`） |
| 网页「选择上传」接管 | `Web.onShowFileSelector` 返回 `true` 接管（ArkWeb 原本弹的那个系统窗**没有进场动效**）；改用**官方半模态 `bindSheet`**（`FIT_CONTENT` + 官方标题 + `$$` 双向绑定，动效/遮罩/圆角/下拉关闭全部系统负责）承载 图库 / 拍照或录像 / 文件 三项，分别拉起 `PhotoViewPicker` / `cameraPicker.pick` / `DocumentViewPicker`；选择器 URI **先复制进 `cacheDir` 沙箱**再 `handleFileList`（跨应用临时授权 URI 渲染进程读不到）；取消/返回键回空列表且不清已挂附件 |
| 错误页 / 兜底 | `ErrorPane`（SymbolGlyph + 光感按钮）；`Splash` 加载期全屏不透明覆盖、结束**瞬时**移除；`onErrorReceive` 只认 `isMainFrame()` |
| 侧栏账号菜单（第十六轮两度变更，**以此行现状为准**） | 账号页脚菜单 = **「系统设置」+「退出登录」**两项；「帮助与反馈」**维持移除**。口径变更史：本轮最初按用户要求把两项都去掉（当时理由是"点了不生效"），**第三批按用户要求恢复「系统设置」且这次真的修好了** —— "点击不生效"的真因是三层叠加（① `runJavaScript` 回传的是 JSON 文本、字符串带引号 ⇒ 精确全等比较恒假；② 官方账号入口在**隐藏抽屉**里，隐藏元素不接收点击；③ 链路是"先点开下拉菜单、再点系统设置"**两步**）。**安全属性没退回自由入参**：原生侧与桥侧各一道**同一份白名单**（`ACCOUNT_OPTION_SETTINGS` / `ACCOUNT_LOGOUT_LABEL`），与为 §3.0-93 立的规矩一致。「帮助与反馈」用户只点名恢复「系统设置」，故维持移除 |
| 设置入口"左下角闪一下"（第十七轮） | **真因**：官方账号下拉菜单是 React portal，挂在 body 级 `.ds-floating-position-wrapper` 下，**不在** `tapInHidden` 那条祖先链里 ⇒ 祖先链的 `opacity:0` 管不住它，整块可见 ≈290ms（rAF 采样 rect `[8,726,136,168]`、opacity 0→1→0，正是左下角）。**修法**：`pickAccountOption('系统设置')` 分支在**派发点击之前** `armMenuVeil()`，给「含 `.ds-dropdown-menu` 的浮层 + 菜单」打 `data-dsh-menu-veil`，由常驻样式表压 `opacity:0 !important; transition:none !important`（**只能动 opacity** —— visibility/pointer-events/display 都会破坏合成事件命中，而这条链路全靠 `dispatchEvent`）。**生命周期三条路都能落闩**：菜单节点从 DOM 消失（主路径）/ 3s 硬超时 / 「退出登录」分支显式落闩。详见 §3.0-154 |
| 侧栏面板圆角裁切（第十七轮二单） | 面板 Column 在 `.borderRadius(...)` 后加 **`.clip(true)`**：ArkUI 的 `borderRadius` 只作用于组件自身背景，**子节点默认不被父圆角裁剪** ⇒ 满宽子行（账号行的按压底色、列表最后一行的选中底色）会在面板右下圆角处露出直角。判据是像素级的：按住行逐行取底色最右 x，收窄 1px（改前 LEAK）→ 80px（改后 CLIPPED）；面板自身投影与顶角逐像素不变（clip 只裁子节点）。见 §3.0-160 |
| 设置页"滑动不出滑块"（第十七轮二单） | 四件一起：① `html[data-dsh-settings-open=1]` 标记随设置页开/关挂摘；② **隐藏滚动条**（`scrollbar-width:none` + `::-webkit-scrollbar{display:none}`，**覆盖 html/body 本身** —— 用户那条竖条几乎整屏高，是文档级的）；③ 隐藏站点自绘 `ds-scroll-area__gutters`；④ **消亚像素溢出**（官方 `--stretch` 把内容撑到取整的 734px，真实内容 733.997/内容盒 733.571 ⇒ 恒溢出 0.426px ⇒ 触摸就画滚动条；改 `min-height:0` + `pinSettingsBody()` 兜底）+ 钉页面（`overscroll-behavior:contain` + `touch-action:pan-y`，**不用** `none`，否则内层滚动一起死）。见 §3.0-161 |
| 系统设置弹层改手机版（第十七轮） | `MOBILE_ADAPTER_JS` 按「`.ds-modal-content__title` 文本 === `'系统设置'`」定位弹层 → 打 `data-dsh-settings-*` 属性（root / lock / modal / panel / main / maininner / tabs / tabstrip / tab / row / group / segrow / seg / body / bodyinner）→ **CSS 全部写在属性选择器上**并包在 `@media not all and (min-width: 768px)` 内。效果：全屏面板（top = topInset，去掉 152px 灰带）+ 标题行在滚动区之外固定 + 4 个页签 `flex:1 1 0` 等分不再裁切 + 圆角卡片行（60px / 16px 字号 / 发丝线）+ 主题三选一改分段控件；**配色不写死**，由 `syncSettingsColors()` 从官方弹层实测色采样后写成内联 CSS 变量（跟随页面主题，含"跟随系统"下的深色）。桌面（≥768px）打标整体跳过、零影响 |

## 5. 构建与运行

### 5.1 DevEco Studio（推荐）

1. `File > Open` 打开本仓库根目录，等待 Sync 完成；
2. `File > Project Structure > Signing Configs` → 勾选 **Automatically generate signature** 并登录华为账号
   （**必须**：没有签名只能得到未签名 HAP，装不到设备上）；
3. `Build > Build Hap(s)/App(s)` 生成签名 HAP；
4. 连接设备后点 **Run entry**，或按 §5.3 用 hdc 安装。

### 5.2 命令行构建（hvigorw）

```bat
set DEVECO_SDK_HOME=<DevEco Studio 安装目录>/sdk
set NODE_HOME=<DevEco Studio 安装目录>/tools/node
set PATH=<DevEco Studio 安装目录>/jbr/bin;%PATH%
"%NODE_HOME%/node.exe" "<DevEco Studio 安装目录>/tools/hvigor/bin/hvigorw.js" --mode module -p product=default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（未配置签名时降级为 `entry-default-unsigned.hap`）。

### 5.3 安装到设备（开发者模式侧载）

> ⚠️ HarmonyOS NEXT 起**不支持**双击 / 文件管理器安装 HAP（不像安卓装 APK），装机只能经 `hdc` 侧载；
> 而 `hdc` 通道要求设备已开启**开发者模式 + USB 调试**。逐步操作见 [`README.md`](README.md) 的「开发者模式侧载安装」一节。

```bat
hdc list targets                                  rem 列出在线设备（真机/模拟器）
hdc -t <sn> install -r entry-default-signed.hap   rem 覆盖安装，保留登录态/Cookie
hdc shell aa force-stop com.example.deepseekhm
hdc shell aa start -a EntryAbility -b com.example.deepseekhm
hdc shell snapshot_display -f x.jpeg              rem 截屏（只接受 .jpeg）
```

- 多设备并存时**一律显式** `hdc -t <sn>`，否则可能装到另一台设备上（表现为「改动没生效」）。
- ⚠️ `hdc install` 打印 `[Fail]` 时**退出码仍是 0**，别只看退出码；`hdc uninstall` 会**连 ArkWeb 的 Cookie 一起清掉**，升级/验证一律用 `install -r`。
- 模拟器：DevEco 的 `Emulator.exe -start "<设备名>"` 启动后同样用 `hdc install`。

### 5.4 验证与回归

开发期的验证证据（整机截屏 / CDP 探针 / `dumpLayout` 读数）**未随本仓库发布**。
改官方适配脚本（`MOBILE_ADAPTER_JS` / `SHELL_JS`）后，建议先跑注入脚本预检再装机。

## 6. 卸载、登录态与数据清理

本应用**不落任何自有账号体系**：登录态与云端历史全部由 ArkWeb 内核管理（Cookie / domStorage /
database），本地只多两类东西 ——

| 位置 | 内容 | 怎么清 |
| --- | --- | --- |
| ArkWeb 内核数据区 | Cookie、localStorage、IndexedDB（登录态、会话缓存的本地副本） | `hdc uninstall com.example.deepseekhm`（会清，也会清掉登录态）；或在应用内用官方网页的「退出登录」 |
| 应用沙箱 `cacheDir` | 网页「选择上传」时落的临时副本（文件名前缀 `dsh-upload-`） | 每次拉起选择器前按前缀自动清理；`卸载` 一并清除 |

**覆盖安装不会丢登录态**（`hdc install -r`），**`uninstall` 会**（连 Cookie 一起清）。
因此验证/升级一律用 `install -r`；确需卸载前先确认登录态可弃
（依据见 `内部踩坑表` §3.0-71`、本文件 §5）。
真实登录态是"从官方 DOM 抽取会话列表"这类功能的验证前提，**不要随手卸载**。

## 7. 隐私与权限说明

- **本应用是第三方站点的容器**：内容、账号与数据都在 `chat.deepseek.com`（运营方为深度求索）。
  用户的对话内容、账号信息由该站点按其自身条款与隐私政策处理，**本应用不做二次收集、
  不上报任何统计、不接入任何第三方 SDK**。
- **权限**：仅 `ohos.permission.INTERNET`。文件/相机/图库的访问走系统选择器与安全控件
  （`PhotoViewPicker` / `cameraPicker` / `DocumentViewPicker`），**不申请**读写媒体库或
  文件的常驻权限（见 §2 权限行与 §4「网页『选择上传』接管」）。
- **网络边界**：主框架导航限制在同源白名单（`chat.deepseek.com` / `deepseek.com` /
  `www.deepseek.com`，大小写与默认端口归一化比较），站外跳转被拦截并给用户可见提示；
  **不放宽** `mixedMode`，不注入任何远程脚本，所有注入脚本都随包内置（`utils/*.ets`）。
- **调试通道**：ArkWeb DevTools 开关仅用于开发期取证
  （`setWebDebuggingAccess` 不指定端口即只建 unix socket、局域网不可达）；
  发布态不保留任何可远程触发的调试后门（`--ps colorMode` / `--ps action` 是启动参数，
  只能由本机 `aa start` 注入）。
- **免责声明（建议随应用内文案/隐私政策一并给出）**：本应用为个人封装的第三方容器，
  与深度求索无隶属关系；服务可用性、账号与数据安全以官方为准，因官方改版导致的
  功能异常会尽力修复但不作保证。

## 8. 版本号与版本历史

版本号在 `AppScope/app.json5`：`versionCode 1000000` / `versionName 1.0.0`。
`versionCode` 的编码约定：**主版本×1000000 + 次版本×10000 + 修订×100**（与 DevEco 默认一致），
本轮系列改动都未跳版本号（同一次开发周期内的修复与优化）。

变更历史按轮次记在 [`CHANGELOG.md`](CHANGELOG.md)：
第一~十一轮（2026-09-05~11，能力建设）→ **第十二轮（2026-09-11，整理轮：迁移与瘦身）** →
第十三轮（上传接管）→ 第十四轮（审查问题修复 P0+P1）→ 第十五轮（P2 官方组件与 UI 统一）→
**第十六轮（2026-09-15，UI 统一与动效 / 残余 BUG / 内存与速度 / 文档订正）** →
第十七轮（设置页手机版 + 浮层闩）→ 第十八轮（顶栏丢包带根治）→ 第十九轮（iOS 对齐 UI）→
第二十轮（顶栏官方 Navigation 沉浸材质）→ **第二十一轮（2026-09-28，UI 官方组件/特效 + 逻辑适配 +
设置页适配收敛，真机验收通过，release 正式版已装机）**。
每轮都带证据目录路径与真机/模拟器标注。

> **轮次口径说明**：第十二轮是**整理轮**（源码迁入 ``、清 2.6GB 验证残留、文档分层为
> 三份），没有独立的用户需求与验收读数，`CHANGELOG.md` 里以「第十二轮（2026-09-11）：迁移与瘦身」
> 记录，不再写作「第十二轮之后」。

## 9. 崩溃与异常日志怎么拿

```bash
# 应用内所有 hilog（含本工程自己的 DeepSeekWeb / DeepSeekShell / DeepSeekHm 标签）
hdc -t <sn> shell "hilog -x | grep -E 'DeepSeekWeb|DeepSeekShell|DeepSeekHm'"
# 只留最近 200 行并抓崩溃族
hdc -t <sn> shell "hilog -x | grep -Ei 'cppcrash|jscrash|SIGABRT|SIGSEGV|render process exited'" | tail -200
# 崩溃落盘目录（设备侧）
hdc -t <sn> shell "ls -t /data/log/faultlog/faultlogger/ | head"
hdc -t <sn> file recv /data/log/faultlog/faultlogger/<文件> ./

# 网页侧异常：走 ArkWeb DevTools（开发期）
#   setWebDebuggingAccess 已开 → 取 pid → fport → CDP Runtime.consoleAPICalled
hdc -t <sn> shell "cat /proc/net/unix | grep webview_devtools"     # 拿 pid
hdc -t <sn> fport tcp:9283 localabstract:webview_devtools_remote_<pid>
```

本工程的注入脚本失败会打 `[DSH] ...` 前缀的 console 信息，`onConsole` 里只透传含 `[DSH` 的行，
所以"注入脚本有没有生效"看 hilog 里的 `DeepSeekWeb: [DSH-...]` 即可（§4）。
`Web.onRenderExited` 会打 `render process exited: <原因>`（第十四轮新增）。

## 10. 配置项清单

> **本节值为第二十轮（2026-09-25 ~ 09-26）冻结态的最终值**（顶栏材质与几何改动见各行的「第二十轮」括注）。
> 第十九轮按 iOS 官方截图对齐 UI：`SLOT_W` 96→52、
> 移除顶栏分享、首页去标题、按钮改圆形浅底、菜单三条→两条，新增 `RADIUS_LG`/`TILE_H`/`TILE_ICON`/
> `ICON_BTN_VISUAL`/`FS_ICON_BTN` 五个令牌与 `settings` 路由类别；上传半模态改三宫格 ——
> 变更史见 `CHANGELOG.md` 第十九轮。冻结前的第十八轮读数为 788,040 B / md5 `9d91b297a9665193b55618ac65d3996a`（备查）。
> 除末两行外，其余令牌都集中在 `common\ShellUi.ets` —— **全工程唯一数值来源**，规范与依据见
> `specs\UI-DESIGN.md`（1vp = pt：设备 1316×2832 / density 560 ⇒ 有效宽 376vp ≈ iPhone 12 mini 的 375pt）。

| 配置 | 位置 | 当前值 | 说明 |
| --- | --- | --- | --- |
| 站点地址 | `utils\DeepSeekConfig.ets` `DEEPSEEK_HOME` | `https://chat.deepseek.com/` | 唯一入口；改它等于换站点 |
| 顶栏高度（接缝常量） | `common\ShellUi.ets` `TOP_BAR_H` | 52 vp | **未变**；同时决定原生顶栏高与网页内容下移量 |
| 玻璃色（面板 / 顶栏） | `resources\{base,dark}\element\color.json` `shell_panel_glass` / `shell_topbar_glass` | 浅 `#40F2F2F3` / 深 `#1728282A`（两处同值） | **alpha 是观感与色差线的唯一旋钮**（§4 磨砂 / 材质）。**第二十轮新增 `icon_btn_material`**（按钮材质色：浅 `#33F2F2F3` / 深 `#242A2A2C`）：喂给 `officialImmersiveMaterial()` 的 `materialColor`，**必须带 alpha**（完全不透明会挡死材质滤镜，SDK `@ohos.arkui.uiMaterial.d.ts:325-327`） |
| 图标按钮直径 | `common\ShellUi.ets` `ICON_BTN` | 44 vp（原 40） | iOS 44pt 最小可点区对齐 |
| 主按钮高 / 紧凑按钮高 | `common\ShellUi.ets` `BTN_H_MD` / `BTN_H_SM` | 44（原 40）/ 32 vp | `BTN_H_MD` 与 `ICON_BTN` 同档 |
| 面板头 · 账号行高 | `common\ShellUi.ets` `ROW_H` | 52 vp | 未变 |
| 列表行高 | `common\ShellUi.ets` `LIST_ROW_H` | 44 vp（原 42） | 与 `ICON_BTN`/`BTN_H_MD` 统一成 44 |
| 分组头高 | `common\ShellUi.ets` `GROUP_ROW_H` | 30 vp（新增） | inset grouped 的分组标题行 |
| 圆角 | `common\ShellUi.ets` `RADIUS_SM` / `RADIUS_MD` / `PANEL_RADIUS` | 10 / 12（新增）/ 22 vp | 面板 22 为第十轮逐像素定标，别单独改 |
| 间距刻度 | `common\ShellUi.ets` `GAP_XS/SM/MD/LG/XL` | 4 / 8 / 12 / 16 / 20 vp（新增） | 消灭页面里散落的间距魔数 |
| 列表内缩 / 分隔线内缩 | `common\ShellUi.ets` `LIST_INSET` / `SEP_INSET` | 8 / 16 vp（新增） | 分隔线从内容起始内缩（iOS inset grouped 观感） |
| 发丝线 | `common\ShellUi.ets` `HAIRLINE` | 0.5 vp（新增） | 分隔线/描边统一用发丝线 |
| 阴影 | `common\ShellUi.ets` `SHADOW_R_SM` / `SHADOW_R_MD` / `SHADOW_DY_SM` | 8 / 16 / **2** | 第十八轮**删除** `SHADOW_DY_MD`(4)：零消费者 —— 唯一用大阴影半径的地方（侧栏面板）走的是「对称淡晕」（`offsetX/offsetY` 都是 0，真机逐像素定标，任何偏移都会在圆角处露硬边）。留处置注释 |
| 动效时长 | `common\ShellUi.ets` `MOTION_FAST` / `MOTION_NORMAL` / `MOTION_SPLASH` | 150 / 250 / 420 ms | 第十八轮**删除** `MOTION_SLOW`(350)：零消费者 —— 面板开合由官方 `SideBarContainer` 自己的动画负责（`specs\UI-DESIGN.md` §4 明文禁止在面板上再套 transform 动画），它成了「看着像配置项」的假旋钮 |
| 动效曲线 | `common\ShellUi.ets` `CURVE_STD` | `Curve.FastOutSlowIn`（新增） | 与官方组件默认动效观感对齐 |
| 按压反馈 | `common\ShellUi.ets` `PRESS_OPACITY` | 0.6 | 第十八轮**删除** `PRESS_SCALE`(0.98)：零消费者，且 iOS 的按压语义本来就是「变底色」不是缩放（缩放锚点还会让长标题行视觉跳动） |
| 模糊半径 | `common\ShellUi.ets` `PANEL_BLUR` / `TOP_BAR_BLUR` | 24 / **6** vp | 第十六轮第四批：`TOP_BAR_BLUR` 由 24 → 12 → **6**（两次下调，对标华为系统设置沉浸顶栏的"字形可辨"观感）。**两者已解耦** —— 旧注释"必须同值以免糊↔更糊分界"不成立（面板与顶栏各在自己层上模糊，不共面），真机复核见 `内部验证记录`。**第二十轮**：`TOP_BAR_BLUR` 这三个参数（半径/饱和度/亮度 + 同一个玻璃色令牌）**原值搬进**框架标题栏的 `backgroundEffect`，只换"谁在画底" |
| 顶栏模糊的**边界外溢** | — | 半径越大外溢越多 | **本轮核心机制**：`backgroundEffect` 的高斯模糊会在组件矩形**之外**继续采样 ⇒ 实际生效高度 = 顶栏高度 + 外溢量。24vp 时顶栏下沿外约 10vp 的正文仍糊成一块（`real-device-r4/same24-3.jpeg`），6vp 时同位置逐字可读（`b6-3.jpeg`）。**判据是对标观感，不是"有没有外溢"** |
| 模糊的饱和度 / 亮度 | `common\ShellUi.ets` `BLUR_SATURATION` / `BLUR_BRIGHTNESS` | 1.0 / 1.0 | 第十八轮新增：顶栏与侧栏面板**必须同值**（各自对背后内容做同一档高斯模糊）。收敛前同一语义在工程里有三种写法（`1.0` / `DARK_BRIGHTNESS` / `isDark ? 1.0 : 1.0`） |
| 深色亮度补偿 | `common\ShellUi.ets` `DARK_BRIGHTNESS` | 1.0（= `BLUR_BRIGHTNESS` 的**别名**） | 第十八轮口径收敛：真机逐像素实测「玻璃色 alpha 归零时模糊区与页面底色完全相等」⇒ 模糊本身中性、色差 100% 来自玻璃色叠加，深色补偿在数值上不存在。**导出名按 RULES §1.5 保留**（W3 在依赖），新代码一律用 `BLUR_BRIGHTNESS` |
| 最小触控目标 | `common\ShellUi.ets` `HOT_MIN` | 44 vp（= `ICON_BTN` 的别名） | 第十八轮新增：可见高度只有 `BTN_H_SM`(32) 的文字按钮用 `.responseRegion()` 把**可点**高度补到本值（面板的「完成 / 全选 / 删除」三处） |
| 图形边长 | `common\ShellUi.ets` `SEARCH_H` / `ICON_INLINE` / `SPINNER_SIZE` / `AVATAR_SIZE` | 36 / 18 / 24 / 28 vp | 第十八轮由 `view\SidePane.ets` 上收（该文件不再声明任何外观数值）。同类值在本工程分裂过（审计 U-11：同一个转圈 18 与 26 两套） |
| 菜单图标几何 | `common\ShellUi.ets` `MENU_BAR_W_LONG` / `_SHORT` / `_MID` / `MENU_BAR_H` / `MENU_BAR_RADIUS` / `MENU_GLYPH_W` / `MENU_GLYPH_H` | 19 / 13 / 16 / 2 / 1 / 24 / 18 vp | 第十八轮由 `view\TopBar.ets` 上收。**不是间距刻度**：19/13/16 的错落是「长短不一」观感的唯一来源（SDK 里的 hamburger 类符号都是等长造型，故自绘） |
| 顶栏渐隐带的渐变 | `common\ShellUi.ets` `FADE_ANGLE_DOWN` / `FADE_STOP_GLASS` / `FADE_STOP_CLEAR` | 180° / 0.0 / 1.0 | 第十八轮新增：渐隐带的**方向与两个端点**不再就地写裸值 |
| 面板避让 | `common\ShellUi.ets` `EDGE_GAP` | 0 vp | 未变 |
| 面板右缝 | ~~`common\ShellUi.ets` `DRAWER_RIGHT_GAP`~~ | **已删除** | 零消费者，**留说明注释**（`ShellUi.ets:213`）备查 |
| 面板投影偏移 | ~~`view\SidePane.ets` `PANEL_SHADOW_DX`~~ | **已删除**（改对称淡晕） | 第十六轮真机复核：横向偏移投影会在**圆角外侧**露直角阴影、形成竖直硬边；现为 `offsetX: 0, offsetY: 0` + 半径走 `SHADOW_R_MD`(16)，同样**留说明注释**（`SidePane.ets:46`） |
| 顶栏渐隐过渡带高度 | `common\ShellUi.ets` `TOPBAR_FADE_H` | **16 vp**（第十八轮新增；**第二十轮起官方档不再使用**） | 过渡带的定义已收口到 `view\TopBar.ets` 的全局构建函数 `TopBarFadeBand()`：玻璃色保持到主体下沿，再在 `TOPBAR_FADE_H` 内**渐隐到全透明** ⇒ "由下自上逐渐模糊"（第十六轮用户第 2 条要求）。**第二十轮**：官方档删除它 —— 官方模糊的边缘已接替"抹平磨砂方块下缘"这一职责，留着会在自己边缘产生**第二条分界**；仅自绘回退档仍在用 |
| 顶栏渐隐色（同 RGB、alpha=0） | `resources\{base,dark}\element\color.json` `shell_topbar_fade` | 浅 `#00F2F2F3` / 深 `#0028282A`（新增） | **必须与玻璃色同 RGB、只把 alpha 归零** —— 用 `Color.Transparent`（透明**黑**）会让过渡带插值**发灰** |
| 面板/顶栏描边 | ~~`resources\...\color.json` `shell_panel_edge`~~ | **已删除**（不再画描边） | 第十六轮第三批：面板右缘与顶栏底边的发丝线就是用户说的"**明显界线**"，两条线都删，边界改由"玻璃色差 + 对称淡晕 + 渐隐过渡带"（都是渐变）表达 |
| 顶栏按钮槽宽 | `view\TopBar.ets` `SLOT_W` | **52 vp** | = `ICON_BTN + GAP_SM`（44+8）；左右槽等宽固定 ⇒ 标题严格居中。**第十九轮由 96 收敛**（移除顶栏「分享会话链接」后右槽恒为 1 个按钮）；本轮据源码订正本行旧值「96 vp（新增）」 |
| 标题栏槽高 / 网页让位加数 | `view\TopBar.ets` `NAV_TITLE_SLOT_VP` | **66 vp**（第二十轮新增） | = 框架栏高 112 − 状态栏 46。**一个常量两个用途**：① 标题栏构造器请求高度（实测被框架钳到 56vp，写 66 与写 56 落点相同）；② 网页侧让位量的加数（必须是 66，否则正文首行落进模糊区）。实测标定见 `view\TopBar.ets` 文件头 |
| 启动页时序 | `pages\Index.ets` `SPLASH_MAX_MS` / `SPLASH_MIN_MS` / `SPLASH_TYPE_MS` | 1200 / 800 / 130 ms | 原 `SPLASH_HOLD_MS = 2200` **已删除**；改为"首个 `sessions` 到达 ∧ 最短 800ms，或 1200ms 硬超时"，逐字间隔 200 → 130（6 字共 780ms，在最短窗口内打完） |
| 外壳巡检 ticker | `utils\ShellScript.ets` | 5 s（原 3 s） | + `visibilityState` 门控 + 路由脏标记；**强制全查安全网墙钟仍 ~30 s** |
| 金属/抽屉搜索节流 | `utils\ShellScript.ets` | 5000 ms | `drawerSearchedAt` 门控 |
| 巡检间隔（网页侧适配器） | `utils\DeepSeekConfig.ets` `patrolInterval` | 5000 ms | 第十四轮由 2s 放宽；带可见性门控 |
| 删除看门狗 | `pages\Index.ets` `armDeleteWatchdog` | 8000 ms | 单步未回报即推进并计失败 |
| 上传看门狗 | `pages\Index.ets` `armPickerWatchdog` | 8000 ms | 面板没呈现时复位，避免网页侧永挂"上传中" |
| 避让区去抖 | `entryability\EntryAbility.ets` `AVOID_DEBOUNCE_MS` | 100 ms | 同值不写（0.5vp 容差） |
| 卡片周期刷新 | `resources\base\profile\form_config.json` | `updateEnabled: false`（原 true） | 第十六轮关闭，并删除 `scheduledUpdateTime` / `updateDuration` |
| 注入脚本体积（剥注释后） | 适配器 / `SHELL_JS` | **65,317 / 43,914 字符** | 第十九轮收口读数。⚠️ **单位口径**：这是 `String.length`（UTF-16 码元）数，**不是字节**；真实 UTF-8 为 65,613 / 44,362 B。第十六轮的 46,013 / 37,100 同属该口径 ⇒ **纵向比较成立**（P2-10）。且**权威口径是"渲染后 + 剥注释"的文本**——模板原文在 ArkTS 求值阶段会还原转义，两者差值恰等于模板内成对反斜杠的处数（SHELL_JS 差 3、适配器差 18），可当"转义指纹"用 |
| 诊断日志（跨组件刷新链） | `pages\Index.ets` + `view\SidePane.ets` | `route filled: active=N` / `sessions applied: rows=N active=N cur=…`（Index）+ `sideRows in: n=N active=N` / `filter recomputed: n=N active=N q=…`（SidePane） | 第十六轮新增：**只在状态真变化时输出**，运行期成本可忽略；用于跨组件边界的刷新链定位（B8 就是靠它一步定位到"数据层对、渲染层断链"，见 `§3.0-152`） |
| 材质 metadata | `module.json5` `ohos.arkui.UIMaterial.state` | **`enable`**（第二十轮由 `disable` 改；**值必须小写**） | 应用级闸门：只开它不给任何组件画材质，但会把「默认开启清单」（含 `bindSheet`）一起翻到材质档（`§3.0-256`）。真正的绘制由挂载点决定：顶栏 = 框架标题栏 `backgroundEffect` + 按钮 `.systemMaterial()`（§4 磨砂 / 材质） |
| 设备类型 | `module.json5` `deviceTypes` | `phone` + `tablet` | 平板双栏**未实测**，见 `内部验证记录` §3 |
| 设置页底部功能栏几何 | `common\ShellUi.ets` `TABBAR_H` / `TABBAR_ICON` / `TABBAR_LABEL_FS` / `TABBAR_SIDE_MARGIN` / `TABBAR_BLUR` / `TABBAR_RADIUS` | 54 vp / 22 vp / 11 fp / 12% / 18 vp / 27 vp（= 高/2） | **第二十一轮新增**：取值口径对着 `aa-hm` 的底部功能栏复刻（那条路径有真机 Δ+16.0 判据）。`TABBAR_BLUR` 与 `TOP_BAR_BLUR`(6) / `PANEL_BLUR`(24) **分开** —— aa-hm 的实测结论是「共用的 6 对 54vp 的底栏太轻」 |
| 底栏玻璃色 / 亮边 / 光层 | `resources\{base,dark}\element\color.json` `shell_tabbar_glass` / `_rim` / `_sheen` / `_sheen_clear` | 浅 `#E6FFFFFF` / `#1A000000` / `#40FFFFFF` / `#00FFFFFF`；深 `#E6202023` / `#1FFFFFFF` / `#14FFFFFF` / `#00FFFFFF` | **第二十一轮新增**（深浅逐键成对）。**不复用** `shell_panel_glass`：后者 alpha 25% 是为与页面底色配平（R10 逐像素定标），叠在设置页底色上会几乎不可见（aa-hm 踩过同款）；`_sheen_clear` 必须**同 RGB、alpha=0**，用 `Color.Transparent` 会让渐变发灰（同 `shell_topbar_fade` 的教训） |

## 11. 文档导航

| 文件 | 内容 |
| --- | --- |
| `README.md` | 项目介绍、构建、**开发者模式侧载安装**、隐私说明与许可 |
| `CHANGELOG.md` | 第一轮 ~ 第二十一轮：做了什么、怎么定位的、证据在哪（原为工程内部工作日志） |
| `EXPERIENCE.md` | 踩坑细则（现象 / 根因 / 修法 / 涉及文件）、验证方法论、脚本手册、注入脚本维护、安全闩 |
| `specs/UI-DESIGN.md` | **iOS 参考 UI 规范**：总原则 / 导航栏 / 侧栏 inset grouped / 动效 / 官方组件清单 / 无障碍 / 禁止事项 / 验证要求 |
| `specs/MATERIAL-ACCESS-POINTS.md` | 官方沉浸材质（沉浸光感）接入点逐条裁决与官方依据 |

> **内部引用说明**：文中出现的「内部验证记录」= 开发期的验证证据目录（整机截屏 / CDP 探针 /
> `dumpLayout` 读数），**未随本仓库发布**；「内部踩坑表 `§3.0-N`」= 开发工作区的跨工程通用踩坑表
> 编号（同样未随本仓库发布），编号保留以便与本项目内部记录对照。

## 12. 本工程踩坑（现状摘要）

> 逐条的**现象 / 根因 / 修法 / 涉及函数**在 [`EXPERIENCE.md`](EXPERIENCE.md) §1（按主题分组，含
> 官方框架对抗、侧栏三症状、几何与安全区、键盘、上传接管、卡片图标等）；
> 下面只列**仍然活着、最容易复发**的几条，并指向权威条目。

| 症状 | 真因 / 修法要点 | 权威条目 |
| --- | --- | --- |
| 侧栏打开"闪一下" | 三种症状要分开：CSS 首帧几何跳变 / 透底叠影 / 卡顿，混一起查必返工 | `EXPERIENCE.md` §1.2-7/8/10 |
| 侧栏打开"卡" | 看 `window.__dshPerf.fastNode`，应为 **0**；不为 0 说明热路径漏了 `inNativeDrawer()` 短路 | `EXPERIENCE.md` §6 速查 |
| 整页发灰 / 面板与页面有色差线 | 先量三个像素值，再查官方抽屉的**兄弟遮罩**有没有一起接管，最后才怀疑 tint | §3.0-28、§3.0-29 |
| 官方 UI 又冒出来 | "本体 + 兄弟遮罩"必须成对处理；`reveal()` 交还外壳时别漏摘标记 | §3.0-29 |
| 输入框位置不对 | 首页是把根高度钉在键盘未弹出时的高度（`pinHomeLayout`），**只对首页生效** | `EXPERIENCE.md` §1.4-35/36 |
| 出现两条滚动条 | `diag().sbHidden` 应为 2；用 `analyze-sb.ps1` 量深色像素 | `EXPERIENCE.md` §1.4-38 |
| 点附件没反应 / 弹层没动效 | 必须走**官方 `bindSheet`**，别自绘覆盖层；看 hilog 有没有 `picker <kind>: …` | §3.0-98、§3.0-99 |
| 选完文件"什么都没上传" | 系统选择器 URI 是跨应用临时授权，**必须先复制进 `cacheDir`** 再 `handleFileList` | §3.0-100 |
| 注入脚本"改了不生效" | 模板字面量里的单反斜杠会被静默吃掉；占位符替换还会被整行注释吃掉 | §3.0-130、§3.0-133 |
| 网页侧报错只在设备上出现 | 注入脚本按"运行时字符串"断言 + 装机前跑语法预检，别只看源码 | §3.0-130、§3.0-133 |
| 自动化"全绿"但真人点不动 | 合成事件不过命中测试，关键动作要补 `uinput -T -c x y` 真实触摸 + 效果回读 | §3.0-81、§3.0-82 |
| 改动"没生效" | 多设备并存时必须 `hdc -t <sn>`，否则命令可能打到另一台 | §3.0-86 |
| 点「系统设置」左下角"闪一下" | 官方账号下拉菜单是 React portal，**祖先链上的 `opacity:0` 管不住它**；给浮层本身打属性 + 常驻样式表压 `opacity`（**不能动 visibility/pointer-events**，会破坏合成事件命中） | §3.0-154 |
| 设置页"还是网页版排布" | 先量 `scrollWidth > clientWidth`：4 × `min-width:108px` 放不进 403px ⇒ 第 4 个页签被裁；改 `flex:1 1 0 + min-width:0` | §3.0-155 |
| 深色兜底把浅色也刷了 | `@media not all and (min-width:768px) and (prefers-color-scheme: dark)` 的 `not` 否定**整条**查询 ⇒ 改嵌套媒体查询 | §3.0-156 |
| ArkWeb 调试端口"连得上不回应" | 应用在后台时 devtools 不应答；先 `aa start` 拉回前台，**建连成功 ≠ 通** | §3.0-157 |
| 某个按钮"点了没反应/要点好几下" | **同 y 换 x** 先把"全宽遮罩"与"局部遮挡"分开：常驻的**隐形**气泡（`NewChatTipLayer`）子节点没写 `HitTestMode.None`，会一直吃掉它矩形内的触摸（`None` 只豁免自身） | §3.0-159 |
| 切主题后设置页配色迟迟不换 | 官方主题在 **body 的 class** 上，真机 `prefers-color-scheme` 恒 false ⇒ 只挂 `matchMedia` 不够；要定向观察 `body`/`html` 的 class（**不做子树**） | `EXPERIENCE.md` §1.11-88 |
| 行底色/选中底色在面板圆角处"露直角" | ArkUI 的 `borderRadius` **不裁子节点**；给父容器 `.clip(true)`（只裁子节点，自身投影不受影响）。判据：按住行逐行取底色最右 x 的收窄量 | §3.0-160 |
| 设置页"内容放得下却冒出滚动条" | 先查**亚像素溢出**（`min-height` 取整差 0.4px）；`scrollTop` 拖后变 0.3xx 即指纹。修：消溢出 + 隐藏滚动条（含 html/body）+ 藏站点 gutter + 钉页面 | §3.0-161 |
| 顶栏下方一条带里的点击"送不到网页" | 顶栏容器高度含装饰性的 `TOPBAR_FADE_H`(16)，**容器整块参与命中测试** ⇒ 带子里的触摸传不到下层。第十八轮已**原生侧根治**：根容器 `.hitTestBehavior(HitTestMode.None)`（自身不吃、子节点照吃），并做了 A/B 正对照（关掉该行 `got=0` ↔ 打开 `got=8`） | §3.0-159 |
| 键盘弹出后网页几何"不重算" | 轻量避让通道可能**恒判不存在**：① 入口名 `window.__dshSetInsets` 从未被定义；② 回传值是**带引号的 JSON 文本**，`res === 'no-channel'` 恒假。两处都要修，只修一处仍然静默失效 | §3.0-153 |
| 站点里切主题，原生外壳不跟 | 真机 `prefers-color-scheme` **恒 false**（站点用 `html.dark` 类）⇒ 只挂 `matchMedia` 不够；读站点**偏好**（`localStorage`）+ 映射 app `colorMode`，并做同值早退防自激 | `EXPERIENCE.md` §1.12 |
| 顶栏材质"有分界线" | **节点级 `systemMaterial` 画的是"有确定边界的圆角材质带"**（自带顶/底缘高光）⇒ 相邻两块各挂一层就是肉眼可见的分界。要"一片连续糊化"用 `backgroundEffect`（纯模糊），相邻两块四参数逐字同值 | `§3.0-250` |
| 材质"看不出生效" | 三件事按序查：① **组件在不在生效范围**（只有弹窗类 / `Slider`·`Toggle`·`Select` / `Navigation`·`NavDestination` 标题栏 / 横向 Tabs 底部 TabBar 会生效，正文里静默无效）；② 应用级 `UIMaterial.state` 是否**小写** `enable`；③ 判"画出像素"必须扣掉**同构建噪声底**且**排除按钮区** | `§3.0-245`、`§3.0-2`、`内部验证记录` §4.3 |

## 13. 下一步 / TODO

**A. 已知残留（`EXPERIENCE.md` §5 回写的 8 条，如实记录）**

| # | 项 | 现状 / 待办 |
| --- | --- | --- |
| 1 | 网页侧 backdrop 不覆盖原生顶栏（官方设置弹层只压暗网页、原生顶栏仍亮） | 架构固有取舍（原生层在 Web 之上）。第十六轮第三批已按用户要求**恢复**侧栏「系统设置」入口，第十七轮又把弹层改成手机版全屏页（面板自己铺满、顶部用面板底色对齐顶栏下沿）—— 观感上已无"网页被压暗、顶栏仍亮"的分裂，本条降级为**已知架构事实** |
| 2 | ~~`injectShell()` 重跑成本未实测~~ | **第十四轮已闭环**（改走 `window.__dshSetInsets` 轻量通道，读数见 `内部验证记录` §2.4） |
| 3 | 真机与模拟器观感差异（dpr 2.975 vs 3.5） | **第十八轮已双机验收**：模拟器 `PASS=27/0`、真机 Mate70 Pro+ `PASS=28/0`（同一份 HAP）。
证据 `内部验证记录`。四条 platform 差异已写进验收脚本（dpr 现算 / 弹窗按钮按文本定位 / 状态先归零 / 日志当场读）。
模拟器仍只用于快速迭代，**材质/安全区/合成类改动仍须真机复核** |
| 4 | 第十一轮无法归因的会话减少（51 → 50） | 安全闩装好后复核：直调 `deleteSession` 返回 `locked`、会话数不变，此后稳定未再变化 |
| 5 | 设备侧历史临时文件（真机 `/data/local/tmp` 下的 `burst*` / `cc.*` / `dsh_*`） | 待用户确认后清理 |
| 6 | ~~四个死资源~~ | **第十五轮已删除**（`shell_topbar_bg` / `shell_sidebar_bg` / `shell_scrim` / `shell_select_bar_bg`；2026-09-15 实测 base/dark 各 0 命中，`color.json` 各 16 条） |
| 7 | 登录态依赖（抽取官方 DOM 的前提） | 覆盖安装一律 `install -r`；确需 `uninstall` 前先确认登录态可弃 |
| 8 | 官方网页改版风险（DOM 选择器与几何判据都可能失效） | 已备通道：UUID 属性兜底、`reveal()` 交还外壳、`diag()` 可断言；改版后按 `EXPERIENCE.md` §3 流程更新两个注入脚本 |

**B. 未闭环 / 待验**

0. **第十九轮（2026-09-18 ~ 09-19）已完成**：精简提速 + 残余 bug + 参考 iOS 彻底优化 UI，真机验收 14 项全过
   （`内部验证记录`；产物 md5 `c29f0b0362822e10f777a9f1d745c534`）。
   **本轮遗留（如实记录，勿当成已闭环）**：
   - 三宫格文案已改「拍照」，但 `cameraPicker` 仍传 `[PHOTO, VIDEO]` ⇒ 系统相机仍可切录像（**刻意保留**，属链路不变口径）；
   - 设置浮层路由上报：**关闭方向最多晚 200ms**（`maybeMarkSettings` 限流），开的方向一帧内到位；
   - `Index.onBackPress()` 在设置浮层下的行为**留到下一单**（非回归）；
   - ~~**P2-9** `boundedText` 与 `textContent` 折叠+`trim()` 在首尾 Unicode 空白上不等价~~ ——**第二十一轮已修**：空白判据补齐为 JS `\s` 全集 + U+200B（新增 `isFoldWs(ch)`，charCode 区间判断避开模板转义坑），30 万例随机对照 0 差异；
   - **首屏主题窗口期**已由 B2 把首读提前到页面就绪即刻（真机 `site theme` 启动后立刻出现），但**未做改前/改后的毫秒 A/B 读数**；
   - 深色玻璃 alpha 9% 的**边界分支**（站点偏好读取失败时保持系统档位）仍可能观感分裂；正解是主题一致而非改 alpha（改 alpha 会推翻 R10 逐像素定标）；
   - 平板双栏（下条）仍**未实测**；官方 iPad 截图**未呈现双栏**（旁证，不替用户下结论）。

1. **平板双栏**：`deviceTypes` 保留 `phone + tablet`，但 ≥768px 是否真出双侧栏**未实测**
   （见 `内部验证记录` §3）——不替用户下"不支持平板"的结论。
2. **探针盲区**：`window.__dshPerf` 只有 4 个计数器，`markSideDrawers` / `removeDownloadPromos`
   无计数 → 要量化性能收益得先补计数器（`内部验证记录` §6）。
3. **文档侧待办**：`specs/` 已建，后续重大改动按 `YYYY-MM-DD-主题.md` 继续补设计文档。
4. **第十七轮已完成（两单，2026-09-16 ~ 09-17）**：结论与证据见 `CHANGELOG.md` 第十七轮段与 `内部验证记录`
   （`REPORT.md` + 真机 A/B 探针数据 + `dumpLayout` + 整屏/页面侧截图 + 集成复核 42 PASS）。
   改动落在 4 个源文件：`ShellScript.ets`（浮层视觉闩 `data-dsh-menu-veil`）与
   `DeepSeekConfig.ets`（`data-dsh-settings-*` 打标 + 手机媒体查询 CSS + `syncSettingsColors` 色采样 +
   主题 class 定向观察器 + 设置页滚动条/亚像素溢出治理）、`Index.ets`（`NewChatTipLayer` 隐形气泡补 `HitTestMode.None`）、
   `view/SidePane.ets`（面板 `.clip(true)`）。第二单的复验在 `REPORT.md` §13；
   最终产物 md5 `9d91b297a9665193b55618ac65d3996a`（clean 全量 **0 warning / 0 error**）。
   **残留实测 0 条新增**：§11.7 的"✕ 与隐形气泡只剩 1.4px 余量"已被"气泡不再参与命中测试"根治。
5. ~~**原生顶栏底部 16vp 是触摸丢包带**~~ —— **第十八轮已原生侧根治**：顶栏根容器补
   `.hitTestBehavior(HitTestMode.None)`，并做了 **A/B 正对照**（注释掉该行 `got=0`（8 点全丢）↔ 该属性在场 `got=8`（8 点全到），
   唯一变量；还原经 W1 独立 md5 复核，与改动前逐字节一致）。网页侧那条 `topInset + 20` 的绕行**不再必需**
   （但"是否收回"属 W3 作用域，本轮未动）。仍未闭环的还有上面 1、2 两项（平板双栏未实测、`window.__dshPerf` 计数器不足）。

6. **第二十轮（2026-09-25 ~ 09-26）**：顶栏改由官方 `Navigation` 标题栏承载 + 官方沉浸光感（3 个按钮）；
   `UIMaterial.state` 由 `disable` 改 `enable`。交付口径与代价见 §4「磨砂 / 材质」与 [`specs/UI-DESIGN.md`](specs/UI-DESIGN.md) §2.1；
   逐点裁决（含"哪些位置必须留自绘"）见 [`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md)。
   **本轮真机结论（T3 独立验证，`内部验证记录`，证据力照抄）**：
   - **框架栏模糊真的糊住正文**：同一行 gradX OFF **8.523** / IMM **0.374** = **22.8×**（dark 23.8×），同帧对照区三臂相等，栏外 MAE **0.0022** ⇒ **可断言（强）**；
   - **交付默认臂无新增分界**：IMM-dark 逐行均值最大一阶差分 **5.26 @ y=77**（与改前 5.25 同位置同量级）；被否决的 SEAM-dark 是 **68.37 @ y=167** + **52.00 @ y=322** ⇒ **可断言（强）**；
   - 几何 **111.714vp ↔ 333px** 双来源吻合；侧栏钮/新建对话钮效果回读通过；栏下缘 y=350 触摸穿透成功；**无本应用崩溃**（hilog 环形缓冲，证据力中）；
   - 用户第二次反馈「又出现很明显的分界线了」落在**对照臂装机窗口**（SEAM）内 ⇒ 不是交付包（时间线可断言）；
   **本轮未闭环（如实登记，勿当成已闭环）**：
   - **顶栏覆盖区（0..332px）内网页元素是否可点 / 是否回归**：verify 实测该区整体不吃给网页（probe=0，**中**）但**未做同口径改前对照** ⇒ **不可断言是否为回归**；
   - **`other` 路由（子页/设置浮层）的返回键**：**未验证**（本轮未能稳定进入该路由）；
   - **观感裁定**：需**用户本人看图**（材料 `compare/*.png`）；改后与改前「观感等价」`REPORT.md` 判为**不可断言**；
   - 让位量 **+14vp**（97.71vp→111.71vp）是**用户真机拍板**的取舍（原硬约束「网页可读区上方被原生覆盖高度不得超过改前」被本轮**覆盖**），**不是**实现副产品；
   - `TOPBAR_BAR_MATERIAL` **旧名语义反转** ⇒ R20 改名 `TOPBAR_FRAMEWORK_BLUR`（教训见 [`EXPERIENCE.md`](EXPERIENCE.md) §9.2-1）；
   - 上传半模态（`bindSheet`）在 `enable` 档下**默认带材质** ⇒ 三宫格观感变化**真机未验证**（`§3.0-256`）；
   - `TOPBAR_FADE_GUARD`（`utils/DeepSeekConfig.ets:100`）判定无需改动，依据是 `131.71 CSS px = 392px > 覆盖区下界 332px` —— **算式推断，未真机打开设置面板复核**；
   - `lightEffect` 顶缘亮线（`§3.0-13` 反例）与按钮材质洗白（`§3.0-58` 反例）两条风险**本轮未单独排除**；
   - **判据③的换臂过程**（原定「IMM vs OFF 中段 MAE」被证伪为无效 —— OFF 臂 `DrawnBar` 同样有 `backgroundEffect`）见 [`EXPERIENCE.md`](EXPERIENCE.md) §9.2-6。

**C. 第十八轮新增遗留项（三条，均为 Lead 已裁定「本轮不动代码」）**

| # | 项 | 现状 / 为什么不修 |
| --- | --- | --- |
| 1 | `view\TopBar.ets` 的 `@Prop isDark` **已不影响任何绘制** | 两个亮度令牌同值（实测模糊中性）；删它必须**同时**改 `pages\Index.ets` 的传参，两份文件在共享工作区里存在「谁先落盘谁打断对方」的必坏窗口，而收益只是清掉一个参数 ⇒ Lead 裁定本轮保留 |
| 2 | `window.__dshSetInsets` **兼容别名保留** | 全工作区**零调用者**（宿主走门面 `window.__dshShellApi.setInsets`，第十四轮的取证脚本也用门面）。它是 W2 为「旧探针名」补的别名；Lead 裁定保留（外部探针可能仍在用这个名字） |
| 3 | `model\ShellTypes.ets` 里 `ChatSessionItem.active` 的注释**已过期**，且该字段在传输层是**死数据** | 注释写「网页侧恒为 false」，而 `ShellScript.collect()` 现在会按路由真算；原生侧 `applySessions()` 又用自己的回填**覆盖**它 ⇒ 渲染真相来源始终是 `syncActiveRow()`。行为无害，订正走文档，本轮不动代码 |

**D. 第十八轮新增两条纪律**

1. **产物 mtime 不能当「是否同步」的判据**：hvigor 从自己的 cache 恢复未变文件时会**保留 mtime**，
   于是「产物旧于源码」是**假信号**（实证：`ShellUi.ts` 产物比源码旧 24s，内容却已含新令牌）。判同步要用**内容抽样**（grep 具体令牌）。
2. **构建判据要加一条**：除 `BUILD SUCCESSFUL` 之外，必须确认 `CompileArkTS` 与 `PackageHap` **都实际执行** ——
   全 `UP-TO-DATE` 的构建也会打印 `BUILD SUCCESSFUL`（假绿），此前正是它掩盖了 `PackageHap` 阶段的 `spawn java ENOENT`。
