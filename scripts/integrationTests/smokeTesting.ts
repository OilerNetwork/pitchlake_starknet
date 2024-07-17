
import { Contract, Provider } from "starknet";
import { auctionOpenTests,auctionStartTests } from "./smokeTest1";
import {ABI as vaultAbi} from "../abi/vaultAbi";
import {ABI as ethAbi} from "../abi/ethAbi";
import { VaultFacade } from "../utils/facades/vaultFacade";
import { EthFacade } from "../utils/facades/ethFacade";
async function smokeTesting(
  provider:Provider,
  vaultAddress: string,
  ethAddress: string,
) {
  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(
    vaultAbi
  );
  const ethContract = new Contract(ethAbi, ethAddress,provider).typedv2(ethAbi);

  const vaultFacade = new VaultFacade(vaultContract);
  const ethFacade = new EthFacade(ethContract);
  const constants = {
    depositAmount:1000
  }
  await auctionOpenTests(provider, vaultFacade,ethFacade,constants);
  await auctionStartTests(provider,vaultFacade,ethFacade,constants);
}

export { smokeTesting };
