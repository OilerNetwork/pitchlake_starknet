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
  const round1 = await simulator.simulateRound(simulationParams[0]);
  const round2 = await simulator.simulateRound(simulationParams[0]);
  const round3 = await simulator.simulateRound(simulationParams[0]);

 
  const data:Results = {results:[]};
  data.results.push(round1);
  data.results.push(round2);
  data.results.push(round3);
  console.log("DATA",{data})
  const stringified = JSON.stringify(data);
  fs.writeFile('myjsonfile.json', stringified, 'utf8',()=>{});

}

export { simulationTesting };
