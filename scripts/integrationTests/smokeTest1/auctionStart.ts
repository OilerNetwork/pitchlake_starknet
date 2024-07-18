import { Provider } from "starknet";
import { getAccount, getCustomAccount } from "../../utils/helpers/common";
import { liquidityProviders, optionBidders } from "../../utils/constants";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
import { setupOptionRound } from "../../utils/helpers/setup";
import { OptionRoundFacade } from "../../utils/facades/optionRoundFacade";
import assert from "assert";
import { Constants } from "../../utils/facades/types";
export const smokeTest = async (
  provider: Provider,
  vaultFacade: VaultFacade,
  ethFacade: EthFacade,
  constants: Constants
) => {
  const optionRoundFacade = await setupOptionRound(vaultFacade, provider);
  const devAccount = getAccount("dev", provider);
  try {
    await vaultFacade.startAuction(devAccount);
  } catch (err) {
    //Failure expected when contracts are changed to revert
  }

  const stateAfter: any =
    await optionRoundFacade.optionRoundContract.get_state();

  const liquidityProviderA = getCustomAccount(
    provider,
    liquidityProviders[0].account,
    liquidityProviders[0].privateKey
  );

  const liquidityProviderB = getCustomAccount(
    provider,
    liquidityProviders[1].account,
    liquidityProviders[1].privateKey
  );
  const optionBidderA = getCustomAccount(
    provider,
    optionBidders[0].account,
    optionBidders[0].privateKey
  );
  const optionBidderB = getCustomAccount(
    provider,
    optionBidders[1].account,
    optionBidders[1].privateKey
  );
  assert(
    stateAfter.activeVariant() === "Open",
    `Expected:Open\nReceived:${stateAfter.activeVariant()}`
  );

  await vaultFacade.startAuctionBystander(provider);

  const unlockedBalanceA = await vaultFacade.getLPUnlockedBalance(
    liquidityProviderA.address
  );
  const unlockedBalanceB = await vaultFacade.getLPUnlockedBalance(
    liquidityProviderB.address
  );
  const lockedBalanceA = await vaultFacade.getLPLockedBalance(
    liquidityProviderA.address
  );
  const lockedBalanceB = await vaultFacade.getLPLockedBalance(
    liquidityProviderB.address
  );
  const totalLockedAmount = await vaultFacade.getTotalLocked();
  const totalUnlockedAmount = await vaultFacade.getTotalUnLocked();

  //Asserts

  assert(
    Number(unlockedBalanceA) === 0,
    `UnlockedBalanceA 0 expected, found ${unlockedBalanceA}`
  );
  assert(
    Number(unlockedBalanceB) === 0,
    `UnlockedBalanceB 0 expected, found ${unlockedBalanceB}`
  );
  assert(
    Number(lockedBalanceA) === constants.depositAmount / 2,
    `LockedBalanceA ${
      constants.depositAmount / 2
    } expected, found ${lockedBalanceA}`
  );
  assert(
    Number(lockedBalanceB) === constants.depositAmount / 2,
    `LockedBalanceB ${
      constants.depositAmount / 2
    } expected, found ${lockedBalanceB}`
  );
  assert(
    Number(totalUnlockedAmount) === 0,
    `Total unlocked 0 expected, found ${totalUnlockedAmount}`
  );
  assert(
    Number(totalLockedAmount) === constants.depositAmount,
    `Total Locked amount ${constants.depositAmount} expected, found ${totalLockedAmount}`
  );
};
