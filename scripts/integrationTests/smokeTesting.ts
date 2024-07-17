
import { Contract, Provider } from "starknet";
import { auctionOpenTests,auctionStartTests } from "./smokeTest1";
import {ABI as vaultAbi} from "../abi/vaultAbi";
import {ABI as ethAbi} from "../abi/ethAbi";
async function smokeTesting(
  provider:Provider,
  vaultAddress: string,
  ethAddress: string,
) {
  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(
    vaultAbi
  );
  const ethContract = new Contract(ethAbi, ethAddress,provider).typedv2(ethAbi);
  await auctionOpenTests(provider, vaultContract,ethContract);
  await auctionStartTests(provider,vaultContract,ethContract);

}

export { smokeTesting };
