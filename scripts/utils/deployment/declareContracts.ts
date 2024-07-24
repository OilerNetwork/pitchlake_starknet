import { Account } from "starknet";
import ethSierra from "../../../target/dev/pitch_lake_starknet_Eth.contract_class.json" assert { type: "json" };
import ethCasm from "../../../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json" assert { type: "json" };
import vaultSierra from "../../../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert { type: "json" };
import vaultCasm from "../../../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json" assert { type: "json" };
import optionRoundSieraa from "../../../target/dev/pitch_lake_starknet_OptionRound.contract_class.json" assert { type: "json" };
import optionRoundCasm from "../../../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json" assert { type: "json" };
import marketAggregatorSierra from "../../../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json" assert { type: "json" };
import marketAggregatorCasm from "../../../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json" assert { type: "json" };
async function declareContract(
  account: Account,
  sierra: any,
  casm: any,
  placeholder: string
) {
  try {
    const declareResult = await account.declare({
      contract: sierra,
      casm: casm,
    });
    console.log(`Declare result for ${placeholder}: `, declareResult);
    return declareResult.class_hash;
  } catch (err) {
    console.log(`Contract ${placeholder} is already declared`, err);
  }
}

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
export { declareContract, declareContracts };
