import { Account, TypedContractV2 } from "starknet";

import { ABI as ethAbi } from "../../abi/ethAbi";
import { ApprovalArgs } from "./types";

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
    const balanceBefore = await ethContract.balance_of(recipient);

    await ethContract.transfer(recipient, amount);

    const balanceAfter = await ethContract.balance_of(recipient);

    console.log(
      `Balance before funding was: ${balanceBefore} and after is: ${balanceAfter}`
    );

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
    await ethContract.approve(spender, amount);

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
  await Promise.all(
    approveData.map(async ({ owner, amount, spender }: ApprovalArgs) => {
      ethContract.connect(owner);
      try {
        await ethContract.approve(spender, amount);
      } catch (err) {
        console.log(err);
      }
    })
  );
};

export { supply, approval, getBalance, approveAll };
