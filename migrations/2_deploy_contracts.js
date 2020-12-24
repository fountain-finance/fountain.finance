// const ConvertLib = artifacts.require("ConvertLib");
// const MetaCoin = artifacts.require("MetaCoin");
const Fountain = artifacts.require("FountainV1");
const Water = artifacts.require("Water");

module.exports = function (deployer, network, accounts) {
  const erc20Address = accounts[3];
  // deployer.deploy(ConvertLib);
  deployer.deploy(Fountain, erc20Address);
  // deployer.link(ConvertLib, MetaCoin);
  // deployer.deploy(MetaCoin);
  deployer.deploy(Water);
};
