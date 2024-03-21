const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the Address from Ganache Chain to deploy.
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address", deployer.address);

  // const MockToken = await ethers.getContractFactory("MockToken");
  const Pool = await ethers.getContractFactory("RewardPool");

  // const _mockToken = await upgrades.deployProxy(MockToken, []);
  // console.log("_mockToken ", _mockToken.address);
// goerli 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  // sepolia 0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0

  // uniswap in mumbai 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
  // usdt in mumbai 0xa02f6adc7926efebbd59fd43a84f4e0c0c91e832
  // uniswap in goerli 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

  const _pool = await upgrades.deployProxy(Pool, []);
  console.log("_pool ", _pool.address);
}

main();
