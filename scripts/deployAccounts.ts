import { RpcProvider, Account, stark, ec, CallData, hash } from "starknet";

async function createTestAccounts(provider:RpcProvider) {
  let optionBuyers: Array<Account> = [];
  let liquidityProviders: Array<Account> = [];

  // new Open Zeppelin account v0.8.1
  // Generate public and private key pair.
  for (let i = 0; i < 10; i++) {
    const privateKey = stark.randomAddress();
    console.log("New OZ account:\nprivateKey=", privateKey);
    const starkKeyPub = ec.starkCurve.getStarkKey(privateKey);
    console.log("publicKey=", starkKeyPub);

    const OZaccountClassHash =
      "0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f";
    // Calculate future address of the account
    const OZaccountConstructorCallData = CallData.compile({
      publicKey: starkKeyPub,
    });
    const OZcontractAddress = hash.calculateContractAddressFromHash(
      starkKeyPub,
      OZaccountClassHash,
      OZaccountConstructorCallData,
      0
    );
    console.log("Precalculated account address=", OZcontractAddress);

    //Fund accounts
    
    const OZaccount = new Account(provider, OZcontractAddress, privateKey);

    const { transaction_hash, contract_address } =
      await OZaccount.deployAccount({
        classHash: OZaccountClassHash,
        constructorCalldata: OZaccountConstructorCallData,
        addressSalt: starkKeyPub,
      });

    await provider.waitForTransaction(transaction_hash);
    console.log(
      " New OpenZeppelin account created.\n   address =",
      contract_address
    );
    let newAccount = new Account(provider, contract_address, privateKey);
    if (i % 2 == 0) {
      optionBuyers.push(newAccount);
    } else {
      liquidityProviders.push(newAccount);
    }
  }
  return {optionBuyers,liquidityProviders}
}

export {
  createTestAccounts,
};
