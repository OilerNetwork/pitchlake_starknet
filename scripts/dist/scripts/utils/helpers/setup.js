import { CairoUint256, Contract } from "starknet";
import { stringToHex } from "./common";
import { erc20ABI, optionRoundABI } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";
export const getOptionRoundFacade = async (provider, vault, prev) => {
    const optionRoundContract = await getOptionRoundContract(provider, vault, prev);
    const optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    return optionRoundFacade;
};
export const getOptionRoundERC20Contract = async (provider, optionRound) => {
    // const optionRoundContract = await getOptionRoundContract(provider, vault);
    const optionRoundERC20Contract = new Contract(erc20ABI, optionRound.address, provider).typedv2(erc20ABI);
    return optionRoundERC20Contract;
};
export const getOptionRoundContract = async (provider, vault, prev) => {
    let optionRoundId = await vault.get_current_round_id();
    let id;
    if (typeof optionRoundId !== "number" && typeof optionRoundId !== "bigint") {
        const temp = new CairoUint256(optionRoundId);
        id = temp.toBigInt();
    }
    else
        id = BigInt(optionRoundId);
    if (prev) {
        id = id - BigInt(1);
    }
    const optionRoundAddressDecimalString = await vault.get_round_address(id);
    const optionRoundAddress = "0x" + stringToHex(optionRoundAddressDecimalString);
    const optionRoundContract = new Contract(optionRoundABI, optionRoundAddress, provider).typedv2(optionRoundABI);
    return optionRoundContract;
};
export const generateSimulationParams = ({ getLiquidityProviderAccounts, getOptionBidderAccounts }, simulationSheets) => {
    const liquidityProviderAccounts = getLiquidityProviderAccounts(5);
    const optionBidderAccounts = getOptionBidderAccounts(5);
    const simulationParams = simulationSheets.map((simulationSheet) => {
        const depositAllArgs = simulationSheet.liquidityProviders.map((provider, index) => {
            return {
                from: liquidityProviderAccounts[provider - 1],
                beneficiary: liquidityProviderAccounts[provider - 1].address,
                amount: simulationSheet.depositAmounts[index],
            };
        });
        const bidAllArgs = simulationSheet.optionBidders.map((bidder, index) => {
            const data = {
                from: optionBidderAccounts[bidder - 1],
                amount: Number(simulationSheet.bidAmounts[index]),
                price: BigInt(simulationSheet.bidPrices[index]),
            };
            return data;
        });
        let ref = {};
        const refundAllArgs = [];
        bidAllArgs.map((bids) => {
            if (!ref[bids.from.address]) {
                ref[bids.from.address] = true;
                refundAllArgs.push({
                    from: bids.from,
                    optionBidder: bids.from.address,
                });
            }
        });
        let withdrawPremiumArgs = [];
        if (simulationSheet.withdrawalsPremium) {
            withdrawPremiumArgs = simulationSheet.withdrawalsPremium.map((bidder) => ({
                account: liquidityProviderAccounts[bidder - 1],
                amount: 0,
            }));
        }
        let withdrawalArgs = [];
        if (simulationSheet.withdrawalAmounts && simulationSheet.withdrawals) {
            withdrawalArgs = simulationSheet.withdrawals.map((bidder, index) => {
                return {
                    account: liquidityProviderAccounts[bidder - 1],
                    amount: Number(simulationSheet.withdrawalAmounts
                        ? simulationSheet.withdrawalAmounts[index]
                        : 0),
                };
            });
        }
        const exerciseOptionsAllArgs = simulationSheet.optionBidders.map((bidder) => ({
            from: optionBidderAccounts[bidder - 1],
        }));
        const data = {
            depositAllArgs,
            bidAllArgs,
            marketData: simulationSheet.marketData,
            withdrawPremiumArgs,
            withdrawalArgs,
            exerciseOptionsAllArgs,
            refundAllArgs,
        };
        return data;
    });
    return simulationParams;
};
