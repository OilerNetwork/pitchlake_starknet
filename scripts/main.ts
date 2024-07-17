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
import { ABI as ethAbi } from "./abi/ethAbi";
import { declareContract } from "./deployments/declareContracts";
import ethSierra from "../target/dev/pitch_lake_starknet_Eth.contract_class.json" assert { type: "json" };
import ethCasm from "../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json" assert { type: "json" };
import vaultSierra from "../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert { type: "json" };
import vaultCasm from "../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json" assert { type: "json" };
import optionRoundSieraa from "../target/dev/pitch_lake_starknet_OptionRound.contract_class.json" assert { type: "json" };
import optionRoundCasm from "../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json" assert { type: "json" };
import marketAggregatorSierra from "../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json" assert { type: "json" };
import marketAggregatorCasm from "../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json" assert { type: "json" };
import { supply, approval } from "./utils/facades/eth";
import { liquidityProviders, optionBidders } from "./utils/constants";
import { smokeTesting } from "./integrationTests/smokeTesting";
import { Account, Contract, Provider } from "starknet";

async function declareContracts(account: Account) {
  let ethHash = await declareContract(account, ethSierra, ethCasm, "eth");
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
  account: Account,
  hashes: {
    ethHash: string;
    vaultHash: string;
    optionRoundHash: string;
    marketAggregatorHash: string;
  }
) {
  let ethAddress = await deployEthContract(
    enviornment,
    account,
    hashes.ethHash
  );
  if (!ethAddress) {
    throw Error("Eth deploy failed");
  }

  let marketAggregatorAddress = await deployMarketAggregator(
    enviornment,
    account,
    hashes.marketAggregatorHash
  );
  if (!marketAggregatorAddress) {
    throw Error("MktAgg deploy failed");
  }

  let vaultAddress = await deployVaultContract(
    enviornment,
    account,
    {
      marketAggregatorContract: marketAggregatorAddress,
      ethContract: ethAddress,
      vaultManager: account.address,
    },
    { optionRound: hashes.optionRoundHash, vault: hashes.vaultHash }
  );
  if (!vaultAddress) {
    throw Error("Eth deploy failed");
  }
  return {
    ethAddress,
    marketAggregatorAddress,
    vaultAddress,
  };
}

async function supplyEth(
  devAccount: Account,
  provider: Provider,
  ethAddress: string,
  approveFor: string
) {
  const ethContract = new Contract(ethAbi, ethAddress, provider).typedv2(
    ethAbi
  );

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
    await supply(devAccount,liquidityProviders[i].account, 1000000, ethContract);
    await approval(
      { owner: lp, amount: 1000000, spender: approveFor },
      ethContract
    );
    console.log(`Liquidity Provider ${i} funded `);

    await supply(devAccount, optionBidders[i].account, 1000000, ethContract);
    await approval({owner:ob, amount:1000000,spender:approveFor}, ethContract, );
    console.log(`Option Bidder ${i} funded `);
  }
}

async function main(environment: string, port?: string) {
  const provider = getProvider(environment, port);
  const devAccount = getAccount(environment, provider);
  let hashes = await declareContracts(devAccount);

  let contractAddresses = await deployContracts(
    environment,
    devAccount,
    hashes
  );

  await supplyEth(
    devAccount,
    provider,
    contractAddresses.ethAddress,
    contractAddresses.vaultAddress
  );

  //Can write to a file here and replace smoke test call to use multiple

  await smokeTesting(
    provider,
    contractAddresses.vaultAddress,
    contractAddresses.ethAddress
  );
}

main(process.argv[2], process.argv[3]);
