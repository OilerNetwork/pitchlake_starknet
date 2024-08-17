import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { marketAggregatorABI } from "../../abi";
import { MarketData } from "./types";

export class MarketAggregatorFacade {
  marketAggregatorContract: TypedContractV2<typeof marketAggregatorABI>;

  constructor(marketAggregatorAddress: string, provider: Provider) {
    this.marketAggregatorContract = new Contract(
      marketAggregatorABI,
      marketAggregatorAddress,
      provider,
    ).typedv2(marketAggregatorABI);
  }

  async setCapLevel(
    account: Account,
    from: number | bigint,
    to: number | bigint,
    capLevel: number | bigint,
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_cap_level_for_time_period(
      from,
      to,
      capLevel,
    );
  }
  async setReservePrice(
    account: Account,
    from: number | bigint,
    to: number | bigint,
    reservePrice: number | bigint,
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_reserve_price_for_time_period(
      from,
      to,
      reservePrice,
    );
  }
  async setStrikePrice(
    account: Account,
    from: number | bigint,
    to: number | bigint,
    strikePrice: number | bigint,
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_strike_price_for_time_period(
      from,
      to,
      strikePrice,
    );
  }
  async setTWAP(
    account: Account,
    from: number | bigint,
    to: number | bigint,
    reservePrice: number | bigint,
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_TWAP_for_time_period(
      from,
      to,
      reservePrice,
    );
  }

  async setMarketParameters(
    devAccount: Account,
    startDate: number | bigint,
    settleDate: number | bigint,
    marketData: MarketData,
  ) {
    await this.setReservePrice(
      devAccount,
      startDate,
      settleDate,
      marketData.reservePrice,
    );
    await this.setCapLevel(
      devAccount,
      startDate,
      settleDate,
      marketData.capLevel,
    );

    await this.setStrikePrice(
      devAccount,
      startDate,
      settleDate,
      marketData.strikePrice,
    );
    await this.setTWAP(
      devAccount,
      startDate,
      settleDate,
      marketData.settlementPrice,
    );
  }
}
