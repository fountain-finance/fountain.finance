const truffleAssert = require("truffle-assertions");

exports.assertMoneyPoolCount = async (instance, count, message) => {
  const currentCount = (await instance.mpCount()).toNumber();
  assert.equal(currentCount, count, message);
};

exports.assertDuration = async (instance, address, duration, message) => {
  const currentDuration = (
    await instance.getMp(
      (await instance.latestMpIds(address)).toNumber()
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
    await instance.getMp(
      (await instance.latestMpIds(address)).toNumber()
    )
  ).target.toNumber();
  assert.equal(currentTarget, target, message);
};

exports.assertSustainerCount = async (instance, address, count, message) => {
  const sustainerCount = (
    await instance.getMp(
      (await instance.latestMpIds(address)).toNumber()
    )
  ).sustainerCount;
  assert.equal(sustainerCount, count, message);
};

exports.assertInitializeMoneyPoolEvent = async (
  tx,
  instance,
  creator, 
  message
) => {
  const currentCount = (await instance.mpCount()).toString();
  truffleAssert.eventEmitted(tx, "InitializeMp", (ev) => {
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
  const currentCount = (await instance.mpCount()).toString();
  truffleAssert.eventEmitted(tx, "ActivateMp", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.target.toString() === target.toString() &&
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
  const currentCount = (await instance.mpCount()).toString();
  truffleAssert.eventEmitted(tx, "ConfigureMp", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.target.toString() === target.toString() &&
      ev.duration.toString() === duration.toString() &&
      ev.want === want
    )
  }, message);
};

exports.assertSustainMoneyPoolEvent = async (
  tx,
  instance,
  creator,
  beneficiary,
  sustainer,
  amount,
  message
) => {
  const currentCount = (await instance.mpCount()).toString();
  truffleAssert.eventEmitted(tx, "SustainMp", (ev) => {
    return (
      ev.id.toString() === currentCount &&
      ev.owner === creator &&
      ev.beneficiary === beneficiary &&
      ev.sustainer === sustainer &&
      ev.amount.toString() === amount.toString() 
    )
  }, message);
};

exports.assertBalance = async (
  instance,
  address,
  amount,
  message,
  from
) => {
  const currentSustainment = (
    await instance.getMp(
      (await instance.latestMpIds(address)).toNumber(), {
        from: from || address
      }
    )
  ).balance.toNumber();
  assert.equal(currentSustainment, amount, message);
};

exports.assertSustainmentAmount = async (
  instance,
  address,
  sustainer,
  amount,
  message,
  from
) => {
  const currentAmount = (
    await instance.getSustainment((await instance.latestMpIds(address)).toNumber(), sustainer, {
      from: from || address
    }
  )).toNumber();
  assert.equal(currentAmount, amount, message);
};

exports.assertRedistributionTrackerAmount = async (
  instance,
  address,
  sustainer,
  amount,
  message
) => {
  const currentAmount = (
    await instance.getTrackedRedistribution((await instance.latestMpIds(address)).toNumber(), sustainer, {
      from: address
    }
  )).toNumber();
  assert.equal(currentAmount, amount, message);
};

exports.assertSustainabilityPoolAmount = async (
  instance,
  address,
  amount,
  message
) => {
  const currentAmount = (await instance.getSustainmentBalance(address, { from: address })).toNumber();
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
    const currentValue = await instance.sustainedAddresses(
      address,
      i
    );
    assert.equal(currentValue, sustainedAddress, message);
  }
  truffleAssert.fails(
    instance.sustainedAddresses(address, sustainedAddresses.length),
    truffleAssert.ErrorType.INVALID_OPCODE
  );
};
