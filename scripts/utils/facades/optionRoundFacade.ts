import { Account, CairoUint256, TypedContractV2 } from "starknet";
import {
  Bid,
  ExerciseOptionArgs,
  OptionBalanceArgs,
  PayoutBalanceArgs,
  PlaceBidArgs,
  RefundableBidsArgs,
  RefundUnusedBidsArgs,
  TokenizableOptionsArgs,
  TokenizeOptionArgs,
  UpdateBidArgs,
} from "./types";
import { optionRoundABI } from "../../abi";

export class OptionRoundFacade {
  optionRoundContract: TypedContractV2<typeof optionRoundABI>;

  constructor(optionRoundContract: TypedContractV2<typeof optionRoundABI>) {
    this.optionRoundContract = optionRoundContract;
  }

  async getTotalPremiums() {
    const res = await this.optionRoundContract.total_premiums();
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    } else return res;
  }
  async getTotalOptionsAvailable() {
    const res = await this.optionRoundContract.get_total_options_available();
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    } else return res;
  }
  async getReservePrice() {
    const res = await this.optionRoundContract.get_reserve_price();
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    } else return res;
  }
  async getBidsFor(address: string) {
    const res = await this.optionRoundContract.get_bids_for(address);
    const bids: Array<Bid> = [];

    for (let data of res) {
      let amount: number | bigint;
      let price: number | bigint;
      if (typeof data.amount !== "bigint" && typeof data.amount !== "number") {
        const res = new CairoUint256(data.amount);
        amount = res.toBigInt();
      } else {
        amount = data.amount;
      }

      if (typeof data.price !== "bigint" && typeof data.price !== "number") {
        const res = new CairoUint256(data.price);
        price = res.toBigInt();
      } else {
        price = data.price;
      }
      const bid: Bid = {
        id: data.id,
        amount: amount,
        nonce: data.nonce,
        owner: data.owner,
        price: price,
        isTokenized: data.is_tokenized,
        isRefunded: data.is_refunded,
      };
      bids.push(bid);
    }
    return bids;
  }

  async getBidsForAll(accounts: Array<Account>) {
    const bids = await Promise.all(
      accounts.map(async (account: Account) => {
        const bidData = await this.getBidsFor(account.address);
        return bidData;
      })
    );
    return bids;
  }
  async updateBid({ bidId, from, amount, price }: UpdateBidArgs) {
    this.optionRoundContract.connect(from);
    try {
      await this.optionRoundContract.update_bid(bidId, amount, price);
    } catch (err) {
      console.log(err);
    }
  }

  async placeBid({ from, amount, price }: PlaceBidArgs) {
    this.optionRoundContract.connect(from);
    try {
      const data = await this.optionRoundContract.place_bid(amount, price);
    } catch (err) {
      console.log(err);
    }
  }

  async placeBidsAll(placeBidData: Array<PlaceBidArgs>) {
    for (const placeBidArgs of placeBidData) {
      await this.placeBid(placeBidArgs);
    }
  }

  async getRefundableBidsFor({ optionBuyer }: RefundableBidsArgs) {
    try {
      const res = await this.optionRoundContract.get_refundable_bids_for(
        optionBuyer
      );
      if (typeof res !== "bigint" && typeof res !== "number") {
        const data = new CairoUint256(res);
        return data.toBigInt();
      } else return res;
    } catch (err) {
      console.log(err);
    }
  }

  async getTotalOptionsBalanceForAll(optionBuyers: Array<Account>) {
    try {
      const optionsBalances = await Promise.all(
        optionBuyers.map(async (account: Account) => {
          const balance = await this.getTotalOptionsBalanceFor(account.address);
          return balance;
        })
      );
      return optionsBalances;
    } catch (err) {
      console.log(err);
    }
  }

  async getTotalOptionsBalanceFor(optionBuyer: string) {
    try {
      const res = await this.optionRoundContract.get_total_options_balance_for(
        optionBuyer
      );
      if (typeof res !== "bigint" && typeof res !== "number") {
        const data = new CairoUint256(res);
        return data.toBigInt();
      } else return res;
    } catch (err) {
      console.log(err);
    }
  }

  async getPayoutBalanceFor({ optionBuyer }: PayoutBalanceArgs) {
    try {
      const res = await this.optionRoundContract.get_payout_balance_for(
        optionBuyer
      );
      if (typeof res !== "bigint" && typeof res !== "number") {
        const data = new CairoUint256(res);
        return data.toBigInt();
      } else return res;
    } catch (err) {
      console.log(err);
    }
  }

  async getTokenizableOptionsFor({ optionBuyer }: TokenizableOptionsArgs) {
    try {
      const res = await this.optionRoundContract.get_tokenizable_options_for(
        optionBuyer
      );
      if (typeof res !== "bigint" && typeof res !== "number") {
        const data = new CairoUint256(res);
        return data.toBigInt();
      } else return res;
    } catch (err) {
      console.log(err);
    }
  }
  async refundUnusedBids({ from, optionBidder }: RefundUnusedBidsArgs) {
    try {
      this.optionRoundContract.connect(from);
      const data = await this.optionRoundContract.refund_unused_bids(
        optionBidder
      );

      console.log("refund unused bids inside -> ", data);
      // @note: here it will return the total refundable_balance
      // if (typeof res !== "bigint" && typeof res !== "number") {
      //   const data = new CairoUint256(res);
      //   return data.toBigInt();
      // } else return res;
    } catch (err) {
      console.log(err);
    }
  }

  async exerciseOptions({ from }: ExerciseOptionArgs) {
    try {
      this.optionRoundContract.connect(from);
      const data = await this.optionRoundContract.exercise_options();
      // @note: here it will return the amount of transfer
      // if (typeof res !== "bigint" && typeof res !== "number") {
      //   const data = new CairoUint256(res);
      //   return data.toBigInt();
      // } else return res;
    } catch (err) {
      console.log(err);
    }
  }

  async tokenizeOptions({ from }: TokenizeOptionArgs) {
    try {
      this.optionRoundContract.connect(from);
      const data = await this.optionRoundContract.tokenize_options();
      // @note: here it will return the total number of tokenizable options
      // if (typeof res !== "bigint" && typeof res !== "number") {
      //   const data = new CairoUint256(res);
      //   return data.toBigInt();
      // } else return res;
    } catch (err) {
      console.log(err);
    }
  }
}
