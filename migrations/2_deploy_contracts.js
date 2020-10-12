// const ConvertLib = artifacts.require("ConvertLib");
// const MetaCoin = artifacts.require("MetaCoin");
const Sustainers = artifacts.require("Sustainers");

module.exports = function(deployer) {
  // deployer.deploy(ConvertLib);
  deployer.deploy(Sustainers);
  // deployer.link(ConvertLib, MetaCoin);
  // deployer.deploy(MetaCoin);
};
