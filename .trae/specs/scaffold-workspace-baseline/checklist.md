# Checklist（ST-0.1 验收清单）

## 工具链与版本（C1）

- [x] 根 `Cargo.toml` 声明 `edition = "2024"`、`rust-version = "1.85"`、`resolver = "3"`
- [x] `rust-toolchain.toml` 存在且固定 `stable` 通道，含 `rustfmt`、`clippy` 组件
- [x] `docs/adr/001-layering.md` 记录了实测 `rustc --version` 与 `cargo --version`
- [x] `cargo metadata --no-deps --format-version 1` 中每个 member 的 `edition` 为 `2024`（11 个 member 实测全为 2024 / 1.85）

## 结构与分层（C2/C3）

- [x] 存在 10 个库 crate（shared/domain/application/infrastructure/api/ai-gateway/ai-rag/ai-agent/worker/channel）与 `apps/server`
- [x] `cargo build --workspace` 成功
- [x] `cargo tree -p domain --edges normal` 输出不含 `axum`/`sqlx`/`reqwest`（实测仅 `domain v0.1.0` 一行）
- [x] `cargo tree -p api --edges normal` 输出不含 `sqlx`/`reqwest`（实测仅 `axum v0.8.9`）
- [x] `crates/application/Cargo.toml` 不含 `axum`/`sqlx`/`reqwest`（全仓 manifest 无 sqlx/reqwest/leptos/pgvector/redis 命中）
- [x] 每个 crate 的 `Cargo.toml` 含 `[lints] workspace = true`（11/11 命中）

## 服务与路由

- [x] `GET /healthz` 返回 `200`，body 为 `ok`
- [x] `GET /readyz` 返回 `404`（未实现不得伪装 200）
- [x] 路由表中除 `/healthz` 外无任何业务路由（`crates/api/src/router.rs` 仅一条 `route("/healthz", ...)`）
- [x] 优雅退出路径已装配：`axum::serve(...).with_graceful_shutdown(shutdown_signal())`，`shutdown_signal` 全平台等 `ctrl_c`、`#[cfg(unix)]` 另等 SIGTERM（Windows 非交互 shell 无法脚本化投递 SIGINT，进程级验证记为遗留项，不在 P0 Gate 内）

## 代码纪律（C4/C7）

- [x] 全仓无 `todo!()`、`unimplemented!()`、`dbg!()`（全量 grep 无命中）
- [x] 全仓无 `unsafe`（全量 grep 无命中，且 workspace lints `unsafe_code = "forbid"`）
- [x] 全仓无 `print!`/`println!`/`eprintln!` 直出（全量 grep 无命中；lints 已 deny）
- [x] 启动期唯一的 `expect` 均带 `// INVARIANT:` 注释（`apps/server/src/main.rs` 四处、路由单测一处）

## 质量门禁

- [x] `cargo fmt --check` 无输出、退出码 0
- [x] `cargo clippy --all-targets -- -D warnings` 无输出、退出码 0
- [x] `cargo test --workspace` 全绿（api 2 条：`healthz_returns_200_ok`、`readyz_is_not_implemented`）
- [x] 未用 `#[ignore]` 或放宽断言让测试通过

## 证据与仓库基线

- [x] `docs/gates/P0.md` 存在，含 P0 六条 Gate 台账，ST-0.1 相关项标 ✅ 并附命令输出摘要，其余标 ⏳ 且注明归属 ST
- [x] `specs/ST-0.1.md` 已落盘，内容与本轮 Spec 一致
- [x] `Cargo.lock` 已入库（`git ls-files Cargo.lock` 有输出）
- [x] `.gitignore` 排除 `target/`，构建后 `git status --porcelain` 为空
- [x] 反向自证记录：临时给 domain 加 `axum` 时 `cargo tree` 报出 `axum v0.8.9`，随后已删除该改动，复验 domain 树恢复单行

## 边界（防越界）

- [x] `docs/spec/AI电商-Spec文档包-v2/**` 与 `docs/prompt/MAIN.md` 无任何改动
- [x] 无数据库/迁移/Redis 代码
- [x] 无 `reqwest`/`leptos`/`pgvector` 依赖
- [x] 未创建 `crates/xtask`（延后至 ST-0.3，已在 Spec 中声明）
- [x] 本轮改动文件全部落在 Spec 白名单内
