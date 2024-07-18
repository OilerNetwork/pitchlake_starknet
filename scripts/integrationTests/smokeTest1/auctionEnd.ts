import {  Provider } from "starknet";
import { getAccount } from "../../utils/helpers/common";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import { OptionRoundFacade } from "../../utils/facades/optionRoundFacade";
import assert from "assert";
import {
  ApprovalArgs,
  Constants,
  PlaceBidArgs,
} from "../../utils/facades/types";
import { mineNextBlock } from "../../utils/katana";
import { getLiquidityProviderAccounts, getOptionBidderAccounts } from "../../utils/helpers/accounts";

export const smokeTest = async (
  provider: Provider,
  vaultFacade: VaultFacade,
  ethFacade: EthFacade,
  constants: Constants
) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract
  );
  const devAccount = getAccount("dev", provider);
  try {
    await vaultFacade.endAuction(devAccount);
  } catch (err) {
    console.log("EXPECTED");
    //Failure expected when contracts are changed to revert
  }

  const state: any = await optionRoundFacade.optionRoundContract.get_state();

  assert(
    state.activeVariant() === "Auctioning",
    `Expected:Auctioning\nReceived:${state.activeVariant()}`
  );

  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider,2);
  const optionBidderAccounts = getOptionBidderAccounts(provider,3);
  
  await vaultFacade.endAuctionBystander(provider);

  const totalPremiums = optionRoundFacade.getTotalPremiums();
  const stateAfter: any =
    await optionRoundFacade.optionRoundContract.get_state();

  assert(
    stateAfter.activeVariant() === "Running",
    `Expected:Running\nReceived:${stateAfter.activeVariant()}`
  );
  //   const unlockedBalanceA = await vaultFacade.getLPUnlockedBalance(
  //     liquidityProviderA.address
  //   );
  //   const unlockedBalanceB = await vaultFacade.getLPUnlockedBalance(
  //     liquidityProviderB.address
  //   );
  //   const lockedBalanceA = await vaultFacade.getLPLockedBalance(
  //     liquidityProviderA.address
  //   );
  //   const lockedBalanceB = await vaultFacade.getLPLockedBalance(
  //     liquidityProviderB.address
  //   );
  //   const totalLockedAmount = await vaultFacade.getTotalLocked();
  //   const totalUnlockedAmount = await vaultFacade.getTotalUnLocked();

  //   //Asserts
  //   checkpoint1({
  //     unlockedBalanceA,
  //     unlockedBalanceB,
  //     lockedBalanceA,
  //     lockedBalanceB,
  //     totalLockedAmount,
  //     totalUnlockedAmount,
  //     constants,
  //   });

  //   //Approve OptionBidders

  //   const approveAllData: Array<ApprovalArgs> = [
  //     {
  //       owner: optionBidderA,
  //       amount: BigInt("90000000000000000000"),
  //       spender: optionRoundFacade.optionRoundContract.address,
  //     },
  //     {
  //       owner: optionBidderB,
  //       amount: BigInt("90000000000000000000"),
  //       spender: optionRoundFacade.optionRoundContract.address,
  //     },
  //   ];
  //   await ethFacade.approveAll(approveAllData);
  //   await mineNextBlock(provider.channel.nodeUrl);

  //   //Place bids according to story script
  //   const reservePrice = await optionRoundFacade.getReservePrice();
  //   const totalOptionAvailable =
  //     await optionRoundFacade.getTotalOptionsAvailable();

  //   const balanceBeforeBidA = await ethFacade.getBalance(optionBidderA.address);
  //   const balanceBeforeBidB = await ethFacade.getBalance(optionBidderB.address);
  //   console.log(
  //     "reservePrice",
  //     Number(reservePrice),
  //     "\ntotalOptionsAvailable:",
  //     totalOptionAvailable
  //   );

  //   const placeBidsData: Array<PlaceBidArgs> = [
  //     {
  //       from: optionBidderA,
  //       amount: BigInt(totalOptionAvailable) / BigInt(2),
  //       price: BigInt(3) * BigInt(reservePrice),
  //     },
  //     {
  //       from: optionBidderB,
  //       amount: BigInt(totalOptionAvailable) / BigInt(2),
  //       price: BigInt(2) * BigInt(reservePrice),
  //     },
  //     {
  //       from: optionBidderB,
  //       amount: BigInt(totalOptionAvailable) / BigInt(2),
  //       price: BigInt(reservePrice),
  //     },
  //   ];
  //   await optionRoundFacade.placeBidsAll(placeBidsData);

  //   const balanceAfterBidA = await ethFacade.getBalance(optionBidderA.address);
  //   const balanceAfterBidB = await ethFacade.getBalance(optionBidderB.address);

  //   const bidsForA = await optionRoundFacade.getBidsFor(optionBidderA.address);
  //   const bidsForB = await optionRoundFacade.getBidsFor(optionBidderB.address);

  //   checkpoint2({
  //     balanceBeforeBidA,
  //     balanceAfterBidA,
  //     balanceBeforeBidB,
  //     balanceAfterBidB,
  //     reservePrice,
  //     totalOptionAvailable,
  //     bidsForA,
  //     bidsForB,
  //   });
};

async function checkpoint1(
  vaultFacade: VaultFacade,
  optionRoundFacade: OptionRoundFacade,
  constants: Constants
) {
    
}
