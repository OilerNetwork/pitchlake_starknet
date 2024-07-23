import { LibraryError } from "starknet";
import { getAccount } from "../../utils/helpers/common";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import { Constants } from "../../utils/facades/types";
import { TestRunner } from "../../utils/facades/TestRunner";

export const smokeTest = async ({
  provider,
  vaultFacade,
  constants,
  getLiquidityProviderAccounts,
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract
  );
  const devAccount = getAccount("dev", provider);
  try {
    await vaultFacade.endAuction(devAccount);
    throw Error("Should have reverted");
  } catch (err) {
    const error = err as LibraryError;
    assert(error.message !== "Should have reverted", error.message);
    //Failure expected when contracts are changed to revert
  }

  const state: any = await optionRoundFacade.optionRoundContract.get_state();

  assert(
    state.activeVariant() === "Auctioning",
    `Expected:Auctioning\nReceived:${state.activeVariant()}`
  );

  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 2);

  await vaultFacade.endAuctionBystander(provider);

  const lpUnlockedBalances = await vaultFacade.getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  const lpLockedBalances = await vaultFacade.getLPLockedBalanceAll(
    liquidityProviderAccounts
  );
  const totalPremiums = await optionRoundFacade.getTotalPremiums();
  const totalLocked = await vaultFacade.getTotalLocked();
  const totalUnlocked = await vaultFacade.getTotalUnLocked();
  checkpoint1({
    lpLockedBalances,
    lpUnlockedBalances,
    totalPremiums,
    totalLocked,
    totalUnlocked,
    constants,
  });
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

async function checkpoint1({
  lpLockedBalances,
  lpUnlockedBalances,
  totalPremiums,
  totalLocked,
  totalUnlocked,
  constants,
}: {
  lpLockedBalances: Array<number | bigint>;
  lpUnlockedBalances: Array<number | bigint>;
  totalPremiums: number | bigint;
  totalLocked: number | bigint;
  totalUnlocked: number | bigint;
  constants: Constants;
}) {
  assert(
    BigInt(lpUnlockedBalances[0]) === BigInt(totalPremiums) / BigInt(2),
    "LP Unlocked for A mismatch"
  );
  assert(
    BigInt(lpUnlockedBalances[1]) === BigInt(totalPremiums) / BigInt(2),
    "LP Unlocked for B mismatch"
  );
  assert(
    BigInt(lpLockedBalances[0]) === BigInt(constants.depositAmount) / BigInt(2),
    "LP Locked for A mismatch"
  );
  assert(
    BigInt(lpLockedBalances[1]) === BigInt(constants.depositAmount) / BigInt(2),
    "LP Locked for B mismatch"
  );
  assert(
    BigInt(totalLocked) === BigInt(constants.depositAmount),
    "totalLocked mismatch"
  );
  assert(
    BigInt(totalUnlocked) === BigInt(totalPremiums),
    "totalUnlocked for A mismatch"
  );
}
