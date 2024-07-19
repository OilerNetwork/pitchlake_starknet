import { getAccount } from "../../utils/helpers/common";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import { Constants } from "../../utils/facades/types";
import {
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
} from "../../utils/helpers/accounts";
import { TestRunner } from "../../utils/facades/TestRunner";
import { LibraryError } from "starknet";

export const smokeTest = async ({
  provider,
  vaultFacade,
  constants: { depositAmount },
  ethFacade,
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract
  );

  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 2);
  const optionBidderAccounts = getOptionBidderAccounts(provider, 3);
  const devAccount = getAccount("dev", provider);

  try {
    await vaultFacade.settleAuction(devAccount);
    throw Error("Should have reverted");
  } catch (err) {
    const error = err as LibraryError;
    assert(error.message !== "Should have reverted", error.message);
    //Failure expected when contracts are changed to revert
  }

  const state: any = await optionRoundFacade.optionRoundContract.get_state();

  assert(
    state.activeVariant() === "Running",
    `Expected:Running\nReceived:${state.activeVariant()}`
  );
  const totalPremiums = await optionRoundFacade.getTotalPremiums();

  const ethBalanceBefore = await ethFacade.getBalance(
    liquidityProviderAccounts[0].address
  );


  vaultFacade.withdraw({
    account: liquidityProviderAccounts[0],
    amount: BigInt(totalPremiums) / BigInt(4),
  });

  const ethBalanceAfter = await ethFacade.getBalance(
    liquidityProviderAccounts[0].address
  );
  const lpUnlockedBalanceAfter = await vaultFacade.getLPLockedBalance(
    liquidityProviderAccounts[0].address
  );

  const totalUnlocked = await vaultFacade.getTotalUnLocked();

  checkpoint1({
    ethBalanceBefore,
    ethBalanceAfter,
    lpUnlockedBalanceAfter,
    totalUnlocked,
    totalPremiums,
  });

  await vaultFacade.settleAuctionBystander(provider);

  const stateAfter: any =
    await optionRoundFacade.optionRoundContract.get_state();

  const lpUnlockedBalances = await vaultFacade.getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  const totalPayout = await optionRoundFacade.getTotalPayout();
  const totalLocked = await vaultFacade.getTotalLocked();
  assert(
    stateAfter.activeVariant() === "Running",
    `Expected:Running\nReceived:${stateAfter.activeVariant()}`
  );

  checkpoint2({
    lpUnlockedBalances,
    totalPremiums,
    totalPayout,
    totalLocked,
    totalUnlocked,
    depositAmount,
  });
};

async function checkpoint1({
  ethBalanceBefore,
  ethBalanceAfter,
  lpUnlockedBalanceAfter,
  totalUnlocked,
  totalPremiums,
}: {
  ethBalanceBefore: number | bigint;
  ethBalanceAfter: number | bigint;
  lpUnlockedBalanceAfter: number | bigint;
  totalUnlocked: number | bigint;
  totalPremiums: number | bigint;
}) {
  assert(
    BigInt(ethBalanceAfter) - BigInt(ethBalanceBefore) ===
      BigInt(totalPremiums) / BigInt(4),
    "LP Unlocked for A mismatch"
  );
  assert(
    BigInt(lpUnlockedBalanceAfter) === BigInt(totalPremiums) / BigInt(4),
    "LP Unlocked for B mismatch"
  );
  assert(
    BigInt(totalUnlocked) === (BigInt(3) * BigInt(totalPremiums)) / BigInt(4),
    "LP Locked for A mismatch"
  );
}

async function checkpoint2({
  lpUnlockedBalances,
  totalPremiums,
  totalPayout,
  totalLocked,
  totalUnlocked,
  depositAmount,
}: {
  lpUnlockedBalances: Array<number | bigint>;
  totalPremiums: number | bigint;
  totalPayout: number | bigint;
  totalLocked: number | bigint;
  totalUnlocked: number | bigint;
  depositAmount: number | bigint;
}) {
  // - A’s unlocked balance should be 1/2 deposit amount + 1/4 total premiums - 1/2 total payout

  assert(
    lpUnlockedBalances[0] ===
      BigInt(depositAmount) / BigInt(2) +
        BigInt(totalPremiums) / BigInt(4) -
        BigInt(totalPayout) / BigInt(2),
    "lpUnlocked for A Mismatch"
  );

  // - B’s unlocked balance should be 1/2 deposit amount + 1/2 total premiums - 1/2 total payout

  assert(
    lpUnlockedBalances[1] ===
      BigInt(depositAmount) / BigInt(2) +
        BigInt(totalPremiums) / BigInt(2) -
        BigInt(totalPayout) / BigInt(2),
    "lpUnlocked for B Mismatch"
  );
  // - The total locked should == 0

  assert(
    Number(totalLocked) === 0,
    `total Locked should be zero, found: ${totalLocked}`
  );
  // - The total unlocked should == deposit amount + 3/4 total premiums - total payout

  assert(
    totalUnlocked ===
      BigInt(depositAmount) +
        (BigInt(3) * BigInt(totalPremiums)) / BigInt(4) -
        BigInt(totalPayout),
    "totalUnlocked mismatch"
  );
}
