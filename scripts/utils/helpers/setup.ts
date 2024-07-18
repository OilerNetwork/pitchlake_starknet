import { Contract, Provider, provider, TypedContractV2 } from "starknet";
import { VaultFacade } from "../facades/vaultFacade";
import { stringToHex } from "./common";
import { optionRoundAbi, vaultAbi } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";

export const getOptionRoundFacade = async (
  provider: Provider,
  vault:  TypedContractV2<typeof vaultAbi>
) => {

  const optionRoundContract = await getOptionRoundContract(
    provider,
    vault
  );
  const optionRoundFacade = new OptionRoundFacade(optionRoundContract);
  return optionRoundFacade;
};

export const getOptionRoundContract = async (
  provider: Provider,
  vault: TypedContractV2<typeof vaultAbi>
) => {
  const optionRoundId = await vault.current_option_round_id();
  const optionRoundAddressDecimalString = await vault.get_option_round_address(
    optionRoundId
  );
  const optionRoundAddress =
    "0x" + stringToHex(optionRoundAddressDecimalString);
  const optionRoundContract = new Contract(
    optionRoundAbi,
    optionRoundAddress,
    provider
  ).typedv2(optionRoundAbi);
  return optionRoundContract;
};
