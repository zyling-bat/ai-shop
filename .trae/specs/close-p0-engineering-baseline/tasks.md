# Tasks · ST-0.5 P0 工程收口

> 仅在用户批准本提案后实施。每个子任务完成后立即勾选；所有完成声明必须对应真实文件或命令输出。

- [x] Task 1: 固化施工 Spec 与文件边界
  - [x] SubTask 1.1: 新建 `specs/ST-0.5.md`，完整承接已批准的 Why、范围、ADR 决策、CI 子集、证据边界和白名单
  - [x] SubTask 1.2: 核对施工 Spec 与 05 §5.1/§5.3、06 §6.5/§6.8 一致，明确完整 CI 目标未被缩减，只是分阶段接入

- [x] Task 2: 补齐 ADR-004～007
  - [x] SubTask 2.1: 新建 `docs/adr/004-transactional-outbox.md`，固化同事务写入、唯一事件键、投递状态、重试/死信、消费者幂等与 P5 实现边界
  - [x] SubTask 2.2: 新建 `docs/adr/005-ai-gateway.md`，固化 Provider 端口、错误分类、任务档位、路由降级、熔断、结构化输出、配额缓存、计量评测与 P11 实现边界
  - [x] SubTask 2.3: 新建 `docs/adr/006-frontend.md`，锁定 Leptos 0.7、CSR 原生壳、Tauri 2 mobile、OpenAPI 生成 SDK 与 P14 实现边界
  - [x] SubTask 2.4: 新建 `docs/adr/007-channel.md`，固化统一渠道上下文、渠道 crate 边界、开放平台安全和接口兼容策略
  - [x] SubTask 2.5: 更新 `docs/adr/001-layering.md` 的 ADR-004～007 预留表状态，不修改既有分层白名单和依赖规则

- [x] Task 3: 建立当前可执行 CI 子集
  - [x] SubTask 3.1: 新建 `.github/workflows/ci.yml`，在 `push` 与 `pull_request` 触发，使用 stable Rust 并安装 rustfmt/clippy
  - [x] SubTask 3.2: 按 05 §5.3 原文配置 fmt、clippy、workspace test 三步；任一步失败即失败，不添加 `continue-on-error`
  - [x] SubTask 3.3: 静态检查工作流不包含无实现依据的 sqlx/xtask/deny/eval 或白名单 diff 占位步骤，不新增 Cargo 依赖或业务代码

- [x] Task 4: 登记技术债并完成真实验证
  - [x] SubTask 4.1: 更新 `docs/tech-debt.md`，保留 TD-006，新增完整 CI 延后项及逐项偿还条件；将 TD-003 的实测偿还边界明确到实际应用部署/P17
  - [x] SubTask 4.2: 本机依次实跑 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test --workspace`，保存真实退出码和测试统计
  - [x] SubTask 4.3: 静态复核 `deploy/docker-compose.yml` 的 PostgreSQL 17、Redis 7、健康检查与卷；确认本机 Docker 证据缺口被如实保留，不执行虚构验证

- [x] Task 5: 更新 Gate、核对范围并完成验收
  - [x] SubTask 5.1: 核查 ADR-001～008 后更新 `docs/gates/P0.md`，将 P0-6 按实际结果标 ✅，追加 ADR、CI、本地命令和环境边界证据
  - [x] SubTask 5.2: 执行 `git diff --check`，并用 `git diff --name-only` 与 `git status --short` 核对所有改动均属于白名单或本变更提案文件
  - [x] SubTask 5.3: 逐项核验 `checklist.md`；任何失败项先新增修复任务并由子代理修复，再重新验证，不能直接勾选
  - [x] SubTask 5.4: 最终响应按 A8 给出变更摘要、文件清单、真实验证输出、Gate 证据与遗留项；明确未实测的 GitHub Actions/Docker 项

- [x] Task 6: 修复 TD-006 验收缺口并复验
  - [x] SubTask 6.1: 在 TD-006 触发偿还条件中明确首个业务查询 ST 入库 `.sqlx/` 并在 CI 接入 `cargo sqlx prepare --check`，保留 `SQLX_OFFLINE=true` 要求
  - [x] SubTask 6.2: 重新验证失败的 checklist 项及全量清单，全部通过后方可完成 ST-0.5

# Task Dependencies

- Task 1 依赖用户批准提案。
- Task 2 依赖 Task 1；SubTask 2.1～2.4 内容相互独立，可并行实施，SubTask 2.5 在四份 ADR 完成后执行。
- Task 3 依赖 Task 1，可与 Task 2 并行。
- Task 4 的 SubTask 4.1 依赖 Task 3，SubTask 4.2～4.3 可在 CI 文件落地后并行。
- Task 5 依赖 Task 2 与 Task 4，最后执行。
