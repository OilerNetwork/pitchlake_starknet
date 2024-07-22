import {  TypedContractV2 } from "starknet";
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
  exerciseOptionsAllArgs: Array<ExerciseOptionArgs>;
  marketData: MarketData;
};

export class RoundSimulator {
  public testRunner: TestRunner;
  public optionRoundFacade: OptionRoundFacade;

  constructor(
    testRunner: TestRunner,
    optionRoundContract: TypedContractV2<typeof optionRoundABI>
  ) {
    this.testRunner = testRunner;
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
  }

  async simulateRound(params: SimulationParameters) {
    //Add market agg setter here or somewhere in openState
    await this.simulateOpenState(params.depositAllArgs);
    await this.simulateAuctioningState(params.bidAllArgs, params.marketData);
    await this.simulateRunningState(params.refundAllArgs);
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
  }
  async simulateRunningState(refundAllArgs: Array<RefundUnusedBidsArgs>) {

    await this.testRunner.vaultFacade.endAuctionBystander(
      this.testRunner.provider
    );
    await this.optionRoundFacade.refundUnusedBidsAll(refundAllArgs);
  }
  async simulateSettledState(exerciseOptionsArgs: Array<ExerciseOptionArgs>) {
    await this.testRunner.vaultFacade.settleOptionRoundBystander(
      this.testRunner.provider
    );
    await this.optionRoundFacade.exerciseOptionsAll(exerciseOptionsArgs);

    //Update optionRoundFacade
    const optionRoundContract = await getOptionRoundContract(
      this.testRunner.provider,
      this.testRunner.vaultFacade.vaultContract
    );
    this.optionRoundFacade = new OptionRoundFacade(optionRoundContract);
  }
}
