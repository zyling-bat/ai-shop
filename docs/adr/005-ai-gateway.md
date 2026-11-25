# ADR-005 AI 网关统一入口与治理边界

- 状态：已接受（Accepted）
- 日期：2026-11-25
- 阶段：P0 / ST-0.5（业务实现归 P11）
- 关联约束：ST-0.5 R2；00 C21–C27；04 §4.1、§4.2；ADR-008（trace 与指标口径）

## 背景

导购、客服、搜索、内容与运营等能力需要复用不同模型，但业务模块若直接接入厂商 SDK，会把厂商域名、凭据、模型名、错误格式和限流策略扩散到交易链路，也无法统一实施降级、配额、审计、内容安全与评测。模型输出又可能包含结构化意图或交易建议，若缺少业务校验和执行边界，会把生成结果误当成已授权的数据库写入或交易操作。

ST-0.5 R2 要求先固化 AI 网关决策边界。本 ADR 依据 04 §4.1、§4.2 与 00 C21–C27，确定唯一入口、端口契约、错误分类、配置化路由及治理口径。**本阶段只接受架构决策，本 ST 不实现任何 AI 运行能力。AI Gateway、Provider 适配及网关治理实现归 P11；RAG 知识库归 P12；Agent、具体 AI 能力及其对应评测归 P13，或该能力所属的后续阶段；不声称相关能力已经可用。**

## 决策

### 1. `ai-gateway` 是模型调用的唯一入口

- 业务模块的 chat、stream、embedding 等模型能力请求只能经 `ai-gateway`，不得直接依赖厂商 SDK，也不得在业务代码中出现厂商域名、API Key 或模型名硬编码。
- Agent 可以参与 AI 调用链的编排，但不是第二个模型入口；其每次模型或向量调用仍须进入 `ai-gateway`。不得形成“业务 → Agent → Provider”或“业务/RAG → Provider”的旁路。
- 四层职责如下，禁止以“内部调用”为由跨层合并职责：

| 层 | 职责 | 明确禁止 |
|---|---|---|
| Agent | 会话状态、工具白名单、Prompt 装配、结果校验与编排；只表达工具调用意图 | 不直接发起 Provider HTTP 请求，不实现模型路由，不直接执行交易写操作 |
| Gateway | 统一接入、能力与任务路由、超时、降级、熔断、配额、结构化输出校验、缓存、计量、审计和 SSE | 不承载商品、订单、价格等业务规则，不绕过业务层执行交易副作用 |
| RAG | 知识召回、重排、引用装配，只向调用链提供证据 | 不冒充模型网关，不无引用地回答平台规则；所需 embedding 调用同样经 Gateway |
| Provider | 适配具体厂商协议，完成中性 DTO 与厂商请求/响应、流和错误的转换 | 不负责跨 Provider 路由、业务编排、配额或业务降级，不暴露 SDK 类型给上层 |

### 2. `ModelProvider` 端口只表达厂商中性能力

P11 实现时，Provider 适配器统一实现以下端口；此处仅固定契约，不在本 ST 添加实现：

```rust
#[async_trait::async_trait]
pub trait ModelProvider: Send + Sync {
    fn id(&self) -> ProviderId;
    fn capabilities(&self) -> Capabilities;
    async fn chat(&self, req: ChatRequest) -> Result<ChatResponse, ModelError>;
    async fn chat_stream(&self, req: ChatRequest) -> Result<ChatStream, ModelError>;
    async fn embed(&self, req: EmbedRequest) -> Result<EmbedResponse, ModelError>;
}
```

- `Capabilities` 至少表达 `chat / stream / tools / vision / json / embed` 与上下文上限；Gateway 先据此筛选可处理任务的 Provider，再执行路由。
- `ChatRequest`、`ChatResponse`、`ChatStream`、`EmbedRequest`、`EmbedResponse` 均为厂商中性类型；业务、Agent 和 Gateway 的公共契约不得泄露厂商 SDK 类型。
- Provider 负责把厂商错误归一化为下述 `ModelError`，上层不得解析厂商私有错误串来猜测类别。
- 凭据和厂商连接参数由受控配置注入 Provider 适配器，日志与错误响应必须脱敏；业务配置不得保存 API Key。

### 3. `ModelError` 必须分类并驱动处理策略

| 分类 | 含义 | Gateway 处理原则 |
|---|---|---|
| `Timeout` | 调用超过任务或 Provider 时限 | 在任务总时限内受控重试或降级，禁止无限等待 |
| `RateLimited` | 厂商或平台限流 | 不做无上限立即重试，按限流信号处理并进入降级链 |
| `Auth` | 认证、授权或凭据失效 | 告警并降级，禁止使用同一失效凭据盲目重试 |
| `BadRequest` | 请求参数、消息或格式不合法 | 保留可诊断的分类错误；修正请求前不得盲目重复调用 |
| `ContentFiltered` | 输入或输出触发内容过滤 | 不展示被过滤内容，转内容安全处理与业务兜底 |
| `ServerError` | Provider 内部错误或 5xx | 在预算内重试、降级，并纳入熔断统计 |
| `ContextOverflow` | 输入或预期输出超过上下文上限 | 先按策略裁剪上下文，仍不满足再降级 |
| `Unsupported` | 当前模型不具备所需能力 | 不重试同一不支持项，按 `Capabilities` 改选或走业务兜底 |

禁止把这些错误统一吞成不分类的 `anyhow` 后再决定重试。重试与降级必须同时受任务总超时、重试次数和配额约束，并保留原始分类用于日志与指标。

### 4. Task 与模型档位全部配置化

- `Task` 固定为：`ShoppingGuide / CustomerService / QueryRewrite / ProductUnderstanding / ReviewSummary / ContentGen / RiskScoring / OpsQuery / PriceSuggest / Judge / Translate / Embedding`。
- 对话与生成任务使用 `best / balanced / fast` 三档：`best` 优先能力，`balanced` 平衡质量、时延与成本，`fast` 优先低时延和低成本。各 Task 的默认档、超时及是否流式遵循 04 §4.2.2；`Embedding` 使用专用向量模型配置。
- `Task + 档位 → (provider, model)` 的映射存入 `sys_config`，支持按租户覆盖；路由配置同时声明所需能力、超时和流式策略，Gateway 按 `Capabilities` 校验可执行性。
- **更换已支持 Provider 下的模型只改配置，不改业务、Agent 或 Gateway 代码。** 新增厂商协议时只增加 Provider 适配器，不改变业务唯一入口，也不把模型名硬编码回业务代码。

### 5. 固定降级链，并按 `(provider, model)` 熔断

- 降级链固定为：**`best → balanced → fast → 规则/模板兜底`**。不得因单次调用便利跳成 Provider 直连，也不得省略最后的业务兜底。
- 超时、`RateLimited`、`ServerError`、`Auth`、配额不足均触发降级；`ContextOverflow` 先裁剪上下文，再进入降级链。其他错误按上表分类处理，不以无差别重试代替降级。
- 发生降级时，响应必须带 `degraded: true`、`provider_used`、`reason`；AI 场景前端据此显示“简化模式”。
- 业务兜底必须可用而非空白：导购退回筛选式推荐，客服退回 FAQ 检索并支持转人工，摘要退回截断原文，文案退回模板库。兜底由业务层提供，Gateway 不伪造业务结果。
- 熔断状态以 **`(provider, model)`** 为键隔离：同一键连续失败达到 **5 次**即打开 **30 秒**；打开期间不发送常规请求，随后进入半开并放行探测。探测成功后关闭并重置连续失败计数，探测失败则继续保持/重新打开。一个模型的熔断不得误伤同 Provider 下其他健康模型。

### 6. 结构化输出必须经 JSON Schema 校验

- 请求必须携带 JSON Schema。Gateway 按“系统约束（只输出 JSON、不含解释）+ Schema 摘要 + 用户输入”三段组织提示词。
- 成功路径必须同时通过 JSON 解析与 Schema 校验，禁止把裸 `from_str` 当成完整校验。数值字段必须在 Schema 中限定范围，例如价格建议满足 `0 ≤ x ≤ 原价 1.3`，越界即判非法。
- 解析或校验失败时，携带错误片段进行**最多 2 次额外重试**。仍失败则返回 `AI_STRUCTURED_OUTPUT_FAILED` 并调用业务兜底，不得向用户返回空白，也不得把未校验内容当成功结果。
- 所有“AI 建议”类型结果必须包含 `confidence`（0–1）与 `reasons[]`；低于对应任务阈值的结果不展示。Schema 通过只代表结构合法，不代表业务规则、权限或交易条件已通过。

### 7. 精确缓存与语义缓存分层使用

- 精确缓存键采用 `hash(task, model, prompt_version, messages, params)`，结果 TTL 按任务配置：查询改写 1h、客服 FAQ 24h、导购 0（不缓存）。修改模型、Prompt 版本、消息或参数后不得错误复用旧结果。
- 语义缓存仅在 embedding 相似度 **≥ 0.95**，且 `task` 与关键参数（如类目、预算区间）一致时命中；客服 FAQ 启用，导购只对首轮启用。
- 缓存命中也必须保留审计口径并记录 `cache_hit`。缓存复用不得跨越数据授权边界或泄露租户私有上下文；涉及私有上下文时必须以租户隔离命名空间。

### 8. 按 `(tenant, task, day)` 同时约束 token 与金额

- 配额键固定为 **`(tenant, task, day)`**，分别设置 token 上限和金额上限，不能只限制调用次数。
- 任一用量达到 **80%** 触发软告警，用于通知和成本治理，软告警本身不拒绝请求。
- 达到硬上限后拒绝新的模型调用并进入既定降级链或业务兜底，不得直接返回空白，也不得借更换 Provider 绕过同一租户、任务和日期的配额。
- 实际模型调用按“模型单价 × tokens”计算 cost；重试、降级到另一模型等每次实际调用分别计量，防止只记录首次尝试而漏算成本。

### 9. 成本日志与可观测是每次调用的必需产物

- 每次 AI 调用均落 `ai_call_log`，至少包含：`provider / model / prompt_id / version / tokens / cost / latency / caller / trace_id / cache_hit / degraded`。缓存命中、重试、失败和降级不得成为审计盲区。
- 日志通过 `trace_id` 串联请求链；不得记录 API Key、厂商认证头或未经脱敏的敏感内容。
- 至少提供以下指标：
  - `ai_request_total{task,provider,status}`；
  - `ai_latency_seconds{task}`，首 token 与总耗时分开统计；
  - `ai_tokens_total{direction}`；
  - `ai_cost_total`；
  - `ai_cache_hit_ratio`；
  - `ai_degraded_total`。
- `/admin/dashboard` 展示“AI 成本 / 单均成本 / 各任务占比”。指标标签沿用 ADR-008 的低基数约束，不得加入原始 Prompt、用户输入或无限增长的标识。

### 10. 内容安全、RAG 引用与评测是上线门槛

- 所有用户可见的 AI 文本必须经过内容安全检查，未通过时不得展示，并转安全答复或业务兜底；AIGC 图片、视频必须带 AIGC 标识。
- RAG 回答必须带可定位引用；无引用不得以“平台规则”的口吻作答。检索结果和引用是证据，不得被模型输出替代。
- 每项 AI 能力必须同时具备评测集与降级路径，**无评测不得上线**。Prompt 以 `prompt_id + version` 管理，版本变更必须附 `evals/` 评测结果，分数不下降才允许升级；评测和灰度不得绕过 Gateway 的日志、安全与配额约束。

### 11. 模型与 Agent 均不得直接产生交易副作用

- 模型只输出建议或结构化意图，**不得直接写数据库，不得直接改价、改库存、发起退款，也不得执行其他交易副作用**。
- Agent 工具采用白名单，工具实现归属业务层；Agent 只发意图。写操作必须生成动作卡片并经用户确认，再由业务层完成输入校验、权限校验、业务规则校验及事务执行。
- JSON Schema 校验、模型高置信度和用户确认都不能替代业务校验。Provider、Gateway、RAG 均不得持有“生成成功即业务写入成功”的语义。

## 后果

- 正面：业务与厂商解耦，模型替换可通过配置完成；错误、重试、降级与熔断口径统一；成本、配额、缓存、trace、内容安全和评测可以集中治理；模型输出与交易执行之间有明确的业务安全边界。
- 代价：P11 需要维护中性 DTO、Provider 适配器、配置、熔断状态、缓存与配额一致性，并承担日志、指标、内容安全和评测的运营成本。多层重试和降级若缺少总时限会放大时延，因此实现时必须执行本 ADR 的预算约束。
- 用户体验：降级后的质量与表达能力可能下降，必须显式标记“简化模式”；业务兜底保证可用性，但不得宣称与完整模型能力等价。
- 实现状态：本 ST 仅新增本决策文档，**未交付 `ModelProvider` 代码、任何 Provider 适配器、真实模型调用、Agent、RAG、缓存、配额、`ai_call_log`、AI 指标或评测集**。AI Gateway、`ModelProvider` 与 Provider 适配、真实模型调用及缓存、配额、`ai_call_log`、AI 指标等网关治理实现归 P11；RAG 知识库归 P12；Agent、具体 AI 能力及其对应评测归 P13，或对应能力所属的后续阶段。不得以本 ADR 的 Accepted 状态作为功能完成证据。

## 回滚

- 本 ST 没有运行时代码、配置或数据迁移，回滚文档变更不会影响现有业务进程。若决策后续改变，应以新 ADR 替代并将本 ADR 标记为已取代，保留决策历史，不静默改写约束。
- P11 实施后的模型或 Prompt 发布问题，通过 `sys_config` 恢复上一组 Task/档位映射及上一 `prompt_id + version`；配置无法恢复或模型持续异常时，沿固定降级链进入规则/模板业务兜底。
- 任何回滚都不得临时开放业务到 Provider 的直连，也不得授权模型或 Agent 直接写库、改价、改库存或退款。
