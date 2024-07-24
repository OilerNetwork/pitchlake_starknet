import { getAccount } from "../../utils/helpers/common";
import {
  getOptionRoundFacade,
} from "../../utils/helpers/setup";
import assert from "assert";
import { TestRunner } from "../../utils/facades/TestRunner";
import { ERC20Facade } from "../../utils/facades/erc20Facade";

export const smokeTest = async ({
  provider,
  vaultFacade: vault,
  getOptionBidderAccounts,
  getBalancesAll
}: TestRunner) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vault.vaultContract
  );

  const optionRoundERC20Contract = new ERC20Facade(
    optionRoundFacade.optionRoundContract.address,
    provider
  );
  const devAccount = getAccount("dev", provider);

  const totalOptionAvailable =
    await optionRoundFacade.getTotalOptionsAvailable();
  const reservePrice = await optionRoundFacade.getReservePrice();
  const optionBidderAccounts = getOptionBidderAccounts(3);

  const balancesBefore = await getBalancesAll(optionBidderAccounts);

  try {
    await optionRoundFacade.refundUnusedBids({
      from: devAccount,
      optionBidder: optionBidderAccounts[0].address,
    });
    await optionRoundFacade.refundUnusedBids({
      from: devAccount,
      optionBidder: optionBidderAccounts[1].address,
    });
  } catch (err) {
    console.log("Error while refunding the unused bids", err);
  }
  const balancesAfter = await getBalancesAll(optionBidderAccounts);

  checkpoint1({
    balancesBefore,
    balancesAfter,
    totalOptionAvailable,
    reservePrice,
  });

  const optionBalancesBefore =
    await optionRoundFacade.getTotalOptionsBalanceForAll(optionBidderAccounts);

  try {
    await optionRoundFacade.tokenizeOptions({
      from: optionBidderAccounts[0],
    });
  } catch (err) {
    console.log("Error while tokenizing the option", err);
  }

  try {
    optionRoundERC20Contract.erc20Contract.connect(optionBidderAccounts[0]);
    await optionRoundERC20Contract.erc20Contract.approve(
      optionRoundERC20Contract.erc20Contract.address,
      BigInt(totalOptionAvailable) / BigInt(4)
    );

    // @dev @note: ideally this should be working:
    // await optionRoundERC20Contract.approval({
    //   owner: optionBidderAccounts[0],
    //   amount: BigInt(totalOptionAvailable) / BigInt(4),
    //   spender: optionRoundERC20Contract.erc20Contract.address,
    // });
    await optionRoundERC20Contract.erc20Contract.transfer(
      optionBidderAccounts[1].address,
      BigInt(totalOptionAvailable) / BigInt(4)
    );
  } catch (err) {
    console.log("Error while transferring the tokenized options", err);
  }

  const optionBalancesAfter =
    await optionRoundFacade.getTotalOptionsBalanceForAll(optionBidderAccounts);

  checkpoint2({
    optionBalancesBefore,
    optionBalancesAfter,
    totalOptionAvailable,
  });
};

async function checkpoint1({
  balancesBefore,
  balancesAfter,
  totalOptionAvailable,
  reservePrice,
}: {
  balancesBefore: Array<bigint | number>;
  balancesAfter: Array<bigint | number>;
  totalOptionAvailable: bigint | number;
  reservePrice: bigint | number;
}) {
  assert(
    BigInt(balancesBefore[0]) +
      (BigInt(totalOptionAvailable) / BigInt(2)) * BigInt(reservePrice) ===
      BigInt(balancesAfter[0]),
    "Unused bids balance fail"
  );
  assert(
    BigInt(balancesBefore[1]) +
      (BigInt(totalOptionAvailable) / BigInt(2)) * BigInt(reservePrice) ===
      BigInt(balancesAfter[1]),
    "Unused bids balance fail"
  );
}

async function checkpoint2({
  optionBalancesBefore,
  optionBalancesAfter,
  totalOptionAvailable,
}: {
  optionBalancesBefore: any;
  optionBalancesAfter: any;
  totalOptionAvailable: bigint | number;
}) {
  assert(
    BigInt(optionBalancesBefore[0]) === BigInt(optionBalancesBefore[1]),
    "Intial options should be equal"
  );

  assert(
    BigInt(optionBalancesBefore[0]) + BigInt(optionBalancesBefore[1]) ===
      BigInt(totalOptionAvailable),
    "Intial sum of options should be total options available"
  );

  assert(
    BigInt(optionBalancesAfter[0]) + BigInt(optionBalancesAfter[1]) ===
      BigInt(totalOptionAvailable),
    "After transfer sum of options should be total options available"
  );
  assert(
    BigInt(optionBalancesBefore[0]) / BigInt(2) ===
      BigInt(optionBalancesAfter[0]),
    "Final option balance of C should be half of initial"
  );

  assert(
    BigInt(optionBalancesBefore[1]) +
      BigInt(optionBalancesBefore[0]) / BigInt(2) ===
      BigInt(optionBalancesAfter[1]),
    "Final option balance of D should be inital + half of C"
  );
}
