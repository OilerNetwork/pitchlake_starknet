import { Account, Contract, Provider } from "starknet";
import assert from "assert";
import { liquidityProviders } from "../utils/constants";
import {
  getProvider,
  getCustomAccount,
  getContract,
} from "../utils/helper/common";
import { getLPUnlockedBalance, deposit } from "../utils/vault";
import { ABI as vaultAbi } from "../abi/vaultAbi";
import { ABI as ethAbi} from "../abi/ethAbi";
import { getBalance,approval } from "../utils/helper/eth";
async function smokeTesting0(
  account: Account,
  provider: Provider,
  vaultAddress: string,
  ethAddress:string
) {
  
  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(
    vaultAbi
  );

  const ethContract = new Contract(ethAbi,ethAddress,provider).typedv2(ethAbi);
  
  const liquidityProviderA = getCustomAccount(
    provider,
    liquidityProviders[0].account,
    liquidityProviders[0].privateKey
  );
  const liquidityProviderB = getCustomAccount(
    provider,
    liquidityProviders[1].account,
    liquidityProviders[1].privateKey
  );

  //@note Wrap this into a try catch to avoid breaking thread and log errors correctly
  //Approve A for depositing 
  await approval(liquidityProviderA,1000000,ethContract,vaultAddress);

  const liquidityBeforeA = await getLPUnlockedBalance(
    liquidityProviderA.address,
    vaultContract
  );

  const balanceBeforeA = await getBalance(liquidityProviderA.address,ethContract)
  
  const liquidityBeforeB = await getLPUnlockedBalance(
    liquidityProviderB.address,
    vaultContract
  );

  await deposit(liquidityProviderA, liquidityProviderB.address, 1000, vaultContract);
  const liquidityAfterA = await getLPUnlockedBalance(
    liquidityProviderA.address,
    vaultContract
  );

  const liquidityAfterB = await getLPUnlockedBalance(
    liquidityProviderB.address,
    vaultContract
  );

  assert(liquidityAfterA!==liquidityBeforeA,"Balagan")
  console.log("difference between both is ",liquidityAfterA,liquidityBeforeA);
}

async function smokeTesting(
  enviornment: string,
  account: Account,
  vaultAddress: string,
  ethAddress:string,
  port?: string
) {
  const provider = getProvider(enviornment, port);
  await smokeTesting0(account, provider, vaultAddress,ethAddress);
}

export { smokeTesting };
