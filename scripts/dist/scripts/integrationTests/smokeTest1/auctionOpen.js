import assert from "assert";
import { getLiquidityProviderAccounts } from "../../utils/helpers/accounts";
//@note Wrap functions into a try catch to avoid breaking thread, log errors correctly
export const smokeTest = async (provider, vault, eth, constants) => {
    const liquidityProviderAccounts = getLiquidityProviderAccounts(provider, 2);
    //Approve A for depositing
    await eth.approval({
        owner: liquidityProviderAccounts[0],
        amount: 1000000,
        spender: vault.vaultContract.address,
    });
    const ethBalancesBefore = await eth.getBalancesAll(liquidityProviderAccounts);
    const lpUnlockedBalancesBefore = await vault.getLPUnlockedBalanceAll(liquidityProviderAccounts);
    //Deposits
    //1. Deposit from A with B as beneficiary
    //2. Deposit from A for self
    const depositAllArgs = [
        {
            from: liquidityProviderAccounts[0],
            beneficiary: liquidityProviderAccounts[1].address,
            amount: constants.depositAmount,
        },
        {
            from: liquidityProviderAccounts[0],
            beneficiary: liquidityProviderAccounts[0].address,
            amount: constants.depositAmount,
        },
    ];
    await vault.depositAll(depositAllArgs);
    //Debug
    const lpUnlockedBalancesAfter = await vault.getLPUnlockedBalanceAll(liquidityProviderAccounts);
    const ethBalancesAfter = await eth.getBalancesAll(liquidityProviderAccounts);
    //Asserts
    //1) Check liquidity for A has increased by depositAmount
    //2) Check liquidity for B has increased by depositAmount
    //3) Check eth balance for A has dropped by 2*depositAmount
    checkpoint1({
        lpUnlockedBalancesBefore,
        lpUnlockedBalancesAfter,
        ethBalancesBefore,
        ethBalancesAfter,
        constants,
    });
    //Withdraws
    //Withdraw constants.depositAmount/2 from vaultContract for A and B positions
    const withdrawAllData = [
        {
            account: liquidityProviderAccounts[0],
            amount: constants.depositAmount / 2,
        },
        {
            account: liquidityProviderAccounts[1],
            amount: constants.depositAmount / 2,
        },
    ];
    await vault.withdrawAll(withdrawAllData);
    const lpUnlockedBalancesAfterWithdraw = await vault.getLPUnlockedBalanceAll(liquidityProviderAccounts);
    const ethBalancesAfterWithdraw = await eth.getBalancesAll(liquidityProviderAccounts);
    //Asserts
    //1) Check liquidity for A & B has decreased by depositAmount/2
    //2) Check balance for A & B has increased by depositAmount/2
    checkpoint2({
        lpUnlockedBalancesBefore: lpUnlockedBalancesAfter,
        lpUnlockedBalancesAfter: lpUnlockedBalancesAfterWithdraw,
        ethBalancesBefore: ethBalancesAfter,
        ethBalancesAfter: ethBalancesAfterWithdraw,
        constants,
    });
};
function checkpoint1({ lpUnlockedBalancesBefore, lpUnlockedBalancesAfter, ethBalancesBefore, ethBalancesAfter, constants, }) {
    assert(Number(lpUnlockedBalancesAfter[0]) ===
        Number(lpUnlockedBalancesBefore[0]) + constants.depositAmount, "liquidity A mismatch");
    assert(Number(lpUnlockedBalancesAfter[1]) ===
        Number(lpUnlockedBalancesBefore[1]) + constants.depositAmount, "liquidity B mismatch");
    assert(Number(lpUnlockedBalancesBefore[0]) ===
        Number(lpUnlockedBalancesAfter[0]) + 2 * constants.depositAmount, "Eth balance for a mismatch");
}
function checkpoint2({ lpUnlockedBalancesAfter, lpUnlockedBalancesBefore, ethBalancesAfter, ethBalancesBefore, constants, }) {
    assert(Number(lpUnlockedBalancesBefore[0]) ==
        Number(lpUnlockedBalancesAfter[0]) + constants.depositAmount / 2, "Mismatch A liquidity");
    assert(Number(lpUnlockedBalancesBefore[1]) ==
        Number(lpUnlockedBalancesAfter[1]) + constants.depositAmount / 2, "Mismatch B liquidity");
    assert(Number(ethBalancesBefore[0]) ==
        Number(ethBalancesAfter[0]) - constants.depositAmount / 2, "Mismatch A balance");
    assert(Number(ethBalancesBefore[1]) ==
        Number(ethBalancesAfter[1]) - constants.depositAmount / 2, "Mismatch B balance");
}
