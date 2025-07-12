const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Swap contract", function () {
  async function deployTokenFixture() {
    const [owner, addr1, addr2] = await ethers.getSigners();

    const Gold = await ethers.getContractFactory("Gold");
    const gold = await Gold.deploy();
    const Silver = await ethers.getContractFactory("Silver");
    const silver = await Silver.deploy();
    const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    const simpleSwap = await SimpleSwap.deploy(await gold.getAddress(), await silver.getAddress());

    return { simpleSwap, gold, silver, owner, addr1, addr2 };
  }

  it("Should set the right owner", async function () {
    const { simpleSwap, owner } = await loadFixture(deployTokenFixture);
    expect(await simpleSwap.balanceOf(owner.address)).to.equal(2000n);  // Use BigInt
  });

  it("owner initial balance of gold should be 1000", async function () {
    const { owner, gold } = await loadFixture(deployTokenFixture);
    expect(await gold.balanceOf(owner.address)).to.equal(1000n);
  });

  it("owner initial balance of silver should be 1000", async function () {
    const { owner, silver } = await loadFixture(deployTokenFixture);
    expect(await silver.balanceOf(owner.address)).to.equal(1000n);
  });

  it("Should add liquidity and mint LP tokens", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    // Mint and approve tokens
    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));

    await gold.approve(simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(simpleSwap.getAddress(), ethers.parseEther("500"));

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    const tx = await simpleSwap.addLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      ethers.parseEther("500"),
      ethers.parseEther("500"),
      ethers.parseEther("400"),
      ethers.parseEther("400"),
      owner.address,
      now + 60 // 1 minute deadline
    );

    const receipt = await tx.wait();

    expect(receipt.status).to.equal(1);

    // Optional checks: liquidity balance, reserves
    const liquidityBalance = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalance).to.be.gt(0);

    const reserveGold = await simpleSwap.reserveGold();
    const reserveSilver = await simpleSwap.reserveSilver();

    expect(reserveGold).to.equal(ethers.parseEther("500") + 1000n); // 1000 initial + 500 added
    expect(reserveSilver).to.equal(ethers.parseEther("500") + 1000n); // 1000 initial + 500 added
  });
  
  it("Should correctly remove liquidity from an initialized pool", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    // Mint and approve tokens
    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));

    await gold.approve(simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(simpleSwap.getAddress(), ethers.parseEther("500"));

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    const tx = await simpleSwap.addLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      ethers.parseEther("0.0000000000000010"),
      ethers.parseEther("0.0000000000000010"),
      ethers.parseEther("0.0000000000000009"),
      ethers.parseEther("0.0000000000000009"),
      owner.address,
      now + 60 // 1 minute deadline
    );

    const liquidityBalanceBefore = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalanceBefore).to.equal(4000);

    // Remove all liquidity
    await simpleSwap.removeLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      2000,
      1,
      1,
      owner.address,
      now + 120
    );

    const liquidityBalanceAfter = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalanceAfter).to.equal(2000);
  });

  it("Should perform a swap and update reserves", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    const path = [await gold.getAddress(), await silver.getAddress()];

    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));

    await gold.mint(await simpleSwap.getAddress(), ethers.parseEther("10000"));
    await silver.mint(await simpleSwap.getAddress(), ethers.parseEther("10000"));

    const initialGoldBalance = await gold.balanceOf(owner.address);
    const initialSilverBalance = await silver.balanceOf(owner.address);

    const amountIn = ethers.parseEther("1");
    const amountOutMin = 1; // Accept any non-zero output for test

    await gold.approve(await simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(await simpleSwap.getAddress(), ethers.parseEther("500"));

    const tx = await simpleSwap.swapExactTokensForTokens(
      amountIn,
      amountOutMin,
      path,
      owner.address,
      now + 60
    );

    await tx.wait();

    const finalGoldBalance = await gold.balanceOf(owner.address);
    const finalSilverBalance = await silver.balanceOf(owner.address);

    expect(finalGoldBalance).to.be.lt(initialGoldBalance);
    expect(finalSilverBalance).to.be.gt(initialSilverBalance);

    const reserveGold = await simpleSwap.reserveGold();
    const reserveSilver = await simpleSwap.reserveSilver();

    expect(reserveGold).to.be.gt(0);
    expect(reserveSilver).to.be.gt(0);
  });

  it("Should revert with 'Insufficient Silver amount'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    const amountGoldDesired = ethers.parseEther("0.5");
    const amountSilverDesired = ethers.parseEther("1"); // Set too high on purpose
    const amountGoldMin = 1;
    const amountSilverMin = ethers.parseEther("0.8"); // Set above expected silver amount to trigger revert

    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        amountGoldDesired,
        amountSilverDesired,
        amountGoldMin,
        amountSilverMin,
        owner.address,
        now + 60
      )
    ).to.be.revertedWith("Insufficient Silver amount");
  });

  it("Should revert with 'Insufficient Gold amount'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    const amountGoldDesired = ethers.parseEther("1");
    const amountSilverDesired = ethers.parseEther("0.5"); // Set to trigger the 'else' condition
    const amountGoldMin = ethers.parseEther("0.9");       // Purposefully set too high
    const amountSilverMin = 1;                            // Smallest non-zero to avoid silver check

    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        amountGoldDesired,
        amountSilverDesired,
        amountGoldMin,
        amountSilverMin,
        owner.address,
        now + 60
      )
    ).to.be.revertedWith("Insufficient Gold amount");
  });

  it("Should revert with 'Transaction expired'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // Expired deadline: now - 60
    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        ethers.parseEther("1"),
        ethers.parseEther("1"),
        1,
        1,
        owner.address,
        now - 60 // Intentionally in the past
      )
    ).to.be.revertedWith("Transaction expired");
  });
  
  it("Should return the correct price based on token balances", async function () {
    const { gold, silver, simpleSwap } = await loadFixture(deployTokenFixture);

    await gold.mint(simpleSwap.getAddress(), ethers.parseEther("2"));
    await silver.mint(simpleSwap.getAddress(), ethers.parseEther("1"));

    const price = await simpleSwap.getPrice(await gold.getAddress(), await silver.getAddress());

    // Manually calculate expected value:
    // silver balance = 1 ether
    // gold balance = 2 ether
    // price = (1 * 1e18) / 2 = 0.5 * 1e18
    const expectedPrice = ethers.parseUnits("0.5", 18);

    expect(price).to.equal(expectedPrice);
  });

  it("Should return a valid amountOut when given correct reserves and amountIn", async function () {
    const { simpleSwap } = await loadFixture(deployTokenFixture);

    const amountIn = ethers.parseUnits("1000", 0);      // 1000 wei
    const reserveIn = ethers.parseUnits("5000", 0);     // 5000 wei
    const reserveOut = ethers.parseUnits("8000", 0);    // 8000 wei

    const amountOut = await simpleSwap.getAmountOut(amountIn, reserveIn, reserveOut);

    const expectedAmountOut = amountIn * reserveOut / (reserveIn + amountIn);

    expect(amountOut).to.equal(expectedAmountOut);
  });

  it("Should revert with 'Invalid reserves or amount' when amountIn is zero", async function () {
    const { simpleSwap } = await loadFixture(deployTokenFixture);

  await expect(
    simpleSwap.getAmountOut(0, 5000, 5000)
  ).to.be.revertedWith("Invalid reserves or amount");
});

});