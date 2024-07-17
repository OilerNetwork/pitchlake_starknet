import { Account, Contract, Provider } from "starknet";
import assert from "assert";
import { liquidityProviders } from "../utils/constants";
import {
  getProvider,
  getCustomAccount,
  getContract,
} from "../utils/helper/common";
import { getLPUnlockedBalance, deposit, withdraw } from "../utils/vault";
import { ABI as vaultAbi } from "../abi/vaultAbi";
import { ABI as ethAbi } from "../abi/ethAbi";
import { getBalance, approval } from "../utils/helper/eth";
async function smokeTesting0(
  provider: Provider,
  vaultAddress: string,
  ethAddress: string
) {
  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(
    vaultAbi
  );

  const ethContract = new Contract(ethAbi, ethAddress, provider).typedv2(
    ethAbi
  );
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

  //@note Wrap this into a try catch to avoid breaking thread and log errors correctly
  //Approve A for depositing
  await approval(liquidityProviderA, 1000000, ethContract, vaultAddress);

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
  await deposit(
    {
      from: liquidityProviderA,
      beneficiary: liquidityProviderB.address,
      amount: depositAmount,
    },
    vaultContract
  );

  await deposit(
    {
      from: liquidityProviderA,
      beneficiary: liquidityProviderA.address,
      amount: depositAmount,
    },
    vaultContract
  );

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
  await withdraw(liquidityProviderA, depositAmount / 2, vaultContract);
  await withdraw(liquidityProviderB, depositAmount / 2, vaultContract);

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
  console.log("liquidityAfterA:",liquidityAfterA,"\nliquidityAfterWithdrawA", liquidityAfterWithdrawA)
  assert(
    Number(liquidityAfterA) ==
      Number(liquidityAfterWithdrawA) + depositAmount / 2
  ,'Mismatch A liquidity');
  assert(
    Number(liquidityAfterB) ==
      Number(liquidityAfterWithdrawB) + depositAmount / 2
  ,'Mismatch B liquidity');
  assert(
    Number(balanceAfterA) == Number(balanceAfterWithdrawA) - depositAmount / 2
  ,'Mismatch A balance');
  assert(
    Number(balanceAfterB) == Number(balanceAfterWithdrawB) - depositAmount / 2
  ,'Mismatch B balance');
}

async function smokeTesting(
  enviornment: string,
  account: Account,
  vaultAddress: string,
  ethAddress: string,
  port?: string
) {
  const provider = getProvider(enviornment, port);
  await smokeTesting0(provider, vaultAddress, ethAddress);
}

export { smokeTesting };
