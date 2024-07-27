import { Account, TypedContractV2 } from "starknet";
import {
  ApprovalArgs,
  DepositArgs,
  ExerciseOptionArgs,
  MarketData,
  PlaceBidArgs,
  RefundUnusedBidsArgs,
} from "./types";
import { TestRunner } from "./TestRunner";
import { getOptionRoundContract, getOptionRoundFacade } from "../helpers/setup";
import { optionRoundABI } from "../../abi";
import { OptionRoundFacade } from "./optionRoundFacade";

export type SimulationSheet = {
  liquidityProviders: Array<number>;
  optionBidders: Array<number>;
  depositAmounts: Array<number | string>;
  bidAmounts: Array<number | string>;
  bidPrices: Array<number | string>;
  marketData: MarketData;
};

export type SimulationParameters = {
  depositAllArgs: Array<DepositArgs>;
  bidAllArgs: Array<PlaceBidArgs>;
  refundAllArgs: Array<RefundUnusedBidsArgs>;
  lpAccounts?: Array<Account>;
  bidderAccounts?: Array<Account>;

  exerciseOptionsAllArgs: Array<ExerciseOptionArgs>;
  marketData: MarketData;
};

export type StateData = {
  lockedUnlockedBalances: {
    lpLockedBalances: Array<string>;
    lpUnlockedBalances: Array<string>;
  };
  vaultBalances:{
    vaultLocked:string;
    vaultUnlocked:string;
  }
  ethBalancesBidders: Array<string>;
  timeStamp?: string | number;
};
export class RoundSimulator {
  public testRunner: TestRunner;
  public optionRoundFacade: OptionRoundFacade;
  public lpAccounts: Array<Account>;
  public bidderAccounts: Array<Account>;

  constructor(
    testRunner: TestRunner,
    optionRoundContract: TypedContractV2<typeof optionRoundABI>
  ) {
    this.testRunner = testRunner;
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    this.lpAccounts = testRunner.getLiquidityProviderAccounts(5);
    this.bidderAccounts = testRunner.getOptionBidderAccounts(5);
  }

  async simulateRound(params: SimulationParameters) {
    const optionRoundContract = await getOptionRoundContract(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    //Add market agg setter here or somewhere in openState

    const openStateData: StateData = await this.simulateOpenState(
      params.depositAllArgs
    );
    const auctioningStateData: StateData = await this.simulateAuctioningState(
      params.bidAllArgs,
      params.marketData
    );
    const optionsAvailable = await this.optionRoundFacade.getTotalOptionsAvailable();
    const runningStateData: StateData = await this.simulateRunningState(
      params.refundAllArgs
    );
    const settledStateData: StateData = await this.simulateSettledState(
      params.exerciseOptionsAllArgs
    );
    const optionsSold = await this.optionRoundFacade.optionRoundContract.total_options_sold();

    const ethBalanceVault = await this.testRunner.ethFacade.getBalance(this.testRunner.vaultFacade.vaultContract.address);
    const ethBalanceRound = await this.testRunner.ethFacade.getBalance(this.optionRoundFacade.optionRoundContract.address);
    if (params.marketData.startTime && params.marketData.endTime) {

      //Mock timestamps if present on the marketData
      const difference =
        Number(params.marketData.endTime) - Number(params.marketData.startTime);
      openStateData.timeStamp =
        Number(params.marketData.startTime) + Math.floor(difference / 8);
      auctioningStateData.timeStamp =
        Number(params.marketData.startTime) + Math.floor((3 * difference) / 8);
      runningStateData.timeStamp =
        Number(params.marketData.startTime) + Math.floor((5 * difference) / 8);
      settledStateData.timeStamp =
        Number(params.marketData.startTime) + Math.floor((7 * difference) / 8);
    }

    return {
      ethBalanceRound:ethBalanceRound.toString(),
      ethBalanceVault:ethBalanceVault.toString(),
      optionsAvailable:optionsAvailable.toString(),
      optionsSold:optionsSold.toString(),
      openStateData,
      auctioningStateData,
      runningStateData,
      settledStateData,
    };
  }

  async captureLockedUnlockedBalances() {
    const lpLockedBalancesBigInt =
      await this.testRunner.getLPLockedBalanceAll(this.lpAccounts);
    const lpUnlockedBalancesBigint =
      await this.testRunner.getLPUnlockedBalanceAll(
        this.lpAccounts
      );
    const lpLockedBalances = lpLockedBalancesBigInt.map((balance) => {
      return balance.toString();
    });
    const lpUnlockedBalances = lpUnlockedBalancesBigint.map((balance) => {
      return balance.toString();
    });
    return { lpLockedBalances, lpUnlockedBalances };
  }

  async captureEthBalancesLiquidityProviders() {
    const ethBalancesBigInt = await this.testRunner.getBalancesAll(
      this.lpAccounts
    );
    const ethBalances = ethBalancesBigInt.map((balance) => {
      return balance.toString();
    });
    return ethBalances;
  }

  async captureVaultBalances() {
    const locked = await this.testRunner.vaultFacade.getTotalLocked();
    const unlocked = await this.testRunner.vaultFacade.getTotalUnLocked();
    return {
      vaultLocked:locked.toString(),
      vaultUnlocked:unlocked.toString()
    } 
  }

  async captureEthBalancesOptionBidders() {
    const ethBalancesBigInt = await this.testRunner.getBalancesAll(
      this.bidderAccounts
    );
    const ethBalances = ethBalancesBigInt.map((balance) => {
      return balance.toString();
    });
    return ethBalances;
  }
  async simulateOpenState(depositAllArgs: Array<DepositArgs>) {
    await this.testRunner.depositAll(depositAllArgs);
    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    const vaultBalances = await this.captureVaultBalances();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances,
    };
    //Add market data setter abstraction after Jithin's merge
  }
  async simulateAuctioningState(
    bidAllArgs: Array<PlaceBidArgs>,
    marketData: MarketData
  ) {
    await this.testRunner.startAuctionBystander(marketData);

    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    const approvalArgs = bidAllArgs.map((arg) => {
      const data: ApprovalArgs = {
        owner: arg.from,
        spender: this.optionRoundFacade.optionRoundContract.address,
        amount: BigInt(arg.amount) * BigInt(arg.price),
      };
      return data;
    });
    await this.testRunner.approveAll(approvalArgs);

    await this.optionRoundFacade.placeBidsAll(bidAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances
    };
  }
  async simulateRunningState(refundAllArgs: Array<RefundUnusedBidsArgs>) {
    const data = await this.testRunner.endAuctionBystander();

    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    await this.optionRoundFacade.refundUnusedBidsAll(refundAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances
    };
  }
  async simulateSettledState(exerciseOptionsArgs: Array<ExerciseOptionArgs>) {
    const data = await this.optionRoundFacade.optionRoundContract.get_state();
    await this.testRunner.settleOptionRoundBystander();

    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    console.log("3");
    await this.optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();

    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances,
    };
  }
}
