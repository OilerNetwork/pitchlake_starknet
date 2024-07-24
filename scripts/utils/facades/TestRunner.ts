import { Account, Provider, TypedContractV2 } from "starknet";
import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { ApprovalArgs, Constants, DepositArgs, WithdrawArgs } from "./types";
import { getAccount, getCustomAccount, stringToHex } from "../helpers/common";
import { liquidityProviders, optionBidders } from "../constants";
import { MarketAggregatorFacade } from "./marketAggregatorFacade";
import { getOptionRoundContract } from "../helpers/setup";
import { getNow, timeskipNextBlock } from "../katana";
import { vaultABI } from "../../abi";

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
          const res = await this.getLPLockedBalanceAll(accounts);
          resultSheet.before.set(StoragePoints.lpLocked, res);
          break;
        }
        case StoragePoints.lpUnlocked: {
          const res = await this.getLPUnlockedBalanceAll(accounts);
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

  getLiquidityProviderAccounts = (length: number) => {
    const liquidityProviderAccounts: Array<Account> = [];
    for (let i = 0; i < length; i++) {
      liquidityProviderAccounts.push(
        getCustomAccount(
          this.provider,
          liquidityProviders[i].account,
          liquidityProviders[i].privateKey
        )
      );
    }
    return liquidityProviderAccounts;
  };

  getOptionBidderAccounts = (length: number) => {
    const optionBidderAccounts: Array<Account> = [];
    for (let i = 0; i < length; i++) {
      optionBidderAccounts.push(
        getCustomAccount(
          this.provider,
          optionBidders[i].account,
          optionBidders[i].privateKey
        )
      );
    }
    return optionBidderAccounts;
  };

  async getLPLockedBalanceAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.vaultFacade.getLPLockedBalance(account.address);
        return res;
      })
    );
    return balances;
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

  async getBalancesAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const balance = await this.ethFacade.getBalance(account.address);
        return balance;
      })
    );
    return balances;
  }

  async approveAll(approveData: Array<ApprovalArgs>) {
    for (const approvalArgs of approveData) {
      await this.ethFacade.approval(approvalArgs);
    }
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

   //@note Only works for katana dev instance with a --dev flag
   async startAuctionBystander(provider: Provider, constants: Constants) {
    const devAccount = getAccount("dev", provider);
    //Set market aggregator reserve_price
    const marketAggregatorString =
      await this.vaultFacade.vaultContract.get_market_aggregator();
    const marketAggregatorAddress = "0x" + stringToHex(marketAggregatorString);
    const marketAggFacade = new MarketAggregatorFacade(
      marketAggregatorAddress,
      provider
    );
    const optionRound = await getOptionRoundContract(
      provider,
      this.vaultFacade.vaultContract
    );
    const startDate = await optionRound.get_auction_start_date();
    const settleDate = await optionRound.get_option_settlement_date();
    await marketAggFacade.setReservePrice(
      devAccount,
      startDate,
      settleDate,
      constants.reservePrice
    );
    await marketAggFacade.setCapLevel(
      devAccount,
      startDate,
      settleDate,
      constants.capLevel
    );

    await marketAggFacade.setStrikePrice(
      devAccount,
      startDate,
      settleDate,
      constants.strikePrice
    );
    await marketAggFacade.setTWAP(
      devAccount,
      startDate,
      settleDate,
      constants.settlementPrice
    );
    await this.vaultFacade.vaultContract.update_round_params();

    await this.accelerateToAuctioning();

    this.vaultFacade.vaultContract.connect(devAccount);
    await this.vaultFacade.vaultContract.start_auction();
  }

  async accelerateToAuctioning() {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );
    const currentTime = await getNow(this.provider);
    const auctionStartDate = await optionRoundContract.get_auction_start_date();
  
    console.log("currentTime:",currentTime,"\nauctionStartDate:",auctionStartDate);;
    await timeskipNextBlock(
      Number(auctionStartDate) - Number(currentTime),
      this.provider.channel.nodeUrl
    );
  }

  async endAuctionBystander(provider: Provider) {
    const devAccount = getAccount("dev", provider);
    await this.accelerateToRunning();
    this.vaultFacade.vaultContract.connect(devAccount);
    await this.vaultFacade.vaultContract.end_auction();
  }

  async accelerateToRunning() {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );
  
    const currentTime = await getNow(this.provider);
    const auctionEndDate = await optionRoundContract.get_auction_end_date();
  
    await timeskipNextBlock(
      Number(auctionEndDate) - Number(currentTime),
      this.provider.channel.nodeUrl
    );
  }

  async settleOptionRoundBystander(provider: Provider) {
    await this.accelerateToSettled();
    const devAccount = getAccount("dev", provider);
    await this.vaultFacade.settleOptionRound(devAccount);
  }

  async  accelerateToSettled( ) {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );
  
    const currentTime = await getNow(this.provider);
    const optionSettleDate =
      await optionRoundContract.get_option_settlement_date();
  
    await timeskipNextBlock(
      Number(optionSettleDate) - Number(currentTime)+1,
      this.provider.channel.nodeUrl
    );
   
  }
}

enum StoragePoints {
  lpUnlocked,
  lpLocked,
  totalLocked,
  totalUnlocked,
}

enum Methods {}
