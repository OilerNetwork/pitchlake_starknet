import {

  Provider,
  Account,
  TypedContractV2,
} from "starknet";
import { getContract } from "./helper/common";
import {ABI as vaultAbi} from "../abi/vaultAbi";
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
  provider: Provider,
  amount: number,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {


  try {
    const res = await vaultContract.withdraw(amount);
    await provider.waitForTransaction(res.transaction_hash);
  } catch (err) {
    console.log(err);
  }
};

export const deposit = async (
  from:Account,
  beneficiary: string,
  amount: number,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {

  vaultContract.connect(from);
  try {
   
    await vaultContract.deposit_liquidity(amount,
    beneficiary);
  } catch (err) {
    console.log(err);
  }
};

