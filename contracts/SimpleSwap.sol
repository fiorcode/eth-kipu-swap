// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Gold Token
/// @notice ERC20 token representing Gold, only the owner can mint
contract Gold is ERC20, Ownable {

    /// @notice Deploys the Gold token and mints initial supply to the owner
    constructor() ERC20("Gold", "GLD") Ownable(msg.sender) {
        _mint(msg.sender, 1000);
    }

    /// @notice Mints new Gold tokens to a given address
    /// @param to The address to receive the minted tokens
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

/// @title Silver Token
/// @notice ERC20 token representing Silver, only the owner can mint
contract Silver is ERC20, Ownable {

    /// @notice Deploys the Silver token and mints initial supply to the owner
    constructor() ERC20("Silver", "SLV") Ownable(msg.sender) {
        _mint(msg.sender, 1000);
    }

    /// @notice Mints new Silver tokens to a given address
    /// @param to The address to receive the minted tokens
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

/// @title Interface for the SimpleSwap liquidity and swap logic
/// @notice Defines core actions for liquidity management and token swaps
interface ISimpleSwap {

    /// @notice Adds liquidity to the token pool
    /// @param goldAddress Address of the Gold token contract
    /// @param silverAddress Address of the Silver token contract
    /// @param amountGoldDesired Amount of Gold tokens to deposit
    /// @param amountSilverDesired Amount of Silver tokens to deposit
    /// @param amountGoldMin Minimum Gold accepted (slippage protection)
    /// @param amountSilverMin Minimum Silver accepted (slippage protection)
    /// @param to Address receiving the liquidity tokens
    /// @param deadline Latest timestamp by which the transaction must be confirmed
    /// @return amountGold Final amount of Gold used
    /// @return amountSilver Final amount of Silver used
    /// @return liquidity Amount of LP tokens minted
    function addLiquidity(
        address goldAddress, 
        address silverAddress,
        uint amountGoldDesired,
        uint amountSilverDesired,
        uint amountGoldMin, 
        uint amountSilverMin, 
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver, uint liquidity);

    /// @notice Removes liquidity from the pool
    /// @param goldAddress Address of the Gold token contract
    /// @param silverAddress Address of the Silver token contract
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountGoldMin Minimum amount of Gold expected
    /// @param amountSilverMin Minimum amount of Silver expected
    /// @param to Address receiving the underlying tokens
    /// @param deadline Expiration timestamp for the operation
    /// @return amountGold Amount of Gold returned
    /// @return amountSilver Amount of Silver returned
    function removeLiquidity(
        address goldAddress, 
        address silverAddress,
        uint liquidity,
        uint amountGoldMin, 
        uint amountSilverMin,
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver);

    /// @notice Swaps an exact amount of tokens along a given path
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens expected
    /// @param path Token address path (e.g., [Gold, Silver])
    /// @param to Address to receive the output tokens
    /// @param deadline Latest time the swap is valid
    /// @return amounts Array of input and output token amounts
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    /// @notice Gets the price of tokenA in terms of tokenB
    /// @param tokenA Base token address
    /// @param tokenB Quote token address
    /// @return price Estimated price of tokenA denominated in tokenB
    function getPrice(
        address tokenA, 
        address tokenB
    ) external view returns (uint price);

    /// @notice Calculates the amount of output tokens for a given input amount
    /// @param amountIn Amount of input tokens
    /// @param reserveIn Reserve amount of input token
    /// @param reserveOut Reserve amount of output token
    /// @return amountOut Amount of output tokens estimated
    function getAmountOut(
        uint amountIn, 
        uint reserveIn, 
        uint reserveOut
    ) external pure returns (uint amountOut);
}

/// @title SimpleSwap DEX contract
/// @notice Handles liquidity provisioning and token swaps between Gold and Silver
contract SimpleSwap is ISimpleSwap, ERC20, Ownable {

    /// @notice Token contract for Gold
    Gold private goldToken;

    /// @notice Token contract for Silver
    Silver private silverToken;

    /// @notice Current reserve of Gold in the pool
    uint public reserveGold;

    /// @notice Current reserve of Silver in the pool
    uint public reserveSilver;

    /// @notice Mapping of user addresses to their liquidity shares
    mapping(address => uint) public liquidities;

    /// @notice Initializes the DEX with Gold and Silver token addresses and initial liquidity
    /// @param _goldToken Address of deployed Gold token contract
    /// @param _silverToken Address of deployed Silver token contract
    constructor(address _goldToken, address _silverToken) ERC20("GoldSilverLP", "GSLP") Ownable(msg.sender) {
        goldToken = Gold(_goldToken);
        silverToken = Silver(_silverToken);

        reserveGold = goldToken.balanceOf(address(owner()));
        reserveSilver = silverToken.balanceOf(address(owner()));

        _mint(address(owner()), reserveGold + reserveSilver);
        liquidities[address(owner())] = reserveGold + reserveSilver;
    }


    /// @notice Adds liquidity to the Gold/Silver pool
    /// @dev Calculates optimal amounts and mints LP tokens to the user
    /// @param goldAddress Address of the Gold token
    /// @param silverAddress Address of the Silver token
    /// @param amountGoldDesired Desired amount of Gold to add
    /// @param amountSilverDesired Desired amount of Silver to add
    /// @param amountGoldMin Minimum acceptable amount of Gold (slippage protection)
    /// @param amountSilverMin Minimum acceptable amount of Silver (slippage protection)
    /// @param to Address to receive liquidity tokens
    /// @param deadline Timestamp by which the transaction must be completed
    /// @return amountGold Actual Gold added
    /// @return amountSilver Actual Silver added
    /// @return liquidity Amount of LP tokens minted
    function addLiquidity(
        address goldAddress, 
        address silverAddress,
        uint amountGoldDesired,
        uint amountSilverDesired,
        uint amountGoldMin, 
        uint amountSilverMin, 
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver, uint liquidity) {
        /// Ensure the transaction hasn't expired
        require(block.timestamp <= deadline, "Transaction expired");

        // Calculate the optimal amount of Silver to match Gold at pool ratio
        uint amountSilverFinal = (amountGoldDesired * reserveSilver) / reserveGold;

        if (amountSilverFinal <= amountSilverDesired) {
            // Accept optimal Silver if it’s within allowed slippage
            require(amountSilverFinal >= amountSilverMin, "Insufficient Silver amount");
            amountGold = amountGoldDesired;
            amountSilver = amountSilverFinal;
        } else {
            // Otherwise, recalculate optimal Gold for given Silver and validate against slippage
            uint amountGoldFinal = (amountSilverDesired * reserveGold) / reserveSilver;
            require(amountGoldFinal <= amountGoldDesired, "Insufficient Gold amount");
            require(amountGoldFinal >= amountGoldMin, "Insufficient Gold amount");
            amountGold = amountGoldFinal;
            amountSilver = amountSilverDesired;
        }

        // Transfer tokens from user to pool
        require(goldToken.transferFrom(msg.sender, address(this), amountGold), "Gold transaction failed");
        require(silverToken.transferFrom(msg.sender, address(this), amountSilver), "Silver transaction failed");

        // Calculate LP tokens to mint based on contribution proportion
        uint256 totalSupply = totalSupply();
        liquidity = min(
            (amountGold * totalSupply) / reserveGold,
            (amountSilver * totalSupply) / reserveSilver
        );

        require(liquidity > 0, "Insufficient liquidity minted");

        // Mint and assign LP tokens to user
        _mint(to, liquidity);
        liquidities[to] += liquidity;

        // Update internal reserves
        reserveGold += amountGold;
        reserveSilver += amountSilver;

        return (amountGold, amountSilver, liquidity);
    }

    /// @notice Removes liquidity from the pool
    /// @dev Burns LP tokens and transfers underlying assets to the user
    /// @param goldAddress Address of the Gold token
    /// @param silverAddress Address of the Silver token
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountGoldMin Minimum acceptable amount of Gold to receive
    /// @param amountSilverMin Minimum acceptable amount of Silver to receive
    /// @param to Recipient of the underlying tokens
    /// @param deadline Expiration time for the transaction
    /// @return amountGold Amount of Gold returned to user
    /// @return amountSilver Amount of Silver returned to user
    function removeLiquidity(
        address goldAddress, 
        address silverAddress,
        uint liquidity,
        uint amountGoldMin, 
        uint amountSilverMin,
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver) {
        /// Ensure the transaction hasn't expired
        require(block.timestamp <= deadline, "Transaction expired");

        /// Verify the sender has enough LP tokens to burn
        require(liquidities[msg.sender] >= liquidity, "Insufficient liquidity");

        // Calculate how much Gold and Silver corresponds to the LP tokens
        uint256 totalSupply = totalSupply();
        amountGold = (liquidity * reserveGold) / totalSupply;
        amountSilver = (liquidity * reserveSilver) / totalSupply;

        // Ensure the amounts meet minimum slippage constraints
        require(amountGold >= amountGoldMin, "Gold less than minimum");
        require(amountSilver >= amountSilverMin, "Silver less than minimum");

        // Update user’s liquidity balance and burn LP tokens
        liquidities[msg.sender] -= liquidity;
        _burn(msg.sender, liquidity);

        // Update pool reserves
        reserveGold -= amountGold;
        reserveSilver -= amountSilver;

        // Transfer the underlying tokens to the user
        require(goldToken.transfer(to, amountGold), "Gold transaction failed");
        require(silverToken.transfer(to, amountSilver), "Silver transaction failed");

        return (amountGold, amountSilver);
    }

    /// @notice Swaps an exact amount of tokens for as many output tokens as possible
    /// @param amountIn Exact amount of input tokens to send
    /// @param amountOutMin Minimum acceptable amount of output tokens (slippage protection)
    /// @param path Token address route (e.g., [Gold, Silver] or [Silver, Gold])
    /// @param to Address to receive the output tokens
    /// @param deadline Timestamp by which the transaction must be completed
    /// @return amounts Array with input/output amount info
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        /// Ensure the swap is executed before the deadline
        require(block.timestamp <= deadline, "Transaction expired");

        // Get current reserves to detect balance changes
        uint goldBalance = goldToken.balanceOf(address(this));
        uint silverBalance = silverToken.balanceOf(address(this));

        // Transfer input tokens to this contract
        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");

        // Determine which reserve increased to infer the direction of the swap
        bool glodReserveIncrease = goldBalance < goldToken.balanceOf(address(this));
        bool silverReserveIncrease = silverBalance < silverToken.balanceOf(address(this));

        // Validate that one of the supported tokens was received
        require(glodReserveIncrease || silverReserveIncrease, "Not valid tokens received");

        uint reserveIn;
        IERC20 tokenOut;
        uint reserveOut;

        // Identify input/output tokens and reserves based on which reserve increased
        if (glodReserveIncrease) {
            reserveIn = reserveGold;
            tokenOut = silverToken;
            reserveOut = reserveSilver;
        } else {
            reserveIn = reserveSilver;
            tokenOut = goldToken;
            reserveOut = reserveGold;
        }

        // Calculate output amount using AMM formula
        uint amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        // Ensure amount is valid and meets slippage requirements
        require(amountOut > 0, "Insufficient output amount");
        require(amountOut >= amountOutMin, "Slippage: insufficient output");

        // Transfer output tokens to recipient
        require(tokenOut.transfer(to, amountOut), "Output transfer failed");

        // Update internal reserves
        reserveGold = goldToken.balanceOf(address(this));
        reserveSilver = silverToken.balanceOf(address(this));

        uint[] memory amount = new uint[](amountOut);
        return amount;
    }

    /// @notice Returns the price of one token in terms of another
    /// @param tokenA The base token address
    /// @param tokenB The quote token address
    /// @return price The amount of tokenB per 1 tokenA, scaled by 1e18
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        return (ERC20(tokenB).balanceOf(address(this)) * 1e18) / ERC20(tokenA).balanceOf(address(this));
    }

    /// @notice Estimates output tokens for a given input based on current reserves
    /// @param amountIn Amount of input tokens
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @return amountOut Estimated amount of output tokens
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut) {
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        return amountOut;
    }

    /// @notice Internal helper to compute output amount for swap
    /// @dev Constant product formula: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
    /// @param amountIn Amount of input tokens
    /// @param reserveIn Reserve of input token
    /// @param reserveOut Reserve of output token
    /// @return Output amount of tokenOut
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) private pure returns (uint) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Invalid reserves or amount");
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /// @notice Returns the smaller of two uints
    /// @param a First value
    /// @param b Second value
    /// @return The minimum value
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

