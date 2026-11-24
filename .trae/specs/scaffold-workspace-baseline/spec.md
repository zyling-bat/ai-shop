# ST-0.1 工程骨架与工具链基线 Spec

> 阶段：P0 工程基座｜本轮只做 ST-0.1，不写任何业务代码。
> 依据：`docs/spec/AI电商-Spec文档包-v2/00-总纲与主Prompt.md`（C1/C2/C3/C4/C6/C7）、`06-工程执行清单.md`（6.1 依赖锁版、6.2 文件级清单、6.5 改动边界）、`05-验收用例与Gate.md`（P0 Gate）。

## Why

当前仓库只有 `docs/`（规格文档包），没有 Rust workspace、没有工具链基线、没有任何可启动进程。P1 起的建模、交易、AI 都无处落地；而 C2（多 crate）、C3（单向依赖）、C1（Edition 2024 / MSRV）这三条一旦开头选错，后面每个域都要返工。

ST-0.1 只解决一件事：**把"骨架 + 可执行的分层约束 + 质量门禁 + 证据台账"立起来**，让后续每个 ST 都有确定的地基和可证伪的边界。

## What Changes

- 新增 Cargo workspace（10 个 crate + `apps/server`），统一 Edition 2024、`rust-version = 1.85`、`resolver = "3"`、`publish = false`
- 新增 `rust-toolchain.toml` 固定 stable 通道与 `rustfmt`/`clippy` 组件，把实测 `rustc --version` 写入 ADR-001（C1）
- 用 Cargo.toml 依赖边固化 A5 分层铁律：`domain → shared`、`application → domain`、`api → application`、`infrastructure → application`、`channel → application`，domain/application 不得出现 axum/sqlx/reqwest（C3）
- 新增最小 axum 服务：只有 `GET /healthz`，无业务路由；`/readyz`、`/metrics` 明确留到 ST-0.2/0.3，**不伪装为 200**
- 新增 workspace lints：`unsafe_code = forbid`、`clippy::todo/unimplemented/dbg_macro/print_stdout/print_stderr = deny`（C4/C7 的可执行化）
- 新增 `docs/adr/001-layering.md`（分层与依赖边 + 工具链实测）与 `docs/gates/P0.md`（P0 证据台账，只记 ST-0.1 可证部分）
- 初始化 git 仓库、`.gitignore`，`Cargo.lock` 入库（06 §6.1）
- **不含**：数据库/迁移、Redis、配置加载、tracing 装配、`/readyz`、`/metrics`、CI 流水线、xtask、任何业务域代码

## Impact

- Affected specs：P0 Gate 第 2 条（fmt/clippy 零输出）、第 1 条中的 `/healthz` 部分、第 6 条中的 ADR-001
- Affected code：仓库根（`Cargo.toml`/`rust-toolchain.toml`/`.gitignore`）、`crates/*`、`apps/server`、`docs/adr/`、`docs/gates/`、`specs/`
- 对既有文档包 `docs/spec/**` 只读，不修改

## 改动文件（白名单）

新增：

- `Cargo.toml`（workspace 根：members、`workspace.package`、`workspace.dependencies` 子集、`workspace.lints`）
- `rust-toolchain.toml`
- `.gitignore`
- `crates/shared/{Cargo.toml, src/lib.rs}`
- `crates/domain/{Cargo.toml, src/lib.rs}`
- `crates/application/{Cargo.toml, src/lib.rs}`
- `crates/infrastructure/{Cargo.toml, src/lib.rs}`
- `crates/api/{Cargo.toml, src/lib.rs, src/router.rs}`
- `crates/ai-gateway/{Cargo.toml, src/lib.rs}`
- `crates/ai-rag/{Cargo.toml, src/lib.rs}`
- `crates/ai-agent/{Cargo.toml, src/lib.rs}`
- `crates/worker/{Cargo.toml, src/lib.rs}`
- `crates/channel/{Cargo.toml, src/lib.rs}`
- `apps/server/{Cargo.toml, src/main.rs}`
- `docs/adr/001-layering.md`
- `docs/gates/P0.md`
- `specs/ST-0.1.md`（内容与本 Spec 一致，供 A2 流程引用）
- `Cargo.lock`（由构建生成，入库）

修改：无（仓库当前无其它可改文件）

## 明确不改

- `docs/spec/AI电商-Spec文档包-v2/**` 与 `docs/prompt/MAIN.md`：只读，一个字节都不动
- 不引入 sqlx / redis / reqwest / leptos / pgvector：P0 后续 ST 各自引入并单独论证
- 不建表、不写迁移、不定义领域模型、不开业务路由、不写 `todo!()` 占位
- 不创建 `crates/xtask`：它的首个真实子命令（migrate/openapi）属于 ST-0.3，此轮创建只会是空壳

## ADDED Requirements

### Requirement: R1 工具链与版本基线

workspace SHALL 以 Rust stable（Edition 2024，`rust-version = 1.85`，`resolver = "3"`）构建，并通过 `rust-toolchain.toml` 固定通道与组件；实测版本 SHALL 写入 ADR-001。

#### Scenario: 版本基线可证
- **WHEN** 执行 `cargo metadata --no-deps --format-version 1`
- **THEN** 每个 workspace member 的 `edition` 为 `2024`，根 `Cargo.toml` 的 `rust-version` 为 `1.85`
- **AND** `docs/adr/001-layering.md` 中记录实测 `rustc --version`（本机为 `rustc 1.99.1 (58cf8f9c3 2026-10-13)`）

#### Scenario: 不降级
- **WHEN** 后续任何 ST 想改 edition/MSRV
- **THEN** 必须先出 ADR 并经用户书面确认（C1）

### Requirement: R2 crate 结构与单向依赖

workspace SHALL 包含 `shared / domain / application / infrastructure / api / ai-gateway / ai-rag / ai-agent / worker / channel` 十个库 crate 与 `apps/server` 一个 bin crate；crate 间依赖边 SHALL 只允许 ADR-001 白名单内的方向，`domain` 与 `application` SHALL NOT 依赖 `axum`/`sqlx`/`reqwest`（C3）。

白名单（允许的边）：

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
| `apps/server` | `api`（+ 启动期依赖 tokio/axum/tracing） |

ST-0.1 阶段各 crate 尚无代码，因此**只声明实际使用到的依赖**（不预埋未用依赖，避免"声明即依赖"的假约束）；未用到的边由 ADR-001 记录，在该 crate 首次落代码的 ST 里补齐。

#### Scenario: 分层可校验
- **WHEN** 执行 `cargo tree -p domain --edges normal` 与 `cargo tree -p api --edges normal`
- **THEN** 两者输出均不含 `axum`、`sqlx`、`reqwest`
- **AND** `cargo build --workspace` 成功

#### Scenario: 越界即被发现
- **WHEN** 有人在 `crates/domain/Cargo.toml` 加入 `axum`
- **THEN** `cargo tree -p domain` 立刻可见该依赖，PR 按 C3 打回；ADR-001 的白名单是评审依据

### Requirement: R3 最小可启动服务

`apps/server` SHALL 启动 axum 服务并只暴露 `GET /healthz`，返回 HTTP 200 与 body `ok`；未实现的探针端点 SHALL NOT 返回成功，业务路由 SHALL NOT 存在。

#### Scenario: 存活探针
- **WHEN** `cargo run -p server` 启动后执行 `GET http://127.0.0.1:8080/healthz`
- **THEN** 返回 `200`，body 为 `ok`

#### Scenario: 不伪装就绪
- **WHEN** 请求 `GET /readyz`
- **THEN** 返回 `404`（ST-0.3 才实现 DB/Redis 检查），不得返回 200 假通过

#### Scenario: 无业务路由
- **WHEN** 检查 `crates/api/src/router.rs`
- **THEN** 路由表仅含 `/healthz` 一项，无购物车/订单/商品等任何业务路径

### Requirement: R4 静态质量门禁

workspace SHALL 在 CI 等价命令下零告警，并通过 lints 固化 C4/C7：SHALL NOT 出现 `unsafe`、`todo!()`、`unimplemented!()`、`dbg!()`、`print!`/`println!` 直出（日志统一走 tracing，ST-0.2 装配）。

#### Scenario: 格式化与静态检查
- **WHEN** 执行 `cargo fmt --check`
- **THEN** 无输出，退出码 0

#### Scenario: 告警即失败
- **WHEN** 执行 `cargo clippy --all-targets -- -D warnings`
- **THEN** 无输出，退出码 0

#### Scenario: 占位符不可提交
- **WHEN** 代码中出现 `todo!()` 或 `unimplemented!()`
- **THEN** clippy 直接报错（`clippy::todo`/`clippy::unimplemented` 已 deny），构建失败

### Requirement: R5 阶段证据落盘

`docs/gates/P0.md` SHALL 建立 P0 六条 Gate 的台账，逐条标注：断言、对应 ST、当前状态（✅ / ⏳）、证据（命令与关键输出）。

#### Scenario: 证据可追溯
- **WHEN** 有人问"P0 第 2 条过了吗"
- **THEN** 在 `docs/gates/P0.md` 能看到断言文本、ST-0.1 结论与 fmt/clippy 的命令输出摘要

### Requirement: R6 仓库基线

仓库 SHALL 是 git 工作区，`.gitignore` 排除 `target/`、`.env*`、本地数据目录；`Cargo.lock` SHALL 入库（06 §6.1）。

#### Scenario: 锁文件在库内
- **WHEN** 执行 `git ls-files Cargo.lock`
- **THEN** 输出 `Cargo.lock`

#### Scenario: 构建产物不入库
- **WHEN** 执行 `git status --porcelain`（构建后）
- **THEN** 不出现 `target/` 下的任何文件

## 验证方式（对应 A2 第 5 步）

在本机真实执行并原样粘贴输出：

1. `rustc --version`、`cargo --version`
2. `cargo build --workspace`
3. `cargo fmt --check`
4. `cargo clippy --all-targets -- -D warnings`
5. `cargo test --workspace`
6. `cargo run -p server` + `curl -i http://127.0.0.1:8080/healthz` + `curl -i http://127.0.0.1:8080/readyz`
7. `cargo tree -p domain --edges normal`、`cargo tree -p api --edges normal`
8. `cargo metadata --no-deps --format-version 1` 中 `edition`/`rust-version` 片段

## 新增依赖说明（C6）

全部取自 06 §6.1 锁版清单，无未批准依赖：

| 依赖 | 位置 | 用途 | 替代方案为何不选 |
|---|---|---|---|
| `tokio` | `apps/server` | multi-thread runtime、信号处理（A4 锁定） | 无（技术栈锁定） |
| `axum 0.8` | `api`、`apps/server` | HTTP 路由与 `axum::serve`（A4 锁定） | 无 |
| `tracing` / `tracing-subscriber` | `api`、`apps/server` | 启动期最小日志出口（完整装配在 ST-0.2） | `println!` 被 lint 禁止，且无法承载 trace 上下文 |
| `tower`（`util` 特性，dev） | `api` | 路由单测用 `oneshot` 发请求 | 直接起端口测试更慢更脆 |

## 风险与回滚

- 风险：`rust-version = 1.85` 与所选依赖的 MSRV 冲突 → 以 `cargo build --workspace` 实测为准；若冲突，只能升 MSRV 并改 ADR（需用户确认）
- 风险：Windows 下 `SIGTERM` 不存在 → 仅 `ctrl_c` 全平台处理 + `#[cfg(unix)]` 分支处理 SIGTERM，不引入额外依赖
- 回滚：删除本轮新增文件即可，`docs/spec/**` 未被改动，无数据/契约影响

## 待确认（不猜）

1. **git 仓库**：当前目录不是 git 仓库。按 06 §6.5（白名单 diff 校验）与 §6.7（分支规范）需要 `git init`；若你已有远端仓库，请在确认时给出地址，改为 `git init` + `remote add`。**这是唯一会改变仓库形态的动作，需你点头。**
2. **数据库/缓存运行环境**：本机无 `docker`、无 `psql`。ST-0.3（`/readyz`、迁移）之前必须确定：装 Docker Desktop / 装本地 PostgreSQL 17 + Redis 7 / 用远程开发库。本轮不受影响，但请提前给方向。
3. **xtask 延后**：06 §6.2 把 `crates/xtask` 归入 P0 落地，本轮不建（首个真实子命令在 ST-0.3），属"减少空壳"的主动调整，若你要求 P0 一次性落齐请驳回本 Spec。

## P0 剩余 ST 切分（建议，供确认，不在本轮实施）

| ST | 内容 | 关键 Gate |
|---|---|---|
| ST-0.1 | 骨架 + 工具链 + `/healthz` + ADR-001（本轮） | P0-2、P0-1（部分） |
| ST-0.2 | 配置加载（06 §6.4 + 启动校验）、tracing/OTel 装配、`/metrics`、request_id | P0-4、P0-5（部分） |
| ST-0.3 | sqlx + `migrations/` 首版 + `/readyz`（DB+Redis）+ `xtask migrate` | P0-1、P0-3 |
| ST-0.4 | 错误分层（DomainError→AppError→ApiError）+ 中间件顺序骨架 | C5、06 §6.3.6 |
| ST-0.5 | CI（05 §5.3 子集）+ `deploy/compose.yaml` + ADR-002~008，P0 Gate 收口 | P0-6 |

## 范围外声明

本轮不产出任何业务能力、不建表、不开业务接口、不接模型。所有"能跑起来"的部分只为证明骨架成立。
