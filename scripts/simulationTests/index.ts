import { TestRunner } from "../utils/facades/TestRunner";
import { SimulationSheet,RoundSimulator } from "../utils/facades/RoundSimulator";
import marketData from "../simulationData/marketData.json" assert { type: "json" };
import {
  generateSimulationParams,
  getOptionRoundContract,
} from "../utils/helpers/setup";
import fs from "fs";
import { MarketData } from "../utils/facades/types";

export type Results = {
  results: Array<Result>;
};
export type Result = any;

async function simulationTesting(testRunner: TestRunner) {
  const optionRoundContract = await getOptionRoundContract(
    testRunner.provider,
    testRunner.vaultFacade.vaultContract
  );

  const simulationMarketData: Array<MarketData> = marketData.map((data) => {
    return {
      reservePrice: Math.floor(data.reserve_price),
      settlementPrice: Math.floor(data.settlement_price),
      strikePrice: Math.floor(data.strike_price),
      capLevel: Math.floor(data.cap_level),
      startTime: data.starting_timestamp,
      endTime: data.ending_timestamp,
    };
  });

  const simulator = new RoundSimulator(testRunner, optionRoundContract);

  const simulationSheets = generateSheet();
  const simulationParams = generateSimulationParams(
    testRunner,
    simulationSheets
  );

  const data: Results = { results: [] };
  for (const roundParams of simulationParams) {
    const roundData = await simulator.simulateRound(roundParams);
    data.results.push(roundData);
  }
  console.log("DATA", data);
  const stringified = JSON.stringify(data);
  fs.writeFile(
    `./simulationData/simulationOutput/simulationResults-${Math.floor(
      Date.now() / 1000
    )}.json`,
    stringified,
    "utf8",
    () => {}
  );
}

export { simulationTesting };

const initial = {
  liquidityProviders: [1, 2],
  depositAmounts: ["50000000000000", "50000000000000"],
  optionBidders: [1, 3],
  bidAmounts: [5000, 7000],
};
const repeating = {
  liquidityProviders: [],
  depositAmounts: [],
  optionBidders: [1, 3],
  bidAmounts: [5000, 7000],
};

export const generateSheet = () => {
  const simulationMarketData: Array<MarketData> = marketData.map((data) => {
    return {
      reservePrice: Math.floor(data.reserve_price),
      settlementPrice: Math.floor(data.settlement_price),
      strikePrice: Math.floor(data.strike_price),
      capLevel: 1500,
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
        }, marketData),
      } as SimulationSheet;
    } else
      return {
        ...repeating,
        bidPrices: initial.optionBidders.map((bidder) => {
          return marketData.reservePrice;
        }),
        marketData,
      } as SimulationSheet;
  });
  return simulationSheet;
};
