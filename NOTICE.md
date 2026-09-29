# NOTICE · 商标与第三方素材声明

## 1. 非官方声明

本项目（deepseek-hm）是**第三方开源客户端**，与杭州深度求索人工智能基础技术研究有限公司
（DeepSeek）**无任何隶属、合作或授权关系**。

## 2. 商标

- “DeepSeek”、鲸鱼（whale）图形标识及相关名称、图标，其商标权与著作权归 DeepSeek 权利人所有；
- 本仓库中的应用图标、启动页图标与 `iconwork/` 下的图标制作素材**引用了官方标识**，
  仅用于“标识所连接的官方服务”这一目的，不表示任何官方认可或背书；
- 若权利人提出异议，将立即移除相关素材。

## 3. 第三方素材清单

| 文件 | 来源 / 用途 |
| --- | --- |
| `AppScope/resources/base/media/foreground.png`、`background.png`、`layered_image.json` | 应用分层图标（含官方鲸鱼标识） |
| `entry/src/main/resources/base/media/startIcon.png` | 启动页图标（透明底 + 官方鲸鱼标识） |
| `iconwork/official-favicon.svg`、`iconwork/official-icon-180.png` | 官方站点图标素材副本，用于生成应用图标 |
| `iconwork/*.html`、`iconwork/make-starticon.js` | 图标生成的中间产物与脚本（不含第三方代码） |

## 4. 运行期依赖

- 本应用**不包含任何第三方运行时依赖**（`oh-package.json5` 的 `dependencies` 为空）；
- 构建期依赖 DevEco Studio / hvigor / HarmonyOS SDK（华为，遵循其各自的许可条款）；
- 应用内展示的网页内容（`chat.deepseek.com`）版权归 DeepSeek 权利人所有，本项目不对其做任何再分发。

## 5. 开源许可

本项目源代码以 Apache License 2.0 授权，见 [`LICENSE`](LICENSE)。
