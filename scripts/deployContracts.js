// deployContracts.js
const fs = require("fs");
const path = require("path");
const { hash, CallData, CairoCustomEnum } = require("starknet");
const ethSierra = require("../target/dev/pitch_lake_starknet_Eth.contract_class.json");
const vaultSierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");
const optionRoundSieraa = require("../target/dev/pitch_lake_starknet_OptionRound.contract_class.json");
const marketAggregatorSierra = require("../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json");

const constantsPath = path.resolve(__dirname, "./utils/constants.json");
let constants = JSON.parse(fs.readFileSync(constantsPath, "utf8"));

const { getAccount, getProvider } = require("./utils/helper");

async function deployEthContract(enviornment, account) {
  let constructorArgs = [
    constants.constructorArgs[enviornment]["eth"].supplyValueLow,
    constants.constructorArgs[enviornment]["eth"].supplyValueHigh,
    constants.constructorArgs[enviornment]["eth"].recipientContractAddress,
  ];

  const deployResult = await account.deploy({
    classHash: constants.declaredContractsMapping[enviornment]["eth"],
    constructorCalldata: constructorArgs,
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

async function deployVaultContract(enviornment, account) {
  const sierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");

  const contractCallData = new CallData(sierra.abi);

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
}

async function deployMarketAggregator(enviornment, account) {
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
}

async function main(enviornment, port = null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);
  await deployEthContract(enviornment, account);
  await deployMarketAggregator(enviornment, account);
  await deployVaultContract(enviornment, account);
}

main(process.argv[2], process.argv[3]);
