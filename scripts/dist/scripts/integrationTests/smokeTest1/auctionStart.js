import { getAccount } from "../../utils/helpers/common";
import { getOptionRoundFacade } from "../../utils/helpers/setup";
import assert from "assert";
import { mineNextBlock } from "../../utils/katana";
export const smokeTest = async ({ provider, vaultFacade, constants, getLPUnlockedBalanceAll, getLPLockedBalanceAll, getBalancesAll, approveAll, startAuctionBystander, getLiquidityProviderAccounts, getOptionBidderAccounts, }) => {
    const optionRoundFacade = await getOptionRoundFacade(provider, vaultFacade.vaultContract);
    const devAccount = getAccount("dev", provider);
    try {
        await vaultFacade.startAuction(devAccount);
        throw Error("Should have reverted");
    }
    catch (err) {
        const error = err;
        assert(error.message !== "Should have reverted", error.message);
        //Failure expected when contracts are changed to revert
    }
    const stateAfter = await optionRoundFacade.optionRoundContract.get_state();
    const liquidityProviderAccounts = getLiquidityProviderAccounts(2);
    const optionBidderAccounts = getOptionBidderAccounts(2);
    assert(stateAfter.activeVariant() === "Open", `Expected:Open\nReceived:${stateAfter.activeVariant()}`);
    await startAuctionBystander();
    const unlockedBalances = await getLPUnlockedBalanceAll(liquidityProviderAccounts);
    const lockedBalances = await getLPLockedBalanceAll(liquidityProviderAccounts);
    const totalLockedAmount = await vaultFacade.getTotalLocked();
    const totalUnlockedAmount = await vaultFacade.getTotalUnLocked();
    //Asserts
    checkpoint1({
        unlockedBalances,
        lockedBalances,
        totalLockedAmount,
        totalUnlockedAmount,
        depositAmount: constants.depositAmount,
    });
    //Approve OptionBidders
    const approveAllData = [
        {
            owner: optionBidderAccounts[0],
            amount: BigInt("90000000000000000000"),
            spender: optionRoundFacade.optionRoundContract.address,
        },
        {
            owner: optionBidderAccounts[1],
            amount: BigInt("90000000000000000000"),
            spender: optionRoundFacade.optionRoundContract.address,
        },
    ];
    await approveAll(approveAllData);
    await mineNextBlock(provider.channel.nodeUrl);
    //Place bids according to story script
    const reservePrice = await optionRoundFacade.getReservePrice();
    const totalOptionAvailable = await optionRoundFacade.getTotalOptionsAvailable();
    const ethBalancesBefore = await getBalancesAll(optionBidderAccounts);
    const placeBidsData = [
        {
            from: optionBidderAccounts[0],
            amount: BigInt(totalOptionAvailable) / BigInt(2),
            price: BigInt(3) * BigInt(reservePrice),
        },
        {
            from: optionBidderAccounts[1],
            amount: BigInt(totalOptionAvailable) / BigInt(2),
            price: BigInt(2) * BigInt(reservePrice),
        },
        {
            from: optionBidderAccounts[1],
            amount: BigInt(totalOptionAvailable) / BigInt(2),
            price: BigInt(reservePrice),
        },
    ];
    await optionRoundFacade.placeBidsAll(placeBidsData);
    const ethBalancesAfter = await getBalancesAll(optionBidderAccounts);
    const bidArrays = await optionRoundFacade.getBidsForAll(optionBidderAccounts);
    checkpoint2({
        ethBalancesBefore,
        ethBalancesAfter,
        bidArrays,
        reservePrice,
        totalOptionAvailable,
    });
};
async function checkpoint1({ lockedBalances, unlockedBalances, totalLockedAmount, totalUnlockedAmount, depositAmount, }) {
    assert(Number(unlockedBalances[0]) === 0, `UnlockedBalanceA 0 expected, found ${unlockedBalances[0]}`);
    assert(Number(unlockedBalances[1]) === 0, `UnlockedBalanceB 0 expected, found ${unlockedBalances[1]}`);
    assert(BigInt(lockedBalances[0]) === BigInt(depositAmount) / BigInt(2), `LockedBalanceA ${BigInt(depositAmount) / BigInt(2)} expected, found ${lockedBalances[0]}`);
    assert(BigInt(lockedBalances[1]) === BigInt(depositAmount) / BigInt(2), `LockedBalanceB ${BigInt(depositAmount) / BigInt(2)} expected, found ${lockedBalances[1]}`);
    assert(BigInt(totalUnlockedAmount) === BigInt(0), `Total unlocked 0 expected, found ${totalUnlockedAmount}`);
    assert(BigInt(totalLockedAmount) === BigInt(depositAmount), `Total Locked amount ${BigInt(depositAmount)} expected, found ${totalLockedAmount}`);
}
async function checkpoint2({ ethBalancesBefore, ethBalancesAfter, bidArrays, totalOptionAvailable, reservePrice, }) {
    console.log("Bids from A:\n", bidArrays[0], "\nBids from B:\n", bidArrays[1]);
    assert(BigInt(ethBalancesBefore[0]) - BigInt(ethBalancesAfter[0]) ===
        (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
            BigInt(2), "Error A");
    assert(BigInt(ethBalancesBefore[1]) - BigInt(ethBalancesAfter[1]) ===
        (BigInt(3) * BigInt(reservePrice) * BigInt(totalOptionAvailable)) /
            BigInt(2), "Error B");
    assert(bidArrays[0].length === 1, `No. of Bids for A wrong,\n Expected:${BigInt(totalOptionAvailable)}\n Received:${bidArrays[0]?.length}`);
    assert(bidArrays[0][0].amount === BigInt(totalOptionAvailable) / BigInt(2), "Bid for A amount wrong");
    assert(bidArrays[0][0].price === BigInt(3) * BigInt(reservePrice), "Bid for A price wrong");
    assert(bidArrays[1].length === 2, "No. of Bids for B wrong");
    assert(bidArrays[1][0].amount === BigInt(totalOptionAvailable) / BigInt(2), "First bid for B amount wrong");
    assert(bidArrays[1][0].price === BigInt(2) * BigInt(reservePrice), "First bid for B price wrong");
    assert(bidArrays[1][1].amount === BigInt(totalOptionAvailable) / BigInt(2), "Second bid for B amount wrong ");
    assert(BigInt(bidArrays[1][1].price) === BigInt(reservePrice), `Second bid for B price wrong.\n Expected:${reservePrice}, Actual:${bidArrays[1][0].price}`);
}