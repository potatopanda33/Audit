const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("Token contract", function () {
    let owner;
    let addr1;
    let addr2;
    let cscrowContract;

    before(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        const MockToken = await ethers.getContractFactory("MockToken");
        const Cscrow = await ethers.getContractFactory("Cscrow");
        const Pool = await ethers.getContractFactory("RewardPool");
        const _pool = await upgrades.deployProxy(Pool, []);


         // uniswap testnet 0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0
         // uniswap  0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
         const mocktoken = await upgrades.deployProxy(MockToken, []);

        await mocktoken.mint("0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0", 100);
         cscrowContract = await upgrades.deployProxy(Cscrow, ["0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0", mocktoken.address]);
        cscrowContract.initialize("0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0", mocktoken.address)
         const pooltrx = await cscrowContract.updateRewardPool(_pool.address)
        const pooltrxres = await pooltrx.wait();


        const collaborator = addr1.address;
        const amount = '0.003956';
        const details = 'details233423';
        const title = 'constracrt0022';
        const token = false;
        const tokenAddress = '0x000000000000000000000000000000000000dEaD';
        // cscrowContract.initialize("0xB26B2De65D07eBB5E54C7F6282424D3be670E1f0", "0x000000000000000000000000000000000000dEaD");
        const trx = await cscrowContract.createContract(
            collaborator.toLowerCase(),
            ethers.utils.parseEther(amount, "ether"),
            details,
            title,
            token,
            tokenAddress,
            {
                value: ethers.utils.parseEther(amount.toString()),
            }
        );
        const res = await trx.wait();
    });
});