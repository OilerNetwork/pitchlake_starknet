import { Account } from "starknet";

// deployContracts.js
const fs = require("fs");
const path = require("path");
const { hash, CallData, CairoCustomEnum } = require("starknet");
const vaultSierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");
import { constructorArgs } from "./utils/constants";
const constantsPath = path.resolve(__dirname, "./utils/constants.json");

function getConstants() {
  return JSON.parse(fs.readFileSync(constantsPath, "utf8"));
}

async function deployEthContract(enviornment:string, account:Account) {
  const constants = getConstants();
  let constructorArgsEth = [...Object.values(constructorArgs[enviornment].eth)];
  const deployResult = await account.deploy({
    classHash: constants.declaredContractsMapping[enviornment]["eth"],
    constructorCalldata: constructorArgsEth,
  });

  constants.deployedContractsMapping[enviornment]["eth"] =
    deployResult.contract_address[0];

  constants.constructorArgs[enviornment]["vault"].ethContract =
    deployResult.contract_address[0];
  deployResult.contract_address[0];
  fs.writeFileSync(constantsPath, JSON.stringify(constants, null, 2), "utf8");

  console.log("ETH contract is deployed successfully at - ", deployResult);

  return deployResult.contract_address[0];
}

async function deployVaultContract(enviornment:string, account:Account) {
  const constants = getConstants();
  const contractCallData = new CallData(vaultSierra.abi);

  const constructorCalldata = contractCallData.compile("constructor", {
    eth_address: constants.constructorArgs[enviornment]["vault"].ethContract,
    vault_manager: constants.constructorArgs[enviornment]["vault"].vaultManager,
    vault_type: new CairoCustomEnum({ InTheMoney: {} }),
    market_aggregator:
      constants.constructorArgs[enviornment]["vault"].marketAggregatorContract,
    option_round_class_hash:
      constants.declaredContractsMapping[enviornment]["optionRound"],
  });

  const deployResult = await account.deploy({
    classHash: constants.declaredContractsMapping[enviornment]["vault"],
    constructorCalldata: constructorCalldata,
  });

  constants.deployedContractsMapping[enviornment]["vault"] =
    deployResult.contract_address[0];

  fs.writeFileSync(constantsPath, JSON.stringify(constants, null, 2), "utf8");

  console.log("Vault contract is deployed successfully at - ", deployResult);
  return deployResult.contract_address[0]
}

async function deployMarketAggregator(enviornment:string, account:Account) {
  const constants = getConstants();
  const deployResult = await account.deploy({
    classHash:
      constants.declaredContractsMapping[enviornment]["marketAggregator"],
  });

  constants.deployedContractsMapping[enviornment]["marketAggregator"] =
    deployResult.contract_address[0];

  constants.constructorArgs[enviornment]["vault"].marketAggregatorContract =
    deployResult.contract_address[0];

  fs.writeFileSync(constantsPath, JSON.stringify(constants, null, 2), "utf8");

  console.log(
    "Market Aggregator contract is deployed successfully at - ",
    deployResult
  );
  return deployResult.contract_address[0]
}

export {
  deployEthContract,
  deployMarketAggregator,
  deployVaultContract,
};
