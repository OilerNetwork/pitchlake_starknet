import { Account, Contract, Provider, TypedContractV2 } from "starknet";

import { ABI as ethAbi } from "../../abi/ethAbi";
import { ApprovalArgs } from "./types";
import { mineNextBlock } from "../katana";
import { getCustomAccount } from "../helpers/common";
import { liquidityProviders, optionBidders } from "../constants";

async function getBalance(
  account: string,
  ethContract: TypedContractV2<typeof ethAbi>
) {
  const balance = await ethContract.balance_of(account);
  return balance;
}

const supply = async (
  devAccount: Account,
  recipient: string,
  amount: number,
  ethContract: TypedContractV2<typeof ethAbi>
) => {
  try {
    ethContract.connect(devAccount);
    await ethContract.transfer(recipient, amount);
    // @note: don't delete it yet, waiting for response from starknet.js team
    // const result = await account.execute({
    //   contractAddress: ethContract,
    //   entrypoint: "transfer",
    //   calldata: CallData.compile({
    //     recipient: liquidityProviders[0].account,
    //     amount: cairo.uint256(10000),
    //   }),
    // });
    // const result2 = await provider.waitForTransaction(result.transaction_hash);
    // console.log(result, result2);
  } catch (err) {
    console.log(err);
  }
};



async function approval(
  { owner, amount, spender }: ApprovalArgs,
  ethContract: TypedContractV2<typeof ethAbi>
) {
  ethContract.connect(owner);
  try {
    ethContract.approve(spender, amount);

    // @note: don't delete it yet, waiting for response from starknet.js team
    // const result = await account.execute({
    //   contractAddress: ethContract,
    //   entrypoint: "transfer",
    //   calldata: CallData.compile({
    //     recipient: liquidityProviders[0].account,
    //     amount: cairo.uint256(10000),
    //   }),
    // });
    // const result2 = await provider.waitForTransaction(result.transaction_hash);
    // console.log(result, result2);
  } catch (err) {
    console.log(err);
  }
}

const approveAll = async (
  approveData: Array<ApprovalArgs>,
  ethContract: TypedContractV2<typeof ethAbi>
) => {
  for (const { owner, spender, amount } of approveData) {
    ethContract.connect(owner);
    try {
      await ethContract.approve(spender, amount);
    } catch (err) {
      console.log(err);
    }
  }
};

async function supplyEth(
  devAccount: Account,
  provider: Provider,
  ethAddress: string,
  approveFor: string
) {
  const ethContract = new Contract(ethAbi, ethAddress, provider).typedv2(
    ethAbi
  );

  for (let i = 0; i < 6; i++) {
    const lp = getCustomAccount(
      provider,
      liquidityProviders[i].account,
      liquidityProviders[i].privateKey
    );
    const ob = getCustomAccount(
      provider,
      optionBidders[i].account,
      optionBidders[i].privateKey
    );
    await supply(
      devAccount,
      liquidityProviders[i].account,
      1000000,
      ethContract
    );
    await approval(
      { owner: lp, amount: 1000000, spender: approveFor },
      ethContract
    );
    console.log(`Liquidity Provider ${i} funded `);

    await supply(devAccount, optionBidders[i].account, 1000000, ethContract);
    await approval(
      { owner: ob, amount: 1000000, spender: approveFor },
      ethContract
    );
    console.log(`Option Bidder ${i} funded `);
  }
}
export { supply, approval, getBalance, approveAll, supplyEth };
