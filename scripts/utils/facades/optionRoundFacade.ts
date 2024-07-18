import { TypedContractV2 } from "starknet";
import { optionRoundAbi } from "../../abi";
import { PlaceBidArgs, UpdateBidArgs } from "./types";

export class OptionRoundFacade {
    optionRoundContract:TypedContractV2<typeof optionRoundAbi>
    
    constructor(optionRoundContract:TypedContractV2<typeof optionRoundAbi>){
        this.optionRoundContract = optionRoundContract
    }


async updateBid (
    { bidId, from, amount, price }: UpdateBidArgs,
  ){
    this.optionRoundContract.connect(from);
    try {
      await this.optionRoundContract.update_bid(bidId, amount, price);
    } catch (err) {
      console.log(err);
    }
  };
  
  
async placeBid (
    { from, beneficiary, amount, price }: PlaceBidArgs,
  ){
    this.optionRoundContract.connect(from);
    try {
      await this.optionRoundContract.place_bid(amount, price, beneficiary);
    } catch (err) {
      console.log(err);
    }
  };
  
async placeBidAll (
    placeBidData: Array<PlaceBidArgs>,
    optionRoundContract: TypedContractV2<typeof optionRoundAbi>
  ){
  
    for (const {from,amount,price,beneficiary} of placeBidData){
      optionRoundContract.connect(from);
          try {
            await optionRoundContract.place_bid(amount, price, beneficiary);
          } catch (err) {
            console.log(err);
          }
    }
  };
  
}