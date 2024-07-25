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

    //Add market agg setter here or somewhere in openState
    const openStateData = await this.simulateOpenState(params.depositAllArgs);
    const AuctioningStateData = await this.simulateAuctioningState(
      params.bidAllArgs,
      params.marketData
    );
    const RunningStateData = this.simulateRunningState(params.refundAllArgs);
    const settledStateData = await this.simulateSettledState(
      params.exerciseOptionsAllArgs
    );
  }

  async captureLockedUnlockedBalances() {
    const lpLockedBalances =
      await this.testRunner.getLPLockedBalanceAll(this.lpAccounts);
    const lpUnlockedBalances =
      await this.testRunner.getLPUnlockedBalanceAll(
        this.lpAccounts
      );
    return { lpLockedBalances, lpUnlockedBalances };
  }

  async captureEthBalancesLiquidityProviders() {
    const ethBalances = await this.testRunner.getBalancesAll(
      this.lpAccounts
    );
    return ethBalances;
  }

  async captureEthBalancesOptionBidders() {
    const ethBalances = await this.testRunner.getBalancesAll(
      this.bidderAccounts
    );
    return ethBalances;
  }
  async simulateOpenState(depositAllArgs: Array<DepositArgs>) {
    await this.testRunner.depositAll(depositAllArgs);
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
    await this.testRunner.approveAll(approvalArgs);

    await this.optionRoundFacade.placeBidsAll(bidAllArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();
    return {
      lockedUnlockedBalances,
      ethBalancesBidders,
    };
  }
  async simulateRunningState(refundAllArgs: Array<RefundUnusedBidsArgs>) {
    await this.testRunner.vaultFacade.endAuctionBystander(
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
    console.log("1");
    await this.testRunner.vaultFacade.settleOptionRoundBystander(
      this.testRunner.provider
    );
    console.log("2");
  
    const lpLockedUnlockedBalances = await this.captureLockedUnlockedBalances();  console.log("3");
    await this.optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);
    const ethBalancesBidders = await this.captureEthBalancesOptionBidders();

    //Update optionRoundFacade
    const optionRoundContract = await getOptionRoundContract(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    return {
      lpLockedUnlockedBalances,
      ethBalancesBidders,
    };
  }
}
