# Freelance ETH Escrow v1 规格说明

- 状态：已通过 review，作为 v1 实现基线
- 范围：独立单订单实例、原生 ETH、一次性全额结算、Factory 创建
- 合约名：`FreelanceEscrow`、`EscrowFactory`
- 金额单位：wei
- 时间单位：秒，统一使用 `block.timestamp`

## 1. 目标

Buyer 创建订单时存入全部订单金额。Seller 可以交付或在开始前取消；Buyer 可以验收或发起争议；Arbiter 只能在争议期内把全部资金判给 Buyer 或 Seller。任一参与者停止操作时，超时路径必须允许订单最终结算。

合约只裁定链上声明和资金流，不判断现实工作是否真正完成。交付物、沟通记录和争议证据全部在链下处理。

## 2. 角色与信任假设

| 角色 | 权力 | 不能做什么 | 信任假设 |
| --- | --- | --- | --- |
| Buyer | 创建并存款；审核期内确认交付或发起争议 | 不能标记交付、裁决争议或把钱转给任意地址 | 会对交付作出主观判断；私钥可能丢失或泄漏 |
| Seller | 交付期限前取消或标记交付；结算后提款 | 不能自行提前释放资金、发起争议或裁决 | 交付声明不等于现实工作已完成；收款地址可能是合约 |
| Arbiter | 仲裁期内二选一裁决全部资金归属 | 不能获得订单资金、拆分金额或指定第三方收款人 | 可能误判、偏袒或失联；v1 只用超时限制其活性风险 |
| 任意账户 | 触发已经到期且收款人固定的超时结算 | 不能改变收款人或提前结算 | 调用者只支付 gas，不获得经济权力 |

额外假设：

- 三个角色地址必须非零且互不相同，部署后不可更换。
- 角色可以是 EOA 或合约；如果收款合约拒收 ETH，它自己的提款可能永久失败。
- 链会继续出块，且至少有人愿意支付 gas 触发超时或提款。
- `block.timestamp` 可能被区块生产者小幅影响，因此业务期限按小时或天设置，不用于精确到秒的公平性或随机数。
- 链上交易、地址、状态和金额全部公开，不提供隐私。

## 3. v1 范围

包含：

- 一个部署对应一个 Buyer、一个 Seller、一个 Arbiter 和一个订单；
- `EscrowFactory` 为每个订单创建独立实例，并通过事件供链下发现；
- 部署时一次性托管原生 ETH；
- 全额付款、全额退款、取消、争议和三条超时路径；
- Pull Payment 提款；
- custom errors、事件、Checks-Effects-Interactions 和重入保护。

不包含：

- ERC-20、手续费、分期付款、部分退款或部分裁决；
- 链上交付物、证据、聊天或身份系统；
- 角色轮换、密钥恢复、暂停、管理员、资金救援；
- 代理升级、多订单共享存储或链上全量订单数组；
- 自动执行。所有状态变化都需要一笔交易触发。

意外强制转入的 ETH 不属于订单资金，v1 不提供取回方式。

## 4. 部署参数与校验

```solidity
constructor(
    address buyer,
    address seller,
    address arbiter,
    uint256 deliveryDeadline,
    uint256 reviewPeriod,
    uint256 arbitrationPeriod
) payable
```

构造参数显式指定 Buyer，使 Factory 部署时不会把 Factory 自身误记为 Buyer。
直接部署者或 Factory 负责转入 `msg.value`，Factory 必须传入其最终调用者作为 Buyer。

| 输入 | 含义 | 必须满足 |
| --- | --- | --- |
| `buyer` | Buyer | 非零；与 Seller、Arbiter 不同 |
| `seller` | Seller | 非零；与 Buyer、Arbiter 不同 |
| `arbiter` | Arbiter | 非零；与 Buyer、Seller 不同 |
| `msg.value` | 托管金额 | `> 0` |
| `deliveryDeadline` | 绝对交付截止时间 | `> block.timestamp` |
| `reviewPeriod` | 交付后的审核时长 | `> 0` |
| `arbitrationPeriod` | 发起争议后的仲裁时长 | `> 0` |

全部校验通过后，合约直接进入 `Funded` 并发出 `EscrowCreated`。构造失败必须整笔 revert。

## 5. 数据模型

不可变数据：

- `buyer`
- `seller`
- `arbiter`
- `depositAmount`
- `deliveryDeadline`
- `reviewPeriod`
- `arbitrationPeriod`

可变数据：

- `state`
- `deliveredAt`
- `reviewDeadline`
- `disputedAt`
- `arbitrationDeadline`
- `pendingWithdrawals[address]`

`reviewDeadline` 在成功交付时计算为 `deliveredAt + reviewPeriod`；`arbitrationDeadline` 在成功发起争议时计算为 `disputedAt + arbitrationPeriod`。Solidity 0.8 的算术溢出必须自然 revert。

## 6. 状态机

```solidity
enum State {
    Funded,
    Delivered,
    Disputed,
    Completed,
    Refunded,
    Cancelled
}
```

状态含义：

| 状态 | 含义 |
| --- | --- |
| `Funded` | ETH 已托管，等待 Seller 取消、交付或交付超时 |
| `Delivered` | Seller 已声明交付，等待 Buyer 确认、争议或审核超时 |
| `Disputed` | Buyer 已发起争议，等待 Arbiter 裁决或仲裁超时 |
| `Completed` | 全部订单金额已分配给 Seller |
| `Refunded` | 全部订单金额已分配给 Buyer |
| `Cancelled` | Seller 在交付期限前取消，全部订单金额已分配给 Buyer |

合法转换：

```text
Funded
├── cancelBySeller                  → Cancelled
├── markDelivered                  → Delivered
└── refundAfterDeliveryTimeout     → Refunded

Delivered
├── approveDelivery                → Completed
├── openDispute                    → Disputed
└── claimAfterReviewTimeout        → Completed

Disputed
├── resolveDispute(true)           → Completed
├── resolveDispute(false)          → Refunded
└── refundAfterArbitrationTimeout  → Refunded
```

`Completed`、`Refunded`、`Cancelled` 是终止状态。提款不会改变业务状态。除 `withdraw()` 外，终止后所有业务入口必须因状态错误而 revert。

## 7. 时间边界

所有期限采用左闭右开切分，恰好等于截止时间时只允许超时路径：

| 操作 | 允许条件 | 恰好等于截止时间 |
| --- | --- | --- |
| 部署 | `deliveryDeadline > block.timestamp` | 不能部署 |
| Seller 取消 | `block.timestamp < deliveryDeadline` | 不能取消 |
| Seller 标记交付 | `block.timestamp < deliveryDeadline` | 不能交付 |
| 交付超时退款 | `block.timestamp >= deliveryDeadline` | 可以退款 |
| Buyer 确认交付 | `block.timestamp < reviewDeadline` | 不能确认 |
| Buyer 发起争议 | `block.timestamp < reviewDeadline` | 不能争议 |
| 审核超时付款 | `block.timestamp >= reviewDeadline` | 可以付款 |
| Arbiter 裁决 | `block.timestamp < arbitrationDeadline` | 不能裁决 |
| 仲裁超时退款 | `block.timestamp >= arbitrationDeadline` | 可以退款 |

同一状态下的两笔合法交易发生竞争时，以链上先确认者为准；后确认者因状态已经改变而 revert。

## 8. 外部入口与状态转换

| 入口 | 调用者 | 前置状态 | 时间条件 | 成功后状态 | 资金记账 | 事件 |
| --- | --- | --- | --- | --- | --- | --- |
| `constructor(...)` | Buyer | 无 | 见部署校验 | `Funded` | 合约接收并记录 `depositAmount` | `EscrowCreated` |
| `cancelBySeller()` | Seller | `Funded` | `< deliveryDeadline` | `Cancelled` | Buyer 待提现 `+ depositAmount` | `EscrowCancelled` |
| `markDelivered()` | Seller | `Funded` | `< deliveryDeadline` | `Delivered` | 不分配资金 | `DeliveryMarked` |
| `approveDelivery()` | Buyer | `Delivered` | `< reviewDeadline` | `Completed` | Seller 待提现 `+ depositAmount` | `DeliveryApproved` |
| `openDispute()` | Buyer | `Delivered` | `< reviewDeadline` | `Disputed` | 不分配资金 | `DisputeOpened` |
| `resolveDispute(true)` | Arbiter | `Disputed` | `< arbitrationDeadline` | `Completed` | Seller 待提现 `+ depositAmount` | `DisputeResolved` |
| `resolveDispute(false)` | Arbiter | `Disputed` | `< arbitrationDeadline` | `Refunded` | Buyer 待提现 `+ depositAmount` | `DisputeResolved` |
| `refundAfterDeliveryTimeout()` | 任意账户 | `Funded` | `>= deliveryDeadline` | `Refunded` | Buyer 待提现 `+ depositAmount` | `EscrowRefunded` |
| `claimAfterReviewTimeout()` | 任意账户 | `Delivered` | `>= reviewDeadline` | `Completed` | Seller 待提现 `+ depositAmount` | `ReviewTimeoutClaimed` |
| `refundAfterArbitrationTimeout()` | 任意账户 | `Disputed` | `>= arbitrationDeadline` | `Refunded` | Buyer 待提现 `+ depositAmount` | `EscrowRefunded` |
| `withdraw()` | 有待提现余额的 Buyer 或 Seller | 任意 | 无 | 不变 | 调用者余额清零后发送 ETH | `Withdrawal` |
| `receive()` / `fallback()` | 任意账户 | 任意 | 任意 | 不变 | 不接收普通转账 | revert |

超时入口是 permissionless 的，但收款人写死在规则中。调用者不能通过触发超时获得资金或改变裁决结果。

## 9. 各入口的业务规则

### `cancelBySeller()`

- 只有 Seller 可以取消。
- 只允许在交付期限前且状态为 `Funded` 时调用。
- 取消只把订单金额记入 Buyer 的待提现余额，不直接发送 ETH。

### `markDelivered()`

- 只有 Seller 可以声明交付。
- 成功时记录 `deliveredAt = block.timestamp` 并计算 `reviewDeadline`。
- 该声明不证明现实交付物的真实性或质量。

### `approveDelivery()`

- 只有 Buyer 可以在审核期内确认。
- 成功时一次性把全部订单金额分配给 Seller。

### `openDispute()`

- 只有 Buyer 可以在审核期内发起争议。
- 成功时记录 `disputedAt = block.timestamp` 并计算 `arbitrationDeadline`。
- 不在链上保存证据、URL 或明文描述。

### `resolveDispute(bool releaseToSeller)`

- 只有 Arbiter 可以在仲裁期内调用。
- `true` 只能把全部金额分配给 Seller；`false` 只能把全部金额分配给 Buyer。
- Arbiter 不能拆分金额、指定其他地址或收取费用。

### 三个超时入口

- 任何账户都可以触发；提前调用必须 revert。
- 交付超时固定退款给 Buyer。
- 审核超时固定付款给 Seller。
- 仲裁超时固定退款给 Buyer。这是明确偏向 Buyer 的产品规则。

### `withdraw()`

- 读取 `pendingWithdrawals[msg.sender]`；为零时 revert。
- 外部调用前先将调用者待提现余额清零。
- 使用低级 `call` 发送全部待提现 ETH，并使用 OpenZeppelin `ReentrancyGuard`。
- 外部调用失败时整笔交易 revert；EVM 原子性必须恢复清零前的待提现余额。
- 成功后发出 `Withdrawal`，重复提款必须失败。

## 10. 资金模型与不变量

业务函数只改变状态并记账，收款人之后主动提款：

```text
终止业务状态
→ pendingWithdrawals[recipient] += depositAmount
→ recipient 调用 withdraw()
```

以下不变量在每次成功调用后都必须成立：

1. **固定本金**：订单本金始终是 constructor 记录的 `depositAmount`，不读取当前合约余额推导。
2. **唯一分配**：一次部署最多执行一次终止结算。
3. **金额上限**：历史累计分配总额不得超过 `depositAmount`。
4. **终止完整性**：首次进入终止状态时，历史累计分配总额必须恰好等于 `depositAmount`。
5. **合法收款人**：订单金额只能分配给 Buyer 或 Seller。
6. **Arbiter 无收益**：`pendingWithdrawals[arbiter]` 永远为零，Arbiter 永远不是结算收款人。
7. **终止不可逆**：进入 `Completed`、`Refunded` 或 `Cancelled` 后不能改变业务结果或再次分配。
8. **提款守恒**：成功提款金额等于调用前的待提现余额；失败提款不改变余额。
9. **额外 ETH 隔离**：强制转入的 ETH 不增加 `depositAmount`、待提现金额或任何结算金额。
10. **无外部循环**：合约不遍历参与者或订单集合，单个订单的结算 gas 不随外部数据增长。

“历史累计分配”是测试和推理概念，v1 不要求为它额外增加 storage；状态机和待提现记账共同保证该性质。

## 11. 活性规则

| 停止操作的一方 | 风险 | 到期后的解决路径 | 固定受益人 |
| --- | --- | --- | --- |
| Seller 未交付 | 本金停留在 `Funded` | 任意账户调用 `refundAfterDeliveryTimeout()` | Buyer |
| Buyer 未审核 | 本金停留在 `Delivered` | 任意账户调用 `claimAfterReviewTimeout()` | Seller |
| Arbiter 未裁决 | 本金停留在 `Disputed` | 任意账户调用 `refundAfterArbitrationTimeout()` | Buyer |

这些规则解决的是“角色不调用业务函数”，不能解决收款人私钥丢失、收款合约永久拒收 ETH、链停止出块或无人支付 gas。

## 12. Custom errors

实现至少提供以下语义明确的 custom errors；测试应断言具体错误而不是只断言任意 revert：

| Error | 使用场景 |
| --- | --- |
| `ZeroDeposit()` | 部署金额为零 |
| `InvalidAddress(address account)` | Seller 或 Arbiter 为零地址 |
| `RolesMustBeDistinct(address buyer, address seller, address arbiter)` | 角色地址重复 |
| `InvalidDeliveryDeadline(uint256 currentTime, uint256 deadline)` | 部署时交付期限不在未来 |
| `InvalidReviewPeriod()` | 审核期为零 |
| `InvalidArbitrationPeriod()` | 仲裁期为零 |
| `Unauthorized(address caller)` | 调用者角色错误 |
| `InvalidState(State current, State expected)` | 状态不允许当前操作 |
| `DeadlinePassed(uint256 currentTime, uint256 deadline)` | 在截止时间或之后调用限期内操作 |
| `DeadlineNotReached(uint256 currentTime, uint256 deadline)` | 在截止时间前调用超时操作 |
| `NothingToWithdraw(address account)` | 调用者没有待提现余额 |
| `TransferFailed(address recipient, uint256 amount)` | ETH 外部转账失败 |
| `DirectPaymentNotAllowed()` | 部署后普通 ETH 转账或未知 payable 调用 |

## 13. 事件

事件只记录链下查询需要的数据，不复制完整 storage：

| 事件 | 必要字段 |
| --- | --- |
| `EscrowCreated` | indexed Buyer、Seller、Arbiter；金额；交付截止时间 |
| `DeliveryMarked` | indexed Seller；交付时间；审核截止时间 |
| `DeliveryApproved` | indexed Buyer、Seller；金额 |
| `DisputeOpened` | indexed Buyer；争议时间；仲裁截止时间 |
| `DisputeResolved` | indexed Arbiter、最终收款人；金额；`releaseToSeller` |
| `EscrowCancelled` | indexed Seller、Buyer；金额 |
| `EscrowRefunded` | indexed Buyer；金额 |
| `ReviewTimeoutClaimed` | indexed Seller；金额 |
| `Withdrawal` | indexed account；金额 |
| Factory `EscrowCreated` | indexed Escrow、Buyer、Seller；Arbiter；金额及三个时间参数 |

状态是业务事实来源，事件用于发现和历史查询，不能代替当前状态读取。

## 14. ETH 接收规则

- 只有 payable constructor 可以正常接收订单 ETH。
- 部署完成后的 `receive()` 和 `fallback()` 必须 revert。
- 其他合约仍可能通过 EVM 机制强制增加本合约余额，因此 `address(this).balance` 不能作为订单金额或状态判断依据。
- 强制转入的额外 ETH 在 v1 中永久留在合约，不引入管理员救援入口。

## 15. 威胁模型

| 威胁 | 可能后果 | v1 控制 | 剩余风险 |
| --- | --- | --- | --- |
| 错误权限 | 非角色执行敏感操作 | 固定角色地址；入口权限检查 | 角色私钥泄漏后攻击者继承其全部权限 |
| 非法状态跳转或重复结算 | 重复付款、付款后退款 | 每个入口检查精确前置状态；终止状态无业务出口 | 实现遗漏状态检查会破坏核心安全性 |
| 重入提款 | 重复提取 ETH | Pull Payment、CEI、`ReentrancyGuard` | 其他未来外部调用也必须重新审查 |
| 收款方拒收 ETH | 提款失败 | 失败整笔 revert，恢复待提现余额 | 固定收款合约若永远拒收，资金无法取出 |
| 普通误转 ETH | 余额与业务账本不一致 | `receive` / `fallback` revert | 无法阻止强制转入 |
| 强制转入 ETH | 合约余额大于订单本金 | 所有结算只使用 `depositAmount` | 额外 ETH 无法救回 |
| 时间边界错误 | 双方在截止点都有权或都无权 | 使用本规格的 `<` 与 `>=` 互补条件 | 区块生产者可小幅调整时间戳 |
| 交易抢跑或同区块竞争 | 两条路径同时尝试改变状态 | 首笔成功后状态改变，后续交易 revert | 先后顺序由链决定；用户必须预留确认时间 |
| Buyer、Seller 或 Arbiter 失联 | 资金永久锁定 | 三条 permissionless 超时路径 | 收款人失联或私钥丢失仍无法提款 |
| 恶意或偏袒的 Arbiter | 错误判给一方 | 只能二选一且不能收款；仲裁超时 | 仲裁期内的主观错误无法由合约纠正 |
| 恶意 ERC-20 | 少到账、回调、返回值异常 | v1 完全不调用 ERC-20 | Step 7 引入代币时必须重新建模和测试 |
| 大数组或无界循环 | 操作因 gas 过高失效 | 单订单、Factory 仅发事件且不保存订单数组 | 链下索引服务必须自行处理事件历史 |
| 链上证据泄露 | 商业信息永久公开 | v1 不存证据内容 | 地址和所有交易行为仍公开 |

## 16. 可直接派生的验收场景

### 构造阶段

- 有效参数部署成功并进入 `Funded`。
- 零金额、零地址、任意角色重复、过去或当前交付期限、零审核期、零仲裁期分别 revert。
- 部署事件和全部 immutable 值正确。
- 部署后普通 ETH 转账与未知 calldata 均 revert。

### 正常与取消路径

- `Funded → Delivered → Completed → Seller withdraw`。
- `Funded → Cancelled → Buyer withdraw`。
- 每一步测试错误调用者、错误状态、重复调用和提款余额。

### 三条超时路径

- `Funded → Refunded → Buyer withdraw`。
- `Delivered → Completed → Seller withdraw`。
- `Disputed → Refunded → Buyer withdraw`。
- 每条路径分别测试 `deadline - 1` 失败、`deadline` 成功、`deadline + 1` 成功。
- 用无关第四方账户触发超时，断言资金仍只分配给固定受益人。

### 争议路径

- Arbiter 判给 Seller：`Disputed → Completed`。
- Arbiter 判给 Buyer：`Disputed → Refunded`。
- 非 Arbiter、过期裁决和重复裁决均失败。

### 对抗路径

- 恶意 Seller 在接收 ETH 时重入，不能多领。
- 收款合约主动 revert，提款失败且待提现余额保持不变。
- 强制转入额外 ETH 后，各路径仍只结算 `depositAmount`。
- 对任意合法调用序列检查第 10 节全部资金不变量。

## 17. Factory 与多订单

```solidity
function createEscrow(
    address seller,
    address arbiter,
    uint256 deliveryDeadline,
    uint256 reviewPeriod,
    uint256 arbitrationPeriod
) external payable returns (address escrow);
```

- Factory 为每次调用部署一个独立 `FreelanceEscrow`，把 `msg.value` 全额转入新实例。
- 新实例的 Buyer 必须是调用 Factory 的 `msg.sender`，不能是 Factory 或 `tx.origin`。
- Factory 不保存订单数组、计数器或 Buyer 到订单的映射；链下通过 `EscrowCreated` 事件索引。
- 任意构造校验失败时，创建、事件和 ETH 转移必须在同一交易中全部回滚。
- 使用普通 `CREATE`。没有经过数据证明的部署 gas 压力，也没有地址预测需求，因此不引入 clone 或 `CREATE2`。

## 18. Review 时需要确认的产品决定

1. 三个超时入口均允许任意账户触发，但受益人固定。
2. 交付、确认、争议和裁决在 `block.timestamp == deadline` 时均已过期。
3. 仲裁超时默认全额退款给 Buyer，明确偏向 Buyer。
4. Seller 只能在交付期限前取消；超时后统一走退款路径。
5. v1 只支持全额二选一结算，不支持手续费或拆分。
6. 角色不可更换，私钥丢失没有恢复机制。
7. 收款地址可以是合约，但拒收 ETH 的后果由该角色承担。
8. 强制转入的额外 ETH 不可救援。

以上决定 review 通过后，Step 2–8 的实现和测试必须以本文为唯一业务规格；任何行为变化先修改规格，再修改代码。
