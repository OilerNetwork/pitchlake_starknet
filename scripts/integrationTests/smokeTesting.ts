
import { auctionEndTetsts, auctionOpenTests,auctionStartTests } from "./smokeTest1";
import { VaultFacade } from "../utils/facades/vaultFacade";
import { EthFacade } from "../utils/facades/ethFacade";
import { TestRunner } from "../utils/facades/TestRunner";
async function smokeTesting(
 testRunner:TestRunner
) {
  await auctionOpenTests(testRunner);
  await auctionStartTests(testRunner);
  await auctionEndTetsts(testRunner);
}

export { smokeTesting };
