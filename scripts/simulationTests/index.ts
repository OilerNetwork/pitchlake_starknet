import { TestRunner } from "../utils/facades/TestRunner";
import simulationJSON from "../simulationData/simulationSheet.json" assert { type: "json" };
import { SimulationSheet } from "../utils/facades/RoundSimulator";
import marketData from "../simulationData/marketData.json" assert {type:"json"};
import { RoundSimulator } from "../utils/facades/RoundSimulator";
import {
  generateSimulationParams,
  getOptionRoundContract,
} from "../utils/helpers/setup";
import fs from "fs"
import { MarketData } from "../utils/facades/types";


export type Results = {
    results:Array<Result>
  }
  export type Result = any;

async function simulationTesting(testRunner: TestRunner) {
  const optionRoundContract = await getOptionRoundContract(
    testRunner.provider,
    testRunner.vaultFacade.vaultContract
  );

  const simulationMarketData:Array<MarketData>=marketData.map((data)=>{

    return {
      reservePrice:Math.floor(data.reserve_price),
      settlementPrice:Math.floor(data.settlement_price),
      strikePrice:Math.floor(data.strike_price),
      capLevel:Math.floor(data.cap_level)
    }
  })

  const simulator = new RoundSimulator(testRunner, optionRoundContract);
  const inputSheets: Array<SimulationSheet> =
    simulationJSON as Array<SimulationSheet>;

  const simulationSheets = plugMarketData(simulationMarketData,inputSheets);
  const simulationParams = generateSimulationParams(
    testRunner.provider,
    simulationSheets
);

const data:Results = {results:[]};
for (const roundParams of simulationParams){
    const roundData = await simulator.simulateRound(roundParams);
    data.results.push(roundData);
}
console.log("DATA",data)
  const stringified = JSON.stringify(data);
  fs.writeFile(`./simulationData/simulationOutput/simulationResults-${Math.floor(Date.now()/1000)}.json`, stringified, 'utf8',()=>{});

}

export { simulationTesting };


const plugMarketData=(marketDataArr:Array<MarketData>,simulationSheet:Array<SimulationSheet>)=>{
  return simulationSheet.map((sheet,index)=>{
    return {
      ...sheet,
      marketData:marketDataArr[index]
    }
  })
}