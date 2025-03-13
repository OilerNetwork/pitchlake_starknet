import { RoundSimulator, } from "../utils/facades/RoundSimulator";
import marketData from "../simulationData/marketData.json" assert { type: "json" };
import { generateSimulationParams, getOptionRoundContract, } from "../utils/helpers/setup";
import fs from "fs";
async function simulationTesting(testRunner) {
    const optionRoundContract = await getOptionRoundContract(testRunner.provider, testRunner.vaultFacade.vaultContract);
    const simulator = new RoundSimulator(testRunner, optionRoundContract);
    const simulationSheets = generateSheet();
    const simulationParams = generateSimulationParams(testRunner, simulationSheets);
    const data = { results: [] };
    for (const roundParams of simulationParams) {
        const roundData = await simulator.simulateRound(roundParams);
        data.results.push(roundData);
    }
    const stringified = JSON.stringify(data);
    fs.writeFile(`./simulationData/simulationOutput/simulationResults-${Math.floor(Date.now() / 1000)}.json`, stringified, "utf8", () => { });
}
export { simulationTesting };
const initial = {
    liquidityProviders: [1, 2],
    depositAmounts: ["50000000000000", "50000000000000"],
    optionBidders: [1, 3],
};
const repeating = {
    liquidityProviders: [],
    depositAmounts: [],
    optionBidders: [1, 3],
};
export const generateSheet = () => {
    const simulationMarketData = marketData.map((data) => {
        return {
            settlementPrice: Math.floor(data.settlement_price),
            maxReturns: data.maxReturns,
            reservePrice: Math.floor(data.reserve_price),
            strikePrice: Math.floor(data.strike_price),
            startTime: data.starting_timestamp,
            endTime: data.ending_timestamp,
        };
    });
    const simulationSheet = simulationMarketData.map((marketData, index) => {
        if (index == 0) {
            return {
                ...initial,
                bidPrices: initial.optionBidders.map((bidder) => {
                    return marketData.reservePrice;
                }),
                marketData,
                bidAmounts: [Math.random(), Math.random()],
                withdrawals: [1, 2],
                withdrawalAmounts: [Math.random() / 2, Math.random() / 2],
            };
        }
        else
            return {
                ...repeating,
                bidAmounts: [Math.random(), Math.random()],
                withdrawals: [1, 2],
                withdrawalAmounts: [Math.random() / 2, Math.random() / 2],
                bidPrices: initial.optionBidders.map((bidder) => {
                    return marketData.reservePrice;
                }),
                marketData,
            };
    });
    return simulationSheet;
};
