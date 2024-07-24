import { getAccount, getProvider } from "./utils/helpers/common";
import { smokeTesting } from "./integrationTests/smokeTesting";
import { declareContracts } from "./utils/deployment/declareContracts";
import { deployContracts } from "./utils/deployment/deployContracts";
import { TestRunner } from "./utils/facades/TestRunner";
import { Constants } from "./utils/facades/types";

async function main(environment: string, port?: string) {
  const provider = getProvider(environment, port);
  const devAccount = getAccount(environment, provider);
  let hashes = await declareContracts(devAccount);
  const constants:Constants={
    depositAmount:BigInt(10000000000000),
    reservePrice:BigInt(4000000000),
    strikePrice:BigInt(8000000000),
    settlementPrice:BigInt(16000000000),
    capLevel:5000,
  }
  let { ethAddress, vaultAddress } = await deployContracts(
    environment,
    devAccount,
    hashes,
  );

  const testRunner = new TestRunner(provider, vaultAddress, ethAddress,constants);


  await testRunner.ethFacade.supplyERC20(
    devAccount,
    provider,
    ethAddress,
    vaultAddress
  );

  //Can write to a file here and replace smoke test call to use multiple
  await smokeTesting(testRunner);
}

main(process.argv[2], process.argv[3]);
