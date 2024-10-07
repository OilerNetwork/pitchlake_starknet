import { Account } from "starknet";

// deployContracts.js
import { CallData, CairoCustomEnum } from "starknet";
import vaultSierra from "../../../target/dev/pitch_lake_Vault.contract_class.json" assert { type: "json" };
import { constructorArgs } from "../constants";

async function deployEthContract(
  enviornment: string,
  account: Account,
  classHash: string,
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
  contractAddresses: {
    ethContract: string;
    factRegistryContract: string;
  },
  hashes: { vault: string; optionRound: string },
) {
  const contractCallData = new CallData(vaultSierra.abi);

  let constants = constructorArgs[enviornment].vault;
  const constructorCalldata = contractCallData.compile("constructor", {
    round_transition_period: constants.roundTransitionPeriod,
    auction_run_time: constants.auctionRunTime,
    option_run_time: constants.optionRunTime,
    eth_address: contractAddresses.ethContract,
    vault_type: new CairoCustomEnum({ AtTheMoney: {} }),
    fact_registry_address: contractAddresses.factRegistryContract,
    option_round_class_hash: hashes.optionRound,
  });

  const deployResult = await account.deploy({
    classHash: hashes.vault,
    constructorCalldata: constructorCalldata,
  });

  console.log("Vault contract is deployed successfully at - ", deployResult);
  return deployResult.contract_address[0];
}

async function deployFactRegistry(
  enviornment: string,
  account: Account,
  factRegistryClassHash: string,
) {
  const deployResult = await account.deploy({
    classHash: factRegistryClassHash,
  });

  console.log(
    "Market Aggregator contract is deployed successfully at - ",
    deployResult,
  );
  return deployResult.contract_address[0];
}

async function deployContracts(
  enviornment: string,
  account: Account,
  hashes: {
    ethHash: string;
    vaultHash: string;
    optionRoundHash: string;
    factRegistryHash: string;
  },
) {
  let ethAddress = await deployEthContract(
    enviornment,
    account,
    hashes.ethHash,
  );
  if (!ethAddress) {
    throw Error("Eth deploy failed");
  }

  let factRegistryAddress = await deployFactRegistry(
    enviornment,
    account,
    hashes.factRegistryHash,
  );
  if (!factRegistryAddress) {
    throw Error("FactRegistry deploy failed");
  }

  let vaultAddress = await deployVaultContract(
    enviornment,
    account,
    {
      factRegistryContract: factRegistryAddress,
      ethContract: ethAddress,
    },
    { optionRound: hashes.optionRoundHash, vault: hashes.vaultHash },
  );
  if (!vaultAddress) {
    throw Error("Eth deploy failed");
  }
  return {
    ethAddress,
    factRegistryAddress,
    vaultAddress,
  };
}

export {
  deployEthContract,
  deployFactRegistry,
  deployVaultContract,
  deployContracts,
};
