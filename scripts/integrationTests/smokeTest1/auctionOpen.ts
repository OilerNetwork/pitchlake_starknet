import { Provider } from "starknet";
import { getCustomAccount } from "../../utils/helpers/common";
import { liquidityProviders } from "../../utils/constants";
import assert from "assert";
import { DepositArgs, WithdrawArgs } from "../../utils/facades/types";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";

//@note Wrap functions into a try catch to avoid breaking thread, log errors correctly

export const smokeTest = async (
  provider: Provider,
  vault: VaultFacade,
  eth: EthFacade
) => {
  const depositAmount = 1000;
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

  //Approve A for depositing
  await eth.approval({
    owner: liquidityProviderA,
    amount: 1000000,
    spender: vault.vaultContract.address,
  });

  const liquidityBeforeA = await vault.getLPUnlockedBalance(
    liquidityProviderA.address
  );

  const balanceBeforeA = await eth.getBalance(liquidityProviderA.address);

  const balanceBeforeB = await eth.getBalance(liquidityProviderB.address);

  const liquidityBeforeB = await vault.getLPUnlockedBalance(
    liquidityProviderB.address
  );

  //Deposits
  //1. Deposit from A with B as beneficiary
  //2. Deposit from A for self

  const depositAllArgs: Array<DepositArgs> = [
    {
      from: liquidityProviderA,
      beneficiary: liquidityProviderB.address,
      amount: depositAmount,
    },
    {
      from: liquidityProviderA,
      beneficiary: liquidityProviderA.address,
      amount: depositAmount,
    },
  ];

  await vault.depositAll(depositAllArgs);
  //Debug

  const liquidityAfterA = await vault.getLPUnlockedBalance(
    liquidityProviderA.address
  );

  const liquidityAfterB = await vault.getLPUnlockedBalance(
    liquidityProviderB.address
  );

  const balanceAfterA = await eth.getBalance(liquidityProviderA.address);

  const balanceAfterB = await eth.getBalance(liquidityProviderB.address);

  //Asserts
  //1) Check liquidity for A has increased by depositAmount
  //2) Check liquidity for B has increased by depositAmount
  //3) Check eth balance for A has dropped by 2*depositAmount

  //Debug
  console.log(
    "liquidityAfterA:",
    liquidityAfterA,
    "\nliquidityBeforeA:",
    liquidityBeforeA
  );
  assert(
    Number(liquidityAfterA) === Number(liquidityBeforeA) + depositAmount,
    "liquidity A mismatch"
  );
  assert(
    Number(liquidityAfterB) === Number(liquidityBeforeB) + depositAmount,
    "liquidity B mismatch"
  );
  assert(
    Number(balanceBeforeA) === Number(balanceAfterA) + 2 * depositAmount,
    "Eth balance for a mismatch"
  );

  //Withdraws
  //Withdraw depositAmount/2 from vaultContract for A and B positions

  const withdrawAllData: Array<WithdrawArgs> = [
    { account: liquidityProviderA, amount: depositAmount / 2 },
    { account: liquidityProviderB, amount: depositAmount / 2 },
  ];
  await vault.withdrawAll(withdrawAllData);

  let liquidityAfterWithdrawA = await vault.getLPUnlockedBalance(
    liquidityProviderA.address
  );
  let liquidityAfterWithdrawB = await vault.getLPUnlockedBalance(
    liquidityProviderB.address
  );

  let balanceAfterWithdrawA = await eth.getBalance(liquidityProviderA.address);
  let balanceAfterWithdrawB = await eth.getBalance(liquidityProviderB.address);

  //Asserts
  //1) Check liquidity for A & B has decreased by depositAmount/2
  //2) Check balance for A & B has increased by depositAmount/2
  console.log(
    "liquidityAfterA:",
    liquidityAfterA,
    "\nliquidityAfterWithdrawA",
    liquidityAfterWithdrawA
  );
  assert(
    Number(liquidityAfterA) ==
      Number(liquidityAfterWithdrawA) + depositAmount / 2,
    "Mismatch A liquidity"
  );
  assert(
    Number(liquidityAfterB) ==
      Number(liquidityAfterWithdrawB) + depositAmount / 2,
    "Mismatch B liquidity"
  );
  assert(
    Number(balanceAfterA) == Number(balanceAfterWithdrawA) - depositAmount / 2,
    "Mismatch A balance"
  );
  assert(
    Number(balanceAfterB) == Number(balanceAfterWithdrawB) - depositAmount / 2,
    "Mismatch B balance"
  );
};
