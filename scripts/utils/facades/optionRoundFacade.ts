import { CairoUint256, TypedContractV2 } from "starknet";
import { optionRoundAbi } from "../../abi";
import { Bid, PlaceBidArgs, UpdateBidArgs } from "./types";

export class OptionRoundFacade {
  optionRoundContract: TypedContractV2<typeof optionRoundAbi>;

  constructor(optionRoundContract: TypedContractV2<typeof optionRoundAbi>) {
    this.optionRoundContract = optionRoundContract;
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
}
