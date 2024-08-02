import { getAccount, getProvider } from "./utils/helpers/common";
import { declareContracts } from "./utils/deployment/declareContracts";
import { deployContracts } from "./utils/deployment/deployContracts";
import { TestRunner } from "./utils/facades/TestRunner";
import { Constants, MarketData } from "./utils/facades/types";
import { simulationTesting } from "./simulationTests";
import { SimulationParameters } from "./utils/facades/RoundSimulator";
import { Account, CallData, hash, Provider } from "starknet";
import { ERC20Facade } from "./utils/facades/erc20Facade";
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

  const feeTokenFacade = new ERC20Facade(
    "0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7",
    provider
  );

  feeTokenFacade.erc20Contract.connect(devAccount);
  await feeTokenFacade.erc20Contract.transfer(
    "0x0134f47366096198eb8f86e3ae6b075d399ca7abd918a56e01bb3b24963c2f75",
    BigInt(1000000000000000000)
  );
  await feeTokenFacade.erc20Contract.transfer(
    "0x01577908d02E0a3A6B243A149Eb91BB4514f3aAb948CFE63b2f8bb52397618D4",
    BigInt(1000000000000000000)
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
