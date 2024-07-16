import { Contract } from "starknet";
import { getAccount, getProvider } from "./utils/helper";
import {
  deployEthContract,
  deployMarketAggregator,
  deployVaultContract,
} from "./deployContracts";

import { ABI } from "./utils/vault/abi";
import fs from "fs";
import { createTestAccounts } from "./deployAccounts";
const { declareContract } = require("./declareContracts");
const ethSierra = require("../target/dev/pitch_lake_starknet_Eth.contract_class.json");
const ethCasm = require("../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json");
const vaultSierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");
const vaultCasm = require("../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json");
const optionRoundSieraa = require("../target/dev/pitch_lake_starknet_OptionRound.contract_class.json");
const optionRoundCasm = require("../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json");
const marketAggregatorSierra = require("../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json");
const marketAggregatorCasm = require("../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json");

async function declareContracts(enviornment: string, port: string | null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);
  await declareContract(enviornment, account, ethSierra, ethCasm, "eth");
  await declareContract(enviornment, account, vaultSierra, vaultCasm, "vault");
  await declareContract(
    enviornment,
    account,
    optionRoundSieraa,
    optionRoundCasm,
    "optionRound"
  );
  await declareContract(
    enviornment,
    account,
    marketAggregatorSierra,
    marketAggregatorCasm,
    "marketAggregator"
  );
}

async function deployContracts(enviornment: string, port: string | null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);

  const eth = await deployEthContract(enviornment, account);
  const mkt = await deployMarketAggregator(enviornment, account);
  const vault = await deployVaultContract(enviornment, account);
  return { eth, mkt, vault };
}

async function main(enviornment: string, port: string | null) {
  await declareContracts(enviornment, port);

  const { eth, mkt, vault } = await deployContracts(enviornment, port);
  const compiledVault = JSON.parse(vaultCasm);
  const provider = getProvider(enviornment, port);
  const contract = new Contract(ABI, vault, provider).typedv2(ABI);
  const { optionBuyers } = await createTestAccounts(provider);
  contract.populate("deposit_liquidity", [20,optionBuyers[0]]);
}

main(process.argv[2], process.argv[3]);
