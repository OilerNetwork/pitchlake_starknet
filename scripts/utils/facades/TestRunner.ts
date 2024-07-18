import { Provider } from "starknet";
import { EthFacade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { Constants } from "./types";

export class TestRunner {
  public provider: Provider;
  public ethFacade: EthFacade;
  public vaultFacade: VaultFacade;
  public constants: Constants;

  constructor(provider: Provider, vaultAddress: string, ethAddress: string) {
    this.vaultFacade = new VaultFacade(vaultAddress, provider);
    this.ethFacade = new EthFacade(ethAddress, provider);
    this.constants = {
      depositAmount: 1000,
    };
    this.provider = provider;
  }
}
