import { getAccount } from "../../utils/helpers/common";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import { TestRunner } from "../../utils/facades/TestRunner";
import { eth, LibraryError } from "starknet";

export const smokeTest = async ({
  provider,
  vaultFacade,
  constants: { depositAmount, settlementPrice, volatility, reservePrice },
  ethFacade,
  getLPUnlockedBalanceAll,
  settleOptionRoundBystander,
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract,
  );

  const liquidityProviderAccounts = getLiquidityProviderAccounts(2);

  const devAccount = getAccount("dev", provider);

  try {
    let jobRequest = await optionRoundFacade.createJobRequest();
    await vaultFacade.settleOptionRound(devAccount, jobRequest);
    throw Error("Should have reverted");
  } catch (err) {
    const error = err as LibraryError;
    assert(error.message !== "Should have reverted", error.message);
    //Failure expected when contracts are changed to revert
  }

  const state: any = await optionRoundFacade.optionRoundContract.get_state();

  assert(
    state.activeVariant() === "Running",
    `Expected:Running\nReceived:${state.activeVariant()}`,
  );
  const totalPremiums = await optionRoundFacade.getTotalPremiums();

  const ethBalanceBefore = await ethFacade.getBalance(
    liquidityProviderAccounts[0].address,
  );

  await vaultFacade.withdraw({
    account: liquidityProviderAccounts[0],
    amount: BigInt(totalPremiums) / BigInt(4),
  });

  const ethBalanceAfter = await ethFacade.getBalance(
    liquidityProviderAccounts[0].address,
  );
  const lpUnlockedBalanceAfter = await vaultFacade.getLPLockedBalance(
    liquidityProviderAccounts[0].address,
  );

  const totalUnlocked = await vaultFacade.getTotalUnLocked();

  checkpoint1({
    ethBalanceBefore,
    ethBalanceAfter,
    lpUnlockedBalanceAfter,
    totalUnlocked,
    totalPremiums,
  });

  const marketData = {
    settlementPrice,
    volatility,
    reservePrice,
  };

  await settleOptionRoundBystander(marketData);

  const stateAfter: any =
    await optionRoundFacade.optionRoundContract.get_state();

  const lpUnlockedBalances = await getLPUnlockedBalanceAll(
    liquidityProviderAccounts,
  );
  const totalPayout = await optionRoundFacade.getTotalPayout();
  const totalLocked = await vaultFacade.getTotalLocked();
  const totalUnlockedAfter = await vaultFacade.getTotalUnLocked();

  assert(
    stateAfter.activeVariant() === "Settled",
    `Expected:Running\nReceived:${stateAfter.activeVariant()}`,
  );

  checkpoint2({
    lpUnlockedBalances,
    totalPremiums,
    totalPayout,
    totalLocked,
    totalUnlocked: totalUnlockedAfter,
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
  console.log(
    "ethBalanceAfter:",
    ethBalanceAfter,
    "\nethBalanceBefore:",
    ethBalanceBefore,
    "\ntotalPremiums",
    totalPremiums,
    "lpUnlockedBalanceAfter:",
    lpUnlockedBalanceAfter,
  );
  assert(
    BigInt(ethBalanceAfter) - BigInt(ethBalanceBefore) ===
      BigInt(totalPremiums) / BigInt(4),
    "LP Unlocked for A mismatch",
  );
  assert(
    BigInt(lpUnlockedBalanceAfter) === BigInt(totalPremiums) / BigInt(4),
    "LP Unlocked for B mismatch",
  );
  assert(
    BigInt(totalUnlocked) === (BigInt(3) * BigInt(totalPremiums)) / BigInt(4),
    "LP Locked for A mismatch",
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
    BigInt(lpUnlockedBalances[0]) ===
      BigInt(depositAmount) / BigInt(2) +
        BigInt(totalPremiums) / BigInt(4) -
        BigInt(totalPayout) / BigInt(2),
    "lpUnlocked for A Mismatch",
  );

  // - B’s unlocked balance should be 1/2 deposit amount + 1/2 total premiums - 1/2 total payout

  assert(
    lpUnlockedBalances[1] ===
      BigInt(depositAmount) / BigInt(2) +
        BigInt(totalPremiums) / BigInt(2) -
        BigInt(totalPayout) / BigInt(2),
    "lpUnlocked for B Mismatch",
  );
  // - The total locked should == 0

  assert(
    Number(totalLocked) === 0,
    `total Locked should be zero, found: ${totalLocked}`,
  );
  // - The total unlocked should == deposit amount + 3/4 total premiums - total payout

  assert(
    BigInt(totalUnlocked) ==
      BigInt(depositAmount) +
        (BigInt(3) * BigInt(totalPremiums)) / BigInt(4) -
        BigInt(totalPayout),
    `totalUnlocked mismatch \n${totalUnlocked}\n${lpUnlockedBalances}`,
  );
}
