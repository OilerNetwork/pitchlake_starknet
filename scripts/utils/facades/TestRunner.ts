import { Account, Provider } from "starknet";
import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { Constants } from "./types";
import { getCustomAccount } from "../helpers/common";
import { liquidityProviders, optionBidders } from "../constants";

export type ResultSheet = {
  accounts: Array<Account>;
  params: Array<StoragePoints>;
  method: Methods;
  before: Map<StoragePoints, (number | bigint) | Array<number | bigint>>;
  after: Map<StoragePoints, (number | bigint) | Array<number | bigint>>;
};

export class TestRunner {
  public provider: Provider;
  public ethFacade: ERC20Facade;
  public vaultFacade: VaultFacade;
  public constants: Constants;

  constructor(
    provider: Provider,
    vaultAddress: string,
    ethAddress: string,
    constants: Constants
  ) {
    this.vaultFacade = new VaultFacade(vaultAddress, provider);
    this.ethFacade = new ERC20Facade(ethAddress, provider);
    this.constants = constants;
    this.provider = provider;
  }

  async testResults(
    accounts: Array<Account>,
    params: Array<StoragePoints>,
    method: Methods
  ) {
    const before: Map<
      StoragePoints,
      (number | bigint) | Array<number | bigint>
    > = new Map();

    const after: Map<
      StoragePoints,
      (number | bigint) | Array<number | bigint>
    > = new Map();

    const resultSheet: ResultSheet = {
      params,
      accounts,
      method,
      before,
      after,
    };
    for (const param of params) {
      switch (param) {
        case StoragePoints.lpLocked: {
          const res = await this.vaultFacade.getLPLockedBalanceAll(accounts);
          resultSheet.before.set(StoragePoints.lpLocked, res);
          break;
        }
        case StoragePoints.lpUnlocked: {
          const res = await this.vaultFacade.getLPUnlockedBalanceAll(accounts);
          resultSheet.before.set(StoragePoints.lpUnlocked, res);
          break;
        }
        case StoragePoints.totalLocked: {
          const res = await this.vaultFacade.getTotalLocked();
          resultSheet.before.set(StoragePoints.totalLocked, res);
          break;
        }
        case StoragePoints.totalUnlocked: {
          const res = await this.vaultFacade.getTotalUnLocked();
          resultSheet.before.set(StoragePoints.totalUnlocked, res);
          break;
        }
      }
    }
  }

  getLiquidityProviderAccounts = (provider: Provider, length: number) => {
    const liquidityProviderAccounts: Array<Account> = [];
    for (let i = 0; i < length; i++) {
      liquidityProviderAccounts.push(
        getCustomAccount(
          provider,
          liquidityProviders[i].account,
          liquidityProviders[i].privateKey
        )
      );
    }
    return liquidityProviderAccounts;
  };

  getOptionBidderAccounts = (provider: Provider, length: number) => {
    const optionBidderAccounts: Array<Account> = [];
    for (let i = 0; i < length; i++) {
      optionBidderAccounts.push(
        getCustomAccount(
          provider,
          optionBidders[i].account,
          optionBidders[i].privateKey
        )
      );
    }
    return optionBidderAccounts;
  };
}

enum StoragePoints {
  lpUnlocked,
  lpLocked,
  totalLocked,
  totalUnlocked,
}

enum Methods {}
