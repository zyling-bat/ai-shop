# Checklist · ST-0.5 P0 工程收口

## Spec 与范围

- [x] `specs/ST-0.5.md` 已落盘，与批准的 `.trae/specs/close-p0-engineering-baseline/spec.md` 范围一致
- [x] 施工 Spec 含改动文件白名单、明确不改、验证命令和证据边界
- [x] 未把《01 · 功能矩阵》展开为本轮业务实现，未新增 M0/M1/M2 半成品入口

## ADR-004～007 与 P0-6

- [x] `docs/adr` 下 001～008 八份 ADR 均存在，编号、主题与 P0-6 一一对应
- [x] ADR-004 明确业务数据与事件同一数据库事务写入，禁止事务内发 HTTP、写 Redis 或调模型
- [x] ADR-004 明确 `event_id` 冲突 `DO NOTHING`、消费者幂等，以及 `pending/sent/failed/dead` 状态语义
- [x] ADR-004 明确按 `pending` 与 `next_retry_at` 批量获取、成功置 `sent`、失败指数退避、超过 8 次置 `dead` 并告警
- [x] ADR-004 只定决策并指向 P5，未声称 outbox 表、worker 或消费者已经实现
- [x] ADR-005 明确业务只经 `ai-gateway`，Agent/Gateway/RAG/Provider 职责不串联，业务代码不含厂商域名、密钥或模型名硬编码
- [x] ADR-005 覆盖分类 `ModelError`、任务档位配置化、降级链、连续失败 5 次打开 30s 的 `(provider, model)` 熔断及半开探测
- [x] ADR-005 覆盖 JSON Schema 校验、最多 2 次重试、业务兜底、建议类结果的 `confidence/reasons`、配额、缓存、成本日志、指标和评测要求
- [x] ADR-005 明确模型不得直接写库或直接执行改价、库存、退款等副作用，业务实现归 P11
- [x] ADR-006 锁定 Leptos 0.7 SSR+CSR、H5/小程序 CSR 产物加原生壳且不用 Taro、移动 App 使用 Tauri 2 mobile
- [x] ADR-006 明确 utoipa/OpenAPI 是契约事实源，前端 SDK 由契约生成，禁止手写两套类型与请求函数
- [x] ADR-007 定义 `ChannelContext{channel, device_id, open_id?, scene?}`，渠道差异只在 `channel` crate，业务代码禁止渠道条件分支
- [x] ADR-007 覆盖 OAuth2、HMAC-SHA256、5 分钟时间窗、nonce 去重、调用日志、应用配额及 Webhook 重试边界
- [x] ADR-007 覆盖破坏性接口变更的 OpenAPI diff、SDK 重生成和至少 30 天兼容期，前端与渠道实现归 P14
- [x] ADR-001 仅更新 ADR-004～007 状态，既有 crate 依赖白名单未被改写
- [x] `docs/gates/P0.md` 的 P0-6 仅在上述文件核查通过后标为 ✅，证据列出八份 ADR

## CI 基线与技术债

- [x] `.github/workflows/ci.yml` 在 `push` 和 `pull_request` 触发
- [x] CI 使用 stable Rust，并安装 rustfmt、clippy 组件
- [x] CI 原样执行 `cargo fmt --check`
- [x] CI 原样执行 `cargo clippy --all-targets -- -D warnings`
- [x] CI 原样执行 `cargo test --workspace`
- [x] 三条 CI 门禁均未配置 `continue-on-error`，任一失败会阻断工作流
- [x] CI 未加入空 sqlx/xtask/deny/eval/白名单检查，未以占位输出伪装完整 CI 全绿
- [x] `docs/tech-debt.md` 保留 TD-006，SQLx 离线元数据与 `cargo sqlx prepare --check` 仍由首个业务查询 ST 偿还
- [x] 新增技术债覆盖 `cargo deny check`、openapi、consistency、eval 和通用 ST 白名单 diff 校验的影响与明确接入条件
- [x] openapi/consistency/eval 分别绑定真实生成器、一致性断言和评测能力所属阶段，没有“以后再说”式无期限条目
- [x] TD-003 未被虚假偿还；其实际应用部署/P17 的来源限制或独立管理端口、抓取配置和运行态证据要求清晰

## 部署证据边界

- [x] 现有 `deploy/docker-compose.yml` 未被重复改写，仍包含 PostgreSQL 17、Redis 7、健康检查和持久化卷
- [x] P0 台账继续引用真实原生 PostgreSQL/Redis、`/healthz` 与 `/readyz` 证据
- [x] 若未实际运行 Docker，Gate 与最终响应均明确“未实测 `docker compose up -d`”，没有 Docker 成功结论
- [x] 若未取得 GitHub Actions 运行记录，Gate 与最终响应均明确“未实测 GitHub-hosted runner”，本地通过未被表述为远端工作流通过

## 真实验证

- [x] 本机 `cargo fmt --check` 无格式差异并退出码 0，真实结果已记录
- [x] 本机 `cargo clippy --all-targets -- -D warnings` 无警告并退出码 0，真实结果已记录
- [x] 本机 `cargo test --workspace` 全绿，真实测试统计已记录且无失败
- [x] 未新增 `#[ignore]`，未删除或放宽断言来取得通过
- [x] `git diff --check` 退出码 0
- [x] `git diff --name-only` 与 `git status --short` 已核对，改动全部属于白名单或本变更提案文件
- [x] `checklist.md` 每项均有文件内容或真实命令输出支撑，失败项已修复并复验后才勾选

## 防越界

- [x] `docs/spec/**` 与 `docs/prompt/MAIN.md` 无任何改动
- [x] `apps/**`、`crates/**` 业务与基础源码无改动
- [x] 根/成员 Cargo manifest、`Cargo.lock`、工具链和依赖版本无改动
- [x] `migrations/**`、`seeds/**`、`.sqlx/**` 无改动
- [x] 未新增 outbox worker、模型 Provider、前端页面、渠道适配器、业务路由或数据表
- [x] 未回滚或覆盖用户既有改动
- [x] 最终响应按 A8 包含变更摘要、文件清单、验证输出、Gate 证据和明确遗留项
