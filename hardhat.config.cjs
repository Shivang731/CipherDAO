const { HardhatUserConfig } = require("hardhat/config");
require("@nomicfoundation/hardhat-toolbox");
require("@fhenixprotocol/cofhe-contracts/hardhat");

const config = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      fhenix: true,
    },
    fhenixNitrogen: {
      url: "https://nitrogen.fhenix.io",
      chainId: 42069,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  mocha: {
    timeout: 120000,
  },
};

module.exports = config;
