import { TestRunner } from "../utils/facades/TestRunner";
import simulationJSON from "../simulationData/simulationSheet.json" assert { type: "json" };
import {
  SimulationSheet,
} from "../utils/facades/Simulator";
import { Simulator } from "../utils/facades/Simulator";
import { generateSimulationParams } from "../utils/helpers/setup";
async function simulationTesting(testRunner: TestRunner) {
  const simulator = new Simulator(testRunner);
  const simulationSheets: Array<SimulationSheet> =
    simulationJSON as Array<SimulationSheet>;
  const simulationParams = generateSimulationParams(
    testRunner.provider,
    simulationSheets
  );
  simulator.simulateRound(simulationParams[0]);
}

export { simulationTesting };
