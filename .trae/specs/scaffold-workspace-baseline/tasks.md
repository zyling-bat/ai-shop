# Tasks

- [x] Task 1: 固化 Spec 与 ADR-001
  - [x] SubTask 1.1: 新建 `specs/ST-0.1.md`，内容与 `.trae/specs/scaffold-workspace-baseline/spec.md` 一致（供 A2 流程引用）
  - [x] SubTask 1.2: 新建 `docs/adr/001-layering.md`：分层铁律、crate 依赖白名单表、依赖边的执行方式（`cargo tree` 校验）、实测 `rustc --version` 与 `cargo --version`
- [x] Task 2: 建 workspace 骨架
  - [x] SubTask 2.1: 根 `Cargo.toml`（11 个 member、`workspace.package` edition=2024/rust-version=1.85/publish=false、`resolver = "3"`、`workspace.lints`、`workspace.dependencies` 仅含 ST-0.1 实际使用项）
  - [x] SubTask 2.2: `rust-toolchain.toml`（channel=stable、components=rustfmt/clippy）+ `.gitignore`（target/、.env*、本地数据目录）
  - [x] SubTask 2.3: 十个库 crate 骨架（`lib.rs` 仅 crate 级文档注释 + `#![forbid(unsafe_code)]` 之外的 lints 走 workspace），`[lints] workspace = true`
  - [x] SubTask 2.4: `apps/server` bin 骨架（`[lints] workspace = true`）
- [x] Task 3: 最小可启动服务
  - [x] SubTask 3.1: `crates/api/src/router.rs` 暴露 `pub fn router() -> Router`，只挂 `GET /healthz` → `200` + `ok`
  - [x] SubTask 3.2: `apps/server/src/main.rs` 绑定 `0.0.0.0:8080`，`axum::serve` + `ctrl_c`（及 `#[cfg(unix)]` SIGTERM）优雅退出；启动期失败用 `expect` 并写 `// INVARIANT:`
  - [x] SubTask 3.3: `crates/api` 增加 `/healthz` 路由单测（`tower::ServiceExt::oneshot` + `axum::body::to_bytes`，断言 200 与 body `ok`；同时断言 `/readyz` 为 404）
- [x] Task 4: 门禁、仓库基线与 P0 证据
  - [x] SubTask 4.1: 实跑 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace`，原样留档输出
  - [x] SubTask 4.2: 实跑 `cargo run -p server` + `curl -i /healthz` 与 `/readyz`，留档
  - [x] SubTask 4.3: `git init`、提交首版（含 `Cargo.lock`）；若用户提供远端地址则加 `remote`
  - [x] SubTask 4.4: 新建 `docs/gates/P0.md`，按 P0 六条 Gate 建台账，写入 ST-0.1 的断言、状态与命令输出摘要（其余标 ⏳ 并注明归属 ST）
  - [x] SubTask 4.5: 反向自证——临时在 `crates/domain/Cargo.toml` 加 `axum`，确认 `cargo tree -p domain` 可见违规依赖后**立即删除**（只留记录，不留改动）

# Task Dependencies

- Task 2 依赖 Task 1（ADR 定义白名单，Cargo.toml 按它落）
- Task 3 依赖 Task 2（需要 crate 与 workspace lints）
- Task 4 依赖 Task 3（需要可构建、可启动的产物）
- 本轮为 P0 首个 ST，无并行分支任务
