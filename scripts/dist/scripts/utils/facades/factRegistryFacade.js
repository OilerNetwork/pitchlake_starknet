import { Contract } from "starknet";
import { factRegistryABI } from "../../abi";
export class FactRegistryFacade {
    factRegistryContract;
    constructor(factRegistryAddress, provider) {
        this.factRegistryContract = new Contract(factRegistryABI, factRegistryAddress, provider).typedv2(factRegistryABI);
    }
    async setFact(account, job_request, market_data) {
        this.factRegistryContract.connect(account);
        await this.factRegistryContract.set_fact(job_request, [
            market_data.settlementPrice,
            market_data.volatility,
            market_data.reservePrice,
        ]);
    }
    //  async setVolatility(
    //    account: Account,
    //    vaultAddress: string,
    //    roundId: number | bigint,
    //    volatility: number | bigint,
    //  ) {
    //    this.marketAggregatorContract.connect(account);
    //    await this.marketAggregatorContract.set_volatility_for_round(
    //      vaultAddress,
    //      roundId,
    //      volatility,
    //    );
    //  }
    //  async setCapLevel(
    //    account: Account,
    //    vaultAddress: string,
    //    roundId: number | bigint,
    //    capLevel: number | bigint,
    //  ) {
    //    this.marketAggregatorContract.connect(account);
    //    await this.marketAggregatorContract.set_cap_level_for_round(
    //      vaultAddress,
    //      roundId,
    //      capLevel,
    //    );
    //  }
    //  async setReservePrice(
    //    account: Account,
    //    vaultAddress: string,
    //    roundId: bigint | number,
    //    reservePrice: number | bigint,
    //  ) {
    //    this.marketAggregatorContract.connect(account);
    //    await this.marketAggregatorContract.set_reserve_price_for_round(
    //      vaultAddress,
    //      roundId,
    //      reservePrice,
    //    );
    //  }
    //  async setTWAP(
    //    account: Account,
    //    from: number | bigint,
    //    to: number | bigint,
    //    reservePrice: number | bigint,
    //  ) {
    //    this.marketAggregatorContract.connect(account);
    //    await this.marketAggregatorContract.set_TWAP_for_time_period(
    //      from,
    //      to,
    //      reservePrice,
    //    );
    //  }
    async setMarketParameters({ devAccount, jobRequest, marketData, }) {
        // job_request and data
        await this.setFact(devAccount, jobRequest, marketData);
        //    await this.setReservePrice(
        //      devAccount,
        //      vaultAddress,
        //      roundId,
        //      marketData.reservePrice,
        //    );
        //    await this.setCapLevel(
        //      devAccount,
        //      vaultAddress,
        //      roundId,
        //      marketData.capLevel,
        //    );
        //
        //    await this.setVolatility(
        //      devAccount,
        //      vaultAddress,
        //      roundId,
        //      marketData.capLevel,
        //    );
        //
        //    await this.setTWAP(
        //      devAccount,
        //      startDatePeriodA,
        //      endDatePeriodA,
        //      marketData.settlementPrice,
        //    );
        //    await this.setTWAP(
        //      devAccount,
        //      startDatePeriodB,
        //      endDatePeriodB,
        //      marketData.settlementPrice,
        //    );
    }
}
