import assert from "assert";
import { DepositArgs, WithdrawArgs } from "../../utils/facades/types";
import { getLiquidityProviderAccounts } from "../../utils/helpers/accounts";
import { TestRunner } from "../../utils/facades/TestRunner";
import { LibraryError } from "starknet";

//@note Wrap functions into a try catch to avoid breaking thread, log errors correctly

export const smokeTest = async ({
  provider,
  vaultFacade: vault,
  ethFacade: eth,
  constants: { depositAmount },
  getLPUnlockedBalanceAll,
  depositAll,
  withdrawAll,
  getBalancesAll
}: TestRunner) => {
  const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 2);

  //Approve A for depositing
  await eth.approval({
    owner: liquidityProviderAccounts[0],
    amount: BigInt(100)*BigInt(depositAmount),
    spender: vault.vaultContract.address,
  });

  const ethBalancesBefore = await getBalancesAll(liquidityProviderAccounts);

  const lpUnlockedBalancesBefore = await getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  //Deposits
  //1. Deposit from A with B as beneficiary
  //2. Deposit from A for self

  const depositAllArgs: Array<DepositArgs> = [
    {
      from: liquidityProviderAccounts[0],
      beneficiary: liquidityProviderAccounts[1].address,
      amount: depositAmount,
    },
    {
      from: liquidityProviderAccounts[0],
      beneficiary: liquidityProviderAccounts[0].address,
      amount: depositAmount,
    },
  ];

  await depositAll(depositAllArgs);
  //Debug

  const lpUnlockedBalancesAfter = await getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  const ethBalancesAfter = await getBalancesAll(liquidityProviderAccounts);

  //Asserts
  //1) Check liquidity for A has increased by depositAmount
  //2) Check liquidity for B has increased by depositAmount
  //3) Check eth balance for A has dropped by 2*depositAmount

  checkpoint1({
    lpUnlockedBalancesBefore,
    lpUnlockedBalancesAfter,
    ethBalancesBefore,
    ethBalancesAfter,
    depositAmount,
  });

  //Withdraws

  //Withdraw constants.depositAmount/2 from vaultContract for A and B positions
  //Withdraw again for B, greater than depositAmount/2 + 1, should revert
  const withdrawAllData: Array<WithdrawArgs> = [
    {
      account: liquidityProviderAccounts[0],
      amount: BigInt(depositAmount) / BigInt(2),
    },
    {
      account: liquidityProviderAccounts[1],
      amount: BigInt(depositAmount) / BigInt(2),
    },
  ];
  await withdrawAll(withdrawAllData);

  const lpUnlockedBalancesAfterWithdraw = await getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );

  const ethBalancesAfterWithdraw = await getBalancesAll(
    liquidityProviderAccounts
  );

  try {
    await vault.withdraw({
      account: liquidityProviderAccounts[1],
      amount: BigInt(depositAmount) / BigInt(2) + BigInt(1),
    });
    throw Error("Should have reverted");
  } catch (err: unknown) {
    const error = err as LibraryError;
    assert(error.message !== "Should have reverted");
  }

  const lpUnlockedBalancesAfterWithdraw2 = await getLPUnlockedBalanceAll(
    liquidityProviderAccounts
  );
  //Asserts
  //1) Check liquidity for A & B has decreased by depositAmount/2
  //2) Check balance for A & B has increased by depositAmount/2

  checkpoint2({
    lpUnlockedBalancesBefore: lpUnlockedBalancesAfter,
    lpUnlockedBalancesAfter: lpUnlockedBalancesAfterWithdraw,
    ethBalancesBefore: ethBalancesAfter,
    ethBalancesAfter: ethBalancesAfterWithdraw,
    depositAmount,
  });
};

function checkpoint1({
  lpUnlockedBalancesBefore,
  lpUnlockedBalancesAfter,
  ethBalancesBefore,
  ethBalancesAfter,
  depositAmount,
}: {
  lpUnlockedBalancesBefore: Array<number | bigint>;
  lpUnlockedBalancesAfter: Array<number | bigint>;
  ethBalancesBefore: Array<number | bigint>;
  ethBalancesAfter: Array<number | bigint>;
  depositAmount: number|bigint;
}) {
  assert(
    BigInt(lpUnlockedBalancesAfter[0]) ===
      BigInt(lpUnlockedBalancesBefore[0]) + BigInt(depositAmount),
    "liquidity A mismatch"
  );
  assert(
    BigInt(lpUnlockedBalancesAfter[1]) ===
      BigInt(lpUnlockedBalancesBefore[1]) + BigInt(depositAmount),
    "liquidity B mismatch"
  );
  assert(
    BigInt(ethBalancesBefore[0]) ===
      BigInt(ethBalancesAfter[0]) + BigInt(2) * BigInt(depositAmount),
    "Eth balance for a mismatch"
  );
}
function checkpoint2({
  lpUnlockedBalancesAfter,
  lpUnlockedBalancesBefore,
  ethBalancesAfter,
  ethBalancesBefore,
  depositAmount,
}: {
  lpUnlockedBalancesAfter: Array<number | bigint>;
  lpUnlockedBalancesBefore: Array<number | bigint>;
  ethBalancesAfter: Array<number | bigint>;
  ethBalancesBefore: Array<number | bigint>;
  depositAmount: number|bigint;
}) {
  assert(
    BigInt(lpUnlockedBalancesBefore[0]) ==
      BigInt(lpUnlockedBalancesAfter[0]) + BigInt(depositAmount) / BigInt(2),
    "Mismatch A liquidity"
  );
  assert(
    BigInt(lpUnlockedBalancesBefore[1]) ==
      BigInt(lpUnlockedBalancesAfter[1]) + BigInt(depositAmount) / BigInt(2),
    "Mismatch B liquidity"
  );
  assert(
    BigInt(ethBalancesBefore[0]) ==
      BigInt(ethBalancesAfter[0]) - BigInt(depositAmount) / BigInt(2),
    "Mismatch A balance"
  );
  assert(
    BigInt(ethBalancesBefore[1]) ==
      BigInt(ethBalancesAfter[1]) - BigInt(depositAmount) / BigInt(2),
    "Mismatch B balance"
  );
}
