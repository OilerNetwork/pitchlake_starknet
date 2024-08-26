import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { marketAggregatorABI } from "../../abi";
import { MarketData } from "./types";

export class MarketAggregatorFacade {
  marketAggregatorContract: TypedContractV2<typeof marketAggregatorABI>;

  constructor(marketAggregatorAddress: string, provider: Provider) {
    this.marketAggregatorContract = new Contract(
      marketAggregatorABI,
      marketAggregatorAddress,
      provider
    ).typedv2(marketAggregatorABI);
  }

  async setVolatility(
    account: Account,
    vaultAddress: string,
    roundId: number | bigint,
    volatility: number | bigint
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_volatility_for_round(
      vaultAddress,
      roundId,
      volatility
    );
  }
  async setCapLevel(
    account: Account,
    vaultAddress: string,
    roundId: number | bigint,
    capLevel: number | bigint
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_cap_level_for_round(
      vaultAddress,
      roundId,
      capLevel
    );
  }
  async setReservePrice(
    account: Account,
    vaultAddress: string,
    roundId: bigint | number,
    reservePrice: number | bigint
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_reserve_price_for_round(
      vaultAddress,
      roundId,
      reservePrice
    );
  }
  async setTWAP(
    account: Account,
    from: number | bigint,
    to: number | bigint,
    reservePrice: number | bigint
  ) {
    this.marketAggregatorContract.connect(account);
    await this.marketAggregatorContract.set_TWAP_for_time_period(
      from,
      to,
      reservePrice
    );
  }

  async setMarketParameters({
    devAccount,
    vaultAddress,
    roundId,
    startDatePeriodA,
    startDatePeriodB,
    endDatePeriodA,
    endDatePeriodB,
    marketData,
  }: {
    devAccount: Account;
    vaultAddress: string;
    roundId: number | bigint;
    startDatePeriodA: number | bigint;
    startDatePeriodB:number|bigint;
    endDatePeriodA: number|bigint;
    endDatePeriodB: number | bigint;
    marketData: MarketData;
  }) {
    await this.setReservePrice(
      devAccount,
      vaultAddress,
      roundId,
      marketData.reservePrice
    );
    await this.setCapLevel(
      devAccount,
      vaultAddress,
      roundId,
      marketData.capLevel
    );

    await this.setVolatility(
      devAccount,
      vaultAddress,
      roundId,
      marketData.capLevel
    )

    await this.setTWAP(
      devAccount,
      startDatePeriodA,
      endDatePeriodA,
      marketData.settlementPrice
    );
    await this.setTWAP(
      devAccount,
      startDatePeriodB,
      endDatePeriodB,
      marketData.settlementPrice
    );
  }
}
