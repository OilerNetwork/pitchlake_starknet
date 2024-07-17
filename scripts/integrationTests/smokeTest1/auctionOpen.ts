import { Provider, TypedContractV2 } from "starknet";
import { ABI as vaultAbi } from "../../abi/vaultAbi";
import { ABI as ethAbi } from "../../abi/ethAbi";
import { getCustomAccount } from "../../utils/helpers/common";
import { liquidityProviders } from "../../utils/constants";
import { approval, getBalance } from "../../utils/facades/eth";
import {
  depositAll,
  getLPUnlockedBalance,
  withdrawAll,
} from "../../utils/facades/vault";

import assert from "assert";
import { DepositArgs, WithdrawArgs } from "../../utils/facades/types";

//@note Wrap functions into a try catch to avoid breaking thread, log errors correctly

export const smokeTest = async (
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>,
  ethContract: TypedContractV2<typeof ethAbi>
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
  await approval(
    {
      owner: liquidityProviderA,
      amount: 1000000,
      spender: vaultContract.address,
    },
    ethContract
  );

  const liquidityBeforeA = await getLPUnlockedBalance(
    liquidityProviderA.address,
    vaultContract
  );

  const balanceBeforeA = await getBalance(
    liquidityProviderA.address,
    ethContract
  );

  const balanceBeforeB = await getBalance(
    liquidityProviderB.address,
    ethContract
  );

  const liquidityBeforeB = await getLPUnlockedBalance(
    liquidityProviderB.address,
    vaultContract
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

  await depositAll(depositAllArgs,vaultContract);
  //Debug


  const liquidityAfterA = await getLPUnlockedBalance(
    liquidityProviderA.address,
    vaultContract
  );

  const liquidityAfterB = await getLPUnlockedBalance(
    liquidityProviderB.address,
    vaultContract
  );

  const balanceAfterA = await getBalance(
    liquidityProviderA.address,
    ethContract
  );

  const balanceAfterB = await getBalance(
    liquidityProviderB.address,
    ethContract
  );

  //Asserts
  //1) Check liquidity for A has increased by depositAmount
  //2) Check liquidity for B has increased by depositAmount
  //3) Check eth balance for A has dropped by 2*depositAmount

  //Debug
  console.log("liquidityAfterA:",liquidityAfterA,"\nliquidityBeforeA:",liquidityBeforeA);
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
  await withdrawAll(
    withdrawAllData,
    vaultContract
  );

  let liquidityAfterWithdrawA = await getLPUnlockedBalance(
    liquidityProviderA.address,
    vaultContract
  );
  let liquidityAfterWithdrawB = await getLPUnlockedBalance(
    liquidityProviderB.address,
    vaultContract
  );

  let balanceAfterWithdrawA = await getBalance(
    liquidityProviderA.address,
    ethContract
  );
  let balanceAfterWithdrawB = await getBalance(
    liquidityProviderB.address,
    ethContract
  );

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
