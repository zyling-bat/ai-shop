# ST-0.5 P0 工程收口与当前可执行 CI 基线 Spec

> 阶段：P0 工程基座｜Change ID：`close-p0-engineering-baseline`｜日期：2026-11-25。
> 本轮只做工程收口：补齐 ADR-004～007、建立当前真实可执行的 CI 子集、登记完整 CI 延后项并澄清 Gate 证据边界；不实现功能矩阵，不交付对应业务模块。
> 依据：`05-验收用例与Gate.md` §5.1/§5.3、`06-工程执行清单.md` §6.5/§6.8，以及已批准提案 `.trae/specs/close-p0-engineering-baseline/spec.md`。

## Why

P0-1～P0-5 已有实测证据，但 P0-6 所要求的 ADR-001～008 尚缺事务消息、AI 网关、前端和渠道四份决策，仓库也尚无 CI 工作流。本 ST 用文档固化后续实现的强制边界，并只启用当前仓库具备真实执行基础的 CI 检查。

05 §5.3 的完整 CI 目标保持不变。当前不存在的 SQLx 业务离线元数据、`xtask` 生成器/断言、依赖政策基线、通用 ST 白名单解析机制和评测能力，不得通过空命令、占位步骤、忽略失败或降级断言伪装完成；延后项必须按 06 §6.8 登记影响与触发偿还条件。

本 Spec 仅规定施工范围和验收口径，不代表其中文件已经交付，也不预设任何本地命令、Docker 或 GitHub Actions 已运行及其结果。

## What Changes

- 新增 ADR-004～007，分别固化事务消息、AI 网关、前端形态与渠道接入决策；只定义约束、边界和未来实现阶段，不实现对应业务功能。
- 修改 ADR-001 的编号预留表，使 ADR-004～007 指向本 ST 的决策文档；业务实现仍归属后续阶段。
- 新增 GitHub Actions 工作流，在 `push`、`pull_request` 时只运行 fmt、clippy、workspace test 三条真实命令，任一失败均阻断。
- 更新 `docs/tech-debt.md`，逐项登记完整 CI 尚未接入的检查、影响及偿还条件；SQLx 离线检查继续由 TD-006 跟踪，不重复建项。
- 静态复核并复用现有 `deploy/docker-compose.yml`，不重复建设、不修改部署配置；沿用 PostgreSQL/Redis 原生运行态及 HTTP 探针证据，不伪造 Docker 证据。
- 更新 `docs/gates/P0.md`：仅在 ADR-001～008 实际齐备且主题核查通过后将 P0-6 标为 ✅；如实追加 ST-0.5 本地命令、CI 和部署证据边界。
- 明确 TD-003 未偿还；`/metrics` 部署保护的偿还边界落到实际应用部署/P17，并取得运行态证据。
- **不含**：outbox worker、AI 网关、前端、渠道适配、业务接口/表/模型调用、完整 CI 或生产部署。

## Impact

- Affected specs：P0-6（ADR 齐备性）、P0 CI 基线（当前可执行子集）、P0 Gate 证据与技术债管理。
- Affected code：无业务代码；仅新增 `.github/workflows/ci.yml`。
- Affected docs：本 Spec、ADR-001/004/005/006/007、`docs/gates/P0.md`、`docs/tech-debt.md`。
- 不改变现有 API、数据库 schema、依赖清单、服务启动方式、CORS/OTel 实现及既有 compose 配置。
- 完整 CI 最终目标不降低；当前三条命令不得宣称为 05 §5.3 的完整 CI。
- 非破坏变更：无 **BREAKING**。

## ADDED Requirements

### Requirement: R1 ADR-004 事务消息与 outbox 决策边界

ADR-004 SHALL 固化以下约定，且明确业务实现归 P5，ADR 落盘不等于事务消息能力已经实现：

- 业务数据与事件必须在同一数据库事务中写入。
- `event_id` 冲突使用 `DO NOTHING`，消费者按 `event_id` 幂等。
- 按 `pending` 与 `next_retry_at` 批量获取；发送成功置 `sent`，失败采用指数退避，超过 8 次置 `dead` 并告警。
- 状态约定完整覆盖现有数据模型的 `pending/sent/failed/dead`。
- 数据库事务内禁止 HTTP、Redis 或模型调用，避免外部副作用与长事务。

#### Scenario: 决策与实现状态分离

- **WHEN** 评审 ADR-004 或更新 P0 Gate
- **THEN** 可逐项核对上述事务、重试、终态、幂等和副作用约束
- **AND** 文档明确实现阶段为 P5，不声称本 ST 已交付 outbox worker 或消息投递能力

### Requirement: R2 ADR-005 AI 网关决策边界

ADR-005 SHALL 固化以下约定，且明确业务实现归 P11：

- 业务只能通过 `ai-gateway` 调用模型；Agent、Gateway、RAG、Provider 职责分离，不得混为不经网关的串联调用。
- 定义分类 `ModelError`；任务与模型档位配置化。
- 降级链固定为 `best → balanced → fast → 规则/模板兜底`。
- 按 `(provider, model)` 维度熔断。
- 结构化输出必须经 Schema 校验，最多重试 2 次。
- 决策覆盖配额、缓存、成本日志、可观测和评测要求。
- 模型不得直接写数据库或执行交易副作用。

#### Scenario: 决策与实现状态分离

- **WHEN** 评审 ADR-005 或更新 P0 Gate
- **THEN** 可逐项核对网关唯一入口、职责、错误、配置、降级、熔断、结构化输出与治理约束
- **AND** 文档明确实现阶段为 P11，不声称本 ST 已接入 Provider、RAG、Agent 或真实模型调用

### Requirement: R3 ADR-006 前端形态决策边界

ADR-006 SHALL 锁定以下技术形态，且明确前端业务实现归 P14：

- Web 使用 Leptos 0.7 SSR+CSR。
- H5/小程序使用 Leptos CSR 产物加原生壳，不使用 Taro。
- 移动 App 使用 Tauri 2 mobile。
- SDK 由 utoipa 生成的 OpenAPI 契约生成，不手写重复契约。

#### Scenario: 仅交付决策

- **WHEN** 评审 ADR-006
- **THEN** 四种形态及 SDK 契约来源均有明确约束
- **AND** 不新增前端工程、页面、SDK 生成物或模型调用，不声称 P14 功能已实现

### Requirement: R4 ADR-007 渠道接入决策边界

ADR-007 SHALL 固化以下约定，且明确渠道业务实现归 P14：

- 统一上下文为 `ChannelContext{channel, device_id, open_id?, scene?}`。
- 协议差异只允许位于 `channel` crate，业务代码禁止按渠道写分支。
- 开放平台采用 OAuth2、HMAC-SHA256、5 分钟时间窗、nonce 去重、调用日志和应用配额。
- 破坏性变更必须执行 OpenAPI diff、重新生成 SDK，并提供至少 30 天兼容期。

#### Scenario: 仅交付决策

- **WHEN** 评审 ADR-007
- **THEN** 上下文、协议隔离、开放平台安全和兼容策略均可逐项核查
- **AND** 不新增渠道适配器、回调接口、签名实现或渠道业务分支，不声称 P14 功能已实现

### Requirement: R5 当前真实可执行 CI 基线

项目 SHALL 新增 `.github/workflows/ci.yml`，在 `push` 与 `pull_request` 事件中安装带 rustfmt、clippy 组件的 stable Rust 工具链，并依次执行且仅执行以下三条 Rust 门禁命令：

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test --workspace
```

三条命令 SHALL 与 05 §5.3 原文一致。任一步非零退出码必须使工作流失败；禁止 `continue-on-error`、忽略退出码、空实现、占位命令或以注释/说明文字替代步骤。

#### Scenario: 推送或提交 PR

- **WHEN** GitHub Actions 收到 `push` 或 `pull_request` 事件
- **THEN** 工作流依次运行 fmt、clippy、workspace test，任一失败均阻断
- **AND** 工作流不出现当前无实现基础的 sqlx、xtask、deny、eval 或通用 ST 白名单检查步骤

#### Scenario: 本地与远端证据分别记录

- **WHEN** 实施者在本机执行同一组三条命令
- **THEN** 将真实退出码、测试统计和失败信息（如有）写入 P0 Gate，不预写通过结论
- **AND** 只有取得实际 GitHub Actions 运行记录时才能声明远端通过；否则明确写“未实测 GitHub-hosted runner”，不得以本地通过替代远端证据

### Requirement: R6 完整 CI 延后项与技术债

05 §5.3 的完整目标仍为下列八条命令。本 ST 只交付前三条，其余五条及 06 §6.5 通用 ST 白名单 diff 校验必须保留为可追踪技术债，不得从最终目标中删除：

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test --workspace
cargo sqlx prepare --check          # 离线元数据与代码一致
cargo xtask openapi --check         # 契约与实现 diff 为零
cargo deny check                    # 依赖与许可证
cargo xtask consistency --check     # 金额/库存/结算一致性断言
cargo xtask eval --smoke            # AI 冒烟评测（分数不下降）
```

`docs/tech-debt.md` SHALL 按下表登记位置、问题、影响、触发偿还条件、负责人和登记日期；编号沿用现有台账，不虚构偿还状态：

| 延后检查 | 当前缺失基础与影响 | 触发偿还条件 |
|---|---|---|
| `cargo sqlx prepare --check` | 无 `.sqlx/` 业务离线元数据，无法校验离线元数据与查询一致 | 继续由 TD-006 跟踪，在首个业务查询 ST 接入；不重复登记 |
| `cargo xtask openapi --check` | 无 `crates/xtask` 与对应生成器，无法自动检查契约漂移 | OpenAPI 生成器落地时接入 |
| `cargo xtask consistency --check` | 无 `xtask` 与业务一致性断言，无法自动检查金额/库存/结算差异 | 对应业务一致性断言落地时接入 |
| `cargo xtask eval --smoke` | 无评测能力与评测集，无法防止 AI 冒烟评分回退 | 对应评测能力与评测集落地时接入 |
| `cargo deny check` | 无 `deny.toml` 评审基线，依赖与许可证政策未自动执行 | 不晚于 P1 的专项完成政策设计并接入，不得逐业务 ST 无限顺延 |
| 通用 ST 白名单 diff 校验 | 无通用 ST 白名单解析机制，无法自动识别越界改动 | 不晚于 P1 的专项完成格式设计并接入，不得逐业务 ST 无限顺延 |

#### Scenario: 延后不等于完成或取消

- **WHEN** 当前仓库缺少某项检查的实现基础
- **THEN** CI 不添加该检查的伪造成功步骤，技术债保留其影响和明确接入条件
- **AND** P0-6 文档 Gate 完成不得关闭上述技术债，也不得把当前 CI 子集描述为完整 CI

### Requirement: R7 Docker、原生服务与 GitHub Actions 证据边界

项目 SHALL 区分静态配置交付、本机原生服务实测和真实 Docker/GitHub Actions 运行证据。

- 静态复核现有 `deploy/docker-compose.yml` 的 PostgreSQL 17、Redis 7、健康检查和数据卷配置，复用而不修改。
- P0 台账沿用已实测的原生 PostgreSQL/Redis 与 `/healthz`、`/readyz` HTTP 探针证据。
- 本机没有 Docker 时，明确“未实测 Docker compose”，不得记录未实际执行的 `docker compose up -d`、容器健康检查或部署成功结论。
- 没有 GitHub Actions 实际运行记录时，明确“未实测 GitHub-hosted runner”；本地三条命令结果不得等同于远端工作流证据。
- 本轮只有依赖服务 compose，没有应用与 ingress 部署清单元件，因此 TD-003 保持待偿还。其偿还边界为实际应用部署/P17：交付 `/metrics` 来源限制或独立管理端口及抓取配置，并取得运行态证据。

#### Scenario: P0-6 收口不吞并证据缺口

- **WHEN** ADR-001～008 均已落盘且八份主题核查通过
- **THEN** P0-6 才可由 🟡 更新为 ✅，证据列出八份 ADR 文件
- **AND** 完整 CI 延后项、未实测的 GitHub-hosted runner、Docker 或 `/metrics` 部署保护仍留在技术债或证据说明中，不因 P0-6 完成而消失

## MODIFIED Requirements

### Requirement: P0-6 ADR Gate

05 §5.1 的“ADR-001～008 齐备”要求不变。P0-6 从“部分完成”改为“完成”的唯一条件是八份 ADR 实际存在、主题完整且通过文件检查；不得用未来业务代码是否实现替代文档 Gate，也不得由文档存在反推业务模块已经实现。

### Requirement: P0 CI 基线

05 §5.3 八条命令及 06 §6.5 白名单 diff 校验仍是最终目标。本 ST 只交付当前可执行的三条 Rust 门禁，其余项以有明确触发条件的技术债保留；不降低最终目标，不宣称完整 CI 已落地。

## REMOVED Requirements

无。既有 Gate、功能矩阵、技术栈、完整 CI 和部署目标均不删除。

## 改动文件（白名单）

新增：

- `specs/ST-0.5.md`（施工 Spec）
- `docs/adr/004-transactional-outbox.md`（事务消息与 outbox 决策）
- `docs/adr/005-ai-gateway.md`（AI 网关决策）
- `docs/adr/006-frontend.md`（前端形态决策）
- `docs/adr/007-channel.md`（渠道接入决策）
- `.github/workflows/ci.yml`（当前可执行 CI 子集）

修改：

- `docs/adr/001-layering.md`（仅更新 ADR 编号预留表状态及链接，不改分层决策）
- `docs/tech-debt.md`（登记延后 CI 项，保留 TD-006 单一跟踪并澄清 TD-003 偿还边界）
- `docs/gates/P0.md`（更新 P0-6 状态与 ST-0.5 真实证据/证据缺口）

本变更另外仅允许存在以下三份已批准提案文件：

- `.trae/specs/close-p0-engineering-baseline/spec.md`
- `.trae/specs/close-p0-engineering-baseline/tasks.md`
- `.trae/specs/close-p0-engineering-baseline/checklist.md`

除以上文件外不得产生其他改动；最终必须用 `git diff --name-only` 与 `git status --short` 同时核对已跟踪和未跟踪文件，不能只依赖白名单文字声明。

## 明确不改

- `docs/spec/**`、`docs/prompt/MAIN.md`。
- `apps/**`、`crates/**` 及其他 Rust 源码；不新增任何业务代码、业务接口或模型调用。
- `Cargo.toml`、`Cargo.lock`、`rust-toolchain.toml`、任何 crate manifest 与依赖版本。
- `migrations/**`、`seeds/**`、`.sqlx/**`；不新增表、迁移、种子或伪造 SQLx 离线元数据。
- `deploy/docker-compose.yml` 及其他部署配置；不重复建设 compose，不补写未经验证的部署清单元件。
- 已完成 ST-0.1～ST-0.4 的功能、测试与 CORS/OTel 配置。
- 功能矩阵 M0/M1/M2 及账号、商品、交易、支付、AI、供应链、渠道等业务实现。
- ADR-002、ADR-003、ADR-008 及其他未列入白名单的 ADR。
- TD-006 不关闭、不重复登记；TD-003 不标记已偿还。

## 验证与证据

以下均为实施阶段的验证要求，不是本 Spec 已取得的运行结果：

1. **ADR 文件核查**：确认 ADR-001～008 均存在；逐条检查 ADR-004～007 满足 R1～R4，ADR-001 预留表指向新增文档且实现阶段未被误改。
2. **CI 静态核查**：检查工作流触发器为 `push`/`pull_request`，stable 工具链含 rustfmt/clippy，仅含 R5 三条真实命令，且无 `continue-on-error`、忽略失败或空实现检查。
3. **本机实跑并原样记录**：依次执行以下命令，向 `docs/gates/P0.md` 记录真实退出码、输出摘要和测试统计；完成要求为三条均退出码 0、测试无失败且无新增忽略用例，失败则不得标为通过。

   ```bash
   cargo fmt --check
   cargo clippy --all-targets -- -D warnings
   cargo test --workspace
   ```

4. **远端 CI 证据**：取得 GitHub Actions 实际运行链接/编号及结果后方可声明远端通过；没有远端、权限或运行记录时，不阻塞文档与本地门禁交付，但最终报告和 P0 Gate 必须写明“未实测 GitHub-hosted runner”。
5. **部署证据边界**：只静态核对现有 compose 的 PostgreSQL 17、Redis 7、健康检查和数据卷；沿用既有原生服务与 HTTP 探针实测证据。没有 Docker 实际运行时明确“未实测 Docker compose”，不得补写 `docker compose up -d` 或容器健康检查通过结论。
6. **技术债核查**：五项延后 CI 与通用 ST 白名单 diff 校验均有影响及触发偿还条件；TD-006 仍唯一跟踪 SQLx，TD-003 仍待实际应用部署/P17 偿还。
7. **Gate 条件核查**：仅在八份 ADR 实际齐备且主题完整后把 P0-6 标为 ✅，证据列出八份文件；完整 CI、远端 CI、Docker 和 TD-003 的证据缺口继续保留。
8. **范围核查**：执行以下命令，确认无格式错误且无白名单外改动，并保留真实输出作为证据。

   ```bash
   git diff --check
   git diff --name-only
   git status --short
   ```

## 完成定义

- ADR-004～007 和 ADR-001 预留表按白名单落盘，ADR-001～008 文件及主题核查通过后，P0-6 才标为 ✅。
- CI 当前子集配置准确，三条本地命令均真实通过并记录退出码与测试统计；未实际取得远端运行证据时明示缺口。
- 完整 CI 未接入项与通用 ST 白名单校验均可追踪，未以 TODO、空命令、忽略失败或降级断言冒充完成。
- 现有 compose 仅静态复核；原生服务、Docker、GitHub Actions 三类证据严格区分，TD-003 与 TD-006 状态不被误改。
- 最终改动仅限精确白名单及三份提案文件，`git diff --check` 通过，范围复核无白名单外文件。
- 不声称已实现 outbox worker、AI 网关、前端、渠道、完整 CI 或生产部署，不将决策文档交付等同于功能矩阵落地。
