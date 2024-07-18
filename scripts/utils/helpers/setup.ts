import { Contract, Provider, provider } from "starknet";
import { VaultFacade } from "../facades/vaultFacade";
import { stringToHex } from "./common";
import { optionRoundAbi } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";

export const setupOptionRound = async (
  vaultFacade: VaultFacade,
  provider: Provider
) => {
  const optionRoundId =
    await vaultFacade.vaultContract.current_option_round_id();
  const optionRoundAddressDecimalString =
    await vaultFacade.vaultContract.get_option_round_address(optionRoundId);
  const optionRoundAddressHexString: string =
    "0x" + stringToHex(optionRoundAddressDecimalString);

  const optionRoundContract = new Contract(
    optionRoundAbi,
    optionRoundAddressHexString,
    provider
  ).typedv2(optionRoundAbi);

  const optionRoundFacade = new OptionRoundFacade(optionRoundContract);
  return optionRoundFacade;
};
