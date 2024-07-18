
import { auctionEndTetsts, auctionOpenTests,auctionStartTests } from "./smokeTest1";
import { TestRunner } from "../utils/facades/TestRunner";
async function smokeTesting(
 testRunner:TestRunner
) {
  await auctionOpenTests(testRunner);
  await auctionStartTests(testRunner);
  await auctionEndTetsts(testRunner);
}

export { smokeTesting };
