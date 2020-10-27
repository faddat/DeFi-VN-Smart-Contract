const DFY = artifacts.require("DFY");
const BigNumber = require('bignumber.js');

module.exports = (deployer, network, accounts) => {
  return deployer.then(async () => {

    await deployer.deploy(
      DFY,
      "Decentralized Finance Token",
      "DFI",
      18,
      new BigNumber(1e30),
      new BigNumber(0),
      false,
      false
    );
    console.log(`[ADDRESS] DFY contracts: ${DFY.address}`);
  });
};
