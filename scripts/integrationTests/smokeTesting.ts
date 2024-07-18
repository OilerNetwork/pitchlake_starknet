import { Contract, Provider } from "starknet";
import {
  auctionEndTetsts,
  auctionOpenTests,
  auctionStartTests,
  refundTokenizeBids,
} from "./smokeTest1";
import { ABI as vaultAbi } from "../abi/vaultAbi";
import { ABI as ethAbi } from "../abi/ethAbi";
import { VaultFacade } from "../utils/facades/vaultFacade";
import { EthFacade } from "../utils/facades/ethFacade";
async function smokeTesting(
  provider: Provider,
  vaultAddress: string,
  ethAddress: string
) {
  const vaultContract = new Contract(vaultAbi, vaultAddress, provider).typedv2(
    vaultAbi
  );
  const ethContract = new Contract(ethAbi, ethAddress, provider).typedv2(
    ethAbi
  );

  const vaultFacade = new VaultFacade(vaultContract);
  const ethFacade = new EthFacade(ethContract);
  const constants = {
    depositAmount: 1000,
  };
  await auctionOpenTests(provider, vaultFacade, ethFacade, constants);
  console.log(1);
  await auctionStartTests(provider, vaultFacade, ethFacade, constants);
  console.log(2);
  await auctionEndTetsts(provider, vaultFacade, ethFacade, constants);
  console.log(3);
  await refundTokenizeBids(provider, vaultFacade, ethFacade, constants);
  console.log(4);
}

export { smokeTesting };
