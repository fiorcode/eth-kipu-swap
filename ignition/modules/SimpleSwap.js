const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const SimplSwapModule = buildModule("SimpleSwapModule", (m) => {
    const gold = m.contract("Gold");
    const silver = m.contract("Silver");
    const simpleSwap = m.contract(
    contractName = "SimpleSwap", 
    args = [gold, silver]
);

  return { gold, silver, simpleSwap };
});

module.exports = SimplSwapModule;