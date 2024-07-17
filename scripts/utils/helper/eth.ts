import { cairo, Provider, Account, TypedContractV2 } from "starknet";
import { getContract } from "./common";

import { ABI as ethAbi } from "../../abi/ethAbi";

async function getBalance(
  account: string,
  ethContract: TypedContractV2<typeof ethAbi>
) {
  const balance = await ethContract.balance_of(account);
  return balance;
}

const supply = async (
  devAccount:Account,
  recipient: string,
  amount: number,
  ethContract: TypedContractV2<typeof ethAbi>
) => {
  try {
    ethContract.connect(devAccount)
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
  approver: Account,
  amount: number,
  ethContract: TypedContractV2<typeof ethAbi>,
  approveFor: string
) {
  ethContract.connect(approver);
  try {
    await ethContract.approve(approveFor, amount);

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

export { supply, approval,getBalance };
