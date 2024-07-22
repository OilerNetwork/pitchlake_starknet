import { CairoUint256, Contract, Provider, TypedContractV2 } from "starknet";
import { stringToHex } from "./common";
import { erc20ABI, optionRoundABI, vaultABI } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";
import { SimulationParameters, SimulationSheet } from "../facades/Simulator";
import { getLiquidityProviderAccounts, getOptionBidderAccounts } from "./accounts";
import { DepositArgs, ExerciseOptionArgs, PlaceBidArgs } from "../facades/types";

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

export const generateSimulationParams = (
  provider: Provider,
  simulationSheets: Array<SimulationSheet>
) => {
  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 5);
  const optionBidderAccounts = getOptionBidderAccounts(provider, 5);
  const simulationParams = simulationSheets.map((simulationSheet) => {
    const depositAllArgs = simulationSheet.liquidityProviders.map(
      (provider, index) => {
        return {
          from: liquidityProviderAccounts[provider - 1],
          beneficiary: liquidityProviderAccounts[provider - 1].address,
          amount: simulationSheet.depositAmounts[index],
        } as DepositArgs;
      }
    );
    const bidAllArgs: Array<PlaceBidArgs> = simulationSheet.optionBidders.map(
      (bidder, index) => {
        const data: PlaceBidArgs = {
          from: optionBidderAccounts[bidder - 1],
          amount: BigInt(simulationSheet.bidAmounts[index]),
          price: BigInt(simulationSheet.bidPrices[index]),
        };
        return data;
      }
    );

    const exerciseOptionsAllArgs: Array<ExerciseOptionArgs> =
      simulationSheet.exerciseOptions.map((bidder) => ({
        from: optionBidderAccounts[bidder - 1],
      }));
    const data: SimulationParameters = {
      depositAllArgs,
      bidAllArgs,
      marketData: simulationSheet.marketData,
      exerciseOptionsAllArgs,
    };
    return data;
  });
  return simulationParams;
};
