import {
  auctionEndTetsts,
  auctionOpenTests,
  auctionStartTests,
  refundTokenizeBids,
} from "./smokeTest1";
import { TestRunner } from "../utils/facades/TestRunner";
async function smokeTesting(testRunner: TestRunner) {
  await auctionOpenTests(testRunner);
  await auctionStartTests(testRunner);
  await auctionEndTetsts(testRunner);
  await refundTokenizeBids(testRunner);
}

export { smokeTesting };
