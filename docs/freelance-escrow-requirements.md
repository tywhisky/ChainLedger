可以。你写的 `REC20` 应该是 `ERC-20`。第一份任务先只处理原生 ETH，不使用 OpenZeppelin，也不实现代币标准。

# 练习任务：自由职业 ETH 托管合约

合约名称：

```solidity
FreelanceEscrow
```

场景：

> 客户把 ETH 存入合约。自由职业者完成工作后提交交付，客户确认后释放款项；出现争议时由仲裁人决定退款或付款。

它不复杂，但能覆盖现实合约开发中最重要的一批问题：

- payable 与 ETH 托管；
- 多角色权限；
- 状态机；
- 超时处理；
- 退款和提现；
- Checks-Effects-Interactions；
- 重入攻击；
- 外部调用失败；
- 事件；
- custom errors；
- 资金不变量；
- 合约活性；
- 强制转入 ETH；
- `block.timestamp` 的合理使用。

---

## 一、参与角色

合约只有三个角色：

### Buyer

客户，也是合约部署者：

- 部署时支付全部托管金额；
- 可以确认交付；
- 可以发起争议；
- 超过交付期限后可以退款。

### Seller

自由职业者：

- 接受托管关系；
- 完成工作后标记已交付；
- 客户确认或审核期结束后获得款项；
- 未开始工作前可以取消订单。

### Arbiter

仲裁人：

- 只在争议发生后介入；
- 决定把全部金额交给 Buyer 或 Seller；
- 不能自己取得资金。

第一版不支持拆分金额。

---

## 二、部署参数

部署合约时传入：

```text
seller
arbiter
deliveryDeadline
reviewPeriod
arbitrationPeriod
```

同时由 Buyer 使用 `msg.value` 存入托管 ETH。

构造函数必须拒绝：

- `msg.value == 0`；
- Seller 为零地址；
- Arbiter 为零地址；
- Buyer、Seller、Arbiter 地址相同；
- 交付期限不在未来；
- 审核期限为零；
- 仲裁期限为零。

部署成功后，合约直接进入 `Funded` 状态。

保存以下不可变信息：

```text
buyer
seller
arbiter
depositAmount
deliveryDeadline
reviewPeriod
arbitrationPeriod
```

能用 `immutable` 的字段使用 `immutable`。

---

## 三、状态机

定义以下状态：

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

合法状态转换：

```text
Funded
├── Seller 标记交付
│   └── Delivered
├── Seller 取消
│   └── Cancelled
└── 超过交付期限，Buyer 申请退款
    └── Refunded

Delivered
├── Buyer 确认
│   └── Completed
├── Buyer 发起争议
│   └── Disputed
└── 审核期结束，Seller 领取
    └── Completed

Disputed
├── Arbiter 判给 Seller
│   └── Completed
├── Arbiter 判给 Buyer
│   └── Refunded
└── 仲裁超时
    └── Refunded
```

终止状态：

```text
Completed
Refunded
Cancelled
```

进入终止状态后不能再改变业务结果。

---

## 四、核心功能

### 1. Seller 取消订单

```solidity
cancelBySeller()
```

规则：

- 只能由 Seller 调用；
- 只能在 `Funded` 状态调用；
- 资金归还 Buyer；
- 状态变为 `Cancelled`；
- 不直接发送 ETH，只增加 Buyer 的待提现余额。

模拟自由职业者尚未开始工作、拒绝订单的场景。

### 2. Seller 标记完成交付

```solidity
markDelivered()
```

规则：

- 只能由 Seller 调用；
- 只能在 `Funded` 状态调用；
- 必须在 `deliveryDeadline` 之前；
- 状态变为 `Delivered`；
- 保存 `deliveredAt`；
- 根据 `reviewPeriod` 计算审核截止时间；
- 不发生资金转移。

链上无法判断现实工作是否真正完成，这个函数只表示 Seller 作出了交付声明。

### 3. Buyer 确认交付

```solidity
approveDelivery()
```

规则：

- 只能由 Buyer 调用；
- 只能在 `Delivered` 状态调用；
- 状态变为 `Completed`；
- 托管金额进入 Seller 的待提现余额；
- 不在该函数中直接向 Seller 转账。

### 4. Buyer 发起争议

```solidity
openDispute()
```

规则：

- 只能由 Buyer 调用；
- 只能在 `Delivered` 状态调用；
- 必须在审核期限结束前；
- 状态变为 `Disputed`；
- 保存 `disputedAt`；
- 计算仲裁截止时间；
- 不发生资金转移。

第一版不要求把争议证据存到链上。证据可以在链下交换，合约只保存仲裁结果。

### 5. Arbiter 解决争议

```solidity
resolveDispute(bool releaseToSeller)
```

规则：

- 只能由 Arbiter 调用；
- 只能在 `Disputed` 状态调用；
- 必须在仲裁期限结束前；
- `releaseToSeller == true` 时：
  - 状态变为 `Completed`；
  - 金额进入 Seller 的待提现余额；
- 否则：
  - 状态变为 `Refunded`；
  - 金额进入 Buyer 的待提现余额。

Arbiter 不能把钱转给任意地址。

### 6. 交付超时退款

```solidity
refundAfterDeliveryTimeout()
```

规则：

- 只能由 Buyer 调用；
- 只能在 `Funded` 状态调用；
- 当前时间必须已经超过 `deliveryDeadline`；
- 状态变为 `Refunded`；
- 金额进入 Buyer 的待提现余额。

这避免 Seller 永远不交付导致资金锁死。

### 7. 审核超时后 Seller 获款

```solidity
claimAfterReviewTimeout()
```

规则：

- 只能由 Seller 调用；
- 只能在 `Delivered` 状态调用；
- 当前时间必须超过审核截止时间；
- 状态变为 `Completed`；
- 金额进入 Seller 的待提现余额。

这避免 Buyer 收到交付后永远不确认。

### 8. 仲裁超时退款

```solidity
refundAfterArbitrationTimeout()
```

规则：

- 可以允许任何人调用；
- 只能在 `Disputed` 状态调用；
- 当前时间必须超过仲裁截止时间；
- 默认判定退款给 Buyer；
- 状态变为 `Refunded`；
- 金额进入 Buyer 的待提现余额。

这里的默认退款是一项明确的产品规则。它解决仲裁人失联导致资金永久锁定的问题，但也偏向 Buyer。

### 9. 提现

```solidity
withdraw()
```

规则：

- Buyer 或 Seller 均可调用；
- 读取 `pendingWithdrawals[msg.sender]`；
- 没有待提现余额时 revert；
- 在外部转账前先将余额清零；
- 使用低级 `call` 发送 ETH；
- 转账失败时整笔交易 revert；
- 防止重入；
- 提现成功后发出事件。

所有业务函数只分配待提现余额，不直接转账：

```text
业务状态改变
→ 记录 pending withdrawal
→ 收款方主动 withdraw
```

这称为 Pull Payment 模式。

---

## 五、权限实现

至少实现以下访问限制：

```text
onlyBuyer
onlySeller
onlyArbiter
```

但不要为了练习而写通用 RBAC 系统。

错误使用 custom errors，例如概念上包含：

```solidity
error Unauthorized();
error InvalidState();
error DeadlineNotReached();
error DeadlinePassed();
error ZeroAmount();
error InvalidAddress();
error NothingToWithdraw();
error TransferFailed();
error Reentrancy();
```

不要使用大量长字符串：

```solidity
require(condition, "Very long error message...");
```

---

## 六、事件

至少发出以下事件：

```text
EscrowCreated
DeliveryMarked
DeliveryApproved
DisputeOpened
DisputeResolved
EscrowCancelled
EscrowRefunded
Withdrawal
```

事件应包含真正有查询价值的信息，例如：

- Buyer；
- Seller；
- Arbiter；
- 托管金额；
- 最终收款方；
- 时间；
- 是否判给 Seller。

不要把整个合约状态重复塞进每一个事件。

---

## 七、ETH 接收规则

部署时允许通过 payable constructor 接收 ETH。

部署完成后，普通转账应被拒绝：

```solidity
receive() external payable
fallback() external payable
```

它们应该 revert，避免用户误将额外 ETH 发入合约。

但你还要理解：

> 即使 `receive()` 会 revert，其他合约仍可能通过特殊机制强制让该地址余额增加。

因此业务逻辑不能使用：

```solidity
address(this).balance
```

来判断本订单应当支付多少。

支付金额必须始终来源于部署时记录的：

```text
depositAmount
```

合约里多出来的意外 ETH 不属于订单资金。

第一版不需要实现“救回强制转入 ETH”的管理员功能。

---

## 八、重入保护

你暂时不用 OpenZeppelin，因此自己实现最小重入锁。

要求：

- 只用于包含外部 ETH 转账的 `withdraw()`；
- 调用期间再次进入 `withdraw()` 必须失败；
- 状态修改发生在外部 `call` 之前；
- 外部调用失败时，交易 revert，并恢复之前的状态。

你需要理解两层保护的区别：

```text
Checks-Effects-Interactions
+
Reentrancy Guard
```

不能只依赖其中一个而完全不理解另一个。

---

## 九、资金不变量

在任何合法操作后，必须满足：

```text
订单资金只能归 Buyer 或 Seller
Arbiter 永远不能获得订单资金
同一笔订单资金只能分配一次
最终可分配总金额不能超过 depositAmount
完成退款后不能再次付款
完成付款后不能再次退款
```

业务逻辑不能依赖合约当前 ETH 余额恰好等于 `depositAmount`，因为：

- 有人可能强制转入 ETH；
- 一部分资金可能已经提现；
- 外部转账可能失败；
- 合约余额与业务账本不是一回事。

---

## 十、Remix 手动验收场景

准备三个 Remix VM 账户：

```text
Account 0：Buyer
Account 1：Seller
Account 2：Arbiter
```

### 场景 1：正常完成

```text
Buyer 部署并存入 1 ETH
→ Seller markDelivered
→ Buyer approveDelivery
→ Seller withdraw
```

验收：

- 最终状态为 `Completed`；
- Seller 可以提取 1 ETH；
- Buyer 不能退款；
- Seller 不能再次提现；
- 事件完整。

### 场景 2：Seller 取消

```text
Buyer 部署并存入 1 ETH
→ Seller cancelBySeller
→ Buyer withdraw
```

验收：

- 最终状态为 `Cancelled`；
- Buyer 得到退款；
- Seller 不能标记交付。

### 场景 3：交付超时

```text
Buyer 部署
→ Seller 一直不操作
→ 超过 deliveryDeadline
→ Buyer refundAfterDeliveryTimeout
→ Buyer withdraw
```

Remix VM 不方便快速控制时间时，可以临时把 deadline 设置得很短等待测试，但正式值应该按天计算。

### 场景 4：Buyer 不确认

```text
Seller markDelivered
→ Buyer 不操作
→ 审核期限结束
→ Seller claimAfterReviewTimeout
→ Seller withdraw
```

验收：

- Buyer 无法无限锁住资金。

### 场景 5：争议判给 Seller

```text
Seller markDelivered
→ Buyer openDispute
→ Arbiter resolveDispute(true)
→ Seller withdraw
```

### 场景 6：争议判给 Buyer

```text
Seller markDelivered
→ Buyer openDispute
→ Arbiter resolveDispute(false)
→ Buyer withdraw
```

### 场景 7：错误权限

分别尝试：

- Buyer 调用 `markDelivered()`；
- Seller 调用 `approveDelivery()`；
- Seller 调用 `resolveDispute()`；
- Arbiter 调用 `withdraw()`。

全部必须失败。

### 场景 8：非法状态转换

尝试：

- 未交付就确认；
- 已确认后再争议；
- 已退款后再交付；
- 已完成后再退款；
- 同一笔资金分配两次；
- 重复提现。

全部必须失败。

### 场景 9：直接转账

部署完成后，直接向合约地址发送 ETH。

交易必须 revert。

### 场景 10：恶意收款合约

额外写一个很小的攻击者合约：

- 将自己设为 Seller；
- 收到 ETH 时重新调用 `withdraw()`；
- 或者在接收 ETH 时主动 revert。

验收：

- 重入不能重复提取；
- 接收方 revert 时，本次提现失败；
- 待提现余额不会永久错误清零；
- 其他业务状态不会被破坏。

---

## 十一、完成标准

完成后，你应该能解释：

1. 为什么不在 `approveDelivery()` 里直接向 Seller 转账？
2. 为什么 `call` 前必须清零待提现余额？
3. 为什么仍然需要重入锁？
4. 为什么不能用 `address(this).balance` 作为订单金额？
5. 为什么每个角色都可能导致资金永久锁定？
6. 每个超时机制解决了谁不操作的问题？
7. 为什么 `block.timestamp` 适合按天计算的期限，但不适合精确到秒的公平随机数？
8. 为什么智能合约无法判断现实工作是否真的完成？
9. 为什么事件不能代替合约状态？
10. 为什么仲裁默认退款是产品规则，而不是技术必然？

## 暂时不要加入

- ERC-20；
- NFT；
- 平台手续费；
- 多订单；
- Factory；
- 部分付款；
- 分期交付；
- 多仲裁人；
- DAO 投票；
- 代理升级；
- 管理员暂停；
- Oracle；
- 前端。

先把这个单订单合约写正确。下一步再增加“仲裁金额按比例拆分”，随后才考虑 Factory 和 ERC-20。
