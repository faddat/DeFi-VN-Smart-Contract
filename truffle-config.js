require('dotenv').config();

const HDWalletProvider = require("@truffle/hdwallet-provider");

const solcStable = {
  version: "^0.7.0",
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
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // eslint-disable-line camelcase
    },
    coverage: {
      host: "localhost",
      network_id: "*", // eslint-disable-line camelcase
      port: 8555,
      gas: 0xfffffffffff,
      gasPrice: 0x01
    },
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
