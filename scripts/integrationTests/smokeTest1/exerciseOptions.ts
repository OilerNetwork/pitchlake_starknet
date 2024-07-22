
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import {
  getOptionBidderAccounts,
} from "../../utils/helpers/accounts";
import { TestRunner } from "../../utils/facades/TestRunner";

export const smokeTest = async ({
  provider,
  vaultFacade,
  constants: { depositAmount },
  ethFacade,
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract,
    true
  );

  const optionBidderAccounts = getOptionBidderAccounts(provider, 3);

  const ethBalancesBefore = await ethFacade.getBalancesAll(
    optionBidderAccounts
  );

  await optionRoundFacade.exerciseOptionsAll(optionBidderAccounts);

  const ethBalancesAfter = await ethFacade.getBalancesAll(optionBidderAccounts);
  const totalPayout = await optionRoundFacade.getTotalPayout();

  checkpoint1({
    ethBalancesBefore,
    ethBalancesAfter,
    totalPayout,
  });

  await optionRoundFacade.exerciseOptionsAll(optionBidderAccounts);
  const ethBalancesAfterTwice = await ethFacade.getBalancesAll(
    optionBidderAccounts
  );

  checkpoint2({
    ethBalancesAfter,
    ethBalancesAfterTwice,
  });
};

async function checkpoint1({
  ethBalancesBefore,
  ethBalancesAfter,
  totalPayout,
}: {
  ethBalancesBefore: Array<number | bigint>;
  ethBalancesAfter: Array<number | bigint>;
  totalPayout: number | bigint;
}) {
  // - Test C & D exercise their options
  // - Test C’s ETH balance increases by 1/4 total payout
  assert(
    BigInt(ethBalancesAfter[0]) - BigInt(ethBalancesBefore[0]) ===
      BigInt(totalPayout) / BigInt(4),
    "Eth Balance for C mismatch"
  );
  // - Test D’s ETH balance increases by 3/4 total payout
  assert(
    BigInt(ethBalancesAfter[1]) - BigInt(ethBalancesBefore[1]) ===
      (BigInt(3) * BigInt(totalPayout)) / BigInt(4),
    "Eth Balance for D mismatch"
  );
}

async function checkpoint2({
  ethBalancesAfter,
  ethBalancesAfterTwice,
}: {
  ethBalancesAfter: Array<number | bigint>;
  ethBalancesAfterTwice: Array<number | bigint>;
}) {
  assert(
    ethBalancesAfter[0] === ethBalancesAfterTwice[0],
    "Balance changed on exercising again"
  );
  assert(
    ethBalancesAfter[1] === ethBalancesAfterTwice[1],
    "Balance changed on exercising again"
  );
}
