import { Contract, Provider, provider, TypedContractV2 } from "starknet";
import { VaultFacade } from "../facades/vaultFacade";
import { stringToHex } from "./common";
import { erc20ABI, optionRoundABI, vaultABI } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";

export const getOptionRoundFacade = async (
  provider: Provider,
  vault: TypedContractV2<typeof vaultABI>
) => {
  const optionRoundContract = await getOptionRoundContract(provider, vault);
  const optionRoundFacade = new OptionRoundFacade(optionRoundContract);
  return optionRoundFacade;
};

export const getOptionRoundERC20Contract = async (
  provider: Provider,
  optionRound: TypedContractV2<typeof optionRoundABI>
) => {
  // const optionRoundContract = await getOptionRoundContract(provider, vault);
  const optionRoundERC20Contract = new Contract(
    erc20ABI,
    optionRound.address,
    provider
  ).typedv2(erc20ABI);
  return optionRoundERC20Contract;
};

export const getOptionRoundContract = async (
  provider: Provider,
  vault: TypedContractV2<typeof vaultABI>
) => {
  const optionRoundId = await vault.current_option_round_id();
  const optionRoundAddressDecimalString = await vault.get_option_round_address(
    optionRoundId
  );
  const optionRoundAddress =
    "0x" + stringToHex(optionRoundAddressDecimalString);
  const optionRoundContract = new Contract(
    optionRoundABI,
    optionRoundAddress,
    provider
  ).typedv2(optionRoundABI);
  return optionRoundContract;
};
