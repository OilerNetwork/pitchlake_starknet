import { getAccount, getProvider } from "./utils/helpers/common";
import { smokeTesting } from "./integrationTests/smokeTesting";
import { declareContracts } from "./utils/deployment/declareContracts";
import { deployContracts } from "./utils/deployment/deployContracts";
import { EthFacade } from "./utils/facades/erc20Facade";
import { erc20ABI } from "./abi";
import { Contract } from "starknet";
import { TestRunner } from "./utils/facades/TestRunner";

async function main(environment: string, port?: string) {
  const provider = getProvider(environment, port);
  const devAccount = getAccount(environment, provider);
  let hashes = await declareContracts(devAccount);

  let { ethAddress, vaultAddress } = await deployContracts(
    environment,
    devAccount,
    hashes
  );

  const testRunner = new TestRunner(provider, vaultAddress, ethAddress);

  await testRunner.ethFacade.supplyEth(
    devAccount,
    provider,
    ethAddress,
    vaultAddress
  );

  //Can write to a file here and replace smoke test call to use multiple
  await smokeTesting(testRunner);
}

main(process.argv[2], process.argv[3]);
