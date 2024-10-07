import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
export const smokeTest = async ({ provider, vaultFacade, getBalancesAll, getOptionBidderAccounts }) => {
    const optionRoundFacade = await getOptionRoundFacade(provider, vaultFacade.vaultContract, true);
    const optionBidderAccounts = getOptionBidderAccounts(3);
    const ethBalancesBefore = await getBalancesAll(optionBidderAccounts);
    const exerciseOptionsAllArgs = optionBidderAccounts.map((bidder) => {
        return { from: bidder };
    });
    await optionRoundFacade.exerciseOptionsAll(exerciseOptionsAllArgs);
    const ethBalancesAfter = await getBalancesAll(optionBidderAccounts);
    const totalPayout = await optionRoundFacade.getTotalPayout();
    checkpoint1({
        ethBalancesBefore,
        ethBalancesAfter,
        totalPayout,
    });
    await optionRoundFacade.exerciseOptionsAll(exerciseOptionsAllArgs);
    const ethBalancesAfterTwice = await getBalancesAll(optionBidderAccounts);
    checkpoint2({
        ethBalancesAfter,
        ethBalancesAfterTwice,
    });
};
async function checkpoint1({ ethBalancesBefore, ethBalancesAfter, totalPayout, }) {
    // - Test C & D exercise their options
    // - Test C’s ETH balance increases by 1/4 total payout
    assert(BigInt(ethBalancesAfter[0]) - BigInt(ethBalancesBefore[0]) ===
        BigInt(totalPayout) / BigInt(4), "Eth Balance for C mismatch");
    // - Test D’s ETH balance increases by 3/4 total payout
    assert(BigInt(ethBalancesAfter[1]) - BigInt(ethBalancesBefore[1]) ===
        (BigInt(3) * BigInt(totalPayout)) / BigInt(4), "Eth Balance for D mismatch");
}
async function checkpoint2({ ethBalancesAfter, ethBalancesAfterTwice, }) {
    assert(ethBalancesAfter[0] === ethBalancesAfterTwice[0], "Balance changed on exercising again");
    assert(ethBalancesAfter[1] === ethBalancesAfterTwice[1], "Balance changed on exercising again");
}
