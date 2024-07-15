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
const constantsPath = path.resolve(__dirname, "../constants.json");

function getConstants() {
  return JSON.parse(fs.readFileSync(constantsPath, "utf8"));
}

async function withdraw(enviornment, provider, account, address, amount) {
  const constants = getConstants();
  let contractAddress =
    constants.deployedContractsMapping[enviornment]["vault"];

  const vaultContract = await getContract(provider, account, contractAddress);

  try {
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
  } catch (err) {
    console.log(err);
  }
}

module.exports = {
  withdraw,
  deposit,
};
