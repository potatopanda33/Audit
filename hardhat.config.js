require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-truffle5");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-contract-sizer");

// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "sepolia",
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
  networks: {
    sepolia: {
      url: 'https://sepolia.infura.io/v3/CHANGETHIS',
      chainId: 11155111,
      accounts: ['0xPRIVATEKEY']
    },
    goerli: {
      url: 'https://goerli.infura.io/v3/CHANGETHIS',
      chainId: 5,
      accounts: ['0xPRIVATEKEY']
    },
    mumbai: {
      url: 'https://polygon-mumbai.infura.io/v3/CHANGETHIS',
      chainId: 80001,
      accounts: ['0xPRIVATEKEY']
    },
    polygon: {
      url: 'https://polygon-mainnet.infura.io/v3/28ebd33371a5473580f64d66cf1d7774',
      chainId: 137,
      accounts: ['0xPRIVATEKEY']
    },
    ropsten: {
      url: process.env.GOERILI_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    "base-mainnet": {
      url: 'https://developer-access-mainnet.base.org',
      accounts:  process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 1000000000,
    },
    testnet: {
      url: process.env.MAIN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: "87SGIVNBWKJSZ2DXWBSSXA9P4UGNWUZGYV",
},
};
