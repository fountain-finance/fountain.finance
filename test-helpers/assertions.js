const truffleAssert = require("truffle-assertions");

exports.assertMoneyPoolCount = async (instance, count, message) => {
  const currentCount = (await instance.moneyPoolCount()).toNumber();
  assert.equal(currentCount, count, message);
};

exports.assertDuration = async (instance, address, duration, message) => {
  const currentDuration = (
    await instance.moneyPools(
      (await instance.latestMoneyPoolIds(address)).toNumber()
    )
  ).duration.toNumber();
  assert.equal(currentDuration, duration, message);
};

exports.assertSustainabilityTarget = async (
  instance,
  address,
  target,
  message
) => {
  const currentTarget = (
    await instance.moneyPools(
      (await instance.latestMoneyPoolIds(address)).toNumber()
    )
  ).sustainabilityTarget.toNumber();
  assert.equal(currentTarget, target, message);
};

exports.assertSustainerCount = async (instance, address, count, message) => {
  const sustainerCount = (await instance.getSustainerCount(address)).toNumber();
  assert.equal(sustainerCount, count, message);
};

exports.assertInitializeMoneyPoolEvent = async (
  tx,
  instance,
  creator, 
  target, 
  duration, 
  want,
  message
) => {
  const currentCount = (await instance.moneyPoolCount()).toString();
  truffleAssert.eventEmitted(tx, "InitializeMoneyPool", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator
    )
  }, message);
};

exports.assertActivateMoneyPoolEvent = async (
  tx,
  instance,
  creator, 
  target, 
  duration, 
  want,
  message
) => {
  const currentCount = (await instance.moneyPoolCount()).toString();
  truffleAssert.eventEmitted(tx, "ActivateMoneyPool", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.sustainabilityTarget.toString() === target.toString() &&
      ev.duration.toString() === duration.toString() &&
      ev.want === want
    )
  }, message);
};

exports.assertConfigureMoneyPoolEvent = async (
  tx,
  instance,
  creator, 
  target, 
  duration, 
  want,
  message
) => {
  const currentCount = (await instance.moneyPoolCount()).toString();
  truffleAssert.eventEmitted(tx, "ConfigureMoneyPool", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.sustainabilityTarget.toString() === target.toString() &&
      ev.duration.toString() === duration.toString() &&
      ev.want === want
    )
  }, message);
};

exports.assertActivateMoneyPoolEvent = async (
  tx,
  instance,
  creator, 
  target, 
  duration, 
  want,
  message
) => {
  const currentCount = (await instance.moneyPoolCount()).toString();
  truffleAssert.eventEmitted(tx, "ActivateMoneyPool", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.sustainabilityTarget.toString() === target.toString() &&
      ev.duration.toString() === duration.toString() &&
      ev.want === want
    )
  }, message);
};

exports.assertSustainMoneyPoolEvent = async (
  tx,
  instance,
  sustainer,
  amount,
  message
) => {
  const currentCount = (await instance.moneyPoolCount()).toString();
  truffleAssert.eventEmitted(tx, "SustainMoneyPool", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.sustainer === sustainer &&
      ev.amount.toString() === amount.toString()
    )
  }, message);
};

exports.assertCurrentSustainment = async (
  instance,
  address,
  amount,
  message
) => {
  const currentSustainment = (
    await instance.moneyPools(
      (await instance.latestMoneyPoolIds(address)).toNumber()
    )
  ).currentSustainment.toNumber();
  assert.equal(currentSustainment, amount, message);
};

exports.assertSustainmentTrackerAmount = async (
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

exports.assertRedistributionTrackerAmount = async (
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

exports.assertSustainabilityPoolAmount = async (
  instance,
  address,
  amount,
  message
) => {
  const currentAmount = (await instance.sustainabilityPool(address)).toNumber();
  assert.equal(currentAmount, amount, message);
};

exports.assertRedistributionPoolAmount = async (
  instance,
  address,
  amount,
  message
) => {
  const currentAmount = (await instance.redistributionPool(address)).toNumber();
  assert.equal(currentAmount, amount, message);
};

exports.assertSustainedAddresses = async (
  instance,
  address,
  sustainedAddresses,
  message
) => {
  for (let i = 0; i < sustainedAddresses.length; i++) {
    const sustainedAddress = sustainedAddresses[i];
    const currentValue = await instance.sustainedAddressesBySustainer(
      address,
      i
    );
    assert.equal(currentValue, sustainedAddress, message);
  }
  truffleAssert.fails(
    instance.sustainedAddressesBySustainer(address, sustainedAddresses.length),
    truffleAssert.ErrorType.INVALID_OPCODE
  );
};
