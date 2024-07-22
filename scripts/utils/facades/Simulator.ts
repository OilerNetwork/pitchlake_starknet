import { Account } from "starknet";
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
import { getOptionRoundFacade } from "../helpers/setup";

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
  marketData: MarketData;
  exerciseOptionsAllArgs: Array<ExerciseOptionArgs>;
};

export class Simulator {
  public testRunner: TestRunner;

  constructor(testRunner: TestRunner) {
    this.testRunner = testRunner;
  }

  async simulateRound(params: SimulationParameters) {
    //Add market agg setter here or somewhere in openState
    await this.simulateOpenState(params.depositAllArgs);
    await this.simulateAuctioningState(params.bidAllArgs, params.marketData);
    await this.simulateRunningState(params.bidAllArgs);
    await this.simulateSettledState(params.exerciseOptionsAllArgs);
  }

  async simulateOpenState(depositAllArgs: Array<DepositArgs>) {
    await this.testRunner.vaultFacade.depositAll(depositAllArgs);
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
    const optionRoundFacade = await getOptionRoundFacade(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    const approvalArgs = bidAllArgs.map((arg) => {
      const data: ApprovalArgs = {
        owner: arg.from,
        spender: optionRoundFacade.optionRoundContract.address,
        amount: BigInt(arg.amount) * BigInt(arg.price),
      };
      return data;
    });
    await this.testRunner.ethFacade.approveAll(approvalArgs);
    await optionRoundFacade.placeBidsAll(bidAllArgs);
  }
  async simulateRunningState(bidAllArgs: Array<PlaceBidArgs>) {
    const optionRoundFacade = await getOptionRoundFacade(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    let ref: { [key: string]: boolean } = {};
    const refundArgs: Array<RefundUnusedBidsArgs> = [];
    bidAllArgs.map((bids) => {
      if (!ref[bids.from.address]) {
        ref[bids.from.address] = true;
        refundArgs.push({ from: bids.from, optionBidder: bids.from.address });
      }
    });
    await this.testRunner.vaultFacade.endAuctionBystander(
      this.testRunner.provider
    );
    await optionRoundFacade.refundUnusedBidsAll(refundArgs);
  }
  async simulateSettledState(exerciseOptionsArgs: Array<ExerciseOptionArgs>) {
    const optionRoundFacade = await getOptionRoundFacade(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    await this.testRunner.vaultFacade.settleOptionRoundBystander(
      this.testRunner.provider
    );
    await optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);
  }
}
