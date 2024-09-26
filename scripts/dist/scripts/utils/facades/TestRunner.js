import { ERC20Facade } from "./erc20Facade";
import { VaultFacade } from "./vaultFacade";
import { getOptionRoundContract, getOptionRoundFacade } from "../helpers/setup";
import { getNow, timeskipNextBlock } from "../katana";
import { getAccount, getCustomAccount, stringToHex } from "../helpers/common";
import { FactRegistryFacade } from "./factRegistryFacade";
import { liquidityProviders, optionBidders } from "../constants";
export class TestRunner {
  provider;
  ethFacade;
  vaultFacade;
  constants;
  constructor(provider, vaultAddress, ethAddress, constants) {
    this.vaultFacade = new VaultFacade(vaultAddress, provider);
    this.ethFacade = new ERC20Facade(ethAddress, provider);
    this.constants = constants;
    this.provider = provider;
  }
  testResults = async (accounts, params, method) => {
    const before = new Map();
    const after = new Map();
    const resultSheet = {
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
  getLPUnlockedBalanceAll = async (accounts) => {
    const balances = await Promise.all(
      accounts.map(async (account) => {
        const res = await this.vaultFacade.getLPUnlockedBalance(
          account.address,
        );
        return res;
      }),
    );
    return balances;
  };
  getLPLockedBalanceAll = async (accounts) => {
    const balances = await Promise.all(
      accounts.map(async (account) => {
        const res = await this.vaultFacade.getLPLockedBalance(account.address);
        return res;
      }),
    );
    return balances;
  };
  depositAll = async (depositData) => {
    for (const depositArgs of depositData) {
      await this.vaultFacade.deposit(depositArgs);
    }
  };
  withdrawAll = async (withdrawData) => {
    for (const withdrawArgs of withdrawData) {
      await this.vaultFacade.withdraw(withdrawArgs);
    }
  };
  getBalancesAll = async (accounts) => {
    const balances = await Promise.all(
      accounts.map(async (account) => {
        const balance = await this.ethFacade.getBalance(account.address);
        return balance;
      }),
    );
    return balances;
  };
  approveAll = async (approveData) => {
    for (const approvalArgs of approveData) {
      await this.ethFacade.approval(approvalArgs);
    }
  };
  accelerateToAuctioning = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract,
    );
    const currentTime = await getNow(this.provider);
    const auctionStartDate = await optionRoundContract.get_auction_start_date();
    console.log(
      "currentTime:",
      currentTime,
      "\nauctionStartDate:",
      auctionStartDate,
    );
    await timeskipNextBlock(
      Number(auctionStartDate) - Number(currentTime),
      this.provider.channel.nodeUrl,
    );
  };
  accelerateToRunning = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract,
    );
    const currentTime = await getNow(this.provider);
    const auctionEndDate = await optionRoundContract.get_auction_end_date();
    await timeskipNextBlock(
      Number(auctionEndDate) - Number(currentTime) + 1,
      this.provider.channel.nodeUrl,
    );
  };
  accelerateToSettled = async () => {
    const optionRoundContract = await getOptionRoundContract(
      this.provider,
      this.vaultFacade.vaultContract,
    );
    const currentTime = await getNow(this.provider);
    const optionSettleDate =
      await optionRoundContract.get_option_settlement_date();
    await timeskipNextBlock(
      Number(optionSettleDate) - Number(currentTime),
      this.provider.channel.nodeUrl,
    );
  };
  //@note Only works for katana dev instance with a --dev flag
  startAuctionBystander = async () => {
    await this.accelerateToAuctioning();
    const devAccount = getAccount("dev", this.provider);
    this.vaultFacade.vaultContract.connect(devAccount);
    await this.vaultFacade.vaultContract.start_auction();
    //    const settleDate =
    //      await optionRound.optionRoundContract.get_option_settlement_date();
    //
    //    const startDate =
    //      await optionRound.optionRoundContract.get_auction_start_date();
    //    const twapPeriod = BigInt(60 * 60 * 24 * 14);
    //
    //    const auctionRunTime =
    //      await this.vaultFacade.vaultContract.get_auction_run_time();
    //    const optionRunTime =
    //      await this.vaultFacade.vaultContract.get_option_run_time();
    //    const roundTransitionPeriod =
    //      await this.vaultFacade.vaultContract.get_round_transition_period();
    //
    //    const duration =
    //      BigInt(auctionRunTime) +
    //      BigInt(optionRunTime) +
    //      BigInt(roundTransitionPeriod);
    //    const endDatePeriodA = BigInt(startDate);
    //    const startDatePeriodA = endDatePeriodA - twapPeriod;
    //
    //    const endDatePeriodB = endDatePeriodA - BigInt(roundTransitionPeriod);
    //    const startDatePeriodB = endDatePeriodB - twapPeriod;
    //
    //    console.log("START DATE, SETTLE DATE", startDate, "\n", settleDate);
    //    const optionSettlementDate = parseInt(
    //      (
    //        await optionRound.optionRoundContract.get_option_settlement_date()
    //      ).toString(),
    //    );
    //
    //    const twapRange = 3600 * 24 * 30;
    //    const volatilityRange = 3600 * 24 * 90;
    //    const reservePriceRange = 3600 * 24 * 90;
    //
    //    const job_request: JobRequest = {
    //      identifiers: ["PITCH_LAKE_V1"],
    //      params: {
    //        twap: [
    //          parseInt(optionSettlementDate.toString()) - twapRange,
    //          optionSettlementDate,
    //        ],
    //        volatility: [
    //          optionSettlementDate - volatilityRange,
    //          optionSettlementDate,
    //        ],
    //        reserve_price: [
    //          optionSettlementDate - reservePriceRange,
    //          optionSettlementDate,
    //        ],
    //      },
    //    };
    //
    //    await factRegFacade.setMarketParameters({
    //      devAccount,
    //      job_request,
    //      market_data: marketData,
    //    });
    //
    //    await this.vaultFacade.vaultContract.update_round_params();
  };
  endAuctionBystander = async () => {
    const devAccount = getAccount("dev", this.provider);
    await this.accelerateToRunning();
    await this.vaultFacade.endAuction(devAccount);
  };
  //@note Only works for katana dev instance with a --dev flag
  settleOptionRoundBystander = async (market_data) => {
    console.log("MARKETDATA:", market_data);
    const factRegistryString =
      await this.vaultFacade.vaultContract.get_market_aggregator_address();
    const factRegistryAddress = "0x" + stringToHex(factRegistryString);
    const factRegFacade = new FactRegistryFacade(
      factRegistryAddress,
      this.provider,
    );
    const optionRound = await getOptionRoundFacade(
      this.provider,
      this.vaultFacade.vaultContract,
    );
    // Mock JobRequest
    const optionSettlementDate = parseInt(
      (
        await optionRound.optionRoundContract.get_option_settlement_date()
      ).toString(),
    );
    const twapRange = 3600 * 24 * 30;
    const volatilityRange = 3600 * 24 * 90;
    const reservePriceRange = 3600 * 24 * 90;
    const job_request = {
      identifiers: ["PITCH_LAKE_V1"],
      params: {
        twap: [
          parseInt(optionSettlementDate.toString()) - twapRange,
          optionSettlementDate,
        ],
        volatility: [
          optionSettlementDate - volatilityRange,
          optionSettlementDate,
        ],
        reserve_price: [
          optionSettlementDate - reservePriceRange,
          optionSettlementDate,
        ],
      },
    };
    const devAccount = getAccount("dev", this.provider);
    await factRegFacade.setMarketParameters({
      devAccount,
      job_request,
      market_data,
    });
    await this.accelerateToSettled();
    await this.vaultFacade.settleOptionRound(devAccount, job_request);
  };
  getLiquidityProviderAccounts = (length) => {
    const liquidityProviderAccounts = [];
    for (let i = 0; i < length; i++) {
      liquidityProviderAccounts.push(
        getCustomAccount(
          this.provider,
          liquidityProviders[i].account,
          liquidityProviders[i].privateKey,
        ),
      );
    }
    return liquidityProviderAccounts;
  };
  getOptionBidderAccounts = (length) => {
    const optionBidderAccounts = [];
    for (let i = 0; i < length; i++) {
      optionBidderAccounts.push(
        getCustomAccount(
          this.provider,
          optionBidders[i].account,
          optionBidders[i].privateKey,
        ),
      );
    }
    return optionBidderAccounts;
  };
}
var StoragePoints;
(function (StoragePoints) {
  StoragePoints[(StoragePoints["lpUnlocked"] = 0)] = "lpUnlocked";
  StoragePoints[(StoragePoints["lpLocked"] = 1)] = "lpLocked";
  StoragePoints[(StoragePoints["totalLocked"] = 2)] = "totalLocked";
  StoragePoints[(StoragePoints["totalUnlocked"] = 3)] = "totalUnlocked";
})(StoragePoints || (StoragePoints = {}));
var Methods;
(function (Methods) {})(Methods || (Methods = {}));
