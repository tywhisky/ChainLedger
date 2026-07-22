# Hardhat 现实合约开发练习 Roadmap

## 项目结论

继续做 **Freelance Escrow（自由职业托管）**，不换题。

它比单独写 ERC-20 或 NFT 更适合完整练习真实合约开发，因为同一个小业务能覆盖：资金托管、多角色权限、状态机、超时、争议、Pull Payment、重入、异常代币、事件、部署与验证。

这次不照搬旧合约，而是按真实迭代重做：

```text
需求与威胁模型
→ ETH 单订单最小版本
→ 完整状态机与攻击测试
→ ERC-20 支付
→ Factory 多订单
→ 质量门禁
→ 本地部署演练
→ 测试网发布、验证与复盘
```

最终目标是走完一条可重复的工程链路，不是声称合约已经可直接承载真实资金。真实上线仍需要独立审计、法律与仲裁规则、密钥管理及持续监控。

## 固定原则

- 严格按编号完成；每一步都要先写失败测试，再写最少实现使它通过。
- 每一步结束做一次小提交，提交前必须通过当时已有的全部检查。
- 金额只用整数最小单位；时间只用秒；测试不得依赖真实等待。
- 业务函数只记账，收款人通过 `withdraw()` 主动提款。
- 不用 `address(this).balance` 代表订单账本余额。
- 角色固定且数量少时直接比较地址，不引入通用 RBAC。
- 复用 OpenZeppelin 的安全实现，不手写 `ReentrancyGuard`、`IERC20` 或 `SafeERC20`。
- 暂不使用代理升级。托管资金合约优先选择简单、不可变、可审计的部署版本。
- 不追求任意代币兼容；每个不支持的代币行为都要明确拒绝并测试。

## Step 0：初始化并认识工具链

目标：从空目录亲手得到一个可编译、可测试的 Hardhat 3 项目。

- [x] 安装 Node.js `>= 22.13.0` 与 pnpm。
- [x] 在当前目录运行 `pnpm dlx hardhat --init --template node-test-runner-viem`。
- [x] 运行 `pnpm hardhat --help`、`pnpm hardhat compile`、`pnpm hardhat test`。
- [x] 读懂生成的 `hardhat.config.ts`、Solidity 示例、TypeScript 测试和 Ignition module。
- [x] 删除 Counter 示例，但保留能证明空项目正常工作的最小配置。
- [x] 确认 `.gitignore` 忽略 `.env`、`artifacts/`、`cache/`、`coverage/`，但保留 lockfile。
- [x] 在 `package.json` 提供统一命令：`compile`、`test`、`coverage`。

完成标准：全新 clone 后只需安装依赖即可编译和运行测试；仓库中没有密钥或生成物。

参考：[Hardhat 3 Getting Started](https://hardhat.org/docs/getting-started)

## Step 1：先写规格，不写合约

目标：让代码实现一份明确的业务协议，而不是边写边猜。

- [x] 新建 `docs/spec.md`，定义 Buyer、Seller、Arbiter 的权力和信任假设。
- [x] 定义状态：`Funded → Delivered → Disputed → Completed/Refunded/Cancelled`。
- [x] 用表格列出每个入口函数的调用者、前置状态、时间边界、状态变化、资金归属和事件。
- [x] 明确三条活性规则：交付超时退款、审核超时付款、仲裁超时退款。
- [ ] 写出资金不变量：只分配一次、总分配不超过存款、Arbiter 永不收款。
- [x] 写威胁模型：错误权限、非法状态跳转、重入、拒收 ETH、强制转入 ETH、时间边界、恶意 ERC-20、密钥泄漏。
- [x] 明确第一版范围：一个部署对应一个 ETH 订单；不含手续费、分期付款、链上证据、升级、暂停和管理员救援。

完成标准：仅阅读规格就能为每条状态转换写出测试；所有超时的“恰好等于截止时间”语义都没有歧义。

## Step 2：ETH Escrow 骨架与构造阶段

目标：先建立可信的初始状态和不可绕过的输入边界。

- [ ] 新建 `contracts/FreelanceEscrow.sol`。
- [ ] 添加 SPDX、固定 Solidity 编译器范围、`State` enum、custom errors、必要事件。
- [ ] payable constructor 接收 Seller、Arbiter、三个期限参数和 ETH 存款。
- [ ] 校验零金额、零地址、角色重复、过去期限和零时长。
- [ ] 对不会改变的数据使用 `immutable`。
- [ ] 部署后直接进入 `Funded`；记录 `depositAmount`，不从余额反推。
- [ ] `receive()` 与 `fallback()` 拒绝部署后的直接付款。
- [ ] 用 TypeScript + Viem 测试成功部署、每个无效参数、事件和初始状态。

完成标准：constructor 的每个分支都有测试；合约部署后无法通过普通转账增加业务存款。

## Step 3：正常交付与 Pull Payment

目标：先跑通最短的真实资金路径。

- [ ] 实现 Seller `markDelivered()`：记录交付与审核截止时间。
- [ ] 实现 Buyer `approveDelivery()`：状态变为 `Completed`，只增加 Seller 待提现余额。
- [ ] 安装并使用 OpenZeppelin `ReentrancyGuard`。
- [ ] 实现 `withdraw()`：Checks-Effects-Interactions、低级 `call`、失败整笔 revert、成功事件。
- [ ] 测试完整路径：部署存款 → 交付 → 确认 → 提现。
- [ ] 测试错误调用者、错误状态、重复确认、重复提现与提款余额变化。

完成标准：正常路径净额正确，同一笔存款不能分配或提取两次。

参考：[OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)、[ReentrancyGuard](https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuard)

## Step 4：取消与双方超时

目标：任何一方失联都不能永久锁住资金。

- [ ] 实现 Seller 在 `Funded` 状态取消，款项记给 Buyer。
- [ ] 实现交付截止后 Buyer 退款。
- [ ] 实现审核截止后 Seller 主动结算。
- [ ] 使用 Hardhat 时间控制测试 `deadline - 1`、`deadline`、`deadline + 1`。
- [ ] 对每个终止状态测试所有后续业务操作均失败。

完成标准：Buyer 或 Seller 单方停止操作时，都存在一条最终结算路径。

## Step 5：争议与仲裁超时

目标：补齐第三方仲裁，但不给 Arbiter 任意转账能力。

- [ ] 实现 Buyer 在审核期内 `openDispute()`。
- [ ] 实现 Arbiter 二选一裁决：全额给 Seller 或全额退 Buyer。
- [ ] 实现仲裁截止后任何人可触发默认退款。
- [ ] 测试两种裁决、越权裁决、过期裁决、重复裁决和仲裁人失联。
- [ ] 断言 Arbiter 在任何路径都没有待提现余额。

完成标准：规格中的每条状态转换至少有一个成功测试和一个拒绝测试。

## Step 6：攻击测试与资金不变量

目标：不只证明“能用”，还要证明关键失败模式不会破坏账本。

- [ ] 写最小恶意 Seller：收 ETH 时重入 `withdraw()`。
- [ ] 写拒收 ETH 的 Seller：提款时主动 revert。
- [ ] 验证重入不能多领，转账失败后待提现余额仍可恢复。
- [ ] 写强制转入 ETH 的测试，证明额外余额不改变 `depositAmount` 或结算金额。
- [ ] 对权限矩阵和全部非法状态跳转做参数化测试，避免重复测试代码。
- [ ] 增加 Solidity fuzz/invariant test：总分配不超过存款、终止后结果不变、Arbiter 永不获款。

完成标准：攻击合约测试通过；任意调用序列都不能让订单资金被重复分配。

参考：[Hardhat Solidity tests and fuzzing](https://hardhat.org/docs/learn-more/whats-new#solidity-tests)

## Step 7：加入 ERC-20 支付

目标：学习现实代币交互，而不把 ETH 版本提前抽象复杂化。

- [ ] 新建独立的 `ERC20FreelanceEscrow.sol`，先允许少量重复；测试稳定后再判断是否值得提取共享逻辑。
- [ ] 使用 OpenZeppelin `IERC20` 与 `SafeERC20`，不得假设代币一定返回 `true`。
- [ ] 采用 `approve → fund()`，并在实际到账后才进入 `Funded`。
- [ ] 通过转账前后余额差校验到账数量；明确拒绝 fee-on-transfer / rebasing token。
- [ ] 测试标准代币、不返回值代币、返回 false、转账手续费、余额不足和 allowance 不足。
- [ ] 复用 Step 3–6 的状态机、超时、攻击和不变量场景。

完成标准：支持边界写进 NatSpec 和 README；不支持的代币会明确 revert，不会悄悄造成坏账。

参考：[OpenZeppelin SafeERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#SafeERC20)

## Step 8：Factory 与多订单

目标：从单订单练习升级到可实际创建多个订单的最小协议。

- [ ] 新建 `EscrowFactory`，由它创建独立 Escrow 实例并转发 ETH。
- [ ] 修正 Factory 成为 `msg.sender` 后的身份问题：Buyer 必须是最终用户而不是 Factory。
- [ ] 通过事件索引订单；不要为了链上列表写无界数组遍历。
- [ ] 测试 ETH 转发、Buyer 身份、不同订单隔离、创建失败回滚和事件内容。
- [ ] 评估 clone / CREATE2 的收益；没有明确 gas 或地址预测需求就不实现。

完成标准：任意两个订单的状态和资金互不影响，链下可仅靠事件发现订单。

## Step 9：工程质量门禁

目标：把“我本地试过”变成每次都可重复的检查。

- [ ] 开启 Solidity optimizer；记录优化前后部署 gas、运行 gas和 bytecode 大小，不凭感觉调参。
- [ ] 运行 Hardhat coverage，确认关键分支而不追求虚假的 100%。
- [ ] 运行 Hardhat gas statistics / snapshots，为关键入口留下基线。
- [ ] 用 Slither 做一次静态分析；逐条判断结果，不盲目消除 warning。
- [ ] 检查 NatSpec、事件 indexed 字段、custom errors、storage layout 与可见性。
- [ ] 建立最小 CI：锁定依赖安装、compile、test、coverage；任一步失败即阻止合并。
- [ ] 固定依赖版本，并用独立提交审查依赖升级。

完成标准：一条命令能执行本地质量门禁；干净环境中的 CI 结果与本地一致。

参考：[Hardhat coverage](https://hardhat.org/docs/guides/testing/code-coverage)、[Hardhat gas statistics](https://hardhat.org/docs/guides/testing/gas-statistics)

## Step 10：可重复部署与本地演练

目标：部署不是临时脚本，而是可审查、可重放的项目资产。

- [ ] 用 Hardhat Ignition 编写 ETH Escrow、测试 ERC-20、Factory 的部署 module。
- [ ] 启动本地节点，用不同账户完成正常交付、退款、争议和提款全流程。
- [ ] 写最小交互脚本读取状态、发送交易、等待 receipt 并解析事件。
- [ ] 验证错误 chain ID、余额不足、nonce / 交易失败时脚本会明确退出。
- [ ] 保存部署参数和地址，但不提交私钥、助记词或 RPC 密钥。

完成标准：删除本地部署状态后仍能按文档重新部署，并跑通同样的验收流程。

参考：[Hardhat Ignition](https://hardhat.org/ignition/docs/getting-started)、[Hardhat configuration variables](https://hardhat.org/docs/guides/configuration-variables)

## Step 11：测试网发布与源码验证

目标：经历一次接近真实发布的受控流程。

- [ ] 选择当前仍受支持的 EVM 测试网，核对 chain ID、RPC、浏览器和测试币来源。
- [ ] 使用专用测试账户；密钥通过 Hardhat 配置变量或安全 keystore 注入。
- [ ] 先模拟部署并复核参数，再用 Ignition 正式部署。
- [ ] 在区块浏览器验证源码和 constructor 参数。
- [ ] 用三个独立账户跑一遍创建、交付、争议/确认和提款。
- [ ] 记录 tx hash、合约地址、编译器设置、commit hash 和已知限制。

完成标准：其他人只看部署记录和 README 就能验证字节码来源并复现交互。

参考：[Hardhat contract verification](https://hardhat.org/docs/guides/smart-contract-verification)

## Step 12：发布前审查与复盘

目标：练习现实团队在冻结版本后的工作，而不是继续堆功能。

- [ ] 冻结功能，重新从规格逐条核对实现和测试。
- [ ] 手工画出实际状态机，与 Step 1 文档比较差异。
- [ ] 列出中心化与活性风险：Arbiter 偏权、时间参数、私钥丢失、恶意收款方、异常代币。
- [ ] 解释为什么默认没有 `pause`、管理员退款、代理升级和资金救援，以及加入它们会新增哪些权力。
- [ ] 请另一位开发者只基于规格做一次独立 review；修复项单独提交并补回归测试。
- [ ] 写 `docs/postmortem.md`：最危险的三个假设、测试发现的真实 bug、若承载资金下一步必须做什么。
- [ ] 打一个练习版 tag；之后的新需求从新分支开始。

完成标准：你能不用看代码解释资金在每条路径中的归属、全部信任假设，以及为什么测试网成功不等于生产安全。

## 延后项

以下内容不是本轮“完整合约开发流程”的必要条件，完成 Step 12 后按兴趣另开项目：

- 分期里程碑与部分裁决；
- EIP-712 签名、permit 与元交易；
- 多签 / DAO 仲裁；
- 前端钱包交互与事件索引器；
- 主网 fork 测试和多链部署；
- 代理升级、协议手续费与治理。

加入条件：必须先写出真实需求、额外信任假设和对应失败测试，不能只因为“生产项目常见”就添加。
