require('dotenv').config();

const HDWalletProvider = require("@truffle/hdwallet-provider");

const solcStable = {
  version: "^0.8.4",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};

const solcNightly = {
  version: "nightly",
  docker: true
};

const useSolcNightly = process.env.SOLC_NIGHTLY === "true";

module.exports = {
  networks: {
    bscTest: {
      provider: () => {
        return new HDWalletProvider(
          process.env.MNEMONIC,
          "https://data-seed-prebsc-1-s1.binance.org:8545"
        );
      },
      from: process.env.WALLET_ADDRESS,
      gas: 8812388,
      // gasPrice: 8000000000,
      network_id: 97
    }
  },
  compilers: {
    solc: useSolcNightly ? solcNightly : solcStable
  },
  plugins: ["solidity-coverage"]
};
