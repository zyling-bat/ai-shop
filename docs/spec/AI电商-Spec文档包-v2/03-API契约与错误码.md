# 03 · API 契约与错误码

> `openapi.json` 是唯一事实源：由 utoipa 注解生成，CI 校验"路由实现 vs 契约 diff 为零"，前端 SDK 全部由它生成。
> 禁止手写前端类型与请求函数，禁止后端口头约定字段。

---

## 3.1 通用约定

- 前缀 `/api/v1`；资源复数；动作型操作用 `:action` 后缀（`POST /orders/{order_no}:cancel`）。
- 内容：`application/json; charset=utf-8`；文件走预签名直传，不经后端中转。
- 必带请求头：`Authorization: Bearer <token>`、`X-Request-Id`（可缺省由服务生成）、写操作 `Idempotency-Key`、渠道 `X-Channel`（web/h5/miniapp/app/open）。
- 响应包：

```json
{ "code": 0, "message": "ok", "data": { }, "trace_id": "01HQ..." }
```

- 失败：`code` 为业务码字符串（如 `ORDER_STATE_INVALID`），`data` 为 `null` 或含 `details`；HTTP 状态码同步语义（400/401/403/404/409/422/429/500）。
- 分页：游标 `?cursor=&limit=`（默认 20，上限 100）→ `{ items, next_cursor, has_more }`；后台表格用 `?page=&size=` + `total`。
- 金额一律**字符串**（`"128.00"`）传，避免 JS 精度；时间 ISO8601 带时区（`2026-11-24T10:00:00+08:00`）。
- 枚举大写下划线；ID 对外用 `short_code`，内部 UUID 不暴露。
- 幂等语义：同 key 同请求指纹 → 返回首次结果（`200` 且带 `Idempotent-Replayed: true`）;同 key 不同指纹 → `409 IDEMPOTENCY_KEY_CONFLICT`。
- 限流：响应头 `X-RateLimit-Limit/Remaining/Reset`，超限 `429 RATE_LIMITED`。

---

## 3.2 端点清单（按域，M0 必做，M1/M2 标出）

### 身份认证 `/auth`
`POST /auth/sms-code`｜`POST /auth/register`｜`POST /auth/login`｜`POST /auth/login/oauth`｜`POST /auth/refresh`｜`POST /auth/logout`｜`POST /auth/password/reset`｜`GET /auth/captcha`｜`M1 POST /auth/realname`｜`M1 GET /auth/devices`、`DELETE /auth/devices/{id}`｜`M1 POST /auth/cancel`（注销申请）

### 用户 `/users`
`GET /users/me`｜`PATCH /users/me`｜`GET/POST/PATCH/DELETE /users/me/addresses[/{id}]`｜`GET/POST/DELETE /users/me/favorites[/{sku_id}]`｜`GET /users/me/footprints`｜`GET /users/me/coupons`｜`GET /users/me/points`｜`GET /users/me/messages`｜`PATCH /users/me/messages/{id}:read`｜`M1 GET /users/me/subscription`

### 商品 `/products`、`/categories`
`GET /categories/tree`｜`GET /products`（筛选/排序/分页）｜`GET /products/{spu_id}`｜`GET /products/{spu_id}/skus`｜`GET /products/{spu_id}/reviews`｜`GET /products/{spu_id}/qa`｜`GET /products/{spu_id}/related`｜`M1 GET /products/compare`

### 搜索 `/search`
`GET /search`｜`GET /search/suggest`｜`GET /search/hot-words`｜`M1 POST /search/image`｜`M2 POST /search/voice`

### 购物车 `/cart`
`GET /cart`｜`POST /cart/items`｜`PATCH /cart/items/{id}`｜`DELETE /cart/items/{id}`｜`POST /cart/items:batch-delete`｜`POST /cart/checkout-preview`（试算）

### 订单 `/orders`
`POST /orders`｜`GET /orders`｜`GET /orders/{order_no}`｜`POST /orders/{order_no}:cancel`｜`POST /orders/{order_no}:confirm`｜`POST /orders/{order_no}:address`（发货前改址）｜`POST /orders/{order_no}:urge`（催付）｜`M1 POST /orders/{order_no}:change-price`（运营改价，需审计）｜`M1 POST /orders:merge-pay`

### 支付 `/payments`、`/refunds`
`POST /payments`｜`GET /payments/{pay_no}`｜`POST /payments/{pay_no}:query`（主动查）｜`POST /payments/callback/{channel}`（免鉴权 + 验签）｜`POST /refunds`｜`GET /refunds/{refund_no}`｜`M1 POST /payments/{pay_no}:split`

### 履约 `/deliveries`
`POST /deliveries`（发货）｜`GET /deliveries/{delivery_no}`｜`GET /deliveries/{delivery_no}/tracks`｜`POST /logistics/subscribe`｜`M1 GET /pickup-points`、`POST /orders/{order_no}:self-pickup-code`

### 售后 `/after-sales`
`POST /after-sales`｜`GET /after-sales`｜`GET /after-sales/{as_no}`｜`POST /after-sales/{as_no}:cancel`｜`POST /after-sales/{as_no}:return-goods`（回填运单）｜`M1 POST /after-sales/{as_no}:appeal`｜`M1 POST /after-sales/{as_no}:price-protection`

### 评价 `/reviews`
`POST /reviews`｜`GET /reviews`｜`POST /reviews/{id}:reply`｜`POST /reviews/{id}:helpful`

### 营销 `/coupons`、`/promotions`
`GET /coupons/available`｜`POST /coupons/{template_id}:claim`｜`GET /promotions`｜`GET /promotions/{id}`｜`GET /seckill/sessions`｜`POST /seckill/sessions/{id}:order`｜`M1 GET /group-buys`、`POST /group-buys/{id}:join`｜`M1 POST /bargains/{id}:cut`

### 分销 `/affiliate`
`M1 POST /affiliate/apply`｜`M1 GET /affiliate/me`｜`M1 GET /affiliate/links`｜`M1 GET /affiliate/commissions`｜`M1 POST /affiliate/withdrawals`

### 内容 `/posts`
`M1 GET /posts`｜`M1 POST /posts`｜`M1 GET /posts/{id}`｜`M1 POST /posts/{id}:like`｜`M1 POST /posts/{id}/comments`｜`M1 POST /posts/{id}:report`

### 直播 `/live`
`M2 GET /live/rooms`｜`M2 GET /live/rooms/{id}`｜`M2 POST /live/rooms/{id}:enter`｜`M2 GET /live/rooms/{id}/products`

### 商家 `/merchant`
`POST /merchant/applications`｜`GET /merchant/applications/me`｜`GET /merchant/shop`｜`PATCH /merchant/shop`｜`GET /merchant/products`｜`POST /merchant/products`｜`PATCH /merchant/products/{spu_id}`｜`POST /merchant/products/{spu_id}:submit-audit`｜`GET /merchant/orders`｜`POST /merchant/orders/{order_no}:ship`｜`GET /merchant/after-sales`｜`POST /merchant/after-sales/{as_no}:approve`｜`POST /merchant/after-sales/{as_no}:reject`｜`GET /merchant/settlements`｜`GET /merchant/settlements/{settle_no}`｜`POST /merchant/withdrawals`｜`GET /merchant/dashboard`

### 平台后台 `/admin`
`GET /admin/merchants`｜`POST /admin/merchants/{id}:audit`｜`GET /admin/products`｜`POST /admin/products/{spu_id}:audit`｜`GET /admin/categories`｜`POST /admin/categories`｜`GET /admin/contents`｜`POST /admin/contents/{id}:audit`｜`GET /admin/orders`｜`POST /admin/orders/{order_no}:close`｜`GET/POST /admin/coupons`｜`GET/POST /admin/promotions`｜`GET /admin/settlements`｜`GET /admin/reconcile/diffs`｜`POST /admin/reconcile/diffs/{id}:handle`｜`GET /admin/users`｜`POST /admin/users/{id}:freeze`｜`GET /admin/dashboard/overview`｜`GET /admin/audit-logs`｜`GET/PATCH /admin/feature-flags`｜`GET /admin/tickets`

### 供应链 `/supply`
`M0 GET/POST /supply/suppliers`｜`M0 GET/POST /supply/purchase-orders`｜`M0 POST /supply/purchase-orders/{po_no}:approve`｜`M0 POST /supply/inbound-orders`｜`M0 GET /supply/stocks`｜`M1 POST /supply/transfers`｜`M1 POST /supply/stock-counts`｜`M1 GET /supply/supplier-settlements`

### 财务 `/finance`
`M0 GET /finance/invoices`｜`M0 POST /finance/invoices:issue`｜`M0 POST /finance/invoices/{id}:red-flush`｜`M0 GET /finance/fund-flows`｜`M1 GET /finance/statements`｜`M1 POST /finance/periods/{period}:close`

### 客服 `/cs`
`POST /cs/sessions`｜`GET /cs/sessions/{id}`｜`POST /cs/sessions/{id}/messages`｜`POST /cs/sessions/{id}:transfer`｜`POST /cs/sessions/{id}:close`｜`POST /cs/sessions/{id}:evaluate`｜`M1 GET/POST /cs/tickets`

### AI `/ai`
`POST /ai/chat`｜`POST /ai/chat/stream`（SSE）｜`GET /ai/conversations/{id}`｜`POST /ai/feedback`｜`POST /ai/recommend`｜`POST /ai/product/analyze`｜`M1 POST /ai/search/rewrite`｜`M1 POST /ai/review/summary`｜`M2 POST /ai/ops/query`｜`M2 POST /ai/aftersale/judge`｜`M2 POST /ai/pricing/suggest`

### 开放平台 `/open`
`POST /open/oauth/token`｜`GET /open/products`｜`POST /open/orders`｜`GET /open/orders/{no}`｜`GET /open/stocks`｜`POST /open/aftersales`｜`POST /open/webhooks/test`｜`GET /open/rate-limit`

### 数据 `/analytics`
`M0 GET /analytics/overview`｜`M0 GET /analytics/funnel`｜`M1 GET /analytics/retention`｜`M1 GET /analytics/attribution`｜`M2 GET /analytics/realtime`

### 系统 `/sys`
`GET /sys/configs/public`｜`GET /sys/regions`｜`POST /sys/exports`｜`GET /sys/exports/{id}`｜`GET /sys/files/{id}:presign`

---

## 3.3 错误码总表

| code | HTTP | 含义 | 前端处置 |
|---|---|---|---|
| OK | 200 | 成功 | — |
| PARAM_INVALID | 400 | 参数校验失败 | 定位字段标红 |
| UNAUTHORIZED | 401 | 未登录/token 失效 | 刷新或跳登录 |
| TOKEN_EXPIRED | 401 | access 过期 | 静默刷新重放 |
| FORBIDDEN | 403 | 无权限 | 提示无权限 |
| DATA_SCOPE_DENIED | 403 | 越出数据权限 | 提示并上报 |
| NOT_FOUND | 404 | 资源不存在 | 空态 |
| METHOD_NOT_ALLOWED | 405 | 方法不支持 | 记录日志 |
| CONFLICT | 409 | 状态冲突 | 刷新后重试 |
| IDEMPOTENCY_KEY_CONFLICT | 409 | 同 key 不同请求 | 换 key |
| DUPLICATE_REQUEST | 200 | 命中幂等返回首次结果 | 直接使用结果 |
| ORDER_STATE_INVALID | 409 | 订单状态不允许该操作 | 刷新订单状态 |
| ORDER_AMOUNT_MISMATCH | 409 | 支付金额与订单不一致 | 重新发起支付 |
| STOCK_INSUFFICIENT | 409 | 库存不足 | 提示并移出购物车 |
| STOCK_RESERVE_FAILED | 409 | 预占失败 | 重试/换仓 |
| PRICE_CHANGED | 409 | 下单价格已变化 | 展示新价重确认 |
| COUPON_UNAVAILABLE | 422 | 券不可用 | 说明原因并移除 |
| COUPON_STACK_CONFLICT | 422 | 券互斥 | 提示替换 |
| PROMOTION_BUDGET_EXHAUSTED | 422 | 活动预算耗尽 | 提示活动结束 |
| SECKILL_SOLD_OUT | 422 | 秒杀售罄 | 推荐替代 |
| PAY_CHANNEL_UNAVAILABLE | 503 | 渠道不可用 | 切换支付方式 |
| PAY_CALLBACK_VERIFY_FAILED | 400 | 回调验签失败 | 告警 |
| REFUND_AMOUNT_EXCEEDED | 422 | 退款超过可退 | 重新核算 |
| AFTER_SALE_STATE_INVALID | 409 | 售后状态不允许 | 刷新进度 |
| AFTER_SALE_SLA_TIMEOUT | 409 | 售后已超时 | 走平台介入 |
| SETTLEMENT_DUPLICATE | 409 | 重复结算 | 拦截并告警 |
| SPLIT_AMOUNT_MISMATCH | 409 | 分账金额不符 | 转人工 |
| AUDIT_REJECTED | 422 | 审核未通过 | 显示驳回理由 |
| FEATURE_DISABLED | 403 | 功能未开放 | 隐藏入口 |
| RATE_LIMITED | 429 | 限流 | 退避重试 |
| RISK_BLOCKED | 403 | 风控拦截 | 显示可读原因 + 申诉入口 |
| CONTENT_RISK_BLOCKED | 422 | 内容未过审 | 提示改写 |
| AI_QUOTA_EXCEEDED | 429 | AI 配额用尽 | 降级提示 |
| AI_STRUCTURED_OUTPUT_FAILED | 502 | 结构化输出失败 | 走兜底文案 |
| AI_PROVIDER_TIMEOUT | 504 | 模型超时 | 降级并提示 |
| AI_DEGRADED | 200 | 已降级作答 | 标注"降级模式" |
| UPSTREAM_UNAVAILABLE | 503 | 上游不可用 | 重试/降级 |
| INTERNAL_ERROR | 500 | 服务内部错误 | 报错页 + trace_id |
| MAINTENANCE | 503 | 维护中 | 维护页 |

**约定**：错误响应必须带 `trace_id` 与 `details`（字段级错误为数组）；不得把内部错误信息（SQL、堆栈）透出。

---

## 3.4 关键接口的字段契约（示例，其余在 ST Spec 里展开）

**`POST /orders`**
请求：`cart_item_ids[]`、`address_id`、`coupon_ids[]`、`use_points`、`channel`、`remark`、`invoice{type,title,tax_no}`、`expected_total_amount`（客户端试算金额，用于价格变化校验）。
响应：`order_no`、`parent_order_no`、`payable_amount`、`pay_expire_at`、`split_orders[]`、`warnings[]`（券不可用/库存不足/价格变化）。

规则：`expected_total_amount` 与服务端计算结果不一致 → `PRICE_CHANGED`（不静默下单）。

**`POST /payments/callback/{channel}`**
必须：验签 → 查单（`pay_no` 存在且金额一致且未成功）→ 幂等入账（`channel_txn_id` 唯一）→ 更新订单 → 发 outbox → 返回渠道要求的应答格式（不能返回业务 JSON）。

**`POST /ai/chat`**
请求：`conversation_id?`、`message`、`context{scene, sku_ids[], filters}`、`stream=false`。
响应：`reply`、`intents[]`、`products[]`（含推荐理由）、`actions[]`（可执行动作：加购/领券/转人工）、`citations[]`、`degraded`、`provider_used`、`trace_id`。

---

## 3.5 版本与兼容

- 新增字段向后兼容；删除/改语义必须新版本路径（`/api/v2`）。
- 破坏性变更需同步：`openapi.json` diff 评审 + 前端 SDK 重生成 + 兼容期双写（≥30 天）。
- 开放平台接口额外要求：签名（HMAC-SHA256 + 时间窗 5 分钟 + nonce 去重）、调用日志、按应用配额。

---

## 3.6 渠道适配层（`channel` crate）

一套业务接口，多渠道壳，只在**协议与能力**上分叉：

| 能力 | Web | H5 | 小程序 | App(Tauri) | 开放平台 |
|---|---|---|---|---|---|
| 登录 | 密码/微信扫码 | 微信授权 | 微信静默 + 手机号 | 密码/微信/Apple | OAuth2 |
| 支付 | 支付宝/微信 H5 | H5 支付 | 小程序支付 | 原生 SDK | 服务商 |
| 分享 | 链接卡片 | 链接/海报 | 转发卡片 | 系统分享 | — |
| 推送 | Web Push | 无 | 订阅消息 | APNs/FCM | Webhook |
| 扫码 | 相机 | 相机 | 扫码 API | 原生扫码 | — |
| 归因 | URL 参数 | URL + 落地页 | `scene` 参数 | 深链 | 应用标识 |

**规则**：渠道差异只能在 `channel` 层实现；业务层拿到的永远是统一 `ChannelContext{channel, device_id, open_id?, scene?}`。禁止在业务代码里写 `if channel == "miniapp"`。
