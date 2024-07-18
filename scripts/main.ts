import { getAccount, getProvider } from "./utils/helpers/common";
import { smokeTesting } from "./integrationTests/smokeTesting";
import { declareContracts } from "./utils/deployment/declareContracts";
import { deployContracts } from "./utils/deployment/deployContracts";
import { EthFacade } from "./utils/facades/ethFacade";
import { ethAbi } from "./abi";
import { Contract } from "starknet";

async function main(environment: string, port?: string) {
  const provider = getProvider(environment, port);
  const devAccount = getAccount(environment, provider);
  let hashes = await declareContracts(devAccount);

  let contractAddresses = await deployContracts(
    environment,
    devAccount,
    hashes
  );

  const eth = new Contract(
    ethAbi,
    contractAddresses.ethAddress,
    provider
  ).typedv2(ethAbi);

  const ethFacade = new EthFacade(eth);

  await ethFacade.supplyEth(
    devAccount,
    provider,
    contractAddresses.ethAddress,
    contractAddresses.vaultAddress
  );

  //Can write to a file here and replace smoke test call to use multiple
  await smokeTesting(
    provider,
    contractAddresses.vaultAddress,
    contractAddresses.ethAddress
  );
}

main(process.argv[2], process.argv[3]);
