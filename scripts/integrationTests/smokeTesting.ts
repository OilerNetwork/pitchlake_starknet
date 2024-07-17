
import { Contract, Provider } from "starknet";
import { smokeTest as smokeTest1 } from "./smokeTest1/auctionOpen";
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
  await smokeTest1(provider, vaultContract,ethContract);
}

export { smokeTesting };
