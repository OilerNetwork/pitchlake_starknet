import { Account, Provider } from "starknet";
import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import {
  ApprovalArgs,
  Constants,
  DepositArgs,
  MarketData,
  WithdrawArgs,
} from "./types";
import { getOptionRoundContract, getOptionRoundFacade } from "../helpers/setup";
import { getNow, timeskipNextBlock } from "../katana";
import { getAccount, getCustomAccount, stringToHex } from "../helpers/common";
import { MarketAggregatorFacade } from "./marketAggregatorFacade";
import { liquidityProviders, optionBidders } from "../constants";

export type ResultSheet = {
  accounts: Array<Account>;
  params: Array<StoragePoints>;
  method: Methods;
  before: Map<StoragePoints, (number | bigint) | Array<number | bigint>>;
  after: Map<StoragePoints, (number | bigint) | Array<number | bigint>>;
};

export type simulationParameters = {
  liquidityProviders: Array<Account>;
  optionBidders: Array<Account>;
  depositAmounts: Array<bigint | number>;
  bidAmounts: Array<bigint | number>;
  constants: Constants;
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

  testResults = async (
    accounts: Array<Account>,
    params: Array<StoragePoints>,
    method: Methods
  ) => {
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
  };

  getLPUnlockedBalanceAll = async (accounts: Array<Account>) => {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.vaultFacade.getLPUnlockedBalance(
          account.address
        );
        return res;
      })
    );
    return balances;
  };

  getLPLockedBalanceAll = async (accounts: Array<Account>) => {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.vaultFacade.getLPLockedBalance(account.address);
        return res;
      })
    );
    return balances;
  };

  depositAll = async (depositData: Array<DepositArgs>) => {
    for (const depositArgs of depositData) {
      await this.vaultFacade.deposit(depositArgs);
    }
  };

  withdrawAll = async (withdrawData: Array<WithdrawArgs>) => {
    for (const withdrawArgs of withdrawData) {
      await this.vaultFacade.withdraw(withdrawArgs);
    }
  };

  getBalancesAll = async (accounts: Array<Account>) => {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const balance = await this.ethFacade.getBalance(account.address);
        return balance;
      })
    );
    return balances;
  };

  approveAll = async (approveData: Array<ApprovalArgs>) => {
    for (const approvalArgs of approveData) {
      await this.ethFacade.approval(approvalArgs);
    }
  };

  accelerateToAuctioning = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );
    const currentTime = await getNow(this.provider);
    const auctionStartDate = await optionRoundContract.get_auction_start_date();

    console.log(
      "currentTime:",
      currentTime,
      "\nauctionStartDate:",
      auctionStartDate
    );
    await timeskipNextBlock(
      Number(auctionStartDate) - Number(currentTime),
      this.provider.channel.nodeUrl
    );
  };

  accelerateToRunning = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );

    const currentTime = await getNow(this.provider);
    const auctionEndDate = await optionRoundContract.get_auction_end_date();

    await timeskipNextBlock(
      Number(auctionEndDate) - Number(currentTime) + 1,
      this.provider.channel.nodeUrl
    );
  };

  accelerateToSettled = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract
    );

    const currentTime = await getNow(this.provider);
    const optionSettleDate =
      await optionRoundContract.get_option_settlement_date();

    await timeskipNextBlock(
      Number(optionSettleDate) - Number(currentTime),
      this.provider.channel.nodeUrl
    );
  };

  //@note Only works for katana dev instance with a --dev flag
  startAuctionBystander = async (marketData: MarketData) => {
    console.log("MARKETDATA:", marketData);
    const devAccount = getAccount("dev", this.provider);
    //Set market aggregator reserve_price
    const marketAggregatorString =
      await this.vaultFacade.vaultContract.get_market_aggregator();
    const marketAggregatorAddress = "0x" + stringToHex(marketAggregatorString);
    const marketAggFacade = new MarketAggregatorFacade(
      marketAggregatorAddress,
      this.provider
    );
    const optionRound = await getOptionRoundFacade(
      this.provider,
      this.vaultFacade.vaultContract
    );

    const roundId = await optionRound.getRoundId();
    const startDate =
      await optionRound.optionRoundContract.get_auction_start_date();
    const settleDate =
      await optionRound.optionRoundContract.get_option_settlement_date();

    await marketAggFacade.setMarketParameters({
      devAccount,
      vaultAddress: this.vaultFacade.vaultContract.address,
      roundId: roundId,
      startDate,
      settleDate,
      marketData,
    });

    await this.vaultFacade.vaultContract.update_round_params();

    await this.accelerateToAuctioning();

    this.vaultFacade.vaultContract.connect(devAccount);
    await this.vaultFacade.vaultContract.start_auction();
  };

  endAuctionBystander = async () => {
    const devAccount = getAccount("dev", this.provider);
    await this.accelerateToRunning();
    await this.vaultFacade.endAuction(devAccount);
  };

  settleOptionRoundBystander = async () => {
    await this.accelerateToSettled();
    const devAccount = getAccount("dev", this.provider);
    await this.vaultFacade.settleOptionRound(devAccount);
  };

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
}

enum StoragePoints {
  lpUnlocked,
  lpLocked,
  totalLocked,
  totalUnlocked,
}

enum Methods {}
