# ChainLedger

基于 Hardhat 3、Node Test Runner 和 Viem 的 Escrow 合约开发练习。

实施顺序与每一步的完成标准见 [ROADMAP.md](./ROADMAP.md)。

## 环境

- Node.js >= 22.13.0
- pnpm 11.9.0

## 使用

```shell
pnpm install
pnpm compile
pnpm test
pnpm coverage
```

## ERC-20 支持边界

`ERC20FreelanceEscrow` 使用 `approve → fund()` 两步注资，并通过
OpenZeppelin `SafeERC20` 兼容标准 ERC-20 和不返回值的旧式代币。

- 仅支持余额固定、转入和转出数量与参数完全一致的 ERC-20。
- 不支持 fee-on-transfer 代币；注资到账不足时整笔交易 revert。
- 不支持 rebasing 代币；余额缩减导致抵押不足时，提款 revert 且保留待提款额度。
- 返回 `false`、余额不足或 allowance 不足的代币操作都会 revert。
- 合约以 `depositAmount` 记账；直接转入的额外代币不会改变订单结算金额。
