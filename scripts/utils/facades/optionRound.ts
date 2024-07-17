import { TypedContractV2 } from "starknet";
import { ABI as optionRoundAbi } from "../../abi/optionRoundAbi";
import { UpdateBidArgs, PlaceBidArgs } from "./types";

export const updateBid = async (
  { bidId, from, amount, price }: UpdateBidArgs,
  optionRoundContract: TypedContractV2<typeof optionRoundAbi>
) => {
  optionRoundContract.connect(from);
  try {
    await optionRoundContract.update_bid(bidId, amount, price);
  } catch (err) {
    console.log(err);
  }
};

export const placeBid = async (
  { from, beneficiary, amount, price }: PlaceBidArgs,
  optionRoundContract: TypedContractV2<typeof optionRoundAbi>
) => {
  optionRoundContract.connect(from);
  try {
    await optionRoundContract.place_bid(amount, price, beneficiary);
  } catch (err) {
    console.log(err);
  }
};

export const placeBidAll = async (
  placeBidData: Array<PlaceBidArgs>,
  optionRoundContract: TypedContractV2<typeof optionRoundAbi>
) => {
  await Promise.all(
    placeBidData.map(
      async ({ from, amount, price, beneficiary }: PlaceBidArgs) => {
        optionRoundContract.connect(from);
        try {
          await optionRoundContract.place_bid(amount, price, beneficiary);
        } catch (err) {
          console.log(err);
        }
      }
    )
  );
};
