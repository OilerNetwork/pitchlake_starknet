import { Provider, Uint256 } from "starknet";
import { getAccount } from "../../utils/helpers/common";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import {
  ApprovalArgs,
  Constants,
  PlaceBidArgs,
} from "../../utils/facades/types";
import { mineNextBlock } from "../../utils/katana";
import {
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
} from "../../utils/helpers/accounts";
import { TestRunner } from "../../utils/facades/TestRunner";

export const smokeTest = async ({
  provider,
  vaultFacade,
  ethFacade,
  constants,
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract
  );
  const devAccount = getAccount("dev", provider);
  try {
    await vaultFacade.startAuction(devAccount);
  } catch (err) {
    //Failure expected when contracts are changed to revert
  }

  const stateAfter: any =
    await optionRoundFacade.optionRoundContract.get_state();

  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 2);
  const optionBidderAccounts = getOptionBidderAccounts(provider, 2);

  assert(
    stateAfter.activeVariant() === "Open",
    `Expected:Open\nReceived:${stateAfter.activeVariant()}`
  );

  await vaultFacade.startAuctionBystander(provider);

  const unlockedBalances = await vaultFacade.getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  const lockedBalances = await vaultFacade.getLPLockedBalanceAll(
    liquidityProviderAccounts
  );
  const totalLockedAmount = await vaultFacade.getTotalLocked();
  const totalUnlockedAmount = await vaultFacade.getTotalUnLocked();

  //Asserts
  checkpoint1({
    unlockedBalances,
    lockedBalances,
    totalLockedAmount,
    totalUnlockedAmount,
    constants,
  });

  //Approve OptionBidders

  const approveAllData: Array<ApprovalArgs> = [
    {
      owner: optionBidderAccounts[0],
      amount: BigInt("90000000000000000000"),
      spender: optionRoundFacade.optionRoundContract.address,
    },
    {
      owner: optionBidderAccounts[1],
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

  const ethBalancesBefore = await ethFacade.getBalancesAll(
    optionBidderAccounts
  );

  const placeBidsData: Array<PlaceBidArgs> = [
    {
      from: optionBidderAccounts[0],
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(3) * BigInt(reservePrice),
    },
    {
      from: optionBidderAccounts[1],
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(2) * BigInt(reservePrice),
    },
    {
      from: optionBidderAccounts[1],
      amount: BigInt(totalOptionAvailable) / BigInt(2),
      price: BigInt(reservePrice),
    },
  ];
  await optionRoundFacade.placeBidsAll(placeBidsData);

  const ethBalancesAfter = await ethFacade.getBalancesAll(optionBidderAccounts);

  const bidArrays = await optionRoundFacade.getBidsForAll(optionBidderAccounts);

  checkpoint2({
    ethBalancesBefore,
    ethBalancesAfter,
    bidArrays,
    reservePrice,
    totalOptionAvailable,
  });
};

async function checkpoint1({
  lockedBalances,
  unlockedBalances,
  totalLockedAmount,
  totalUnlockedAmount,
  constants,
}: {
  lockedBalances: Array<bigint | number>;
  unlockedBalances: Array<bigint | number>;
  totalLockedAmount: bigint | number | Uint256 | undefined;
  totalUnlockedAmount: bigint | number | Uint256 | undefined;
  constants: Constants;
}) {
  assert(
    Number(unlockedBalances[0]) === 0,
    `UnlockedBalanceA 0 expected, found ${unlockedBalances[0]}`
  );
  assert(
    Number(unlockedBalances[1]) === 0,
    `UnlockedBalanceB 0 expected, found ${unlockedBalances[1]}`
  );
  assert(
    Number(lockedBalances[0]) === constants.depositAmount / 2,
    `LockedBalanceA ${constants.depositAmount / 2} expected, found ${
      lockedBalances[0]
    }`
  );
  assert(
    Number(lockedBalances[1]) === constants.depositAmount / 2,
    `LockedBalanceB ${constants.depositAmount / 2} expected, found ${
      lockedBalances[1]
    }`
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
  ethBalancesBefore,
  ethBalancesAfter,
  bidArrays,
  totalOptionAvailable,
  reservePrice,
}: {
  ethBalancesBefore: Array<number | bigint>;
  ethBalancesAfter: Array<number | bigint>;
  bidArrays: Array<Array<any>>;
  totalOptionAvailable: number | bigint;
  reservePrice: number | bigint;
}) {
  console.log("Bids from A:\n", bidArrays[0], "\nBids from B:\n", bidArrays[1]);
  assert(
    BigInt(ethBalancesBefore[0]) - BigInt(ethBalancesAfter[0]) ===
      (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
        BigInt(2),
    "Error A"
  );
  assert(
    BigInt(ethBalancesBefore[1]) - BigInt(ethBalancesAfter[1]) ===
      (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
        BigInt(2),
    "Error B"
  );

  assert(bidArrays[0].length === 1, "No. of Bids for A wrong");
  assert(
    bidArrays[0][0].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "Bid for A amount wrong"
  );
  assert(
    bidArrays[0][0].price === BigInt(3) * BigInt(reservePrice),
    "Bid for A price wrong"
  );
  assert(bidArrays[1].length === 2, "No. of Bids for B wrong");
  assert(
    bidArrays[1][0].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "First bid for B amount wrong"
  );
  assert(
    bidArrays[1][0].price === BigInt(2) * BigInt(reservePrice),
    "First bid for B price wrong"
  );
  assert(
    bidArrays[1][1].amount === BigInt(totalOptionAvailable) / BigInt(2),
    "Second bid for B amount wrong "
  );
  assert(
    BigInt(bidArrays[1][1].price) === BigInt(reservePrice),
    `Second bid for B price wrong.\n Expected:${reservePrice}, Actual:${bidArrays[1][0].price}`
  );
}
