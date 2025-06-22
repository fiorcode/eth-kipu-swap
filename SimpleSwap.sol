// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Gold is ERC20, Ownable {
    constructor() ERC20("Gold", "GLD") Ownable(msg.sender) {
        _mint(msg.sender, 1000);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract Silver is ERC20, Ownable {
    constructor() ERC20("Silver", "SLV") Ownable(msg.sender) {
        _mint(msg.sender, 1000);
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

    function getPrice(
        address tokenA, 
        address tokenB
    ) external view returns (uint price);

    function getAmountOut(
        uint amountIn, 
        uint reserveIn, 
        uint reserveOut
    ) external pure returns (uint amountOut);
}

contract SimpleSwap is ISimpleSwap, ERC20, Ownable {

    Gold private goldToken;
    Silver private silverToken;

    uint public reserveGold;
    uint public reserveSilver;
    mapping(address => uint) public liquidities;

    constructor(address _goldToken, address _silverToken) ERC20("GoldSilverLP", "GSLP") Ownable(msg.sender) {
        goldToken = Gold(_goldToken);
        silverToken = Silver(_silverToken);

        reserveGold = goldToken.balanceOf(address(owner()));
        reserveSilver = silverToken.balanceOf(address(owner()));

        _mint(address(owner()), reserveGold + reserveSilver);
        liquidities[address(owner())] = reserveGold + reserveSilver;
    }

    /* 
    * Function to add liquidity to the swap contract. 
    *
    * The pool has an initial liquidity provided by the owner.
    */
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
        // Verifies if the transaction is not expired
        require(block.timestamp <= deadline, "Transaction expired");
        
        /*
        * Calculates amount of silver that correspond for the amount of gold desired.
        *
        * If amount of silver desired is greater than the silver amount calculated 
		* and this silver amount caluclated is greater than the minimun set by the sender then
        * gold desired is setted as final amount.
        */
        uint amountSilverFinal = (amountGoldDesired * reserveSilver) / reserveGold;
        if (amountSilverFinal <= amountSilverDesired) {
            require(amountSilverFinal >= amountSilverMin, "Insufficient Silver amount");
            amountGold = amountGoldDesired;
            amountSilver = amountSilverFinal;
        } else {
            /*
            * If amount of silver desired was NOT greater than the silver amount calculated, 
            * it calculates amount of gold that correspond for the amount of silver desired.
            * If amount of gold desired is greater than the gold amount calculated 
            * and this gold amount caluclated is greater than the minimun set by the sender then
            * silver desired is setted as final amount.
            */
            uint amountGoldFinal = (amountSilverDesired * reserveGold) / reserveSilver;

            require(amountGoldFinal <= amountGoldDesired, "Insufficient Gold amount");
            require(amountGoldFinal >= amountGoldMin, "Insufficient Gold amount");
            amountGold = amountGoldFinal;
            amountSilver = amountSilverDesired;
        }

        // Transfers tokens from the user to the contract
        require(Gold(goldAddress).transferFrom(msg.sender, address(this), amountGold), "Gold transaction failed");
        require(Silver(silverAddress).transferFrom(msg.sender, address(this), amountSilver), "Silver transaction failed");

        // Calculate the liquidity
        liquidity = min(amountGold / reserveGold, amountSilver / reserveSilver) * totalSupply();

        // If liquidity is grater than zero then is minted in contract and asigned to the user
        require(liquidity > 0, "Insufficient liquidity minted");
        _mint(to, liquidity);
        liquidities[to] += liquidity;

        // Reserve tokens values are updated
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
        // Verifies if the transaction is not expired
        require(block.timestamp <= deadline, "Transaction expired");

        // Verifies if user has enough liquidity
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
        // Verifies if the transaction is not expired
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
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Invalid reserves or amount");
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}
