import { Provider, Account, TypedContractV2 } from "starknet";
import { getContract } from "./helper/common";
import { ABI as vaultAbi } from "../abi/vaultAbi";

type DepositArgs = {
  from: Account;
  beneficiary: string;
  amount: number;
};

type WithdrawArgs = {
  account: Account;
  amount: number;
  vaultContract: TypedContractV2<typeof vaultAbi>;
};
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
  account: Account,
  amount: number,
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

export const depositN = async (
  depositData: Array<DepositArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  await Promise.all(
    depositData.map(async (data: DepositArgs) => {
      vaultContract.connect(data.from);
      try {
        await vaultContract.deposit_liquidity(data.amount, data.beneficiary);
      } catch (err) {
        console.log(err);
      }
    })
  );
};

export const withdrawN = async (
  withdrawData: Array<WithdrawArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  await Promise.all(
    withdrawData.map(async (data: WithdrawArgs) => {
      vaultContract.connect(data.account);
      try {
        await vaultContract.withdraw_liquidity(data.amount);
      } catch (err) {
        console.log(err);
      }
    })
  );
};
