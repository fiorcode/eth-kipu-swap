const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * @title Test Suite for the SimpleSwap Contract
 * @dev This suite tests the functionality of the SimpleSwap contract,
 * including liquidity provision, removal, and token swaps.
 */
describe("Swap contract", function () {
  /**
   * @dev Deploys the necessary contracts (Gold, Silver, SimpleSwap)
   * and sets up signer accounts for testing.
   * This fixture is used to ensure a clean state for each test.
   * @returns {Object} An object containing the deployed contract instances
   * and signer accounts.
   */
  async function deployTokenFixture() {
    // Get signers
    const [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy ERC20 token contracts
    const Gold = await ethers.getContractFactory("Gold");
    const gold = await Gold.deploy();
    const Silver = await ethers.getContractFactory("Silver");
    const silver = await Silver.deploy();

    // Deploy the main SimpleSwap contract
    const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    const simpleSwap = await SimpleSwap.deploy(await gold.getAddress(), await silver.getAddress());

    // Return all contracts and signers
    return { simpleSwap, gold, silver, owner, addr1, addr2 };
  }

  /**
   * @dev Verifies that the initial GSLP (LP token) balance of the contract
   * deployer (owner) is correctly set upon deployment.
   */
  it("Initial GSLP balance of the owner should be 2000", async function () {
    const { simpleSwap, owner } = await loadFixture(deployTokenFixture);

    expect(await simpleSwap.balanceOf(owner.address)).to.equal(2000n);
  });

  /**
   * @dev Checks that the owner's initial balance of the Gold token is 1000.
   */
  it("Owner initial balance of Gold should be 1000", async function () {
    const { owner, gold } = await loadFixture(deployTokenFixture);
    expect(await gold.balanceOf(owner.address)).to.equal(1000n);
  });

  /**
   * @dev Checks that the owner's initial balance of the Silver token is 1000.
   */
  it("owner initial balance of Silver should be 1000", async function () {
    const { owner, silver } = await loadFixture(deployTokenFixture);
    expect(await silver.balanceOf(owner.address)).to.equal(1000n);
  });

  /**
   * @dev Tests the addLiquidity function to ensure it correctly mints LP tokens
   * and updates the contract's reserves.
   */
  it("Should add liquidity and mint LP tokens", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    // Mint additional tokens for the owner
    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));

    // Approve the SimpleSwap contract to spend the owner's tokens
    await gold.approve(simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(simpleSwap.getAddress(), ethers.parseEther("500"));

    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // Call addLiquidity
    const tx = await simpleSwap.addLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      ethers.parseEther("500"),
      ethers.parseEther("500"),
      ethers.parseEther("400"),
      ethers.parseEther("400"),
      owner.address,
      now + 60 // Set a deadline for the transaction
    );

    const receipt = await tx.wait();

    // Assert that the transaction was successful
    expect(receipt.status).to.equal(1);

    // Assert that the owner's LP token balance has increased
    const liquidityBalance = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalance).to.be.gt(0);

    // Assert that the contract's reserves have been updated correctly
    const reserveGold = await simpleSwap.reserveGold();
    const reserveSilver = await simpleSwap.reserveSilver();
    expect(reserveGold).to.equal(ethers.parseEther("500") + 1000n); 
    expect(reserveSilver).to.equal(ethers.parseEther("500") + 1000n); 
  });
  
  /**
   * @dev Tests the removeLiquidity function to ensure it correctly burns
   * LP tokens and returns the underlying assets to the user.
   */
  it("Should correctly remove liquidity from an initialized pool", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);

    // Setup: Add initial liquidity to the pool
    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));
    await gold.approve(simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(simpleSwap.getAddress(), ethers.parseEther("500"));
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    await simpleSwap.addLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      ethers.parseEther("0.0000000000000010"),
      ethers.parseEther("0.0000000000000010"),
      ethers.parseEther("0.0000000000000009"),
      ethers.parseEther("0.0000000000000009"),
      owner.address,
      now + 60 
    );

    const liquidityBalanceBefore = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalanceBefore).to.equal(4000);

    // Call removeLiquidity
    await simpleSwap.removeLiquidity(
      await gold.getAddress(),
      await silver.getAddress(),
      2000, // Amount of LP tokens to burn
      1,    // Minimum amount of Gold to receive
      1,    // Minimum amount of Silver to receive
      owner.address,
      now + 120 // Set a new deadline
    );

    // Assert that the owner's LP token balance has decreased
    const liquidityBalanceAfter = await simpleSwap.balanceOf(owner.address);
    expect(liquidityBalanceAfter).to.equal(2000);
  });

  /**
   * @dev Tests the swapExactTokensForTokens function to verify that a token
   * swap is executed correctly and that the contract's reserves are updated.
   */
  it("Should perform a swap and update reserves", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const path = [await gold.getAddress(), await silver.getAddress()];

    // Setup: Mint tokens for user and provide initial liquidity to the contract
    await gold.mint(owner.address, ethers.parseEther("1000"));
    await silver.mint(owner.address, ethers.parseEther("1000"));
    await gold.mint(await simpleSwap.getAddress(), ethers.parseEther("10000"));
    await silver.mint(await simpleSwap.getAddress(), ethers.parseEther("10000"));

    const initialGoldBalance = await gold.balanceOf(owner.address);
    const initialSilverBalance = await silver.balanceOf(owner.address);

    const amountIn = ethers.parseEther("1");
    const amountOutMin = 1; 

    // Approve the contract to spend tokens
    await gold.approve(await simpleSwap.getAddress(), ethers.parseEther("500"));
    await silver.approve(await simpleSwap.getAddress(), ethers.parseEther("500"));

    // Execute the swap
    const tx = await simpleSwap.swapExactTokensForTokens(
      amountIn,
      amountOutMin,
      path,
      owner.address,
      now + 60
    );
    await tx.wait();

    // Assert that the user's balances have changed as expected
    const finalGoldBalance = await gold.balanceOf(owner.address);
    const finalSilverBalance = await silver.balanceOf(owner.address);
    expect(finalGoldBalance).to.be.lt(initialGoldBalance);
    expect(finalSilverBalance).to.be.gt(initialSilverBalance);

    // Assert that reserves have been updated
    const reserveGold = await simpleSwap.reserveGold();
    const reserveSilver = await simpleSwap.reserveSilver();
    expect(reserveGold).to.be.gt(0);
    expect(reserveSilver).to.be.gt(0);
  });

  /**
   * @dev Tests that the addLiquidity function reverts with 'Insufficient Silver amount'
   * when the amount of Silver provided is less than the calculated minimum.
   */
  it("Should revert with 'Insufficient Silver amount'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // Attempt to add liquidity with an insufficient amount of Silver
    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        ethers.parseEther("0.5"),  // Desired Gold
        ethers.parseEther("1"),    // Desired Silver
        1,                         // Minimum Gold (low)
        ethers.parseEther("0.8"),  // Minimum Silver (higher than what would be calculated)
        owner.address,
        now + 60
      )
    ).to.be.revertedWith("Insufficient Silver amount");
  });

  /**
   * @dev Tests that the addLiquidity function reverts with 'Insufficient Gold amount'
   * when the amount of Gold provided is less than the calculated minimum.
   */
  it("Should revert with 'Insufficient Gold amount'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // Attempt to add liquidity with an insufficient amount of Gold
    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        ethers.parseEther("1"),    // Desired Gold
        ethers.parseEther("0.5"),  // Desired Silver
        ethers.parseEther("0.9"),  // Minimum Gold (higher than what would be calculated)
        1,                         // Minimum Silver (low)
        owner.address,
        now + 60
      )
    ).to.be.revertedWith("Insufficient Gold amount");
  });

  /**
   * @dev Tests that functions with a deadline modifier revert if the
   * transaction is executed after the deadline has passed.
   */
  it("Should revert with 'Transaction expired'", async function () {
    const { gold, silver, simpleSwap, owner } = await loadFixture(deployTokenFixture);
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // Attempt to call addLiquidity with a past deadline
    await expect(
      simpleSwap.addLiquidity(
        await gold.getAddress(),
        await silver.getAddress(),
        ethers.parseEther("1"),
        ethers.parseEther("1"),
        1,
        1,
        owner.address,
        now - 60 // Deadline is in the past
      )
    ).to.be.revertedWith("Transaction expired");
  });
  
  /**
   * @dev Tests the getPrice view function to ensure it returns the correct
   * price based on the ratio of the reserves.
   */
  it("Should return the correct price based on token balances", async function () {
    const { gold, silver, simpleSwap } = await loadFixture(deployTokenFixture);

    // Manually set reserves by minting tokens directly to the contract
    await gold.mint(simpleSwap.getAddress(), ethers.parseEther("2"));
    await silver.mint(simpleSwap.getAddress(), ethers.parseEther("1"));

    // Get the price
    const price = await simpleSwap.getPrice(await gold.getAddress(), await silver.getAddress());

    // Calculate expected price (1 Silver / 2 Gold = 0.5)
    const expectedPrice = ethers.parseUnits("0.5", 18);
    expect(price).to.equal(expectedPrice);
  });

  /**
   * @dev Tests the getAmountOut view function to ensure it calculates the
   * correct output amount for a given input amount and reserves.
   */
  it("Should return a valid amountOut when given correct reserves and amountIn", async function () {
    const { simpleSwap } = await loadFixture(deployTokenFixture);
    const amountIn = ethers.parseUnits("1000", 0); 
    const reserveIn = ethers.parseUnits("5000", 0);
    const reserveOut = ethers.parseUnits("8000", 0);

    // Call getAmountOut
    const amountOut = await simpleSwap.getAmountOut(amountIn, reserveIn, reserveOut);

    // Calculate the expected output based on the formula: (amountIn * reserveOut) / (reserveIn + amountIn)
    const expectedAmountOut = amountIn * reserveOut / (reserveIn + amountIn);
    expect(amountOut).to.equal(expectedAmountOut);
  });

  /**
   * @dev Tests that the getAmountOut function reverts if the input amount is zero,
   * as this is an invalid condition.
   */
  it("Should revert with 'Invalid reserves or amount' when amountIn is zero", async function () {
    const { simpleSwap } = await loadFixture(deployTokenFixture);

    // Expect the call to revert when amountIn is 0
    await expect(
      simpleSwap.getAmountOut(0, 5000, 5000)
    ).to.be.revertedWith("Invalid reserves or amount");
  });
});