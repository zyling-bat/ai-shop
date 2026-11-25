# ADR-001 分层与依赖方向

- 状态：已接受（Accepted）
- 日期：2026-11-24
- 阶段：P0 / ST-0.1
- 关联约束：C1（Edition 2024 / MSRV）、C2（多 crate）、C3（单向依赖）、C4（无占位符、日志走 tracing）、06 §6.1（依赖锁版）、06 §6.2（crate 文件级清单）、05 §5.1 P0 Gate 第 6 条

## 背景

系统按 C2 拆为多 crate 的 Cargo workspace：`shared / domain / application / infrastructure / api / ai-gateway / ai-rag / ai-agent / worker / channel` 十个库 crate 与 `apps/server` 一个 bin crate。

C3 要求依赖方向单向：领域层不感知框架，应用层不感知传输与存储细节。若这条约束只写在文档里，第一个"临时引一下 axum 方便调试"的提交就会把它击穿，且后续每个域都要返工。因此本 ADR 把分层固化为**可执行的两样东西**：

1. 每个成员 `Cargo.toml` 中的依赖边（编译器强制）；
2. 一条 `cargo tree` 校验命令（评审强制）。

## 决策

### 1. 分层铁律

- `shared`：无业务语义的基础类型（金额、ID、时间、错误码等），**不依赖任何内部 crate**。
- `domain`：实体、值对象、状态机、领域错误。**纯 Rust，不出现 axum / sqlx / reqwest**。
- `application`：用例编排、端口（trait）、DTO、工作单元。**不出现 axum / sqlx / reqwest**。
- `infrastructure`：数据库、缓存、外部服务适配器，实现 `application` 定义的端口。
- `api`：HTTP 路由、中间件、错误映射；只做协议转换，不含业务规则。
- `ai-gateway` / `ai-rag` / `ai-agent`：AI 能力分层，`ai-agent` 可依赖 `application`，`ai-rag` 只依赖 `ai-gateway`。
- `worker`：后台任务（outbox、定时作业、导出）。
- `channel`：渠道适配（Web / H5 / 小程序 / App / 开放平台）。
- `apps/server`：唯一的可执行入口，装配 `api` 与启动期依赖（tokio / axum / tracing）。

### 2. 允许的内部依赖边（白名单）

| crate | 允许依赖内部 crate |
|---|---|
| `shared` | — |
| `domain` | `shared` |
| `application` | `domain`, `shared` |
| `infrastructure` | `application`, `domain`, `shared` |
| `api` | `application`, `shared` |
| `ai-gateway` | `shared` |
| `ai-rag` | `ai-gateway`, `shared` |
| `ai-agent` | `application`, `ai-gateway`, `shared` |
| `worker` | `application`, `infrastructure`, `shared` |
| `channel` | `application`, `shared` |
| `apps/server` | `api`, `shared`（启动期配置类型；ST-0.2 起）, `infrastructure`（启动期装配连接池；ST-0.3 起）+ 启动期依赖 tokio / axum / tracing |

白名单之外的边一律视为越界，评审按 C3 打回。

本表的变更记录：

| 日期 | ST | 变更 | 依据 |
|---|---|---|---|
| 2026-11-24 | ST-0.1 | 建表：11 个 crate 的初始依赖边 | C3、06 §6.2 |
| 2026-11-24 | ST-0.2 | 新增 `apps/server → shared`（启动期配置类型 `AppConfig`） | 用户书面确认（本 ST Spec「待确认 3」）；配置需被 `infrastructure` 在 ST-0.3 复用，放 `shared` 避免二次搬迁 |
| 2026-11-24 | ST-0.3 | 新增 `apps/server → infrastructure`（装配 PG / Redis 连接池、就绪探针与审计适配器） | 用户书面确认（`specs/ST-0.3.md`「待确认 1」）；server 只做装配，不写 SQL，SQL 全部在 `infrastructure` |

ST-0.1 阶段各 crate 尚无代码，因此**只声明实际使用到的依赖**，不预埋未用依赖（避免"声明即依赖"的假约束）。上表中尚未落地的边，在该 crate 首次写入代码的 ST 里按本表补齐。

### 3. 执行方式（校验命令）

```bash
cargo tree -p domain --edges normal
cargo tree -p api --edges normal
```

- `domain` 的输出必须为**空**（或仅 `shared`），不得出现 `axum` / `sqlx` / `reqwest`。
- `api` 允许出现 `axum`（它是 HTTP 层），同样不得出现 `sqlx` / `reqwest`。
- 违反即评审打回，并要求修改 `Cargo.toml` 而非"下不为例"。

反向自证（ST-0.1 已实测）：在 `crates/domain/Cargo.toml` 临时加入 `axum.workspace = true` 后，`cargo tree -p domain` 立刻出现 `axum v0.8.x`；删除该行后输出恢复为空。记录见 `docs/gates/P0.md`。

### 4. 工具链基线

实测（2026-11-24，本机 stable）：

```
rustc 1.99.1 (58cf8f9c3 2026-10-13)
cargo 1.99.1 (5f94df478 2026-08-27)
```

workspace 基线：

- `edition = "2024"`，`rust-version = "1.85"`（Edition 2024 的最低支持版本，见 C1）
- `resolver = "3"`（Edition 2024 的默认 MSRV 感知解析器）
- `publish = false`（内部 crate，不发 crates.io）
- `rust-toolchain.toml` 固定 `channel = "stable"`，组件 `rustfmt`、`clippy`

`tokio` 在 `apps/server` 中额外启用 `net` 特性：`axum::serve` 需要把一个 `tokio::net::TcpListener` 交给运行时；`axum 0.8` 的 `serve` 签名直接接收 `TcpListener`，因此 `rt-multi-thread` / `macros` / `signal` 之外必须包含 `net`。若不启用 `net`，`cargo build` 会在 `TcpListener::bind` 处失败。

### 5. 变更流程

修改以下任一项，必须**先改本 ADR 并经用户书面确认**，再动代码：

- Edition 或 `rust-version`（含降级/升级 MSRV）
- `resolver` 版本
- 上表白名单中的依赖方向（新增边、反转边）
- 引入锁版清单（06 §6.1）之外的新依赖

## ADR-002 ~ ADR-008 编号预留

| 编号 | 主题 | 预计归属 ST |
|---|---|---|
| ADR-002 | 数据库与 ORM（sqlx、迁移策略、连接池） | ST-0.3（已落地） |
| ADR-003 | 缓存与分布式锁（Redis 客户端选型、锁语义） | ST-0.3（已落地，锁协议 P4 实现） |
| ADR-004 | [事务消息与 outbox 投递语义](004-transactional-outbox.md) | ST-0.5（决策已落地，业务实现归 P5） |
| ADR-005 | [AI 网关（多厂商路由、配额、降级、结构化输出）](005-ai-gateway.md) | ST-0.5（决策已落地，业务实现归 P11） |
| ADR-006 | [前端形态（SSR / CSR / 小程序 build 链路）](006-frontend.md) | ST-0.5（决策已落地，业务实现归 P14） |
| ADR-007 | [渠道接入（Web / H5 / 小程序 / App / 开放平台）](007-channel.md) | ST-0.5（决策已落地，业务实现归 P14） |
| ADR-008 | 可观测（tracing、metrics、OTel、trace 串联） | ST-0.2（已落地，OTLP 导出部分见 TD-001） |

本表用于避免后续 ADR 抢号；ADR-004～ADR-007 的决策已在 ST-0.5 成文，业务实现仍分别在 P5 / P11 / P14 / P14 落地，其余各条在对应 ST 落地时单独成文。
