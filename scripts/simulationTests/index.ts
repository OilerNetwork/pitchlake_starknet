import { TestRunner } from "../utils/facades/TestRunner";
import simulationJSON from "../simulationData/simulationSheet.json" assert { type: "json" };
import { SimulationSheet } from "../utils/facades/RoundSimulator";
import { RoundSimulator } from "../utils/facades/RoundSimulator";
import {
  generateSimulationParams,
  getOptionRoundContract,
} from "../utils/helpers/setup";
import fs from "fs"


export type Results = {
    results:Array<Result>
  }
  export type Result = any;

async function simulationTesting(testRunner: TestRunner) {
  const optionRoundContract = await getOptionRoundContract(
    testRunner.provider,
    testRunner.vaultFacade.vaultContract
  );
  const simulator = new RoundSimulator(testRunner, optionRoundContract);
  const simulationSheets: Array<SimulationSheet> =
    simulationJSON as Array<SimulationSheet>;
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
  fs.writeFile(`./simulationData/simulationResults.json`, stringified, 'utf8',()=>{});

}

export { simulationTesting };
