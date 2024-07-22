import { TestRunner } from "../utils/facades/TestRunner";
import {
  Constants,
  DepositArgs,
  ExerciseOptionArgs,
  PlaceBidArgs,
} from "../utils/facades/types";
import simulationJSON from "../simulationData/simulationSheet.json" assert { type: "json" };
import {
  SimulationSheet,
  SimulationParameters,
} from "../utils/facades/Simulator";
import { Simulator } from "../utils/facades/Simulator";
import {
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
} from "../utils/helpers/accounts";
import { Provider } from "starknet";
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
