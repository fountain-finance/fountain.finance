const Fountain = artifacts.require("FountainV1");
const truffleAssert = require("truffle-assertions");

const assertPurposeCount = async (instance, count, message) => {
  const currentCount = (await instance.purposeCount()).toNumber();
  assert.equal(currentCount, count, message);
};

const assertDuration = async (instance, address, duration, message) => {
  const currentDuration = (await instance.getDuration(address)).toNumber();
  assert.equal(currentDuration, duration, message);
};

const assertSustainabilityTarget = async (
  instance,
  address,
  target,
  message
) => {
  const currentTarget = (
    await instance.getSustainabilityTarget(address)
  ).toNumber();
  assert.equal(currentTarget, target, message);
};

const assertSustainerCount = async (instance, address, count, message) => {
  const sustainerCount = (await instance.getSustainerCount(address)).toNumber();
  assert.equal(sustainerCount, count, message);
};

const assertCurrentSustainment = async (instance, address, amount, message) => {
  const currentSustainment = (
    await instance.getCurrentSustainment(address)
  ).toNumber();
  assert.equal(currentSustainment, amount, message);
};

const assertSustainmentTrackerAmount = async (
  instance,
  address,
  by,
  amount,
  message
) => {
  const currentAmount = (
    await instance.getSustainmentTrackerAmount(address, by)
  ).toNumber();
  assert.equal(currentAmount, amount, message);
};

const assertRedistributionTrackerAmount = async (
  instance,
  address,
  by,
  amount,
  message
) => {
  const currentAmount = (
    await instance.getRedistributionTrackerAmount(address, by)
  ).toNumber();
  assert.equal(currentAmount, amount, message);
};

const assertSustainabilityPoolAmount = async (
  instance,
  address,
  amount,
  message
) => {
  const currentAmount = (
    await instance.getSustainabilityPool(address)
  ).toNumber();
  assert.equal(currentAmount, amount, message);
};

const assertRedistributionPoolAmount = async (
  instance,
  address,
  amount,
  message
) => {
  const currentAmount = (
    await instance.getRedistributionPool(address)
  ).toNumber();
  assert.equal(currentAmount, amount, message);
};

const assertSustainedAddressCount = async (
  instance,
  address,
  count,
  message
) => {
  const currentCount = (
    await instance.getSustainedAddressCount(address)
  ).toNumber();
  assert.equal(currentCount, count, message);
};

// TODO: document owner, creator, sustainer
// owner: the address that deploys the Fountain contract
// creator: an address that creates a Purpose
// sustainer: an address that sustains a Purpose
contract("Fountain", ([owner, creator, sustainer]) => {
  let fountain;
  let DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

  describe("constructor", async () => {
    beforeEach(async () => {
      fountain = await Fountain.new(); // create new instance each test
      // fountain = await Fountain.deployed(); // reuse same instance each test
    });

    it("initially has no purposes", async () => {
      assert.equal(await fountain.purposeCount(), 0);
    });

    it("stores expected address for DAI", async () => {
      assert.equal(await fountain.DAI(), DAI);
    });
  });

  describe("createPurpose", async () => {
    beforeEach(async () => {
      fountain = await Fountain.new();
    });

    it("initializes purpose for an uninitialized address", async () => {
      const target = 100;
      const duration = 30;
      const result = await fountain.createPurpose(target, duration, {
        from: creator,
      });
      await assertSustainabilityTarget(
        fountain,
        creator,
        target,
        "Invalid sustainability target"
      );
      await assertDuration(fountain, creator, duration, "Invalid duration");
      await assertPurposeCount(fountain, 1, "Only one purpose should exist");
      truffleAssert.eventEmitted(result, "PurposeCreated");
    });

    it("fails to initialize purpose for already initialized address", async () => {
      const target = 100;
      const duration = 30;
      await fountain.createPurpose(target, duration, {
        from: creator,
      });
      const result = fountain.createPurpose(target, duration, {
        from: creator,
      });
      truffleAssert.fails(result, truffleAssert.ErrorType.REVERT);
    });
  });

  describe("updatePurpose when purpose has not been sustained", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      fountain = await Fountain.new(); // create new instance each test
      await fountain.createPurpose(initialTarget, initialDuration, {
        from: creator,
      });
    });

    it("updates existing purpose", async () => {
      const target = 200;
      const duration = 50;
      const result = await fountain.updatePurpose(target, duration, {
        // Using address that has already created a purpose
        from: creator,
      });
      truffleAssert.eventEmitted(result, "PurposeUpdated", {
        // Including params doesn't work, tried with various param numbers.
        // `AssertionError: Event filter for PurposeUpdated returned no results`.
        // param3: target,
        // param4: duration,
      });

      await assertSustainabilityTarget(
        fountain,
        creator,
        target,
        "Invalid sustainability target"
      );
      await assertDuration(fountain, creator, duration, "Invalid duration");
      await assertPurposeCount(fountain, 1, "Only one purpose should exist");
    });

    it("fail when no purpose has been created", async () => {
      const target = 100;
      const duration = 30;
      await truffleAssert.fails(
        fountain.updatePurpose(target, duration, {
          // Using address that has not created a purpose
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });
  });

  describe("sustain", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      fountain = await Fountain.new(); // create new instance each test
      await fountain.createPurpose(initialTarget, initialDuration, {
        from: creator,
      });
    });

    const scenarios = [
      {
        description: "sustainment less than target",
        amount: 10,
        expectedCurrentSustainment: 10,
        expectedSustainmentTrackerAmount: 10,
        expectedRedistributionTrackerAmount: 0,
        expectedSustainabilityPoolAmount: 10,
        expectedRedistributionPoolAmount: 0,
        expectedSustainerCount: 1,
        expectedSustainedAddressCount: 1,
      },
      {
        description: "sustainment equal to target",
        amount: 100,
        expectedCurrentSustainment: 100,
        expectedSustainmentTrackerAmount: 100,
        expectedRedistributionTrackerAmount: 0,
        expectedSustainabilityPoolAmount: 100,
        expectedRedistributionPoolAmount: 0,
        expectedSustainerCount: 1,
        expectedSustainedAddressCount: 1,
      },
      {
        description: "sustainment greater than target",
        amount: 150,
        expectedCurrentSustainment: 150,
        expectedSustainmentTrackerAmount: 150,
        expectedRedistributionTrackerAmount: 50,
        expectedSustainabilityPoolAmount: 100,
        expectedRedistributionPoolAmount: 0, // Redistribution hasn't triggered yet
        expectedSustainerCount: 1,
        expectedSustainedAddressCount: 1,
      },
    ];

    scenarios.forEach((scenario) => {
      it(`sustains existing purpose - ${scenario.description}`, async () => {
        const result = await fountain.sustain(creator, scenario.amount, {
          // Using address that did not create the purpose
          from: sustainer,
        });
        truffleAssert.eventEmitted(result, "PurposeSustained");

        await assertCurrentSustainment(
          fountain,
          creator,
          scenario.expectedCurrentSustainment,
          "Invalid currentSustainment"
        );
        await assertSustainerCount(
          fountain,
          creator,
          scenario.expectedSustainerCount,
          "Invalid sustainerCount"
        );
        await assertSustainmentTrackerAmount(
          fountain,
          creator,
          sustainer,
          scenario.expectedSustainmentTrackerAmount,
          "Invalid sustainmentTracker amount"
        );
        await assertRedistributionTrackerAmount(
          fountain,
          creator,
          sustainer,
          scenario.expectedRedistributionTrackerAmount,
          "Invalid redistributionTracker amount"
        );
        await assertSustainabilityPoolAmount(
          fountain,
          creator,
          scenario.expectedSustainabilityPoolAmount,
          "Invalid sustainabilityPool amount"
        );
        await assertRedistributionPoolAmount(
          fountain,
          creator,
          scenario.expectedRedistributionPoolAmount,
          "Invalid redistributionPool amount"
        );
        await assertSustainedAddressCount(
          fountain,
          sustainer,
          scenario.expectedSustainedAddressCount,
          "Invalid sustainedAddressCount amount"
        );
      });
    });

    it("fails when sustainment amount is not a positive amount", async () => {
      const amount = 0;
      await truffleAssert.fails(
        fountain.sustain(creator, amount, {
          // Using address that did not create the purpose
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("fails when no purpose found at address", async () => {
      const amount = 10;
      await truffleAssert.fails(
        fountain.sustain(owner, amount, {
          // Using address that did not create the purpose
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });
  });

  // it("should contribute correctly", async () => {
  //   const instance = await Fountain.deployed();
  //   await instance.contribute(accounts[0], 10, { from: accounts[1] });
  //   const contribution = (
  //     await instance.getContribution.call(accounts[0], accounts[1])
  //   ).toNumber();
  //   // const accountOne = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();

  //   assert.equal(contribution, 10, "hmm");
  // });
  // it('should call a function that depends on a linked library', async () => {
  //   const metaCoinInstance = await MetaCoin.deployed();
  //   const metaCoinBalance = (await metaCoinInstance.getBalance.call(accounts[0])).toNumber();
  //   const metaCoinEthBalance = (await metaCoinInstance.getBalanceInEth.call(accounts[0])).toNumber();

  //   assert.equal(metaCoinEthBalance, 2 * metaCoinBalance, 'Library function returned unexpected function, linkage may be broken');
  // });
  // it('should send coin correctly', async () => {
  //   const metaCoinInstance = await MetaCoin.deployed();

  //   // Setup 2 accounts.
  //   const accountOne = accounts[0];
  //   const accountTwo = accounts[1];

  //   // Get initial balances of first and second account.
  //   const accountOneStartingBalance = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();
  //   const accountTwoStartingBalance = (await metaCoinInstance.getBalance.call(accountTwo)).toNumber();

  //   // Make transaction from first account to second.
  //   const amount = 10;
  //   await metaCoinInstance.sendCoin(accountTwo, amount, { from: accountOne });

  //   // Get balances of first and second account after the transactions.
  //   const accountOneEndingBalance = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();
  //   const accountTwoEndingBalance = (await metaCoinInstance.getBalance.call(accountTwo)).toNumber();

  //   assert.equal(accountOneEndingBalance, accountOneStartingBalance - amount, "Amount wasn't correctly taken from the sender");
  //   assert.equal(accountTwoEndingBalance, accountTwoStartingBalance + amount, "Amount wasn't correctly sent to the receiver");
  // });
});
