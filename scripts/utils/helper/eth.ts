import {

  cairo,

  Provider,
  Account,
} from "starknet";
import { getContract } from "./common";

async function supply(
  provider: Provider,
  account: Account,
  recipient: string,
  amount: number | string,
  ethAddress: string
) {
  const ethContract = await getContract(provider, account, ethAddress);


  try {
    const balanceBefore = await ethContract.balance_of(recipient);
    const myCall = ethContract.populate("transfer", [
      recipient,
      cairo.uint256(amount),
    ]);
    const res = await ethContract.transfer(myCall.calldata);

    await provider.waitForTransaction(res.transaction_hash);
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
}

async function approval(
  provider: Provider,
  account: Account,
  amount: number,
  ethAddress: string,
  approveFor: string
) {
  const ethContract = await getContract(provider, account, ethAddress);
  ethContract.connect(account)
  try {
    const myCall = ethContract.populate("approve", [
      approveFor,
      cairo.uint256(amount),
    ]);
    const res = await ethContract.approve(myCall.calldata);
    await provider.waitForTransaction(res.transaction_hash);

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

export { supply, approval };
