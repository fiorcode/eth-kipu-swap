# eth-kipu-swap
Trabajo practico 3

# SimpleSwap

A sample smart contract written in Solidity that enables swapping between two ERC20 tokens: **Gold (GLD)** and **Silver (SLV)**. It includes functionality for adding liquidity, removing it, and performing token swaps.

## 📄 Contracts

### `Gold` and `Silver`

Basic ERC20 tokens based on OpenZeppelin with `mint` functionality restricted to the contract owner.

- `Gold`: Symbol `GLD`
- `Silver`: Symbol `SLV`

### `SimpleSwap`

The main contract that supports:

- Adding liquidity (`addLiquidity`)
- Removing liquidity (`removeLiquidity`)
- Swapping tokens (`swapExactTokensForTokens`)

## 🔧 Features

### `addLiquidity(...)`

Adds liquidity to the token pool.

**Parameters**:
- `goldAddress`: Address of the Gold token
- `silverAddress`: Address of the Silver token
- `amountGoldDesired`, `amountSilverDesired`: Amounts to deposit
- `amountGoldMin`, `amountSilverMin`: Minimums accepted (slippage protection)
- `to`: Address to receive LP tokens
- `deadline`: Latest valid timestamp for the operation

---

### `removeLiquidity(...)`

Allows a liquidity provider to withdraw their share from the pool.

---

### `swapExactTokensForTokens(...)`

Swaps an exact amount of one token for the maximum possible amount of another.

**Parameters**:
- `amountIn`: Input token amount
- `amountOutMin`: Minimum output accepted
- `path`: Swap route (`[GLD, SLV]` or vice versa)
- `to`: Recipient of the output tokens
- `deadline`: Deadline timestamp

## 🛠️ Requirements

- Solidity ^0.8.0
- OpenZeppelin Contracts

## ▶️ Running on Remix

1. Compile `SimpleSwap.sol`.
2. Deploy `Gold` and `Silver` contracts.
3. Deploy the `SimpleSwap` contract.
4. Use the `mint` function to create tokens.
5. Call `approve` to allow `SimpleSwap` to transfer tokens on your behalf.
6. Interact with the liquidity and swap functions.

## 📦 Dependencies

```bash
npm install @openzeppelin/contracts
