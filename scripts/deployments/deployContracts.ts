import { Account } from "starknet";

// deployContracts.js
import { hash, CallData, CairoCustomEnum } from "starknet";
import vaultSierra from "../../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert { type: "json" };
import { constructorArgs } from "../utils/constants";
import assert from "assert";

async function deployEthContract(
  enviornment: string,
  account: Account,
  classHash: string
) {
  let constructorArgsEth = [...Object.values(constructorArgs[enviornment].eth)];
  const deployResult = await account.deploy({
    classHash,
    constructorCalldata: constructorArgsEth,
  });

  console.log("ETH contract is deployed successfully at - ", deployResult);

  return deployResult.contract_address[0];
}

async function deployVaultContract(
  enviornment: string,
  account: Account,
  contractHash: string,
  classHashOptionRound: string
) {
  const contractCallData = new CallData(vaultSierra.abi);

  let constants = constructorArgs[enviornment];
  let vaultConstants = constants["vault"];
  const constructorCalldata = contractCallData.compile("constructor", {
    eth_address: vaultConstants.ethContract,
    vault_manager: vaultConstants.vaultManager,
    vault_type: new CairoCustomEnum({ InTheMoney: {} }),
    market_aggregator: vaultConstants.marketAggregatorContract,
    option_round_class_hash: classHashOptionRound,
  });

  const deployResult = await account.deploy({
    classHash: contractHash,
    constructorCalldata: constructorCalldata,
  });

  console.log("Vault contract is deployed successfully at - ", deployResult);
  return deployResult.contract_address[0];
}

async function deployMarketAggregator(
  enviornment: string,
  account: Account,
  marketAggregatorClassHash: string
) {
  const deployResult = await account.deploy({
    classHash: marketAggregatorClassHash,
  });

  console.log(
    "Market Aggregator contract is deployed successfully at - ",
    deployResult
  );
  return deployResult.contract_address[0];
}

export { deployEthContract, deployMarketAggregator, deployVaultContract };
