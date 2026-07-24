import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, parseEventLogs, zeroAddress } from "viem";

describe("FreelanceEscrow", async function () {
  const { viem, networkHelpers } = await network.create();
  const [buyer, seller, arbiter, outsider] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();
  const decoder = await viem.getContractAt("FreelanceEscrow", zeroAddress);

  const DEPOSIT = 1n * 10n ** 18n;
  const DAY = 24n * 60n * 60n;
  const REVIEW_PERIOD = 3n * DAY;
  const ARBITRATION_PERIOD = 5n * DAY;

  async function validArgs() {
    const deadline = BigInt(await networkHelpers.time.latest()) + 7n * DAY;

    return [
      buyer.account.address,
      seller.account.address,
      arbiter.account.address,
      deadline,
      REVIEW_PERIOD,
      ARBITRATION_PERIOD,
    ] as const;
  }

  async function deployEscrow() {
    const args = await validArgs();
    const contract = await viem.deployContract("FreelanceEscrow", args, {
      value: DEPOSIT,
    });

    return { contract, deliveryDeadline: args[3] };
  }

  async function deliverEscrow() {
    const deployment = await deployEscrow();
    await deployment.contract.write.markDelivered({
      account: seller.account,
    });

    return {
      ...deployment,
      reviewDeadline: await deployment.contract.read.reviewDeadline(),
    };
  }

  async function disputeEscrow() {
    const delivery = await deliverEscrow();
    await delivery.contract.write.openDispute({ account: buyer.account });

    return {
      ...delivery,
      arbitrationDeadline:
        await delivery.contract.read.arbitrationDeadline(),
    };
  }

  async function completeEscrow() {
    const delivery = await deliverEscrow();
    await delivery.contract.write.approveDelivery({ account: buyer.account });
    return delivery;
  }

  async function refundEscrow() {
    const deployment = await deployEscrow();
    await networkHelpers.time.setNextBlockTimestamp(
      deployment.deliveryDeadline,
    );
    await deployment.contract.write.refundAfterDeliveryTimeout();
    return deployment;
  }

  async function cancelEscrow() {
    const deployment = await deployEscrow();
    await deployment.contract.write.cancelBySeller({
      account: seller.account,
    });
    return deployment;
  }

  it("stores the funded escrow and emits EscrowCreated", async function () {
    const args = await validArgs();
    const { contract, deploymentTransaction } =
      await viem.sendDeploymentTransaction("FreelanceEscrow", args, {
        value: DEPOSIT,
      });
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: deploymentTransaction.hash,
    });
    const [created] = parseEventLogs({
      abi: contract.abi,
      logs: receipt.logs,
      eventName: "EscrowCreated",
    });

    assert.equal(
      await contract.read.buyer(),
      getAddress(buyer.account.address),
    );
    assert.equal(
      await contract.read.seller(),
      getAddress(seller.account.address),
    );
    assert.equal(
      await contract.read.arbiter(),
      getAddress(arbiter.account.address),
    );
    assert.equal(await contract.read.depositAmount(), DEPOSIT);
    assert.equal(await contract.read.deliveryDeadline(), args[3]);
    assert.equal(await contract.read.reviewPeriod(), REVIEW_PERIOD);
    assert.equal(await contract.read.arbitrationPeriod(), ARBITRATION_PERIOD);
    assert.equal(await contract.read.state(), 0);
    assert.equal(
      await publicClient.getBalance({ address: contract.address }),
      DEPOSIT,
    );
    assert.deepEqual(created?.args, {
      buyer: getAddress(buyer.account.address),
      seller: getAddress(seller.account.address),
      arbiter: getAddress(arbiter.account.address),
      amount: DEPOSIT,
      deliveryDeadline: args[3],
    });
  });

  it("rejects a zero deposit", async function () {
    await viem.assertions.revertWithCustomError(
      viem.deployContract("FreelanceEscrow", await validArgs()),
      decoder,
      "ZeroDeposit",
    );
  });

  it("rejects a zero buyer address", async function () {
    const [
      ,
      sellerAddress,
      arbiterAddress,
      deadline,
      reviewPeriod,
      arbitrationPeriod,
    ] = await validArgs();

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
          zeroAddress,
          sellerAddress,
          arbiterAddress,
          deadline,
          reviewPeriod,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidAddress",
      [zeroAddress],
    );
  });

  it("rejects a zero seller address", async function () {
    const [
      buyerAddress,
      ,
      arbiterAddress,
      deadline,
      reviewPeriod,
      arbitrationPeriod,
    ] = await validArgs();

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          zeroAddress,
          arbiterAddress,
          deadline,
          reviewPeriod,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidAddress",
      [zeroAddress],
    );
  });

  it("rejects a zero arbiter address", async function () {
    const [
      buyerAddress,
      sellerAddress,
      ,
      deadline,
      reviewPeriod,
      arbitrationPeriod,
    ] = await validArgs();

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          sellerAddress,
          zeroAddress,
          deadline,
          reviewPeriod,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidAddress",
      [zeroAddress],
    );
  });

  it("rejects every duplicate role pairing", async function () {
    const [, , , deadline, reviewPeriod, arbitrationPeriod] =
      await validArgs();
    const buyerAddress = buyer.account.address;
    const sellerAddress = seller.account.address;
    const arbiterAddress = arbiter.account.address;
    const duplicateRoles = [
      [
        buyerAddress,
        arbiterAddress,
        [buyerAddress, buyerAddress, arbiterAddress],
      ],
      [
        sellerAddress,
        buyerAddress,
        [buyerAddress, sellerAddress, buyerAddress],
      ],
      [
        sellerAddress,
        sellerAddress,
        [buyerAddress, sellerAddress, sellerAddress],
      ],
    ] as const;

    for (const [sellerArg, arbiterArg, errorArgs] of duplicateRoles) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        viem.deployContract(
          "FreelanceEscrow",
          [
            buyerAddress,
            sellerArg,
            arbiterArg,
            deadline,
            reviewPeriod,
            arbitrationPeriod,
          ],
          { value: DEPOSIT },
        ),
        decoder,
        "RolesMustBeDistinct",
        [...errorArgs],
      );
    }
  });

  it("rejects a past delivery deadline", async function () {
    const [
      buyerAddress,
      sellerAddress,
      arbiterAddress,
      ,
      reviewPeriod,
      arbitrationPeriod,
    ] =
      await validArgs();
    const deadline = BigInt(await networkHelpers.time.latest());

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          sellerAddress,
          arbiterAddress,
          deadline,
          reviewPeriod,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidDeliveryDeadline",
      [(currentTime) => currentTime >= deadline, deadline],
    );
  });

  it("rejects a delivery deadline equal to the deployment time", async function () {
    const [
      buyerAddress,
      sellerAddress,
      arbiterAddress,
      ,
      reviewPeriod,
      arbitrationPeriod,
    ] =
      await validArgs();
    const deadline = BigInt(await networkHelpers.time.latest()) + 1n;
    await networkHelpers.time.setNextBlockTimestamp(deadline);

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          sellerAddress,
          arbiterAddress,
          deadline,
          reviewPeriod,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidDeliveryDeadline",
      [deadline, deadline],
    );
  });

  it("rejects a zero review period", async function () {
    const [
      buyerAddress,
      sellerAddress,
      arbiterAddress,
      deadline,
      ,
      arbitrationPeriod,
    ] =
      await validArgs();

    await viem.assertions.revertWithCustomError(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          sellerAddress,
          arbiterAddress,
          deadline,
          0n,
          arbitrationPeriod,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidReviewPeriod",
    );
  });

  it("rejects a zero arbitration period", async function () {
    const [
      buyerAddress,
      sellerAddress,
      arbiterAddress,
      deadline,
      reviewPeriod,
    ] =
      await validArgs();

    await viem.assertions.revertWithCustomError(
      viem.deployContract(
        "FreelanceEscrow",
        [
          buyerAddress,
          sellerAddress,
          arbiterAddress,
          deadline,
          reviewPeriod,
          0n,
        ],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidArbitrationPeriod",
    );
  });

  it("rejects a direct ETH transfer", async function () {
    const contract = await viem.deployContract(
      "FreelanceEscrow",
      await validArgs(),
      { value: DEPOSIT },
    );

    await viem.assertions.revertWithCustomError(
      buyer.sendTransaction({ to: contract.address, value: 1n }),
      contract,
      "DirectPaymentNotAllowed",
    );
  });

  it("rejects unknown calldata", async function () {
    const contract = await viem.deployContract(
      "FreelanceEscrow",
      await validArgs(),
      { value: DEPOSIT },
    );

    await viem.assertions.revertWithCustomError(
      buyer.sendTransaction({ to: contract.address, data: "0xdeadbeef" }),
      contract,
      "DirectPaymentNotAllowed",
    );
  });

  it("completes delivery, approval, and withdrawal", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);
    const deliveryHash = await contract.write.markDelivered({
      account: seller.account,
    });
    const deliveryReceipt = await publicClient.waitForTransactionReceipt({
      hash: deliveryHash,
    });
    const deliveryBlock = await publicClient.getBlock({
      blockNumber: deliveryReceipt.blockNumber,
    });
    const deliveredAt = deliveryBlock.timestamp;
    const reviewDeadline = deliveredAt + REVIEW_PERIOD;
    const [marked] = parseEventLogs({
      abi: contract.abi,
      logs: deliveryReceipt.logs,
      eventName: "DeliveryMarked",
    });

    assert.equal(await contract.read.state(), 1);
    assert.equal(await contract.read.deliveredAt(), deliveredAt);
    assert.equal(await contract.read.reviewDeadline(), reviewDeadline);
    assert.deepEqual(marked?.args, {
      seller: getAddress(seller.account.address),
      deliveredAt,
      reviewDeadline,
    });

    await viem.assertions.emitWithArgs(
      contract.write.approveDelivery({ account: buyer.account }),
      contract,
      "DeliveryApproved",
      [buyer.account.address, seller.account.address, DEPOSIT],
    );
    assert.equal(await contract.read.state(), 3);
    assert.equal(
      await contract.read.pendingWithdrawals([seller.account.address]),
      DEPOSIT,
    );
    assert.equal(
      await publicClient.getBalance({ address: contract.address }),
      DEPOSIT,
    );

    const withdrawal = contract.write.withdraw({ account: seller.account });
    await viem.assertions.balancesHaveChanged(
      withdrawal,
      [
        { address: seller.account.address, amount: DEPOSIT },
        { address: contract.address, amount: -DEPOSIT },
      ],
    );
    await viem.assertions.emitWithArgs(
      withdrawal,
      contract,
      "Withdrawal",
      [seller.account.address, DEPOSIT],
    );
    assert.equal(
      await contract.read.pendingWithdrawals([seller.account.address]),
      0n,
    );
    assert.equal(
      await publicClient.getBalance({ address: contract.address }),
      0n,
    );
    assert.equal(await contract.read.state(), 3);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.withdraw({ account: seller.account }),
      contract,
      "NothingToWithdraw",
      [seller.account.address],
    );
  });

  it("only lets the seller mark delivery", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);

    for (const caller of [buyer, arbiter]) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.markDelivered({ account: caller.account }),
        contract,
        "Unauthorized",
        [caller.account.address],
      );
    }
  });

  it("rejects delivery at the delivery deadline", async function () {
    const { contract, deliveryDeadline } =
      await networkHelpers.loadFixture(deployEscrow);
    await networkHelpers.time.setNextBlockTimestamp(deliveryDeadline);

    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.markDelivered({ account: seller.account }),
      contract,
      "DeadlinePassed",
      [deliveryDeadline, deliveryDeadline],
    );
  });

  it("only lets the buyer approve before the review deadline", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);
    await contract.write.markDelivered({ account: seller.account });

    for (const caller of [seller, arbiter]) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.approveDelivery({ account: caller.account }),
        contract,
        "Unauthorized",
        [caller.account.address],
      );
    }

    const reviewDeadline = await contract.read.reviewDeadline();
    await networkHelpers.time.setNextBlockTimestamp(reviewDeadline);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.approveDelivery({ account: buyer.account }),
      contract,
      "DeadlinePassed",
      [reviewDeadline, reviewDeadline],
    );
  });

  it("rejects operations in the wrong state", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);

    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.approveDelivery({ account: buyer.account }),
      contract,
      "InvalidState",
      [0, 1],
    );
    await contract.write.markDelivered({ account: seller.account });
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.markDelivered({ account: seller.account }),
      contract,
      "InvalidState",
      [1, 0],
    );
    await contract.write.approveDelivery({ account: buyer.account });
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.approveDelivery({ account: buyer.account }),
      contract,
      "InvalidState",
      [3, 1],
    );
  });

  it("rejects withdrawal before funds are allocated", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);

    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.withdraw({ account: buyer.account }),
      contract,
      "NothingToWithdraw",
      [buyer.account.address],
    );
  });

  it("lets only the seller cancel before the delivery deadline", async function () {
    const { contract, deliveryDeadline } =
      await networkHelpers.loadFixture(deployEscrow);

    for (const caller of [buyer, arbiter, outsider]) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.cancelBySeller({ account: caller.account }),
        contract,
        "Unauthorized",
        [caller.account.address],
      );
    }

    await networkHelpers.time.setNextBlockTimestamp(deliveryDeadline - 1n);
    await viem.assertions.emitWithArgs(
      contract.write.cancelBySeller({ account: seller.account }),
      contract,
      "EscrowCancelled",
      [seller.account.address, buyer.account.address, DEPOSIT],
    );
    assert.equal(await contract.read.state(), 5);
    assert.equal(
      await contract.read.pendingWithdrawals([buyer.account.address]),
      DEPOSIT,
    );
  });

  it("rejects cancellation at or after the delivery deadline", async function () {
    const { contract, deliveryDeadline } =
      await networkHelpers.loadFixture(deployEscrow);

    for (const offset of [0n, 1n]) {
      const snapshot = await networkHelpers.takeSnapshot();
      const timestamp = deliveryDeadline + offset;
      await networkHelpers.time.setNextBlockTimestamp(timestamp);
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.cancelBySeller({ account: seller.account }),
        contract,
        "DeadlinePassed",
        [timestamp, deliveryDeadline],
      );
      await snapshot.restore();
    }
  });

  it("refunds the buyer at or after the delivery deadline", async function () {
    const { contract, deliveryDeadline } =
      await networkHelpers.loadFixture(deployEscrow);

    const beforeDeadline = await networkHelpers.takeSnapshot();
    await networkHelpers.time.setNextBlockTimestamp(deliveryDeadline - 1n);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.refundAfterDeliveryTimeout({
        account: outsider.account,
      }),
      contract,
      "DeadlineNotReached",
      [deliveryDeadline - 1n, deliveryDeadline],
    );
    await beforeDeadline.restore();

    for (const offset of [0n, 1n]) {
      const snapshot = await networkHelpers.takeSnapshot();
      await networkHelpers.time.setNextBlockTimestamp(
        deliveryDeadline + offset,
      );
      await viem.assertions.emitWithArgs(
        contract.write.refundAfterDeliveryTimeout({
          account: outsider.account,
        }),
        contract,
        "EscrowRefunded",
        [buyer.account.address, DEPOSIT],
      );
      assert.equal(await contract.read.state(), 4);
      assert.equal(
        await contract.read.pendingWithdrawals([buyer.account.address]),
        DEPOSIT,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([outsider.account.address]),
        0n,
      );
      await snapshot.restore();
    }
  });

  it("pays the seller at or after the review deadline", async function () {
    const { contract, reviewDeadline } =
      await networkHelpers.loadFixture(deliverEscrow);

    const beforeDeadline = await networkHelpers.takeSnapshot();
    await networkHelpers.time.setNextBlockTimestamp(reviewDeadline - 1n);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.claimAfterReviewTimeout({
        account: outsider.account,
      }),
      contract,
      "DeadlineNotReached",
      [reviewDeadline - 1n, reviewDeadline],
    );
    await beforeDeadline.restore();

    for (const offset of [0n, 1n]) {
      const snapshot = await networkHelpers.takeSnapshot();
      await networkHelpers.time.setNextBlockTimestamp(reviewDeadline + offset);
      await viem.assertions.emitWithArgs(
        contract.write.claimAfterReviewTimeout({
          account: outsider.account,
        }),
        contract,
        "ReviewTimeoutClaimed",
        [seller.account.address, DEPOSIT],
      );
      assert.equal(await contract.read.state(), 3);
      assert.equal(
        await contract.read.pendingWithdrawals([seller.account.address]),
        DEPOSIT,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([outsider.account.address]),
        0n,
      );
      await snapshot.restore();
    }
  });

  it("lets only the buyer open a dispute before the review deadline", async function () {
    const { contract, reviewDeadline } =
      await networkHelpers.loadFixture(deliverEscrow);

    for (const caller of [seller, arbiter, outsider]) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.openDispute({ account: caller.account }),
        contract,
        "Unauthorized",
        [caller.account.address],
      );
    }

    const hash = await contract.write.openDispute({ account: buyer.account });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const block = await publicClient.getBlock({
      blockNumber: receipt.blockNumber,
    });
    const disputedAt = block.timestamp;
    const arbitrationDeadline = disputedAt + ARBITRATION_PERIOD;
    const [opened] = parseEventLogs({
      abi: contract.abi,
      logs: receipt.logs,
      eventName: "DisputeOpened",
    });

    assert.ok(disputedAt < reviewDeadline);
    assert.equal(await contract.read.state(), 2);
    assert.equal(await contract.read.disputedAt(), disputedAt);
    assert.equal(
      await contract.read.arbitrationDeadline(),
      arbitrationDeadline,
    );
    assert.deepEqual(opened?.args, {
      buyer: getAddress(buyer.account.address),
      disputedAt,
      arbitrationDeadline,
    });
    assert.equal(
      await contract.read.pendingWithdrawals([arbiter.account.address]),
      0n,
    );
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.openDispute({ account: buyer.account }),
      contract,
      "InvalidState",
      [2, 1],
    );
  });

  it("rejects disputes before delivery or at the review deadline", async function () {
    const { contract } = await networkHelpers.loadFixture(deployEscrow);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.openDispute({ account: buyer.account }),
      contract,
      "InvalidState",
      [0, 1],
    );

    await contract.write.markDelivered({ account: seller.account });
    const reviewDeadline = await contract.read.reviewDeadline();
    await networkHelpers.time.setNextBlockTimestamp(reviewDeadline);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.openDispute({ account: buyer.account }),
      contract,
      "DeadlinePassed",
      [reviewDeadline, reviewDeadline],
    );
  });

  it("lets only the arbiter resolve a live dispute", async function () {
    const { contract } = await networkHelpers.loadFixture(disputeEscrow);

    for (const caller of [buyer, seller, outsider]) {
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.resolveDispute([true], { account: caller.account }),
        contract,
        "Unauthorized",
        [caller.account.address],
      );
    }
  });

  it("resolves the full deposit to either party only once", async function () {
    const { contract } = await networkHelpers.loadFixture(disputeEscrow);

    for (const releaseToSeller of [true, false]) {
      const snapshot = await networkHelpers.takeSnapshot();
      const recipient = releaseToSeller ? seller : buyer;
      const otherParty = releaseToSeller ? buyer : seller;
      const terminalState = releaseToSeller ? 3 : 4;

      await viem.assertions.emitWithArgs(
        contract.write.resolveDispute([releaseToSeller], {
          account: arbiter.account,
        }),
        contract,
        "DisputeResolved",
        [
          arbiter.account.address,
          recipient.account.address,
          DEPOSIT,
          releaseToSeller,
        ],
      );
      assert.equal(await contract.read.state(), terminalState);
      assert.equal(
        await contract.read.pendingWithdrawals([recipient.account.address]),
        DEPOSIT,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([otherParty.account.address]),
        0n,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([arbiter.account.address]),
        0n,
      );
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.resolveDispute([releaseToSeller], {
          account: arbiter.account,
        }),
        contract,
        "InvalidState",
        [terminalState, 2],
      );
      await snapshot.restore();
    }
  });

  it("rejects arbitration at or after its deadline", async function () {
    const { contract, arbitrationDeadline } =
      await networkHelpers.loadFixture(disputeEscrow);

    for (const offset of [0n, 1n]) {
      const snapshot = await networkHelpers.takeSnapshot();
      const timestamp = arbitrationDeadline + offset;
      await networkHelpers.time.setNextBlockTimestamp(timestamp);
      await viem.assertions.revertWithCustomErrorWithArgs(
        contract.write.resolveDispute([true], { account: arbiter.account }),
        contract,
        "DeadlinePassed",
        [timestamp, arbitrationDeadline],
      );
      await snapshot.restore();
    }
  });

  it("refunds the buyer when arbitration times out", async function () {
    const { contract, arbitrationDeadline } =
      await networkHelpers.loadFixture(disputeEscrow);

    const beforeDeadline = await networkHelpers.takeSnapshot();
    await networkHelpers.time.setNextBlockTimestamp(arbitrationDeadline - 1n);
    await viem.assertions.revertWithCustomErrorWithArgs(
      contract.write.refundAfterArbitrationTimeout({
        account: outsider.account,
      }),
      contract,
      "DeadlineNotReached",
      [arbitrationDeadline - 1n, arbitrationDeadline],
    );
    await beforeDeadline.restore();

    for (const offset of [0n, 1n]) {
      const snapshot = await networkHelpers.takeSnapshot();
      await networkHelpers.time.setNextBlockTimestamp(
        arbitrationDeadline + offset,
      );
      await viem.assertions.emitWithArgs(
        contract.write.refundAfterArbitrationTimeout({
          account: outsider.account,
        }),
        contract,
        "EscrowRefunded",
        [buyer.account.address, DEPOSIT],
      );
      assert.equal(await contract.read.state(), 4);
      assert.equal(
        await contract.read.pendingWithdrawals([buyer.account.address]),
        DEPOSIT,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([arbiter.account.address]),
        0n,
      );
      assert.equal(
        await contract.read.pendingWithdrawals([outsider.account.address]),
        0n,
      );
      await snapshot.restore();
    }
  });

  it("keeps every terminal state final", async function () {
    const terminalFixtures = [
      [completeEscrow, 3],
      [refundEscrow, 4],
      [cancelEscrow, 5],
    ] as const;

    for (const [fixture, terminalState] of terminalFixtures) {
      const { contract } = await networkHelpers.loadFixture(fixture);
      const calls = [
        [
          () => contract.write.cancelBySeller({ account: seller.account }),
          0,
        ],
        [() => contract.write.markDelivered({ account: seller.account }), 0],
        [() => contract.write.approveDelivery({ account: buyer.account }), 1],
        [() => contract.write.refundAfterDeliveryTimeout(), 0],
        [() => contract.write.claimAfterReviewTimeout(), 1],
        [() => contract.write.openDispute({ account: buyer.account }), 1],
        [
          () =>
            contract.write.resolveDispute([true], {
              account: arbiter.account,
            }),
          2,
        ],
        [() => contract.write.refundAfterArbitrationTimeout(), 2],
      ] as const;

      for (const [call, expectedState] of calls) {
        await viem.assertions.revertWithCustomErrorWithArgs(
          call(),
          contract,
          "InvalidState",
          [terminalState, expectedState],
        );
      }
      assert.equal(await contract.read.state(), terminalState);
    }
  });
});
