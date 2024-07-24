import {
  Account,
  CairoUint256,
  Contract,
  Provider,
  TypedContractV2,
} from "starknet";
import { optionRoundABI, vaultABI } from "../../abi";
import { Constants, DepositArgs, WithdrawArgs } from "./types";
import {
  accelerateToAuctioning,
  accelerateToRunning,
  accelerateToSettled,
} from "../helpers/accelerators";
import { convertToBigInt, getAccount, stringToHex } from "../helpers/common";
import { MarketAggregatorFacade } from "./marketAggregatorFacade";
import { getOptionRoundContract } from "../helpers/setup";

export class VaultFacade {
  vaultContract: TypedContractV2<typeof vaultABI>;
  currentOptionRound?: TypedContractV2<typeof optionRoundABI>;

  constructor(
    vaultAddress: string,
    provider: Provider,
    optionRoundAddress?: string
  ) {
    this.vaultContract = new Contract(vaultABI, vaultAddress, provider).typedv2(
      vaultABI
    );
    if (optionRoundAddress)
      this.currentOptionRound = new Contract(
        optionRoundABI,
        optionRoundAddress,
        provider
      ).typedv2(optionRoundABI);
  }

  async getTotalLocked() {
    const res = await this.vaultContract.get_total_locked_balance();
    return convertToBigInt(res);
  }

  async getTotalUnLocked() {
    const res = await this.vaultContract.get_total_unlocked_balance();
    return convertToBigInt(res);
  }

  async getLPLockedBalance(address: string) {
    const res = await this.vaultContract.get_lp_locked_balance(address);
    return convertToBigInt(res);
  }


  async getLPUnlockedBalance(address: string) {
    const res = await this.vaultContract.get_lp_unlocked_balance(address);
    return convertToBigInt(res);
  }

  async withdraw({ account, amount }: WithdrawArgs) {
    this.vaultContract.connect(account);
    await this.vaultContract.withdraw_liquidity(amount);
  }

  async deposit({ from, beneficiary, amount }: DepositArgs) {
    this.vaultContract.connect(from);
    try {
      const data = await this.vaultContract.deposit_liquidity(
        amount,
        beneficiary
      );
      data;
    } catch (err) {
      console.log(err);
    }
  }

  //State Transitions
  async startAuction(account: Account) {
    this.vaultContract.connect(account);
    await this.vaultContract.start_auction();
  }

  //@note Only works for katana dev instance with a --dev flag
  async startAuctionBystander(provider: Provider, constants: Constants) {
    const devAccount = getAccount("dev", provider);
    //Set market aggregator reserve_price
    const marketAggregatorString =
      await this.vaultContract.get_market_aggregator();
    const marketAggregatorAddress = "0x" + stringToHex(marketAggregatorString);
    const marketAggFacade = new MarketAggregatorFacade(
      marketAggregatorAddress,
      provider
    );
    const optionRound = await getOptionRoundContract(
      provider,
      this.vaultContract
    );
    const startDate = await optionRound.get_auction_start_date();
    const settleDate = await optionRound.get_option_settlement_date();
    await marketAggFacade.setReservePrice(
      devAccount,
      startDate,
      settleDate,
      constants.reservePrice
    );
    await marketAggFacade.setCapLevel(
      devAccount,
      startDate,
      settleDate,
      constants.capLevel
    );

    await marketAggFacade.setStrikePrice(
      devAccount,
      startDate,
      settleDate,
      constants.strikePrice
    );
    await marketAggFacade.setTWAP(
      devAccount,
      startDate,
      settleDate,
      constants.settlementPrice
    );
    await this.vaultContract.update_round_params();

    await accelerateToAuctioning(provider, this.vaultContract);

    this.vaultContract.connect(devAccount);
    await this.vaultContract.start_auction();
  }

  async endAuction(account: Account) {
    this.vaultContract.connect(account);
    const res = await this.vaultContract.end_auction();
  }

  async endAuctionBystander(provider: Provider) {
    const devAccount = getAccount("dev", provider);
    await accelerateToRunning(provider, this.vaultContract);
    this.vaultContract.connect(devAccount);
    await this.vaultContract.end_auction();
  }

  async settleOptionRound(account: Account) {
    this.vaultContract.connect(account);
    await this.vaultContract.settle_option_round();
  }

  async settleOptionRoundBystander(provider: Provider) {
    await accelerateToSettled(provider, this.vaultContract);
    const devAccount = getAccount("dev", provider);
    await this.settleOptionRound(devAccount);
  }
}
