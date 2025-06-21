// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Gold is ERC20, Ownable {
    constructor() ERC20("Gold", "GLD") Ownable(msg.sender) {
        _mint(msg.sender, 100);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract Silver is ERC20, Ownable {
    constructor() ERC20("Silver", "SLV") Ownable(msg.sender) {
        _mint(msg.sender, 100);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

interface ISimpleSwap {
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

    function removeLiquidity(
        address goldAddress, 
        address silverAddress,
        uint liquidity,
        uint amountGoldMin, 
        uint amountSilverMin,
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver);

    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    function getPrice(address tokenA, address tokenB) external view returns (uint price);

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
}

contract SimpleSwap is ISimpleSwap, ERC20, Ownable {

    Gold public goldToken;
    Silver public silverToken;

    uint public reserveGold;
    uint public reserveSilver;
    mapping(address => uint) public liquidities;

    constructor(address _goldToken, address _silverToken) ERC20("GoldSilverLP", "GST") Ownable(msg.sender) {
        goldToken = Gold(_goldToken);
        silverToken = Silver(_silverToken);

        reserveGold = goldToken.balanceOf(address(owner()));
        reserveSilver = silverToken.balanceOf(address(owner()));

        uint amountToMint = (reserveGold + reserveSilver) * 10 ** decimals();
        _mint(address(owner()), amountToMint);
        liquidities[address(owner())] = amountToMint;
    }

    // We assume that the pool has an initial liquidity
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
        require(block.timestamp <= deadline, "Transaction expired");

        uint amountSilverOptimal = (amountGoldDesired * reserveSilver) / reserveGold;
        if (amountSilverOptimal <= amountSilverDesired) {
            require(amountSilverOptimal >= amountSilverMin, "Insufficient Silver amount");
            amountGold = amountGoldDesired;
            amountSilver = amountSilverOptimal;
        } else {
            uint amountGoldOptimal = (amountSilverDesired * reserveGold) / reserveSilver;
            require(amountGoldOptimal <= amountGoldDesired, "Insufficient Gold amount");
            require(amountGoldOptimal >= amountGoldMin, "Insufficient Gold amount");
            amountGold = amountGoldOptimal;
            amountSilver = amountSilverDesired;
        }

        require(Gold(goldAddress).transferFrom(msg.sender, address(this), amountGold), "Gold transaction failed");
        require(Silver(silverAddress).transferFrom(msg.sender, address(this), amountSilver), "Silver transaction failed");

        liquidity = min(amountGold / reserveGold, amountSilver / reserveSilver) * totalSupply();

        require(liquidity > 0, "Insufficient liquidity minted");
        _mint(to, liquidity);
        liquidities[to] += liquidity;

        reserveGold += amountGold;
        reserveSilver += amountSilver;

        return (amountGold, amountSilver, liquidity);
    }

    function removeLiquidity(
        address goldAddress, 
        address silverAddress,
        uint liquidity,
        uint amountGoldMin, 
        uint amountSilverMin,
        address to, 
        uint deadline
    ) external returns (uint amountGold, uint amountSilver) {
        require(block.timestamp <= deadline, "Transaction expired");

        require(liquidities[msg.sender] >= liquidity, "Insufficient liquidity");

        amountGold = (liquidity * reserveGold) / totalSupply();
        amountSilver = (liquidity * reserveSilver) / totalSupply();

        require(amountGold >= amountGoldMin, "Gold less than minimum");
        require(amountSilver >= amountSilverMin, "Silver less than minimum");

        // Burn the liquidity
        liquidities[msg.sender] -= liquidity;
        _burn(msg.sender, liquidity);

        // Update reserves
        reserveGold -= amountGold;
        reserveSilver -= amountSilver;

        // Transfer tokens to user
        require(Gold(goldAddress).transfer(to, amountGold), "Gold transaction failed");
        require(Silver(silverAddress).transfer(to, amountSilver), "Silver transaction failed");

        return (amountGold, amountSilver);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "Transaction expired");

        uint goldBalance = goldToken.balanceOf(address(this));
        uint silverBalance = silverToken.balanceOf(address(this));

        // Transfer the input tokens to contract
        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");

        bool glodReserveIncrease = goldBalance < goldToken.balanceOf(address(this));
        bool silverReserveIncrease = silverBalance < silverToken.balanceOf(address(this));

        require(glodReserveIncrease || silverReserveIncrease, "Not valid tokens received");

        uint reserveIn;
        IERC20 tokenOut;
        uint reserveOut;

        if (glodReserveIncrease) {
            reserveIn = reserveGold;
            tokenOut = silverToken;
            reserveOut = reserveSilver;
        } else {
            reserveIn = reserveSilver;
            tokenOut = goldToken;
            reserveOut = reserveGold;
        }

        uint amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        require(amountOut > 0, "Insufficient output amount");

        require(amountOut >= amountOutMin, "Slippage: insufficient output");
        
        require(tokenOut.transfer(to, amountOut), "Output transfer failed");

        reserveGold = goldToken.balanceOf(address(this));
        reserveSilver = silverToken.balanceOf(address(this));

        uint[] memory amount = new uint[](amountOut);

        return amount;
    }

    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        return (ERC20(tokenB).balanceOf(address(this)) * 1e18) / ERC20(tokenA).balanceOf(address(this));
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut) {
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        return amountOut;
    }

    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) private pure returns (uint) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Invalid reserves or amountIn");
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

/**
 * @title SwapVerifier
 * @notice Verifies a SimpleSwap implementation by exercising its functions and asserting correct behavior.
 */
contract SwapVerifier {

    string[] public authors;

    /// @notice Runs end-to-end checks on a deployed SimpleSwap contract.
    /// @param swapContract Address of the SimpleSwap contract to verify.
    /// @param tokenA Address of a test ERC20 token (must implement IMintableERC20).
    /// @param tokenB Address of a test ERC20 token (must implement IMintableERC20).
    /// @param amountA Initial amount of tokenA to mint and add as liquidity.
    /// @param amountB Initial amount of tokenB to mint and add as liquidity.
    /// @param amountIn Amount of tokenA to swap for tokenB.
    /// @param author Name of the author of swap contract
    function verify(
        address swapContract,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 amountIn,
        string memory author
    ) external {
        require(amountA > 0 && amountB > 0, "Invalid liquidity amounts");
        require(amountIn > 0 && amountIn <= amountA, "Invalid swap amount");
        require(IERC20(tokenA).balanceOf(address(this)) >= amountA, "Insufficient token A supply for this contact");
        require(IERC20(tokenB).balanceOf(address(this)) >= amountB, "Insufficient token B supply for this contact");

        // Approve SimpleSwap to transfer tokens
        IERC20(tokenA).approve(swapContract, amountA);
        IERC20(tokenB).approve(swapContract, amountB);

        // Add liquidity
        (uint256 aAdded, uint256 bAdded, uint256 liquidity) = ISimpleSwap(swapContract)
            .addLiquidity(tokenA, tokenB, amountA, amountB, amountA, amountB, address(this), block.timestamp + 1);
        require(aAdded == amountA && bAdded == amountB, "addLiquidity amounts mismatch");
        require(liquidity > 0, "addLiquidity returned zero liquidity");

        // Check price = bAdded * 1e18 / aAdded
        uint256 price = ISimpleSwap(swapContract).getPrice(tokenA, tokenB);
        require(price == (bAdded * 1e18) / aAdded, "getPrice incorrect");

        // Compute expected output for swap
        uint256 expectedOut = ISimpleSwap(swapContract).getAmountOut(amountIn, aAdded, bAdded);
        // Perform swap
        IERC20(tokenA).approve(swapContract, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        ISimpleSwap(swapContract).swapExactTokensForTokens(amountIn, expectedOut, path, address(this), block.timestamp + 1);
        require(IERC20(tokenB).balanceOf(address(this)) >= expectedOut, "swapExactTokensForTokens failed");

        // Remove liquidity
        (uint256 aOut, uint256 bOut) = ISimpleSwap(swapContract)
            .removeLiquidity(tokenA, tokenB, liquidity, 0, 0, address(this), block.timestamp + 1);
        require(aOut + bOut > 0, "removeLiquidity returned zero tokens");

        // Add author
        authors.push(author);
    }
}
