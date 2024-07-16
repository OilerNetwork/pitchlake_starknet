const fs = require("fs");
const path = require("path");
const {
  hash,
  CallData,
  CairoCustomEnum,
  cairo,
  Contract,
  json,
} = require("starknet");
const { getContract } = require("./helper/common");
const constantsPath = path.resolve(__dirname, "./constants.json");

function getConstants() {
  return JSON.parse(fs.readFileSync(constantsPath, "utf8"));
}

async function getLPUnlockedBalance(enviornment, provider, account, address) {
  const constants = getConstants();
  let contractAddress =
    constants.deployedContractsMapping[enviornment]["vault"];

  const vaultContract = await getContract(provider, account, contractAddress);

  try {
    const res = await vaultContract.get_lp_unlocked_balance(address);
    return res;
  } catch (err) {
    console.log(err);
  }
}

async function withdraw(enviornment, provider, account, amount) {
  const constants = getConstants();
  let contractAddress =
    constants.deployedContractsMapping[enviornment]["vault"];

  const vaultContract = await getContract(provider, account, contractAddress);

  try {
    const myCall = vaultContract.populate("withdraw", [cairo.uint256(amount)]);
    const res = await vaultContract.withdraw(myCall.calldata);
    await provider.waitForTransaction(res.transaction_hash);
  } catch (err) {
    console.log(err);
  }
}

async function deposit(enviornment, provider, account, address, amount) {
  const constants = getConstants();
  let contractAddress =
    constants.deployedContractsMapping[enviornment]["vault"];

  const vaultContract = await getContract(provider, account, contractAddress);

  try {
    const myCall = vaultContract.populate("deposit_liquidity", [
      cairo.uint256(amount),
      address,
    ]);
    const res = await vaultContract.deposit_liquidity(myCall.calldata);
    await provider.waitForTransaction(res.transaction_hash);
  } catch (err) {
    console.log(err);
  }
}

module.exports = {
  withdraw,
  deposit,
  getLPUnlockedBalance,
};
