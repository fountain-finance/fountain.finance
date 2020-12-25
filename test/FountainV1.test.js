const Fountain = artifacts.require("FountainV1");
const truffleAssert = require("truffle-assertions");
const MockContract = artifacts.require("./MockContract.sol");
const {
  assertMoneyPoolCount,
  assertDuration,
  assertSustainabilityTarget,
  assertSustainerCount,
  assertInitializeMoneyPoolEvent,
  assertActivateMoneyPoolEvent,
  assertConfigureMoneyPoolEvent,
  assertSustainMoneyPoolEvent,
  assertBalance,
  assertSustainmentAmount,
  assertRedistributionTrackerAmount,
  assertSustainabilityPoolAmount,
  assertRedistributionPoolAmount,
  assertSustainedAddresses,
} = require("../test-helpers/assertions.js");

// TODO: document owner, creator, sustainer
// owner: the address that deploys the Fountain contract
// creator: an address that creates a MoneyPool
// sustainer: an address that sustains a MoneyPool
contract("Fountain", ([owner, creator, sustainer]) => {
  let fountain;
  // let DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  let erc20Mock;

  describe("constructor", async () => {
    beforeEach(async () => {
      // Instantiate mock and make it return true for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(true);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
      // fountain = await Fountain.deployed(); // reuse same instance each test
    });

    it("initially has no MoneyPools", async () => {
      assert.equal(await fountain.mpCount(), 0);
    });

    it("stores expected address for DAI", async () => {
      assert.equal(await fountain.DAI(), erc20Mock.address);
    });
  });

  describe("initialize Money pool", async () => {
    beforeEach(async () => {
      // Instantiate mock and make it return true for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(true);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
    });

    it("initializes Money pool for an uninitialized address", async () => {
      const target = 100;
      const duration = 30;
      const result = await fountain.configureMp(
        target,
        duration,
        erc20Mock.address,
        {
          from: creator,
        }
      );
      await assertSustainabilityTarget(
        fountain,
        creator,
        target,
        "Invalid sustainability target"
      );
      await assertDuration(fountain, creator, duration, "Invalid duration");
      await assertMoneyPoolCount(
        fountain,
        1,
        "Only one Money pool should exist"
      );
      await assertInitializeMoneyPoolEvent(
        result, 
        fountain, 
        creator, 
        "Invalid InitializeMp event"
      );
      await assertConfigureMoneyPoolEvent(
        result, 
        fountain, 
        creator, 
        target, 
        duration, 
        erc20Mock.address,
        "Invalid ConfigureMp event"
      );
    });
  });

  describe("updates Money pool when it has not been sustained", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      // Instantiate mock and make it return true for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(true);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
      await fountain.configureMp(
        initialTarget,
        initialDuration,
        erc20Mock.address,
        {
          from: creator,
        }
      );
    });

    it("configures existing MoneyPool", async () => {
      const target = 200;
      const duration = 50;
      const result = await fountain.configureMp(
        target,
        duration,
        erc20Mock.address,
        {
          // Using address that has already created a MoneyPool
          from: creator,
        }
      );
      await assertConfigureMoneyPoolEvent(
        result, 
        fountain, 
        creator, 
        target, 
        duration, 
        erc20Mock.address,
        "Invalid ConfigureMp event"
      );
      await assertSustainabilityTarget(
        fountain,
        creator,
        target,
        "Invalid sustainability target"
      );
      await assertDuration(fountain, creator, duration, "Invalid duration");
      await assertMoneyPoolCount(
        fountain,
        1,
        "Only one Money pool should exist"
      );
    });
  });

  describe("sustain", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      // Instantiate mock and make it return true for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(true);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
      await fountain.configureMp(
        initialTarget,
        initialDuration,
        erc20Mock.address,
        {
          from: creator,
        }
      );
    });

    // when there is an active money pool (tests getActiveMoneyPoolId)
    // when there is no active money pool but there is a upcoming money pool (tests getUpcomingMoneyPoolId)
    // when there is no upcoming money pool and the latest pool is cloned (tests createMoneyPoolFromId)

    const scenarios = [
      {
        description: "sustainment less than target",
        amount: 10,
        expectedCurrentSustainment: 10,
        expectedSustainmentAmount: 10,
        expectedRedistributionTrackerAmount: 0,
        expectedSustainabilityPoolAmount: 10,
        expectedRedistributionPoolAmount: 0,
        expectedSustainerCount: 1,
        expectedSustainedAddresses: [creator],
      },
      {
        description: "sustainment equal to target",
        amount: 100,
        expectedCurrentSustainment: 100,
        expectedSustainmentAmount: 100,
        expectedRedistributionTrackerAmount: 0,
        expectedSustainabilityPoolAmount: 100,
        expectedRedistributionPoolAmount: 0,
        expectedSustainerCount: 1,
        expectedSustainedAddresses: [creator],
      },
      {
        description: "sustainment greater than target",
        amount: 150,
        expectedCurrentSustainment: 150,
        expectedSustainmentAmount: 150,
        expectedRedistributionTrackerAmount: 50,
        expectedSustainabilityPoolAmount: 100,
        expectedRedistributionPoolAmount: 0, // Redistribution hasn't triggered yet
        expectedSustainerCount: 1,
        expectedSustainedAddresses: [creator],
      },
    ];

    scenarios.forEach((scenario) => {
      it(`sustains existing money pool when ${scenario.description}`, async () => {
        const result = await fountain.sustain(creator, scenario.amount, {
          // Using address that did not create the MoneyPool
          from: sustainer,
        });
        await assertSustainMoneyPoolEvent(
          result, 
          fountain, 
          creator,
          sustainer, 
          "Invalid SustainMp event"
        );
        await assertActivateMoneyPoolEvent(
          result, 
          fountain, 
          creator, 
          initialTarget, 
          initialDuration, 
          erc20Mock.address,
          "Invalid ActivateMp event"
        );
        await assertBalance(
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
        await assertSustainmentAmount(
          fountain,
          creator,
          sustainer,
          scenario.expectedSustainmentAmount,
          "Invalid sustainment amount"
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
        await assertSustainedAddresses(
          fountain,
          sustainer,
          scenario.expectedSustainedAddresses,
          "Invalid sustainedAddressCount amount"
        );
      });
    });

    it("fails when sustainment amount is not a positive amount", async () => {
      const amount = 0;
      await truffleAssert.fails(
        // Using "creator" address which has a moneyPool
        fountain.sustain(creator, amount, {
          // Using address that did not create the MoneyPool
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });

    it("fails when no moneyPool found at address", async () => {
      const amount = 10;
      await truffleAssert.fails(
        // Using "owner" address which does not have a moneyPool
        fountain.sustain(owner, amount, {
          // Using address that did not create the MoneyPool
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });
  });

  describe("withdrawRedistributions", async () => {});

  describe("withdrawSustainments", async () => {});

  describe("ERC20 failure conditions", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      // Instantiate mock and make it return false for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(false);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
      await fountain.configureMp(
        initialTarget,
        initialDuration,
        erc20Mock.address,
        {
          from: creator,
        }
      );
    });

    it("sustain fails when ERC20.transferFrom fails", async () => {
      const amount = 10;
      await truffleAssert.fails(
        // Using "creator" address which has a moneyPool
        fountain.sustain(creator, amount, {
          // Using address that did not create the MoneyPool
          from: sustainer,
        }),
        truffleAssert.ErrorType.REVERT
      );
    });
  });

  describe("Permissions failure conditions", async () => {
    const initialTarget = 100;
    const initialDuration = 30;

    beforeEach(async () => {
      // Instantiate mock and make it return false for any invocation
      erc20Mock = await MockContract.new();
      await erc20Mock.givenAnyReturnBool(true);
      // instantiate Fountain with mocked contract
      fountain = await Fountain.new(erc20Mock.address); // create new instance each test
      await fountain.configureMp(
        initialTarget,
        initialDuration,
        erc20Mock.address,
        {
          from: creator,
        }
      );
    });

    it("Balance not available to address other than owner", async () => {
      const amount = 123;
      fountain.sustain(creator, amount, {
        // Using address that did not create the MoneyPool
        from: sustainer,
      }),
      await assertBalance(
        fountain,
        creator,
        amount,
        "Invalid access to Money pool balance"
      );
      await assertBalance(
        fountain,
        creator,
        0,
        "Invalid access to Money pool balance",
        sustainer
      );
    });
  });

  // // it("should contribute correctly", async () => {
  // //   const instance = await Fountain.deployed();
  // //   await instance.contribute(accounts[0], 10, { from: accounts[1] });
  // //   const contribution = (
  // //     await instance.getContribution.call(accounts[0], accounts[1])
  // //   ).toNumber();
  // //   // const accountOne = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();

  // //   assert.equal(contribution, 10, "hmm");
  // // });
  // // it('should call a function that depends on a linked library', async () => {
  // //   const metaCoinInstance = await MetaCoin.deployed();
  // //   const metaCoinBalance = (await metaCoinInstance.getBalance.call(accounts[0])).toNumber();
  // //   const metaCoinEthBalance = (await metaCoinInstance.getBalanceInEth.call(accounts[0])).toNumber();

  // //   assert.equal(metaCoinEthBalance, 2 * metaCoinBalance, 'Library function returned unexpected function, linkage may be broken');
  // // });
  // // it('should send coin correctly', async () => {
  // //   const metaCoinInstance = await MetaCoin.deployed();

  // //   // Setup 2 accounts.
  // //   const accountOne = accounts[0];
  // //   const accountTwo = accounts[1];

  // //   // Get initial balances of first and second account.
  // //   const accountOneStartingBalance = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();
  // //   const accountTwoStartingBalance = (await metaCoinInstance.getBalance.call(accountTwo)).toNumber();

  // //   // Make transaction from first account to second.
  // //   const amount = 10;
  // //   await metaCoinInstance.sendCoin(accountTwo, amount, { from: accountOne });

  // //   // Get balances of first and second account after the transactions.
  // //   const accountOneEndingBalance = (await metaCoinInstance.getBalance.call(accountOne)).toNumber();
  // //   const accountTwoEndingBalance = (await metaCoinInstance.getBalance.call(accountTwo)).toNumber();

  // //   assert.equal(accountOneEndingBalance, accountOneStartingBalance - amount, "Amount wasn't correctly taken from the sender");
  // //   assert.equal(accountTwoEndingBalance, accountTwoStartingBalance + amount, "Amount wasn't correctly sent to the receiver");
  // // });
});
