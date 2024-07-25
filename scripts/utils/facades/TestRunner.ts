import { Account, Provider } from "starknet";
import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { Constants, DepositArgs, WithdrawArgs } from "./types";

export type ResultSheet = {
  accounts: Array<Account>;
  params: Array<StoragePoints>;
  method: Methods;
  before: Map<StoragePoints,(number|bigint)|Array<number|bigint>>
  after:Map<StoragePoints,(number|bigint)|Array<number|bigint>>
};

export type simulationParameters = {
  liquidityProviders:Array<Account>;
  optionBidders:Array<Account>;
  depositAmounts:Array<bigint|number>;
  bidAmounts:Array<bigint|number>;
  constants:Constants;
}


export class TestRunner {
  public provider: Provider;
  public ethFacade: ERC20Facade;
  public vaultFacade: VaultFacade;
  public constants: Constants;

  constructor(provider: Provider, vaultAddress: string, ethAddress: string,constants:Constants) {
    this.vaultFacade = new VaultFacade(vaultAddress, provider);
    this.ethFacade = new ERC20Facade(ethAddress, provider);
    this.constants = constants;
    this.provider = provider;
  }

  async testResults(accounts:Array<Account>,params: Array<StoragePoints>, method: Methods) {


  const before:Map<StoragePoints,(number|bigint)|Array<number|bigint>> = new Map;

  const after:Map<StoragePoints,(number|bigint)|Array<number|bigint>> = new Map;
    const resultSheet:ResultSheet = {params,accounts,method,before,after};
    for( const param of params)
    {
      switch (param){
        case StoragePoints.lpLocked:
          {
            const res = await this.getLPLockedBalanceAll(accounts);
            resultSheet.before.set(StoragePoints.lpLocked,res);
            break;
          }
        case StoragePoints.lpUnlocked:
          {
            const res = await this.getLPUnlockedBalanceAll(accounts);
            resultSheet.before.set(StoragePoints.lpUnlocked,res);
            break;
          }
        case StoragePoints.totalLocked:
          {
            const res = await this.vaultFacade.getTotalLocked();
            resultSheet.before.set(StoragePoints.totalLocked,res);
            break;
          }
        case StoragePoints.totalUnlocked:
          {
            const res = await this.vaultFacade.getTotalUnLocked();
            resultSheet.before.set(StoragePoints.totalUnlocked,res);
            break;
          }
      }
    }
  }

  async getLPUnlockedBalanceAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.vaultFacade.getLPUnlockedBalance(account.address);
        return res;
      })
    );
    return balances;
  }

  async getLPLockedBalanceAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.vaultFacade.getLPLockedBalance(account.address);
        return res;
      })
    );
    return balances;
  }

  async depositAll(depositData: Array<DepositArgs>) {
    for (const depositArgs of depositData) {
      await this.vaultFacade.deposit(depositArgs);
    }
  }

  async withdrawAll(withdrawData: Array<WithdrawArgs>) {
    for (const withdrawArgs of withdrawData) {
      await this.vaultFacade.withdraw(withdrawArgs);
    }
  }
}

enum StoragePoints {
  lpUnlocked,
  lpLocked,
  totalLocked,
  totalUnlocked,
}

enum Methods {

}
