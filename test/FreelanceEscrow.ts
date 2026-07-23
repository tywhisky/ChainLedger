import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, parseEventLogs, zeroAddress } from "viem";

describe("FreelanceEscrow constructor", async function () {
  const { viem, networkHelpers } = await network.create();
  const [buyer, seller, arbiter] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();
  const decoder = await viem.getContractAt("FreelanceEscrow", zeroAddress);

  const DEPOSIT = 1n * 10n ** 18n;
  const DAY = 24n * 60n * 60n;
  const REVIEW_PERIOD = 3n * DAY;
  const ARBITRATION_PERIOD = 5n * DAY;

  async function validArgs() {
    const deadline = BigInt(await networkHelpers.time.latest()) + 7n * DAY;

    return [
      seller.account.address,
      arbiter.account.address,
      deadline,
      REVIEW_PERIOD,
      ARBITRATION_PERIOD,
    ] as const;
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
    assert.equal(await contract.read.deliveryDeadline(), args[2]);
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
      deliveryDeadline: args[2],
    });
  });

  it("rejects a zero deposit", async function () {
    await viem.assertions.revertWithCustomError(
      viem.deployContract("FreelanceEscrow", await validArgs()),
      decoder,
      "ZeroDeposit",
    );
  });

  it("rejects a zero seller address", async function () {
    const [, arbiterAddress, deadline, reviewPeriod, arbitrationPeriod] =
      await validArgs();

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
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
    const [sellerAddress, , deadline, reviewPeriod, arbitrationPeriod] =
      await validArgs();

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
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
    const [, , deadline, reviewPeriod, arbitrationPeriod] = await validArgs();
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
    const [sellerAddress, arbiterAddress, , reviewPeriod, arbitrationPeriod] =
      await validArgs();
    const deadline = BigInt(await networkHelpers.time.latest());

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
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
    const [sellerAddress, arbiterAddress, , reviewPeriod, arbitrationPeriod] =
      await validArgs();
    const deadline = BigInt(await networkHelpers.time.latest()) + 1n;
    await networkHelpers.time.setNextBlockTimestamp(deadline);

    await viem.assertions.revertWithCustomErrorWithArgs(
      viem.deployContract(
        "FreelanceEscrow",
        [
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
    const [sellerAddress, arbiterAddress, deadline, , arbitrationPeriod] =
      await validArgs();

    await viem.assertions.revertWithCustomError(
      viem.deployContract(
        "FreelanceEscrow",
        [sellerAddress, arbiterAddress, deadline, 0n, arbitrationPeriod],
        { value: DEPOSIT },
      ),
      decoder,
      "InvalidReviewPeriod",
    );
  });

  it("rejects a zero arbitration period", async function () {
    const [sellerAddress, arbiterAddress, deadline, reviewPeriod] =
      await validArgs();

    await viem.assertions.revertWithCustomError(
      viem.deployContract(
        "FreelanceEscrow",
        [sellerAddress, arbiterAddress, deadline, reviewPeriod, 0n],
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
});
