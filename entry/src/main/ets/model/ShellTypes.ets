// 「原生外壳 + ArkWeb 聊天区」的数据契约。
//
// 分工：网页侧桥脚本（utils/ShellScript.ets）负责读官方 DOM 并上报，原生侧只消费
// 结构化数据渲染原生侧栏/顶栏。所有消息经 javaScriptProxy 以 JSON 字符串传递。

/** 一条会话记录（来自官方侧栏 DOM 抽取）。 */
export interface ChatSessionItem {
  id: string;
  title: string;
  /** 官方分组标题（今天/昨天/7 天内…），抽不到时为空串。 */
  group: string;
  // 这里曾有一个 `active: boolean`（"网页侧上报的是否当前会话"）。第十九轮**删除**，理由三条：
  //   · 原生侧**零读者**（grep：`ChatSessionItem` 的消费点只有 `Index.toSessionItems` 与
  //     `applySessions`，后者一律按 `id === currentSessionId` 自己回填，从不读这个字段）；
  //   · 旧注释"网页侧恒为 false"**已过期**（`ShellScript.collect()` 现在会按路由真算并上报）；
  //   · 网页侧消息体里仍带着这个键 —— 多余的键对 `JSON.parse` 无任何影响，两侧不必同步改。
  // 真正驱动渲染的"当前会话"标记在 `SideRow.active`（由原生侧回填，见 Index.applySessions /
  // syncActiveRow），它才是**唯一**的真相来源。
}

/** 侧栏列表的渲染行：分组标题行 + 会话行拍平成一维，避免嵌套 ForEach。 */
export interface SideRow {
  /** 'group' 分组标题；'session' 会话项。 */
  kind: string;
  key: string;
  text: string;
  id: string;
  active: boolean;
}

/** 网页侧上报的消息体。 */
export interface ShellMessage {
  /** sessions | route | ready | log | account | deleted */
  t: string;
  items?: ChatSessionItem[];
  /**
   * 当前路由的 pathname（`route` 与 `ready` 两类消息都会带）。
   *
   * 原生侧目前**不消费**它：路由判据用 `kind` + `id`，标题用 `title` 或会话列表里的行文案。
   * 保留是因为它是网页侧已在发送的字段（删字段属跨文件契约变更），
   * 后续若要支持"按路径回退一层"之类的功能可直接取用。
   */
  path?: string;
  /** home 新会话页；chat 会话页；other 设置/搜索等子页 */
  kind?: string;
  id?: string;
  title?: string;
  /**
   * `log` 类消息的文本。
   *
   * **保留字段：网页侧当前没有任何代码发出 `log`**（`isKnownShellKind` 仍然接受它，
   * 这是"协议放宽"而非缺陷：多接受一类消息不会造成任何行为）。
   * 若要启用，网页侧只需 `bridge({t:'log', m:'...'})`，原生侧会打成一条 hilog
   * （第十八轮补齐了 `onShellMessage` 的 `log` 分支 —— 在此之前注释写着会打 hilog，
   * 实现里却没有分支，被 `isKnownShellKind` 放行后**静默丢弃**）。
   */
  m?: string;
  /** account：账号昵称 */
  name?: string;
  /** account：头像 URL */
  avatar?: string;
  /** deleted：删除结果 done | locked | busy | no-row | no-option | no-confirm | stale-menu | stale-modal | verify-failed | aborted */
  status?: string;
}
