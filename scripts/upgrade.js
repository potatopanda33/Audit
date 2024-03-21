const { ethers, upgrades } = require("hardhat");

async function main() {
  const contract = await ethers.getContractFactory("Cscrow");
  const upgrade = await upgrades.upgradeProxy(
    "0x8eF2Fdc40155519FEF17Df0f031DaFcd9DEF639d",
    contract
  );
  console.log("Contract upgraded", upgrade);
}

main();