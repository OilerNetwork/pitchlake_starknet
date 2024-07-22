import { CairoUint256, Contract, Provider, TypedContractV2 } from "starknet";
import { stringToHex } from "./common";
import { erc20ABI, optionRoundABI, vaultABI } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";

export const getOptionRoundFacade = async (
  provider: Provider,
  vault: TypedContractV2<typeof vaultABI>,
  prev?: boolean
) => {
  const optionRoundContract = await getOptionRoundContract(
    provider,
    vault,
    prev
  );
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
  vault: TypedContractV2<typeof vaultABI>,
  prev?: boolean
) => {
  let optionRoundId = await vault.current_option_round_id();
  let id;
  if (typeof optionRoundId !== "number" && typeof optionRoundId !== "bigint") {
    const temp = new CairoUint256(optionRoundId);
    id = temp.toBigInt();
  } else id = BigInt(optionRoundId);
  if (prev) {
    id = id - BigInt(1);
  }
  const optionRoundAddressDecimalString = await vault.get_option_round_address(
    id
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
