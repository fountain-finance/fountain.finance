const Fountain = artifacts.require("Fountain");
const truffleAssert = require("truffle-assertions");

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

    it("should initialize a purpose for the address", async () => {
      const target = 100;
      const duration = 30;
      const result = await fountain.createPurpose(target, duration, {
        from: creator,
      });
      const updatedTarget = (
        await fountain.getSustainabilityTarget(creator)
      ).toNumber();
      const updatedDuration = (await fountain.getDuration(creator)).toNumber();
      assert.equal(updatedTarget, target, "Invalid sustainability target");
      assert.equal(updatedDuration, duration, "Invalid duration");
      assert.equal(
        (await fountain.purposeCount()).toNumber(),
        1,
        "Only one purpose should exist"
      );
      truffleAssert.eventEmitted(result, "PurposeCreated");
    });

    it("should fail to initialize a purpose for a non-owner", async () => {
      const target = 100;
      const duration = 30;
      const result = fountain.createPurpose(target, duration, {
        from: sustainer,
      });
      truffleAssert.fails(result, truffleAssert.ErrorType.REVERT);
      // truffleAssert.eventNotEmitted(result, "PurposeCreated");
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

    it("should update a purpose for the owner", async () => {
      const target = 200;
      const duration = 50;
      const result = await fountain.updatePurpose(target, duration, {
        from: creator,
      });
      const updatedTarget = (
        await fountain.getSustainabilityTarget(creator)
      ).toNumber();
      const updatedDuration = (await fountain.getDuration(creator)).toNumber();
      assert.equal(updatedTarget, target, "Invalid sustainability target");
      assert.equal(updatedDuration, duration, "Invalid duration");
      assert.equal(
        (await fountain.purposeCount()).toNumber(),
        1,
        "Only one purpose should exist"
      );
      truffleAssert.eventEmitted(result, "PurposeUpdated", {
        // sustainabilityTarget: target,
        // duration,
      });
    });

    it("should fail to update a purpose for a non-owner", async () => {
      const target = 100;
      const duration = 30;
      await truffleAssert.fails(
        fountain.updatePurpose(target, duration, {
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
