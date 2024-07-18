import { Provider } from "starknet";
import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { Constants } from "./types";

export class TestRunner {
  public provider: Provider;
  public ethFacade: ERC20Facade;
  public vaultFacade: VaultFacade;
  public constants: Constants;

  constructor(provider: Provider, vaultAddress: string, ethAddress: string) {
    this.vaultFacade = new VaultFacade(vaultAddress, provider);
    this.ethFacade = new ERC20Facade(ethAddress, provider);
    this.constants = {
      depositAmount: 1000,
    };
    this.provider = provider;
  }
}
