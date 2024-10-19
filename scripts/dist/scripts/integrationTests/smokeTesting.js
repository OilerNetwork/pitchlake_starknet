import { auctionEndTetsts, auctionOpenTests, auctionStartTests, exerciseOptions, optionSettle, refundTokenizeBids, } from "./smokeTest1";
async function smokeTesting(testRunner) {
    await auctionOpenTests(testRunner);
    await auctionStartTests(testRunner);
    await auctionEndTetsts(testRunner);
    await refundTokenizeBids(testRunner);
    await optionSettle(testRunner);
    await exerciseOptions(testRunner);
}
export { smokeTesting };
