import { CairoUint256, Contract, Provider, TypedContractV2 } from "starknet";
import { stringToHex } from "./common";
import { erc20ABI, optionRoundABI, vaultABI } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";
import {
  SimulationParameters,
  SimulationSheet,
} from "../facades/RoundSimulator";
import {
  DepositArgs,
  ExerciseOptionArgs,
  PlaceBidArgs,
  RefundUnusedBidsArgs,
  WithdrawArgs,
} from "../facades/types";
import { TestRunner } from "../facades/TestRunner";
import { liquidityProviders } from "../constants";

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
  let optionRoundId = await vault.get_current_round_id();
  let id;
  if (typeof optionRoundId !== "number" && typeof optionRoundId !== "bigint") {
    const temp = new CairoUint256(optionRoundId);
    id = temp.toBigInt();
  } else id = BigInt(optionRoundId);
  if (prev) {
    id = id - BigInt(1);
  }
  const optionRoundAddressDecimalString = await vault.get_round_address(
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
  { getLiquidityProviderAccounts, getOptionBidderAccounts }: TestRunner,
  simulationSheets: Array<SimulationSheet>
) => {
  const liquidityProviderAccounts = getLiquidityProviderAccounts(5);
  const optionBidderAccounts = getOptionBidderAccounts(5);
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
          amount: Number(simulationSheet.bidAmounts[index]),
          price: BigInt(simulationSheet.bidPrices[index]),
        };
        return data;
      }
    );
    let ref: { [key: string]: boolean } = {};
    const refundAllArgs: Array<RefundUnusedBidsArgs> = [];
    bidAllArgs.map((bids) => {
      if (!ref[bids.from.address]) {
        ref[bids.from.address] = true;
        refundAllArgs.push({
          from: bids.from,
          optionBidder: bids.from.address,
        });
      }
    });

    let withdrawPremiumArgs: Array<WithdrawArgs> = [];
    if (simulationSheet.withdrawalsPremium) {
      withdrawPremiumArgs = simulationSheet.withdrawalsPremium.map(
        (bidder) => ({
          account: liquidityProviderAccounts[bidder - 1],
          amount: 0,
        })
      );
    }

    let withdrawalArgs: Array<WithdrawArgs> = [];
    if (simulationSheet.withdrawalAmounts && simulationSheet.withdrawals) {
      withdrawalArgs = simulationSheet.withdrawals.map((bidder, index) => {
        return {
          account: liquidityProviderAccounts[bidder - 1],
          amount: Number(
            simulationSheet.withdrawalAmounts
              ? simulationSheet.withdrawalAmounts[index]
              : 0
          ),
        };
      });
    }

    const exerciseOptionsAllArgs: Array<ExerciseOptionArgs> =
      simulationSheet.optionBidders.map((bidder) => ({
        from: optionBidderAccounts[bidder - 1],
      }));
    const data: SimulationParameters = {
      depositAllArgs,
      bidAllArgs,
      marketData: simulationSheet.marketData,
      withdrawPremiumArgs,
      withdrawalArgs,
      exerciseOptionsAllArgs,
      refundAllArgs,
    };
    return data;
  });
  return simulationParams;
};
