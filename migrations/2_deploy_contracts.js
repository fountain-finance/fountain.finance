const Fountain = artifacts.require("Fountain");

// Dynamically obtain DAI contract address based on deployment network (mainnet address is different than ropsten)
const DAI = {
  live: "0x6b175474e89094c44da98b954eedeac495271d0f",
  ropsten: "0xad6d458402f60fd3bd25163575031acdce07538d",
};

module.exports = function (deployer, network, accounts) {
  deployer.deploy(Fountain, DAI[network] || accounts[3]);
};

