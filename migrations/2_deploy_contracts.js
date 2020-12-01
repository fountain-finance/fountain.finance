// const ConvertLib = artifacts.require("ConvertLib");
// const MetaCoin = artifacts.require("MetaCoin");
const Fountain = artifacts.require("FountainV1");

module.exports = function (deployer, network, accounts) {
  const daiAddress = accounts[3];
  // deployer.deploy(ConvertLib);
  deployer.deploy(Fountain, daiAddress);
  // deployer.link(ConvertLib, MetaCoin);
  // deployer.deploy(MetaCoin);
};
