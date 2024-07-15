const fs = require("fs");
const path = require("path");
const {
  hash,
  CallData,
  CairoCustomEnum,
  cairo,
  Contract,
  json,
} = require("starknet");
const { getContract } = require("./common");
const constantsPath = path.resolve(__dirname, "../constants.json");

function getConstants() {
  return JSON.parse(fs.readFileSync(constantsPath, "utf8"));
}

async function supply(enviornment, provider, account, recipient, amount) {
  const constants = getConstants();
  let contractAddress = constants.deployedContractsMapping[enviornment]["eth"];

  const ethContract = await getContract(provider, account, contractAddress);

  try {
    const myCall = ethContract.populate("transfer", [
      recipient,
      cairo.uint256(amount),
    ]);
    const res = await ethContract.transfer(myCall.calldata);
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

module.exports = {
  supply,
};
