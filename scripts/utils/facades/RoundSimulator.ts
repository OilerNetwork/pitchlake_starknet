import { Account, TypedContractV2 } from "starknet";
import {
  ApprovalArgs,
  DepositArgs,
  ExerciseOptionArgs,
  MarketData,
  PlaceBidArgs,
  RefundableBidsArgs,
  RefundUnusedBidsArgs,
} from "./types";
import { TestRunner } from "./TestRunner";
import { getOptionRoundContract, getOptionRoundFacade } from "../helpers/setup";
import { optionRoundABI } from "../../abi";
import { OptionRoundFacade } from "./optionRoundFacade";
import {
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
} from "../helpers/accounts";

export type SimulationSheet = {
  liquidityProviders: Array<number>;
  optionBidders: Array<number>;
  depositAmounts: Array<number | string>;
  bidAmounts: Array<number | string>;
  bidPrices: Array<number | string>;
  marketData: MarketData;
  exerciseOptions: Array<number>;
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
    this.lpAccounts = getLiquidityProviderAccounts(testRunner.provider, 5);
    this.bidderAccounts = getOptionBidderAccounts(testRunner.provider, 5);
  }

  async simulateRound(params: SimulationParameters) {
    const optionRoundContract = await getOptionRoundContract(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    //Add market agg setter here or somewhere in openState
    const openStateData = await this.simulateOpenState(params.depositAllArgs);
    const auctioningStateData = await this.simulateAuctioningState(
      params.bidAllArgs,
      params.marketData
    );
    const runningStateData = await this.simulateRunningState(
      params.refundAllArgs
    );
    const settledStateData = await this.simulateSettledState(
      params.exerciseOptionsAllArgs
    );

    return {
      openStateData,
      auctioningStateData,
      runningStateData,
      settledStateData,
    };
  }

  async captureLockedUnlockedBalances() {
    const lpLockedBalancesBigInt =
      await this.testRunner.vaultFacade.getLPLockedBalanceAll(this.lpAccounts);
    const lpUnlockedBalancesBigint =
      await this.testRunner.vaultFacade.getLPUnlockedBalanceAll(
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
    const ethBalancesBigInt = await this.testRunner.ethFacade.getBalancesAll(
      this.lpAccounts
    );
    const ethBalances = ethBalancesBigInt.map((balance) => {
      return balance.toString();
    });
    return ethBalances;
  }

  async captureEthBalancesOptionBidders() {
    const ethBalancesBigInt = await this.testRunner.ethFacade.getBalancesAll(
      this.bidderAccounts
    );
    const ethBalances = ethBalancesBigInt.map((balance) => {
      return balance.toString();
    });
    return ethBalances;
  }
  async simulateOpenState(depositAllArgs: Array<DepositArgs>) {
    await this.testRunner.vaultFacade.depositAll(depositAllArgs);
    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
    };
    //Add market data setter abstraction after Jithin's merge
  }
  async simulateAuctioningState(
    bidAllArgs: Array<PlaceBidArgs>,
    marketData: MarketData
  ) {
    await this.testRunner.vaultFacade.startAuctionBystander(
      this.testRunner.provider,
      marketData
    );

    const lockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    const approvalArgs = bidAllArgs.map((arg) => {
      const data: ApprovalArgs = {
        owner: arg.from,
        spender: this.optionRoundFacade.optionRoundContract.address,
        amount: BigInt(arg.amount) * BigInt(arg.price),
      };
      return data;
    });
    await this.testRunner.ethFacade.approveAll(approvalArgs);

    await this.optionRoundFacade.placeBidsAll(bidAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
    };
  }
  async simulateRunningState(refundAllArgs: Array<RefundUnusedBidsArgs>) {
    const data = await this.testRunner.vaultFacade.endAuctionBystander(
      this.testRunner.provider
    );

    const lpLockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    await this.optionRoundFacade.refundUnusedBidsAll(refundAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lpLockedUnlockedBalances,
      ethBalancesBidders,
    };
  }
  async simulateSettledState(exerciseOptionsArgs: Array<ExerciseOptionArgs>) {
    const data = await this.optionRoundFacade.optionRoundContract.get_state();
    await this.testRunner.vaultFacade.settleOptionRoundBystander(
      this.testRunner.provider
    );

    const lpLockedUnlockedBalances = await this.captureLockedUnlockedBalances();
    console.log("3");
    await this.optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();

    return {
      lpLockedUnlockedBalances,
      ethBalancesBidders,
    };
  }
}
