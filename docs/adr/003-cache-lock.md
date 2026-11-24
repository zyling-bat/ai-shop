# ADR-003 缓存与分布式锁

- 状态：已接受（Accepted）
- 日期：2026-11-24
- 阶段：P0 / ST-0.3（锁协议在 P4 落地）
- 关联约束：A4（Redis 7，`fred` 或 `deadpool-redis` 二选一并写 ADR）、C13–C20（交易正确性）、C18（分布式锁）、06 §6.4、05 §5.1 P0-1

## 背景

A4 允许在 `fred` 与 `deadpool-redis` 之间二选一，要求写 ADR。ST-0.3 需要 Redis 连接池与 `/readyz` 探活；真正的分布式锁、限流、幂等存储在 P4/P5 才被业务使用。本 ADR 先定客户端、连接与键空间约定，锁协议只定语义，不写实现（C7：不落空壳）。

## 决策

### 1. 客户端选型

- 采用 `deadpool-redis 0.23`（用户在本 ST 决策中选择），底层 `redis` crate。
- 理由：与 `sqlx::PgPool` 同样的"池 + 借出连接"心智模型；`PING` 探活与后续 `SET NX PX` / Lua 脚本调用直接可用；团队不需要同时维护两套连接生命周期。
- 不选 `fred`：能力更全（集群、客户端缓存），但 P0–P5 单实例开发环境用不到，额外抽象会增加评审面。
- 后续若需要 Redis Cluster / Sentinel，另立 ADR 评估迁移，不在本 ADR 内预留空分支。

### 2. 连接与探活

- 连接串来自 `REDIS_URL`（`redis://` 或 `rediss://`），必填；`RedisConfig` 的 `Debug` 对密码脱敏。
- 连接池在 `infrastructure::bootstrap` 中创建；**连接在首次使用时建立**，因此启动期不因 Redis 暂时不可达而拒绝启动，但 `/readyz` 会立即报告 `redis: down`。
- 探活：`PING` 期望 `PONG`，超时 2s（`infrastructure::redis::PROBE_TIMEOUT`）。
- 失败只返回脱敏文本（`redis: PING 失败` / `redis: 探测超时`），完整错误只进日志。

### 3. 数据边界（与 C13 / C14 一致）

- Redis **不是**库存、余额、订单状态的权威存储；权威数据只在 PostgreSQL。
- Redis 只承载：缓存、限流计数、会话/refresh 令牌辅助状态、幂等键、分布式锁。
- 所有 Redis 故障必须能降级为"数据库仍然正确"，不允许把 Redis 写入成功当作业务成功。

### 4. 键空间约定

- 统一前缀：`ecom:{env}:`（如 `ecom:dev:`），由调用方拼接，避免多环境共用实例时互相污染。
- 键必须带业务维度与 TTL；禁止无 TTL 的高基数键（C11 同理）。
- 键名格式：`ecom:{env}:{domain}:{purpose}:{id}`，如 `ecom:dev:lock:stock:sku-123`。

### 5. 分布式锁语义（P4 实现，本轮不写代码）

- 加锁：`SET key token NX PX ttl`；`token` 为 UUID v7，禁止用固定值。
- 解锁：Lua 比较 `token` 后删除，禁止裸 `DEL`。
- 临界区必须可重入检测（同一 token 视为已持有）与超时上限；锁过期不代表业务安全，关键写操作仍需数据库条件更新（C13 `UPDATE ... WHERE available_qty >= ?`）。
- 锁只用于降低竞争，不作为正确性的唯一保证； fencing token 在涉及外部副作用的场景（支付、分账）另行设计。

## 后果

- 正面：客户端与池模型统一；`/readyz` 可独立报告 Redis；键空间与锁语义先定，P4 不需要返工命名。
- 负面：单实例客户端在集群场景需要迁移（未来 ADR）；锁协议尚未有实现与测试，P4 前 `worker` 不得依赖锁。
- 回滚：删除 `infrastructure/src/redis.rs` 与 `bootstrap` 中的 Redis 装配；`REDIS_URL` 恢复为可选。
