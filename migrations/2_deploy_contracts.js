// const ConvertLib = artifacts.require("ConvertLib");
// const MetaCoin = artifacts.require("MetaCoin");
const Fountain = artifacts.require("Fountain");

module.exports = function (deployer) {
  // deployer.deploy(ConvertLib);
  deployer.deploy(Fountain);
  // deployer.link(ConvertLib, MetaCoin);
  // deployer.deploy(MetaCoin);
};
