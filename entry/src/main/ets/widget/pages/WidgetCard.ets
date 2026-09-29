// DeepSeek 桌面卡片（ArkTS 服务卡片）。
//
// ## 本轮（第十六轮）改了三处，逐条写清依据
//
// ### 1. 图标不再加圆角（audit §1 U-16）
// `startIcon` 是一张**背景透明**的 PNG（`iconwork/make-starticon.js` 生成，1024 画布内
// 鲸鱼本体只占 692×516、四周留白）。给它 `borderRadius(10)` 等于"把透明区当卡片切"，
// 四个角会削掉一块。与启动页（`pages/Index.ets` 的 `Splash()`）口径统一：**透明底不加圆角**。
// 顺带说明显示尺度：36vp 的框里，1024 画布中的鲸鱼本体只有约 24vp 宽 —— 这是既有取值，
// 本轮不动；若日后觉得偏小，参照启动页的口径（要 113vp 的鲸鱼本体需 168vp 的框）按比例放大。
//
// ### 2. 图标解码按显示尺寸（audit §3「内存」P0 项）
// 该资源实测 1024×1024 RGBA / 33,440 B，而 `Image` 的 `autoResize` SDK 默认是 **false**
// （`component/image.d.ts:1014`，默认值 false）→ 按原图解码，单实例解码缓冲约 4 MB。
// 卡片只显示 36vp，加 `.autoResize(true)` 后按显示尺寸降采样解码（约 0.1 MB 量级）。
// `autoResize` 在卡片组件白名单内：SDK `ets/build-tools/ets-loader/form_components/image.json`。
// 代价是缩小解码会有一点锯齿（官方文档原话："may reduce the image quality, causing issues
// such as aliasing"）—— 在 36vp 的小图标上不可见，用内存换这点质量是划算的。
//
// ### 3. 三种尺寸（2×2 / 2×4 / 4×4）改用 `GridRow/GridCol` 响应式（audit §1 U-10）
// `form_config.json` 声明了三种尺寸，但早先只有一套固定布局。这里用官方响应式栅格按
// **容器宽度**分档 —— 卡片宽度就是容器宽度，所以断点必须用
// `BreakpointsReference.ComponentSize` 而不是窗口断点（窗口宽度对卡片没有意义）。
//
// 断点值 200vp 的来历（可复算）：目标机 1316×2832 / density 560 ⇒ 有效宽 376vp；
// 桌面 4 列栅格下 2 列宽的小卡（2×2、2×4）≈ 166vp、4 列宽的大卡（4×4）≈ 344vp，
// 再扣掉本卡片自身 16vp 内边距 ⇒ GridRow 实得约 134vp / 312vp，取中值 200vp 作断点，
// 两侧各留约 66vp / 112vp 余量，不会因主题或栅格微调而误判。
//   · xs（< 200vp，即 2×2 与 2×4）：三块内容都占满 12 列 —— **与改造前的排布逐项一致**（零回归）；
//   · sm（≥ 200vp，即 4×4）：标语只占左侧 8 列、CTA 落到右下 8 列（`offset: 4`），
//     大卡右下角由一个满宽色条变成一枚右对齐胶囊。
// 2×2 与 2×4 的**宽度相同、只差高度**，高度差由 `Blank()` 自然吸收（栅格断点只看宽度，
// 无法区分二者；要按高度分档得走 `formDimension` 通道，那需要改 EntryFormAbility，不在本轮范围）。
//
// 实证：① 官方文档同款写法（DevEco 内置 API 参考的 GridRow 示例）就是
// `GridCol({ span: { xs: 1, sm: 2, md: 3, lg: 4 }, offset: 0, order: 0 })`，故
// `span/offset` 传断点对象是受支持的正规写法；② `GridRow/GridCol` 在**卡片**白名单内：
// `form_components/grid_row.json` / `form_components/grid_col.json`（后者的 attrs 正是
// span/offset/order）；③ 本文件用到的组件会被编译期收进卡片的组件集合
// （HAP 内 `ets/widget/component_collection.json` 当前为 Column/Row/Image/Text/Blank，
//  改造后会多出 GridRow/GridCol）。
//
// ## 卡片为什么不刷新 —— form_config.json 把 updateEnabled 改成 false 的依据
// 本卡片是**纯静态**的启动入口：内容只有品牌名与一句标语，唯一交互是 `postCardAction`
// 路由到 EntryAbility（点一下开始新对话），没有任何需要重新取数的字段；
// `EntryFormAbility.onUpdateForm` 也只打一行 hilog。而原先 form_config.json 声明
// `updateEnabled: true` + `updateDuration: 1`（每 30 分钟定时唤醒卡片进程一次）——
// 零收益的周期唤醒（audit §3「功耗」，也被审计称为"唯一改一行、确定性收益、零风险"的项）。
// 故本轮：`updateEnabled` 置 **false**，并**同时删掉** `updateDuration` 与
// `scheduledUpdateTime` —— 留着这两个字段会让人误以为"刷新已经实现了，只是没开"。
//
// 将来若卡片要显示真实数据（例：最近会话数），必须三件事一起做，缺一不可：
//   ① form_config.json 恢复 `updateEnabled: true` 并给出合理的 `updateDuration`；
//   ② `EntryFormAbility.onUpdateForm` 里真正取数并 `formProvider.updateForm(formId, data)`；
//   ③ 卡片侧改读 `LocalStorageProp` 而不是写死文案。
// 注：`resources/base/profile/form_config.json` 是**严格 JSON**，写不了注释，故依据留在这里。
//
// ## 4. 数值全部收敛为「命名常量」，一个裸数字都不留（本轮）
// 卡片与主外壳**必须**共用同一套刻度：卡片上的品牌名与外壳顶栏是同一层信息，
// 字号一旦各写各的，桌面（卡片）与窗口内（顶栏）就会出现同一品牌名两种大小。
//
// ⚠️ **但不能直接 import `common/ShellUi`**（本轮试过、已回退，有构建产物实证）：
// 卡片走的是**卡片编译单元**，import 会把整个 `ShellUi.ets` 拉进卡片包。导入后
// `entry/build/default/cache/default/default@CompileArkTS/esmodule/debug_widget/component_collection.json`
// 把该文件登记为 `["Button", "Circle", "SymbolGlyph"]` —— 而 SDK 的卡片组件白名单
// （`sdk/default/openharmony/ets/build-tools/ets-loader/form_components/`）里
// **没有 symbol_glyph.json**（button.json / circle.json 有）。也就是说：为了几个数值，
// 把 ShellUi 里那个圆形图标按钮配方（Button + SymbolGlyph）塞进了卡片的组件预加载集，
// 顺带让 HAP 多了约 16 KB（750,965 → 767,004 B）。收益为负，故改用**本地等值常量**。
//
// 一致性由**机器**保证、不靠注释约定：`tmp/r18/w3-check.sh` 逐对断言下面这些 `CARD_*`
// 与 ShellUi 里同语义令牌数值相等 —— 任一侧改了而另一侧没跟，脚本就 FAIL。
//
// 栅格里的 `columns: 12` / `span: { xs: 12, sm: 8 }` / `offset` **不做常量替换**：
// 它们是"12 栅格制"的结构语义（与官方 GridCol 示例逐字同形），不是可调的 vp 尺寸；
// 给 12 起个名字反而会掩盖"这是栅格列数"这层意思。

const CARD_GAP_XS: number = 4; // = ShellUi.GAP_XS
const CARD_GAP_SM: number = 8; // = ShellUi.GAP_SM
const CARD_GAP_MD: number = 12; // = ShellUi.GAP_MD
const CARD_GAP_LG: number = 16; // = ShellUi.GAP_LG
const CARD_FS_TITLE: number = 16; // = ShellUi.FS_TITLE（品牌名）
const CARD_FS_CAPTION: number = 12; // = ShellUi.FS_CAPTION（标语）
const CARD_FS_LABEL: number = 13; // = ShellUi.FS_LABEL（CTA 文案）
/** 品牌图标显示边长（vp）：沿用第十六轮定标值，与启动页共用 1024 画布的同一张透明底鲸鱼。 */
const CARD_ICON_SIZE: number = 36;
/** 品牌行内部间距（vp）：图标与品牌名之间，比 GAP_SM 略松以免图形贴字。 */
const CARD_BRAND_GAP: number = 10;
/** 卡片整体圆角（vp）：桌面卡片是小尺寸容器，比面板 22 略大才有"圆润的桌面块"观感。 */
const CARD_RADIUS: number = 24;
/** CTA 胶囊圆角（vp）：取值约等于半高（13 行高 + 上下各 9 内边距 ⇒ 高 31，半高 15.5），故 14 即成胶囊。 */
const CARD_CTA_RADIUS: number = 14;
/** CTA 纵向内边距（vp）：撑到约 31vp 高，够到最小可点区附近又不把卡片压满。 */
const CARD_CTA_PAD_V: number = 9;
/**
 * 宽卡断点（vp）：大于此宽度即视为 4×4 大卡。
 * 来历可复算：目标机 1316×2832 / density 560 ⇒ 有效宽 376vp；桌面 4 列栅格下 2 列宽的小卡
 * 约 166vp、4 列宽的约 344vp，再扣掉卡片自身 16vp 内边距 ⇒ 栅格实得约 134vp / 312vp，
 * 取中值 200vp，两侧各留约 66vp / 112vp 余量。
 */
const CARD_WIDE_BP: string = '200vp';

@Entry
@Component
struct WidgetCard {
  build() {
    Column({ space: CARD_GAP_SM }) {
      // ── 上区：品牌行 + 标语（栅格化，供 4×4 大卡重新分栏）──
      // gutter 的 y 用 CARD_GAP_SM 是为了保住改造前「品牌行与标语之间 8vp」的纵向间距
      // （栅格行间距由 gutter.y 决定，不再由 Column 的 space 决定）。
      GridRow({
        columns: 12,
        gutter: { x: CARD_GAP_MD, y: CARD_GAP_SM },
        breakpoints: {
          value: [CARD_WIDE_BP],
          reference: BreakpointsReference.ComponentSize
        }
      }) {
        // 品牌行：三种尺寸都占满整行（与改造前完全一致）
        GridCol({ span: { xs: 12, sm: 12 } }) {
          Row({ space: CARD_BRAND_GAP }) {
            // 品牌图标替代原 'D' 字母色块，与桌面/启动页图标一致
            Image($r('app.media.startIcon'))
              .width(CARD_ICON_SIZE)
              .height(CARD_ICON_SIZE)
              // 透明底不加 borderRadius（与启动页口径统一），并按显示尺寸解码省内存
              .autoResize(true)
            Text('DeepSeek')
              .fontSize(CARD_FS_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
          }
          .width('100%')
        }

        // 标语：窄卡整行（= 改造前）；宽卡（4×4）只占左侧 8 列
        GridCol({ span: { xs: 12, sm: 8 } }) {
          Text('探索未至之境')
            .fontSize(CARD_FS_CAPTION)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
      }
      .width('100%')

      // 弹性空隙：把 CTA 压到卡片底部（原实现也是这个作用）
      Blank()

      // ── 下区：CTA ──
      // 窄卡整行满宽（= 改造前）；宽卡靠右占 8 列（offset 4 → 左侧 4 列留白）
      GridRow({
        columns: 12,
        gutter: { x: CARD_GAP_MD, y: CARD_GAP_SM },
        breakpoints: {
          value: [CARD_WIDE_BP],
          reference: BreakpointsReference.ComponentSize
        }
      }) {
        GridCol({ span: { xs: 12, sm: 8 }, offset: { xs: 0, sm: 4 } }) {
          Row({ space: CARD_GAP_XS }) {
            Text('点击开始新对话')
              .fontSize(CARD_FS_LABEL)
              .fontWeight(FontWeight.Medium)
              // 用双值资源而非 Color.White：深色档下 accent 变浅，纯白字对比不足
              // （与原生外壳 P2-1 的处理同源；`on_accent` 已在 base/dark 成对定义）
              .fontColor($r('app.color.on_accent'))
            Blank()
          }
          .width('100%')
          .padding({ left: CARD_GAP_MD, right: CARD_GAP_MD, top: CARD_CTA_PAD_V, bottom: CARD_CTA_PAD_V })
          .borderRadius(CARD_CTA_RADIUS)
          .backgroundColor($r('app.color.accent'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(CARD_GAP_LG)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_bg'))
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          action: 'newChat'
        }
      });
    })
  }
}
