# Go Web3 后端链下操作 Roadmap

目标不是一次搭完生产系统，而是逐步做出一条完整链路：**读链 → 索引 → 入库 → 发交易 → 对外提供 API → 处理异常**。

## 0. 跑通基础骨架（当前已完成）

- [x] 理解 EVM JSON-RPC 请求/响应结构
- [x] 用 `eth_blockNumber` 读取最新区块
- [x] 暴露 `/healthz` 和 `/chain/head`
- [x] 为 RPC 解析留下一个可运行测试

练习：启动 Anvil、Hardhat 或其他本地 EVM 节点，观察节点停止时 API 的状态码和日志。

## 1. 常见只读查询

- [ ] `eth_getBalance`：查询原生币余额
- [ ] `eth_call`：调用合约只读方法
- [ ] ABI 编解码：读取本仓库 Escrow 合约状态
- [ ] `eth_getLogs`：按合约地址、事件 topic 和区块范围查日志
- [ ] 批量 RPC、超时和限流

产物：`GET /accounts/{address}/balance` 和一个 Escrow 详情接口。

## 2. 事件索引器

- [ ] 从指定起始区块分批拉取日志
- [ ] 解码 Escrow 事件并写入 PostgreSQL
- [ ] 保存扫描游标，重启后继续
- [ ] 用 `(chain_id, tx_hash, log_index)` 做唯一键，保证幂等
- [ ] 等待确认数后再标记 final
- [ ] 检测区块哈希变化并回滚重组区块

产物：可重复运行、不重不漏的 Escrow 事件同步命令。

## 3. 交易发送与生命周期

- [ ] 获取 chain ID、nonce、gas estimate 和费用建议
- [ ] 本地签名并发送 raw transaction
- [ ] 私钥只从环境变量/密钥服务读取，绝不入库或记录日志
- [ ] 跟踪 pending、confirmed、failed、replaced 状态
- [ ] 处理 nonce 冲突、费用不足和重试

产物：调用 Escrow 写方法的 CLI；先在本地链、小额测试账户上完成。

## 4. 链下数据与业务 API

- [ ] PostgreSQL migration 和查询
- [ ] 地址、金额、chain ID、分页参数校验
- [ ] 金额使用整数最小单位，不使用浮点数
- [ ] API 返回链上来源区块和同步状态

产物：Escrow 列表、详情和状态历史 API。

## 5. 后台任务与可靠性

- [ ] 用数据库任务表实现最小队列
- [ ] 指数退避、最大重试次数和 dead-letter 状态
- [ ] 用 outbox 保证业务写入与待发送任务一致
- [ ] 优雅关停、结构化日志、指标和告警
- [ ] RPC provider 故障切换与速率限制

产物：节点短暂故障、服务重启后仍能自动恢复的同步服务。

## 6. 安全与上线检查

- [ ] RPC、数据库和密钥最小权限
- [ ] 管理接口鉴权、请求限流和审计日志
- [ ] 防止任意 calldata、任意目标地址和 SSRF
- [ ] 主网前做测试网演练、余额告警和熔断开关

## 推荐推进方式

每一阶段只增加一个真实场景和一个能失败的测试。第 1～2 阶段再引入 `go-ethereum` 与 PostgreSQL 驱动；当前骨架刻意使用标准库，方便先看清 JSON-RPC 的原始形态。
