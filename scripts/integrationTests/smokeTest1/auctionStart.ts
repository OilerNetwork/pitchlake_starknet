import { CairoUint256, Provider, Uint256 } from "starknet";
import { getAccount, getCustomAccount } from "../../utils/helpers/common";
import { liquidityProviders, optionBidders } from "../../utils/constants";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
import { setupOptionRound } from "../../utils/helpers/setup";
import { OptionRoundFacade } from "../../utils/facades/optionRoundFacade";
import assert from "assert";
import {
  ApprovalArgs,
  Constants,
  PlaceBidArgs,
} from "../../utils/facades/types";
import { mineNextBlock } from "../../utils/katana";

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

  const optionBidderC = getCustomAccount(
    provider,
    optionBidders[2].account,
    optionBidders[2].privateKey
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
  checkpoint1({
    unlockedBalanceA,
    unlockedBalanceB,
    lockedBalanceA,
    lockedBalanceB,
    totalLockedAmount,
    totalUnlockedAmount,
    constants,
  });

  //Approve OptionBidders

  const approveAllData: Array<ApprovalArgs> = [
    {
      owner: optionBidderA,
      amount: BigInt("90000000000000000000"),
      spender: optionRoundFacade.optionRoundContract.address,
    },
    {
      owner: optionBidderB,
      amount: BigInt("90000000000000000000"),
      spender: optionRoundFacade.optionRoundContract.address,
    },
  ];
  await ethFacade.approveAll(approveAllData);
  await mineNextBlock(provider.channel.nodeUrl);

  //Place bids according to story script
  const reservePrice = await optionRoundFacade.getReservePrice();
  const totalOptionAvailable =
    await optionRoundFacade.getTotalOptionsAvailable();

  const balanceBeforeBidA = await ethFacade.getBalance(optionBidderA.address);
  const balanceBeforeBidB = await ethFacade.getBalance(optionBidderB.address);
  console.log(
    "reservePrice",
    Number(reservePrice),
    "\ntotalOptionsAvailable:",
    totalOptionAvailable
  );

  const placeBidsData: Array<PlaceBidArgs> = [
    {
      from: optionBidderA,
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(3) * BigInt(reservePrice),
    },
    {
      from: optionBidderB,
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(2) * BigInt(reservePrice),
    },
    {
      from: optionBidderB,
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(reservePrice),
    },
  ];
  await optionRoundFacade.placeBidsAll(placeBidsData);

  const balanceAfterBidA = await ethFacade.getBalance(optionBidderA.address);
  const balanceAfterBidB = await ethFacade.getBalance(optionBidderB.address);

  const bidsForA = await optionRoundFacade.getBidsFor(optionBidderA.address);
  const bidsForB = await optionRoundFacade.getBidsFor(optionBidderB.address);

  checkpoint2({
    balanceBeforeBidA,
    balanceAfterBidA,
    balanceBeforeBidB,
    balanceAfterBidB,
    reservePrice,
    totalOptionAvailable,
    bidsForA,
    bidsForB,
  });
};

async function checkpoint1({
  lockedBalanceA,
  lockedBalanceB,
  unlockedBalanceA,
  unlockedBalanceB,
  totalLockedAmount,
  totalUnlockedAmount,
  constants,
}: {
  lockedBalanceA: bigint | number | Uint256 | undefined;
  lockedBalanceB: bigint | number | Uint256 | undefined;
  unlockedBalanceA: bigint | number | Uint256 | undefined;
  unlockedBalanceB: bigint | number | Uint256 | undefined;
  totalLockedAmount: bigint | number | Uint256 | undefined;
  totalUnlockedAmount: bigint | number | Uint256 | undefined;
  constants: Constants;
}) {

  const data = {
    lockedBalanceA,
    lockedBalanceB,
    unlockedBalanceA,
    unlockedBalanceB,
    totalLockedAmount,
    totalUnlockedAmount,
    constants,
  }
  console.log("checkpoint1:\n",data)
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
}

async function checkpoint2({
  balanceBeforeBidA,
  balanceAfterBidA,
  balanceBeforeBidB,
  balanceAfterBidB,
  totalOptionAvailable,
  reservePrice,
  bidsForA,
  bidsForB,
}: {
  balanceBeforeBidA: number | bigint;
  balanceAfterBidA: number | bigint;
  balanceBeforeBidB: number | bigint;
  balanceAfterBidB: number | bigint;
  totalOptionAvailable: number | bigint;
  reservePrice: number | bigint;
  bidsForA: Array<any>;
  bidsForB: Array<any>;
}) {
  console.log("Bids from A:\n", bidsForA, "\nBids from B:\n", bidsForB);
  assert(
    BigInt(balanceBeforeBidA) - BigInt(balanceAfterBidA) ===
      (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
        BigInt(2),
    "Error A"
  );
  assert(
    BigInt(balanceBeforeBidB) - BigInt(balanceAfterBidB) ===
      (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
        BigInt(2),
    "Error B"
  );

  assert(bidsForA.length === 1, "No. of Bids for A wrong");
  assert(
    bidsForA[0].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "Bid for A amount wrong"
  );
  assert(
    bidsForA[0].price === BigInt(3) * BigInt(reservePrice),
    "Bid for A price wrong"
  );
  assert(bidsForB.length === 2, "No. of Bids for B wrong");
  assert(
    bidsForB[1].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "First bid for B amount wrong"
  );
  assert(
    bidsForB[1].price === BigInt(2) * BigInt(reservePrice),
    "First bid for B price wrong"
  );
  assert(
    bidsForB[0].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "Second bid for B amount wrong "
  );
  assert(
    BigInt(bidsForB[0].price) === BigInt(reservePrice),
    `Second bid for B price wrong.\n Expected:${reservePrice}, Actual:${bidsForB[1].price}`
  );
}
