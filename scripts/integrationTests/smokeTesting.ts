import { Account, Contract, Provider } from "starknet";

import { liquidityProviders } from "../utils/constants";
import { getProvider, getCustomAccount, getContract } from "../utils/helper/common";
import { getLPUnlockedBalance, deposit } from "../utils/vault";
import {ABI as vaultAbi} from "../abi/vaultAbi"

async function smokeTesting0(
  account:Account,
  provider: Provider,
  vaultAddress: string
) {


  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(vaultAbi);
  const lp = getCustomAccount(
    provider,
    liquidityProviders[0].account,
    liquidityProviders[0].privateKey
  );
  const liquidityBefore = await getLPUnlockedBalance(
    liquidityProviders[0].account,
    vaultContract
  );
  await deposit(
    account,
    liquidityProviders[0].account,
    1000,
    vaultContract
  );
  const liquidityAfter = await getLPUnlockedBalance(
    liquidityProviders[0].account,
    vaultContract
  );

  console.log("difference between both are: ", liquidityBefore, liquidityAfter);
}

async function smokeTesting(enviornment: string,account:Account,vaultAddress:string, port?: string) {
  const provider = getProvider(enviornment, port);
  await smokeTesting0( account,provider,vaultAddress);
}

export { smokeTesting };
