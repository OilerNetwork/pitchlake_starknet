import { Contract } from "starknet";
import { getAccount, getProvider } from "./utils/helper";
import {
  deployEthContract,
  deployMarketAggregator,
  deployVaultContract,
} from "./deployContracts";

import { ABI } from "./utils/vault/abi";
import { createTestAccounts } from "./deployAccounts";
import { declareContract } from "./declareContracts";
import ethSierra from "../target/dev/pitch_lake_starknet_Eth.contract_class.json" assert { type: "json" };
import ethCasm from "../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json" assert { type: "json" };
import vaultSierra from "../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert { type: "json" };
import vaultCasm from "../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json" assert { type: "json" };
import optionRoundSieraa from "../target/dev/pitch_lake_starknet_OptionRound.contract_class.json" assert { type: "json" };
import optionRoundCasm from "../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json" assert { type: "json" };
import marketAggregatorSierra from "../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json" assert { type: "json" };
import marketAggregatorCasm from "../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json" assert { type: "json" };

async function declareContracts(enviornment: string, port?: string) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);
  let ethHash = await declareContract(
    enviornment,
    account,
    ethSierra,
    ethCasm,
    "eth"
  );
  console.log("ETHASH", ethHash);
  if (!ethHash) {
    ethHash="abc";
  }
  let vaultHash = await declareContract(
    enviornment,
    account,
    vaultSierra,
    vaultCasm,
    "vault"
  );
  if (!vaultHash) {
    throw Error("Failed to deploy Vault");
  }
  let optionRoundHash = await declareContract(
    enviornment,
    account,
    optionRoundSieraa,
    optionRoundCasm,
    "optionRound"
  );
  if (!optionRoundHash) {
    throw Error("Failed to deploy OptionRound");
  }
  let marketAggregatorHash = await declareContract(
    enviornment,
    account,
    marketAggregatorSierra,
    marketAggregatorCasm,
    "marketAggregator"
  );
  if (!marketAggregatorHash) {
    throw Error("Failed to deploy MarketAggregator");
  }
  return { ethHash, vaultHash, optionRoundHash, marketAggregatorHash };
}

async function deployContracts(
  enviornment: string,
  hashes: {
    ethHash: string;
    vaultHash: string;
    optionRoundHash: string;
    marketAggregatorHash: string;
  },
  port?: string
) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);

  const eth = await deployEthContract(enviornment, account, hashes.ethHash);
  const mkt = await deployMarketAggregator(
    enviornment,
    account,
    hashes.marketAggregatorHash
  );
  const vault = await deployVaultContract(
    enviornment,
    account,
    hashes.vaultHash,
    hashes.optionRoundHash
  );
  return { eth, mkt, vault };
}

async function main(enviornment: string, port?: string) {
  console.log("PORT",port)
  let hashes = await declareContracts(enviornment, port);
  console.log("HI",hashes)
  const { eth, mkt, vault } = await deployContracts(enviornment, hashes, port);

}

main(process.argv[2], process.argv[3]);
