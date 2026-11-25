# ST-0.5 · P0 工程收口 Spec

- Change ID：`close-p0-engineering-baseline`
- 阶段：P0 / ST-0.5
- 日期：2026-11-25
- 前置依据：05 §5.1、§5.3，06 §6.5、§6.8，00 A4/A5，02 §2.14，03 §3.5/§3.6，04 §4.1/§4.2

## Why

P0-1～P0-5 已有实测证据，P0-6 仍缺 ADR-004～007，仓库也尚无 CI 工作流。需要补齐架构决策与当前真实可执行的 CI 基线，同时明确尚未具备实现基础的检查不得用空命令或忽略失败伪装通过。

## What Changes

- 新增 `specs/ST-0.5.md`，把批准后的范围、文件白名单和验证口径固化为施工 Spec。
- 新增 ADR-004～007，分别固化事务消息、AI 网关、前端形态和渠道接入决策；只定义约束与未来实现边界，不交付对应业务功能。
- 更新 ADR-001 的编号预留表，使 ADR-004～007 指向本 ST 已落地的决策文档，并保留业务实现所属阶段。
- 新增 GitHub Actions CI，当前只执行已经具备条件的 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace`；失败必须阻断，不设置 `continue-on-error`。
- 在 `docs/tech-debt.md` 登记完整 CI 清单中尚未接入的检查及逐项偿还条件；TD-006 保持待偿还，不重复登记 SQLx 离线检查。
- 复用并静态复核现有 `deploy/docker-compose.yml`，不重复建设；本机没有 Docker，因此只能沿用 PostgreSQL/Redis 原生运行态证据，不能声称执行过 `docker compose up -d`。
- 更新 `docs/gates/P0.md`：仅在 ADR-001～008 实际齐备后将 P0-6 标为 ✅，追加 ST-0.5 的真实命令输出和 CI 证据边界。
- 不实现《01 · 功能矩阵》的 M0/M1/M2 业务条目，不新增业务接口、表、前端或模型调用。

## Impact

- 受影响能力：P0 工程基座、架构决策追溯、持续集成、Gate 证据与技术债管理。
- 受影响代码：无业务代码；仅新增 CI 工作流。
- 受影响文档：`specs/ST-0.5.md`、ADR-001/004/005/006/007、`docs/gates/P0.md`、`docs/tech-debt.md`。
- 不影响现有 API、数据库 schema、依赖清单、服务启动方式和 CORS/OTel 实现。
- 非破坏变更：无 **BREAKING**。

## ADDED Requirements

### Requirement: 架构决策完整性

项目 SHALL 以 ADR-004～007 固化未来实现的强制边界，且 ADR-001～008 的主题与 P0-6 要求一一对应。ADR 文档存在不得被表述为对应业务模块已经实现。

#### Scenario: 事务消息决策评审

- **WHEN** 评审 ADR-004
- **THEN** 可见业务数据与事件同一数据库事务写入、`event_id` 冲突 `DO NOTHING`、按 `pending` 与 `next_retry_at` 批量获取、成功置 `sent`、失败指数退避、超过 8 次置 `dead` 并告警的约定
- **AND** 状态约定覆盖数据模型已有的 `pending/sent/failed/dead`
- **AND** 明确消费者按 `event_id` 幂等，事务内禁止 HTTP、Redis 或模型调用，业务实现归 P5

#### Scenario: AI 网关决策评审

- **WHEN** 评审 ADR-005
- **THEN** 可见业务只经 `ai-gateway` 调用模型，Agent/Gateway/RAG/Provider 职责不串联
- **AND** 决策覆盖分类 `ModelError`、任务与模型档位配置化、`best → balanced → fast → 规则/模板兜底`、按 `(provider, model)` 熔断、结构化输出 Schema 校验与最多 2 次重试、配额/缓存/成本日志/可观测/评测要求
- **AND** 明确模型不得直接写库或执行交易副作用，业务实现归 P11

#### Scenario: 前端与渠道决策评审

- **WHEN** 评审 ADR-006 与 ADR-007
- **THEN** 前端决策锁定 Leptos 0.7 SSR+CSR、H5/小程序使用 Leptos CSR 产物加原生壳且不用 Taro、移动 App 使用 Tauri 2 mobile、SDK 由 utoipa 生成的 OpenAPI 契约生成
- **AND** 渠道决策统一 `ChannelContext{channel, device_id, open_id?, scene?}`，协议差异只位于 `channel` crate，业务代码禁止按渠道写分支
- **AND** 开放平台决策包含 OAuth2、HMAC-SHA256、5 分钟时间窗、nonce 去重、调用日志、应用配额，以及破坏性变更的 OpenAPI diff、SDK 重生成和至少 30 天兼容期
- **AND** 明确前端与渠道业务实现归 P14

### Requirement: 当前可执行 CI 基线

项目 SHALL 在 `push` 与 `pull_request` 时执行当前真实可运行的三条 Rust 门禁，任一非零退出码均使工作流失败。

#### Scenario: 推送或提交 PR

- **WHEN** GitHub Actions 收到 `push` 或 `pull_request` 事件
- **THEN** 工作流安装带 rustfmt/clippy 的 stable Rust 工具链并依次运行 fmt、clippy、workspace test
- **AND** 三条命令与 05 §5.3 原文一致
- **AND** 不使用空实现、占位命令、`continue-on-error` 或忽略失败来制造绿色状态

#### Scenario: 本地复核 CI 子集

- **WHEN** 在本机依次执行相同三条命令
- **THEN** 三条命令均退出码 0，测试结果无失败、无新增忽略用例
- **AND** 真实结果写入 P0 Gate；若未取得 GitHub Actions 运行记录，必须明确“未实测 GitHub-hosted runner”，不得把本地通过等同于远端工作流已运行

### Requirement: 延后检查必须有偿还边界

项目 SHALL 保留 05 §5.3 全量 CI 目标，但只为当前已存在的能力启用检查；延后项必须能在技术债台账中追踪。

#### Scenario: 当前仓库尚无对应能力

- **WHEN** 当前无 `.sqlx/` 业务离线元数据、无 `crates/xtask`、无 `deny.toml` 评审基线、无通用 ST 白名单解析机制、无评测集
- **THEN** CI 不出现伪造成功的 sqlx/xtask/deny/eval 或白名单检查步骤
- **AND** `docs/tech-debt.md` 说明缺失检查的影响和逐项接入条件
- **AND** SQLx 检查继续由 TD-006 跟踪，在首个业务查询 ST 接入；openapi、consistency、eval 分别在对应生成器、业务一致性断言和评测能力落地时接入
- **AND** `cargo deny check` 与通用 ST 白名单 diff 校验在不晚于 P1 的专项中完成政策/格式设计并接入，不能在每个业务 ST 中无限顺延

### Requirement: 部署与 Gate 证据边界

项目 SHALL 区分静态配置交付、本机原生服务验证和真实 Docker/GitHub Actions 运行证据。

#### Scenario: 本机无 Docker

- **WHEN** 复核 P0-1 与 compose 文件
- **THEN** 现有 PostgreSQL 17、Redis 7、健康检查和数据卷配置保持可用
- **AND** P0 台账沿用已实测的原生 PostgreSQL/Redis 与 HTTP 探针证据
- **AND** 不记录未实际执行的 `docker compose up -d` 或 Docker 健康检查结论

#### Scenario: P0-6 收口

- **WHEN** ADR-001～008 均已落盘且内容通过检查
- **THEN** P0-6 可由 🟡 更新为 ✅，证据列出八份文档
- **AND** 完整 CI 尚未接入、GitHub-hosted runner 未实测等事项继续留在技术债或证据说明中，不因 P0-6 完成而消失

#### Scenario: `/metrics` 部署保护尚未实测

- **WHEN** 本轮只有依赖服务 compose，没有应用与 ingress 部署清单元件
- **THEN** TD-003 不被伪装为已偿还
- **AND** 台账将其偿还边界调整为实际应用部署/P17：必须交付来源限制或独立管理端口及抓取配置，并取得运行态证据

### Requirement: ST 文件边界

实施 SHALL 只修改本 Spec 的白名单文件，完成后以 `git diff --name-only` 和 `git status --short` 复核。

#### Scenario: 最终范围检查

- **WHEN** 完成实现与证据登记
- **THEN** 改动只落在白名单及本变更的三份提案文件内
- **AND** `docs/spec/**`、`docs/prompt/MAIN.md`、业务源码、Cargo manifest/lock、migrations 和现有 compose 文件均无改动

## MODIFIED Requirements

### Requirement: P0-6 ADR Gate

原要求“ADR-001～008 齐备”保持不变；本 ST 将状态从“部分完成”改为“完成”的唯一条件是八份 ADR 实际存在、主题完整且经文件检查，不以未来业务代码是否实现作为 P0 文档 Gate 的替代标准。

### Requirement: P0 CI 基线

原目标仍为 05 §5.3 的八条命令及 06 §6.5 白名单 diff 校验；本 ST 只交付当前可执行子集，其余项以有明确触发条件的技术债保留，不降低最终目标，也不将当前子集宣称为完整 CI。

## REMOVED Requirements

无。既有 Gate、功能矩阵、技术栈和部署目标均不删除。

## 改动文件（白名单）

- `specs/ST-0.5.md`：新增，施工 Spec
- `docs/adr/004-transactional-outbox.md`：新增，事务消息与 outbox 决策
- `docs/adr/005-ai-gateway.md`：新增，AI 网关决策
- `docs/adr/006-frontend.md`：新增，前端形态决策
- `docs/adr/007-channel.md`：新增，渠道接入决策
- `docs/adr/001-layering.md`：修改，仅更新 ADR 编号预留表状态
- `.github/workflows/ci.yml`：新增，当前可执行 CI 子集
- `docs/tech-debt.md`：修改，登记延后 CI 项并澄清 TD-003 偿还边界
- `docs/gates/P0.md`：修改，更新 P0-6 和 ST-0.5 实测证据

本提案阶段仅允许另外存在：`.trae/specs/close-p0-engineering-baseline/{spec,tasks,checklist}.md`。

## 明确不改

- `docs/spec/**`、`docs/prompt/MAIN.md`
- `apps/**`、`crates/**` 及其他 Rust 源码
- `Cargo.toml`、`Cargo.lock`、`rust-toolchain.toml`、任何 crate manifest 与依赖版本
- `migrations/**`、`seeds/**`、`.sqlx/**`
- `deploy/docker-compose.yml` 及其他部署配置
- 已完成 ST-0.1～ST-0.4 的功能、测试与 CORS/OTel 配置
- 功能矩阵中的账号、商品、交易、支付、AI、供应链、渠道等业务实现

## 验证与证据

1. 文件核查：ADR-001～008 均存在，四份新增 ADR 含本 Spec 要求的决策和实现阶段。
2. CI 静态核查：事件、工具链和三条命令准确，无忽略失败或无实现检查。
3. 本机实跑：`cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace`，保存退出码与测试统计。
4. 部署边界：静态核对现有 compose；没有 Docker 运行证据时明确写“未实测”。
5. 范围核查：`git diff --check`、`git diff --name-only`、`git status --short`，确认无白名单外改动。
6. 若环境没有 GitHub 远端或 Actions 运行权限，不阻塞文档与本地门禁交付，但最终响应和 Gate 必须列出该证据缺口。

## 完成定义

- P0-6 仅在八份 ADR 核查通过后标 ✅。
- CI 当前子集配置完成，本地三条命令真实通过；远端未运行则明示。
- 所有延后项保留可追踪技术债，不以 TODO、空命令或降级断言冒充完成。
- 不声称已实现 outbox worker、AI 网关、前端、渠道、完整 CI 或生产部署。
