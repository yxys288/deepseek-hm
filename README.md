# DeepSeek 鸿蒙端（deepseek-hm）

把 DeepSeek 官方网页端（`chat.deepseek.com`）封装成 HarmonyOS 应用：**原生 ArkUI 外壳 + ArkWeb 聊天区**。
侧栏、顶栏与设置页底栏由原生组件渲染，网页只承载聊天区 —— 因此登录态与云端会话历史完整保留，
观感与官方移动端一致（进入即聊天页，没有独立的软件首页）。

> ⚠️ **免责声明（非官方客户端）**：本项目是**第三方开源客户端**，与 DeepSeek 官方**无任何隶属或合作关系**。
> “DeepSeek”名称、鲸鱼标识及相关商标归其权利人所有，本项目仅在**学习与个人使用**目的下引用。
> 应用内的对话内容与账号数据全部由 `chat.deepseek.com` 处理，本项目**不做二次收集、不上报统计、不接入第三方 SDK**。
> **请勿将本项目用于商业分发或冒充官方应用**；如需分发，请自行更换应用名与图标并遵守华为应用市场规则。

---

## 功能特性

| 能力 | 实现要点 |
| --- | --- |
| 原生外壳 + ArkWeb 聊天区 | `SideBarContainer(Overlay)` + 全窗口 `Web`；侧栏/顶栏/设置底栏都是原生 ArkUI 组件，网页只做聊天区 |
| 沉浸全屏直入 | `setWindowLayoutFullScreen(true)` + 透明系统栏 + 避让区经 `avoidAreaChange` 落到网页侧安全区内边距 |
| 原生侧栏 | 会话列表由网页侧桥脚本抽取后经 `javaScriptProxy` 上报，原生渲染分组列表（行高 44 / inset grouped / 搜索 / 批量选择） |
| 官方沉浸光感（材质） | 顶栏走官方 `Navigation` 标题栏 + `.systemMaterial(...)`；面板磨砂走 `backgroundEffect`（逐点裁决见 `specs/MATERIAL-ACCESS-POINTS.md`） |
| 设置页底部功能栏 | 官方 `Navigation` 工具条承载 + 栏内自绘悬浮胶囊；点击经桥 `setSettingsTab(i)` 驱动网页切页签 |
| 深浅色跟随 | `WebDarkMode.Auto` + 双值资源；系统深浅色变化时校验网页 `prefers-color-scheme` 并重注入适配脚本 |
| 网页「选择上传」接管 | `onShowFileSelector` 接管，用官方半模态 `bindSheet` 承载 图库 / 拍照 / 文件，选择器 URI 先复制进沙箱 `cacheDir` |
| 批量删除（带安全闩） | 串行驱动官方 DOM 完成删除；未进入选择模式时桥侧返回 `locked`，避免任何脚本删用户数据 |
| 服务卡片 | `FormExtensionAbility` + ArkTS 卡片（2x2 / 2x4 / 4x4），点击拉起并新建对话 |
| 移动端兜底适配 | 注入 `MOBILE_ADAPTER_JS`：禁横向溢出、弹层限宽高、代码换行、`viewport-fit=cover`、入口隐藏 + SPA 路由监听 |

## 环境要求

| 项 | 要求 |
| --- | --- |
| 开发工具 | DevEco Studio（含 HarmonyOS SDK） |
| SDK | `compatibleSdkVersion` / `targetSdkVersion` = **26.0.0**（HarmonyOS 7 / API 26），`runtimeOS: HarmonyOS` |
| 设备 | HarmonyOS 7 手机或平板（`deviceTypes`：`phone` / `tablet`），或 DevEco 模拟器 |
| 签名 | 需自行配置（见下）。仓库内**不含**任何签名材料 |

## 构建

1. `File > Open` 打开本仓库根目录，等待 Sync 完成；
2. `File > Project Structure > Signing Configs` → 勾选 **Automatically generate signature** 并登录华为开发者账号
   （**必须**：没有签名只能得到未签名 HAP，无法安装到设备）；
3. `Build > Build Hap(s)/App(s)`；
4. 产物在 `entry/build/default/outputs/default/entry-default-signed.hap`。

> 开源版本的 `build-profile.json5` 已移除 `signingConfigs`（原文件含本机密钥库路径与加密口令，属个人凭据）。
> 生成自动签名后 DevEco 会补回 `signingConfigs`，并把 `products[0].signingConfig` 指向 `default`；
> 若手工配置，注意 `products[0]` 必须引用签名配置，否则报 `No signingConfig found for product default`。

命令行构建（可选）：

```bat
set DEVECO_SDK_HOME=<DevEco Studio 安装目录>/sdk
set NODE_HOME=<DevEco Studio 安装目录>/tools/node
set PATH=<DevEco Studio 安装目录>/jbr/bin;%PATH%
"%NODE_HOME%/node.exe" "<DevEco Studio 安装目录>/tools/hvigor/bin/hvigorw.js" --mode module -p product=default assembleHap --no-daemon
```

## 开发者模式侧载安装

> **本应用只能通过开发者模式侧载安装，不能像 APK 那样双击安装。**
> HarmonyOS NEXT 起系统**不支持**用文件管理器打开 HAP 安装包；装机通道只有 `hdc`（USB 调试），
> 而 `hdc` 本身就要求设备开启**开发者模式**。第三方“鸿蒙一键安装器”同样走 `hdc`，绕不过这一步。

### 1. 设备侧：打开开发者模式与 USB 调试

1. 设置 → **关于本机**（部分机型为“关于手机”）→ 连续点击 **版本号** 约 7 次，直到提示“已进入开发者模式”；
2. 返回 设置 → **系统和更新** → **开发人员选项** → 打开 **USB 调试**；
3. 用 USB 数据线连接电脑，手机上弹出“是否允许 USB 调试”时选择**允许**（可勾选“始终允许”）。

> 菜单名称随 HarmonyOS 版本略有差异，以设备实际菜单为准。

### 2. 电脑侧：用 hdc 安装

`hdc` 在 DevEco Studio 的 SDK 里：`<DevEco Studio 安装目录>/sdk/default/openharmony/toolchains/hdc.exe`
（Linux/macOS 下为同目录的 `hdc`）。

```bat
hdc list targets                                   rem 确认设备已连接（多设备时记下 sn）
hdc -t <sn> install -r entry-default-signed.hap    rem 覆盖安装（保留登录态/Cookie）
hdc shell aa force-stop com.example.deepseekhm
hdc shell aa start -a EntryAbility -b com.example.deepseekhm
```

安装成功后桌面会出现应用图标，打开即进入 DeepSeek 聊天页，按页面提示登录即可。

### 3. 三条容易踩的坑

- **侧载只认调试（debug）签名**：DevEco 的“自动签名”就是调试证书，可以直接侧载；
  发布证书签名的包**无法**用 `bm install -p` 侧载，只能走华为官方分发通道。
- **`hdc install` 打印 `[Fail]` 时退出码仍是 0**，不要只看退出码；多设备并存时**一律显式** `hdc -t <sn>`，
  否则可能装到另一台设备上（表现为“改动没生效”）。
- **`hdc uninstall` 会连 ArkWeb 的 Cookie 一起清掉**（= 退出登录）。升级与验证一律用 `hdc install -r`。

> 未实测/需自行确认的项：调试 Profile 的有效期（社区口径约 90 天，过期后需重新签名安装）、
> 关闭开发者模式后 debug 签名应用能否长期运行 —— 这两条在本项目开发期**未做实测**，不作为已知结论。

## 项目结构

```text
AppScope/                     应用级配置与分层图标（layered_image）
entry/
  src/main/module.json5       模块声明：能力、权限、沉浸材质 metadata
  src/main/ets/
    pages/Index.ets           原生外壳主页面（SideBarContainer + Web + 桥回调分发 + 覆盖层）
    view/TopBar.ets           原生顶栏（Navigation 标题栏构造器）
    view/SidePane.ets         原生侧栏面板（会话列表 / 搜索 / 批量选择 / 账号页脚）
    view/SettingsTabBar.ets   设置页底部功能栏（悬浮胶囊）
    utils/ShellScript.ets     网页侧桥脚本 SHELL_JS（会话抽取 / 路由上报 / 让位 / 遮罩接管）
    utils/DeepSeekConfig.ets  常量 + 移动端兜底适配 MOBILE_ADAPTER_JS
    common/ShellUi.ets        设计令牌表（尺寸 / 间距 / 圆角 / 模糊 / 动效）+ 官方材质入口
    model/ShellTypes.ets      原生 ↔ 网页数据契约
    entryability/             沉浸式窗口、避让区桥接、卡片拉起参数
    entryformability/ widget/ 服务卡片
  src/main/resources/         深浅双值颜色、字符串、图标、页面与卡片配置
specs/                        UI 设计规范、官方材质接入点清单
PROJECT.md / CHANGELOG.md / EXPERIENCE.md   工程现状 / 逐轮变更史 / 踩坑与验证细则
```

## 隐私与权限

- **仅声明 `ohos.permission.INTERNET`**；
- `onLoadIntercept` 只放行官方主域的**主框架**导航，未放开 ArkWeb `mixedMode`；
- 登录态（Cookie / localStorage / IndexedDB）只保存在应用私有 ArkWeb 数据区，本项目不读取、不上传；
- 应用不接入任何统计或广告 SDK；卸载应用即清除全部本地数据。

## 已知限制

- 聊天区是官方网页，**官方改版可能让适配脚本（入口隐藏、设置页改造、会话抽取）失效**，需要跟着更新；
- “新建对话”依赖网页端按钮 DOM（服务卡片触发时由脚本点击），官方改版后可能需要补选择器；
- 平板/折叠屏的双栏形态**未实测**；
- 官方沉浸光感只在 `Navigation` / `NavDestination` 标题栏等位置生效，挂在页面正文里会**静默无效**。

## 文档

| 文件 | 内容 |
| --- | --- |
| [`PROJECT.md`](PROJECT.md) | 项目现状：架构、关键实现、配置项清单、踩坑摘要 |
| [`CHANGELOG.md`](CHANGELOG.md) | 逐轮变更史（原为工程内部工作日志） |
| [`EXPERIENCE.md`](EXPERIENCE.md) | 现象 / 根因 / 修法 / 验证读数、验证方法论 |
| [`specs/UI-DESIGN.md`](specs/UI-DESIGN.md) | UI 设计规范（顶栏 / 侧栏 / 动效 / 禁止事项） |
| [`specs/MATERIAL-ACCESS-POINTS.md`](specs/MATERIAL-ACCESS-POINTS.md) | 官方沉浸材质接入点逐条裁决与官方依据 |

> 文档中出现的“内部验证记录”指开发期的验证证据目录（整机截屏 / CDP 探针 / `dumpLayout` 读数），
> 以及“内部踩坑表 `§3.0-N`”的编号，二者**均未随本仓库发布**，编号保留以便与项目内部记录对照。

## 许可

本项目以 **Apache License 2.0** 开源，见 [`LICENSE`](LICENSE)。
商标与第三方素材声明见 [`NOTICE.md`](NOTICE.md)。
