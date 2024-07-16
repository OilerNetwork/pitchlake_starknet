import { Provider } from "starknet";

import { liquidityProviders } from "../utils/constants";
import { getProvider, getCustomAccount } from "../utils/helper/common";
import { getLPUnlockedBalance, deposit } from "../utils/vault";

async function smokeTesting0(
  enviornment: string,
  provider: Provider,
  vaultAddress: string
) {
  const lp = getCustomAccount(
    provider,
    liquidityProviders[0].account,
    liquidityProviders[0].privateKey
  );
  const liquidityBefore = await getLPUnlockedBalance(
    provider,
    lp,
    liquidityProviders[0].account,
    vaultAddress
  );
  await deposit(
    provider,
    lp,
    liquidityProviders[0].account,
    1000,
    vaultAddress
  );
  const liquidityAfter = await getLPUnlockedBalance(
    provider,
    lp,
    liquidityProviders[0].account,
    vaultAddress
  );

  console.log("difference between both are: ", liquidityBefore, liquidityAfter);
}

async function smokeTesting(enviornment: string,vaultAddress:string, port?: string) {
  const provider = getProvider(enviornment, port);
  await smokeTesting0(enviornment, provider,vaultAddress);
}

export { smokeTesting };
