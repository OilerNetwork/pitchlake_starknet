import { Account, TypedContractV2 } from "starknet";
import { ABI as vaultAbi } from "../../abi/vaultAbi";
import { DepositArgs, WithdrawArgs } from "./types";

export const getLPUnlockedBalance = async (
  address: string,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  try {
    const res = await vaultContract.get_lp_unlocked_balance(address);
    return res;
  } catch (err) {
    console.log(err);
  }
};

export const withdraw = async (
  { account, amount }: WithdrawArgs,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  vaultContract.connect(account);
  try {
    await vaultContract.withdraw_liquidity(amount);
  } catch (err) {
    console.log(err);
  }
};

export const deposit = async (
  { from, beneficiary, amount }: DepositArgs,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  vaultContract.connect(from);
  try {
    await vaultContract.deposit_liquidity(amount, beneficiary);
  } catch (err) {
    console.log(err);
  }
};

export const depositAll = async (
  depositData: Array<DepositArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  for (const args of depositData) {
      await deposit(args,vaultContract);
  }
};

export const withdrawAll = async (
  withdrawData: Array<WithdrawArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {

  for (const data of withdrawData){
    vaultContract.connect(data.account);
    try {
      await vaultContract.withdraw_liquidity(data.amount);
    } catch (err) {
      console.log(err);
    }
  }
};
