# Checklist（ST-0.1 验收清单）

## 工具链与版本（C1）

- [ ] 根 `Cargo.toml` 声明 `edition = "2024"`、`rust-version = "1.85"`、`resolver = "3"`
- [ ] `rust-toolchain.toml` 存在且固定 `stable` 通道，含 `rustfmt`、`clippy` 组件
- [ ] `docs/adr/001-layering.md` 记录了实测 `rustc --version` 与 `cargo --version`
- [ ] `cargo metadata --no-deps --format-version 1` 中每个 member 的 `edition` 为 `2024`

## 结构与分层（C2/C3）

- [ ] 存在 10 个库 crate（shared/domain/application/infrastructure/api/ai-gateway/ai-rag/ai-agent/worker/channel）与 `apps/server`
- [ ] `cargo build --workspace` 成功
- [ ] `cargo tree -p domain --edges normal` 输出不含 `axum`/`sqlx`/`reqwest`
- [ ] `cargo tree -p api --edges normal` 输出不含 `sqlx`/`reqwest`
- [ ] `crates/application/Cargo.toml` 不含 `axum`/`sqlx`/`reqwest`
- [ ] 每个 crate 的 `Cargo.toml` 含 `[lints] workspace = true`

## 服务与路由

- [ ] `GET /healthz` 返回 `200`，body 为 `ok`
- [ ] `GET /readyz` 返回 `404`（未实现不得伪装 200）
- [ ] 路由表中除 `/healthz` 外无任何业务路由
- [ ] 服务可 `Ctrl-C` 退出，退出码正常

## 代码纪律（C4/C7）

- [ ] 全仓无 `todo!()`、`unimplemented!()`、`dbg!()`
- [ ] 全仓无 `unsafe`
- [ ] 全仓无 `print!`/`println!`/`eprintln!` 直出（lints 已 deny，构建能过即证明）
- [ ] 启动期唯一的 `expect` 均带 `// INVARIANT:` 注释

## 质量门禁

- [ ] `cargo fmt --check` 无输出、退出码 0
- [ ] `cargo clippy --all-targets -- -D warnings` 无输出、退出码 0
- [ ] `cargo test --workspace` 全绿（至少含 `/healthz` 一条单测）
- [ ] 未用 `#[ignore]` 或放宽断言让测试通过

## 证据与仓库基线

- [ ] `docs/gates/P0.md` 存在，含 P0 六条 Gate 台账，ST-0.1 相关项标 ✅ 并附命令输出摘要，其余标 ⏳ 且注明归属 ST
- [ ] `specs/ST-0.1.md` 已落盘，内容与本轮 Spec 一致
- [ ] `Cargo.lock` 已入库（`git ls-files Cargo.lock` 有输出）
- [ ] `.gitignore` 排除 `target/`，构建后 `git status --porcelain` 无 `target/` 文件
- [ ] 反向自证记录：临时给 domain 加 `axum` 时 `cargo tree` 能报出违规，随后已删除该改动

## 边界（防越界）

- [ ] `docs/spec/AI电商-Spec文档包-v2/**` 与 `docs/prompt/MAIN.md` 无任何改动
- [ ] 无数据库/迁移/Redis 代码
- [ ] 无 `reqwest`/`leptos`/`pgvector` 依赖
- [ ] 未创建 `crates/xtask`（延后至 ST-0.3，已在 Spec 中声明）
- [ ] 本轮改动文件全部落在 Spec 白名单内
