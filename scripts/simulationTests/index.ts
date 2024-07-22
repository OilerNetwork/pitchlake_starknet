import { TestRunner } from "../utils/facades/TestRunner";
import simulationJSON from "../simulationData/simulationSheet.json" assert { type: "json" };
import { SimulationSheet } from "../utils/facades/RoundSimulator";
import { RoundSimulator } from "../utils/facades/RoundSimulator";
import {
  generateSimulationParams,
  getOptionRoundContract,
} from "../utils/helpers/setup";
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
  await simulator.simulateRound(simulationParams[0]);
  await simulator.simulateRound(simulationParams[0]);
  await simulator.simulateRound(simulationParams[0]);
}

export { simulationTesting };
