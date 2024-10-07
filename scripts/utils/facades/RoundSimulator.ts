import { Account, TypedContractV2 } from "starknet";
import {
  ApprovalArgs,
  DepositArgs,
  ExerciseOptionArgs,
  MarketData,
  PlaceBidArgs,
  RefundUnusedBidsArgs,
  WithdrawArgs,
} from "./types";
import { TestRunner } from "./TestRunner";
import { getOptionRoundContract } from "../helpers/setup";
import { optionRoundABI } from "../../abi";
import { OptionRoundFacade } from "./optionRoundFacade";

export type SimulationSheet = {
  liquidityProviders: Array<number>;
  optionBidders: Array<number>;
  depositAmounts: Array<number | string>;
  bidAmounts: Array<number | string>;
  bidPrices: Array<number | string>;
  withdrawalsPremium?: Array<number>;
  withdrawalsFromQueue?: Array<number>;
  withdrawalsFromQueueAmounts?: Array<number | string>;
  withdrawals?: Array<number>;
  withdrawalAmounts?: Array<number | string>;
  marketData: MarketData;
};

export type SimulationParameters = {
  depositAllArgs: Array<DepositArgs>;
  bidAllArgs: Array<PlaceBidArgs>;
  refundAllArgs: Array<RefundUnusedBidsArgs>;
  lpAccounts?: Array<Account>;
  bidderAccounts?: Array<Account>;
  withdrawPremiumArgs: Array<WithdrawArgs>;
  withdrawalQueueArgs?: Array<WithdrawArgs>;
  withdrawalArgs: Array<WithdrawArgs>;
  exerciseOptionsAllArgs: Array<ExerciseOptionArgs>;
  marketData: MarketData;
};

export type StateData = {
  lockedUnlockedBalances: {
    lpLockedBalances: Array<string>;
    lpUnlockedBalances: Array<string>;
  };
  vaultBalances: {
    vaultLocked: string;
    vaultUnlocked: string;
  };
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
    optionRoundContract: TypedContractV2<typeof optionRoundABI>,
  ) {
    this.testRunner = testRunner;
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    this.lpAccounts = testRunner.getLiquidityProviderAccounts(5);
    this.bidderAccounts = testRunner.getOptionBidderAccounts(5);
  }

  async simulateRound(params: SimulationParameters) {
    const optionRoundContract = await getOptionRoundContract(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract,
    );
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    //Add market agg setter here or somewhere in openState

    const openStateData: StateData = await this.simulateOpenState(
      params.depositAllArgs,
    );
    const auctioningStateData: StateData = await this.simulateAuctioningState(
      params.bidAllArgs,
    );
    const optionsAvailable =
      await this.optionRoundFacade.getTotalOptionsAvailable();
    const runningStateData: StateData = await this.simulateRunningState(
      params.refundAllArgs,
      params.withdrawPremiumArgs,
    );
    const settledStateData: StateData = await this.simulateSettledState(
      params.exerciseOptionsAllArgs,
      params.withdrawalArgs,
      params.marketData,
    );
    const optionsSold =
      await this.optionRoundFacade.optionRoundContract.get_options_sold();

    const ethBalanceVault = await this.testRunner.ethFacade.getBalance(
      this.testRunner.vaultFacade.vaultContract.address,
    );
    const ethBalanceRound = await this.testRunner.ethFacade.getBalance(
      this.optionRoundFacade.optionRoundContract.address,
    );
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
      ethBalanceRound: ethBalanceRound.toString(),
      ethBalanceVault: ethBalanceVault.toString(),
      optionsAvailable: optionsAvailable.toString(),
      optionsSold: optionsSold.toString(),
      openStateData,
      auctioningStateData,
      runningStateData,
      settledStateData,
    };
  }

  async captureLockedUnlockedBalances() {
    const lpLockedBalancesBigInt = await this.testRunner.getLPLockedBalanceAll(
      this.lpAccounts,
    );
    const lpUnlockedBalancesBigint =
      await this.testRunner.getLPUnlockedBalanceAll(this.lpAccounts);
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
      this.lpAccounts,
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
      vaultLocked: locked.toString(),
      vaultUnlocked: unlocked.toString(),
    };
  }

  async captureEthBalancesOptionBidders() {
    const ethBalancesBigInt = await this.testRunner.getBalancesAll(
      this.bidderAccounts,
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
  async simulateAuctioningState(bidAllArgs: Array<PlaceBidArgs>) {
    await this.testRunner.startAuctionBystander();

    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    const optionsAvailable =
      await this.optionRoundFacade.getTotalOptionsAvailable();

    const bidAllArgsAdjusted = bidAllArgs.map((args) => {
      return {
        from: args.from,
        amount: Math.floor(Number(args.amount) * Number(optionsAvailable)),
        price: args.price,
      } as PlaceBidArgs;
    });
    const approvalArgs = bidAllArgsAdjusted.map((arg) => {
      const data: ApprovalArgs = {
        owner: arg.from,
        spender: this.optionRoundFacade.optionRoundContract.address,
        amount: BigInt(arg.amount) * BigInt(arg.price),
      };
      return data;
    });

    await this.testRunner.approveAll(approvalArgs);

    await this.optionRoundFacade.placeBidsAll(bidAllArgsAdjusted);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances,
    };
  }
  async simulateRunningState(
    refundAllArgs: Array<RefundUnusedBidsArgs>,
    withdrawPremiumArgs: Array<WithdrawArgs>,
  ) {
    await this.testRunner.endAuctionBystander();

    const totalPremiums = await this.optionRoundFacade.getTotalPremiums();
    const startingLiquidity =
      await this.optionRoundFacade.getStartingLiquidity();
    const withdrawPremiumArgsAdjusted: Array<WithdrawArgs> = [];
    for (const args of withdrawPremiumArgs) {
      const lockedBalance =
        await this.testRunner.vaultFacade.getLPLockedBalance(
          args.account.address,
        );
      const premiumsToWithdraw =
        (BigInt(lockedBalance) * BigInt(totalPremiums)) /
        BigInt(startingLiquidity);
      withdrawPremiumArgs.push({
        account: args.account,
        amount: Math.floor(Number(premiumsToWithdraw)),
      });
    }

    await this.testRunner.withdrawAll(withdrawPremiumArgsAdjusted);
    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    await this.optionRoundFacade.refundUnusedBidsAll(refundAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances,
    };
  }
  async simulateSettledState(
    exerciseOptionsArgs: Array<ExerciseOptionArgs>,
    withdrawalArgs: Array<WithdrawArgs>,
    marketData: MarketData,
  ) {
    const data = await this.optionRoundFacade.optionRoundContract.get_state();
    await this.testRunner.settleOptionRoundBystander(marketData);

    const withdrawArgsAdjusted: Array<WithdrawArgs> = [];

    for (const args of withdrawalArgs) {
      const unlockedBalance =
        await this.testRunner.vaultFacade.getLPUnlockedBalance(
          args.account.address,
        );
      console.log("UNLOCKED", unlockedBalance);
      withdrawArgsAdjusted.push({
        account: args.account,
        amount: Math.floor(Number(args.amount) * Number(unlockedBalance)),
      });
    }

    const lpBefore = await this.captureLockedUnlockedBalances();
    await this.testRunner.withdrawAll(withdrawArgsAdjusted);
    const lpAfter = await this.captureLockedUnlockedBalances();
    console.log("ARGS:", withdrawalArgs, "\nADjusted:", withdrawArgsAdjusted);
    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const vaultBalances = await this.captureVaultBalances();
    await this.optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();

    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
      vaultBalances,
    };
  }
}
