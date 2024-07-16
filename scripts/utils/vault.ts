import {
  hash,
  CallData,
  CairoCustomEnum,
  cairo,
  Contract,
  json,
  Provider,
  Account,
} from "starknet";
import { getContract } from "./helper/common";

export const getLPUnlockedBalance = async (
  provider: Provider,
  account: Account,
  address: string,
  vaultAddress: string
) => {
  const vaultContract = await getContract(provider, account, vaultAddress);

  try {
    const res = await vaultContract.get_lp_unlocked_balance(address);
    return res;
  } catch (err) {
    console.log(err);
  }
};

export const withdraw = async (
  provider: Provider,
  account: Account,
  amount: number,
  vaultAddress: string
) => {
  let contractAddress = vaultAddress;

  const vaultContract = await getContract(provider, account, contractAddress);

  try {
    const myCall = vaultContract.populate("withdraw", [cairo.uint256(amount)]);
    const res = await vaultContract.withdraw(myCall.calldata);
    await provider.waitForTransaction(res.transaction_hash);
  } catch (err) {
    console.log(err);
  }
};

export const deposit = async (
  provider: Provider,
  account: Account,
  address: string,
  amount: number|string,
  vaultAddress: string
) => {
  const vaultContract = await getContract(provider, account, vaultAddress);

  try {
    const myCall = vaultContract.populate("deposit_liquidity", [
      cairo.uint256(amount),
      address,
    ]);
    const res = await vaultContract.deposit_liquidity(myCall.calldata);
    await provider.waitForTransaction(res.transaction_hash);
  } catch (err) {
    console.log(err);
  }
};
