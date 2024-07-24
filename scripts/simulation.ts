import { getAccount, getProvider } from "./utils/helpers/common";
import { declareContracts } from "./utils/deployment/declareContracts";
import { deployContracts } from "./utils/deployment/deployContracts";
import { TestRunner } from "./utils/facades/TestRunner";
import { Constants, MarketData } from "./utils/facades/types";
import { simulationTesting } from "./simulationTests";
import { SimulationParameters } from "./utils/facades/RoundSimulator";
async function main(environment: string, port?: string) {
  const provider = getProvider(environment, port);
  const devAccount = getAccount(environment, provider);
  let hashes = await declareContracts(devAccount);
  let { ethAddress, vaultAddress } = await deployContracts(
    environment,
    devAccount,
    hashes
  );

  //@Note remove this when testRunner refactor by Jithin is finished

  const constants: Constants = {
    depositAmount: BigInt(10000000000000),
    reservePrice: BigInt(4000000000),
    strikePrice: BigInt(8000000000),
    settlementPrice: BigInt(16000000000),
    capLevel: 5000,
  };

  const testRunner = new TestRunner(
    provider,
    vaultAddress,
    ethAddress,
    constants
  );


  await testRunner.ethFacade.supplyERC20(
    devAccount,
    provider,
    ethAddress,
    vaultAddress
  );
  await simulationTesting(testRunner);
}

main(process.argv[2], process.argv[3]);

