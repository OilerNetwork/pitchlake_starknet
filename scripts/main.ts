import {
  getAccount,
  getProvider,
  getCustomAccount,
} from "./utils/helper/common";
import {
  deployEthContract,
  deployMarketAggregator,
  deployVaultContract,
} from "./deployments/deployContracts";

import { declareContract } from "./deployments/declareContracts";
import ethSierra from "../target/dev/pitch_lake_starknet_Eth.contract_class.json" assert {type:"json"};
import ethCasm from "../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json" assert {type:"json"};
import vaultSierra from "../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert {type:"json"};
import vaultCasm from "../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json" assert {type:"json"};
import optionRoundSieraa from "../target/dev/pitch_lake_starknet_OptionRound.contract_class.json" assert {type:"json"};
import optionRoundCasm from "../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json" assert {type:"json"};
import marketAggregatorSierra from "../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json" assert {type:"json"};
import marketAggregatorCasm from "../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json" assert {type:"json"};
import { supply, approval } from "./utils/helper/eth";
import { liquidityProviders, optionBidders } from "./utils/constants";
import { smokeTesting } from "./intergration_test/smokeTesting";

async function declareContracts(enviornment: string, port?: string) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);
  let ethHash = await declareContract(
    account,
    ethSierra,
    ethCasm,
    "eth"
  );
  if (!ethHash) {
    throw Error("Eth Deploy Failed");
  }
  let vaultHash = await declareContract(
    account,
    vaultSierra,
    vaultCasm,
    "vault"
  );

  if (!vaultHash) {
    throw Error("Vault Deploy Failed");
  }
  let optionRoundHash = await declareContract(
    account,
    optionRoundSieraa,
    optionRoundCasm,
    "optionRound"
  );

  if (!optionRoundHash) {
    throw Error("OptionRound Deploy Failed");
  }

  let marketAggregatorHash = await declareContract(
    account,
    marketAggregatorSierra,
    marketAggregatorCasm,
    "marketAggregator"
  );
  if (!marketAggregatorHash) {
    throw Error("MarketAggregator Deploy Failed");
  }
  return {
    ethHash,
    vaultHash,
    optionRoundHash,
    marketAggregatorHash,
  };
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

  let ethAddress = await deployEthContract(enviornment, account, hashes.ethHash);
  if(!ethAddress)
    {
      throw Error("Eth deploy failed")
    }

  let marketAggregatorAddress = await deployMarketAggregator(
    enviornment,
    account,
    hashes.marketAggregatorHash
  );
  if(!marketAggregatorAddress)
    {
      throw Error("MktAgg deploy failed")
    }
 
  let vaultAddress = await deployVaultContract(
    enviornment,
    account,
    hashes.vaultHash,
    hashes.optionRoundHash
  );
  if(!vaultAddress)
    {
      throw Error("Eth deploy failed")
    }
    return {
      ethAddress,marketAggregatorAddress,vaultAddress
    }
}

async function supplyEth(
  enviornment: string,
  ethAddress: string,
  approveFor: string,
  port?: string
) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);

  for (let i = 0; i < 2; i++) {
    const lp = getCustomAccount(
      provider,
      liquidityProviders[i].account,
      liquidityProviders[i].privateKey
    );
    const ob = getCustomAccount(
      provider,
      optionBidders[i].account,
      optionBidders[i].privateKey
    );
    await supply(
      provider,
      account,
      liquidityProviders[i].account,
      1000000,
      ethAddress
    );
    await approval(provider, lp, 1000000, ethAddress, approveFor);
    console.log(`Liquidity Provider ${i} funded `);

    await supply(
      provider,
      account,
      optionBidders[i].account,
      1000000,
      ethAddress
    );
    await approval(provider, ob, 1000000, ethAddress, approveFor);
    console.log(`Option Bidder ${i} funded `);
  }
}

async function main(enviornment: string, port?: string) {
  let hashes = await declareContracts(enviornment, port);

  let contractAddresses = await deployContracts(enviornment, hashes, port);

  await supplyEth(enviornment,contractAddresses.ethAddress,contractAddresses.vaultAddress, port);

  await smokeTesting(enviornment,contractAddresses.vaultAddress, port);
}

main(process.argv[2], process.argv[3]);
