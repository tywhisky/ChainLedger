import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, parseEventLogs, zeroAddress } from "viem";

describe("EscrowFactory", async function () {
  const { viem, networkHelpers } = await network.create();
  const [buyer, seller, arbiter, secondBuyer, secondSeller] =
    await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();
  const factory = await viem.deployContract("EscrowFactory");
  const escrowDecoder = await viem.getContractAt(
    "FreelanceEscrow",
    zeroAddress,
  );

  const DEPOSIT = 1n * 10n ** 18n;
  const DAY = 24n * 60n * 60n;
  const REVIEW_PERIOD = 3n * DAY;
  const ARBITRATION_PERIOD = 5n * DAY;

  async function createEscrow(
    buyerClient: typeof buyer,
    sellerAddress: `0x${string}`,
  ) {
    const deadline = BigInt(await networkHelpers.time.latest()) + 7n * DAY;
    const hash = await factory.write.createEscrow(
      [
        sellerAddress,
        arbiter.account.address,
        deadline,
        REVIEW_PERIOD,
        ARBITRATION_PERIOD,
      ],
      { account: buyerClient.account, value: DEPOSIT },
    );
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const [created] = parseEventLogs({
      abi: factory.abi,
      logs: receipt.logs,
      eventName: "EscrowCreated",
    });
    assert.ok(created);

    const escrow = await viem.getContractAt(
      "FreelanceEscrow",
      created.args.escrow,
    );

    return { escrow, event: created, deadline };
  }

  it("forwards ETH, preserves the final Buyer, and emits a discoverable order", async function () {
    const { escrow, event, deadline } = await createEscrow(
      buyer,
      seller.account.address,
    );

    assert.equal(
      await escrow.read.buyer(),
      getAddress(buyer.account.address),
    );
    assert.equal(
      await escrow.read.seller(),
      getAddress(seller.account.address),
    );
    assert.equal(
      await escrow.read.arbiter(),
      getAddress(arbiter.account.address),
    );
    assert.equal(await escrow.read.depositAmount(), DEPOSIT);
    assert.equal(
      await publicClient.getBalance({ address: escrow.address }),
      DEPOSIT,
    );
    assert.equal(
      await publicClient.getBalance({ address: factory.address }),
      0n,
    );
    assert.deepEqual(event.args, {
      escrow: getAddress(escrow.address),
      buyer: getAddress(buyer.account.address),
      seller: getAddress(seller.account.address),
      arbiter: getAddress(arbiter.account.address),
      amount: DEPOSIT,
      deliveryDeadline: deadline,
      reviewPeriod: REVIEW_PERIOD,
      arbitrationPeriod: ARBITRATION_PERIOD,
    });
  });

  it("keeps independently created orders isolated", async function () {
    const first = await createEscrow(buyer, seller.account.address);
    const second = await createEscrow(
      secondBuyer,
      secondSeller.account.address,
    );

    await first.escrow.write.markDelivered({ account: seller.account });
    assert.equal(await first.escrow.read.state(), 1);
    assert.equal(await second.escrow.read.state(), 0);

    await second.escrow.write.cancelBySeller({
      account: secondSeller.account,
    });
    assert.equal(await second.escrow.read.state(), 5);
    assert.equal(
      await second.escrow.read.pendingWithdrawals([
        secondBuyer.account.address,
      ]),
      DEPOSIT,
    );
    assert.equal(await first.escrow.read.state(), 1);
    assert.equal(
      await publicClient.getBalance({ address: first.escrow.address }),
      DEPOSIT,
    );
    assert.equal(
      await publicClient.getBalance({ address: second.escrow.address }),
      DEPOSIT,
    );
  });

  it("rolls back a failed creation without trapping ETH", async function () {
    const deadline = BigInt(await networkHelpers.time.latest()) + 7n * DAY;

    await viem.assertions.revertWithCustomErrorWithArgs(
      factory.write.createEscrow(
        [
          zeroAddress,
          arbiter.account.address,
          deadline,
          REVIEW_PERIOD,
          ARBITRATION_PERIOD,
        ],
        { account: buyer.account, value: DEPOSIT },
      ),
      escrowDecoder,
      "InvalidAddress",
      [zeroAddress],
    );

    assert.equal(
      await publicClient.getBalance({ address: factory.address }),
      0n,
    );
  });
});
