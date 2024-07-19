import {
  Account,
  CairoUint256,
  Contract,
  Provider,
  TypedContractV2,
} from "starknet";
import { vaultABI } from "../../abi";
import { DepositArgs, WithdrawArgs } from "./types";
import {
  accelerateToAuctioning,
  accelerateToRunning,
  accelerateToSettled,
} from "../helpers/accelerators";

export class VaultFacade {
  vaultContract: TypedContractV2<typeof vaultABI>;

  constructor(vaultAddress: string, provider: Provider) {
    this.vaultContract = new Contract(vaultABI, vaultAddress, provider).typedv2(
      vaultABI
    );
  }

  async getTotalLocked() {
    const res = await this.vaultContract.get_total_locked_balance();
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    }
    return res;
  }

  async getTotalUnLocked() {
    const res = await this.vaultContract.get_total_unlocked_balance();
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    }
    return res;
  }

  async getLPLockedBalance(address: string) {
    const res = await this.vaultContract.get_lp_locked_balance(address);
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    }
    return res;
  }
  async getLPLockedBalanceAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.getLPLockedBalance(account.address);
        return res;
      })
    );
    return balances;
  }

  async getLPUnlockedBalance(address: string) {
    const res = await this.vaultContract.get_lp_unlocked_balance(address);
    if (typeof res !== "bigint" && typeof res !== "number") {
      const data = new CairoUint256(res);
      return data.toBigInt();
    }
    return res;
  }

  async getLPUnlockedBalanceAll(accounts: Array<Account>) {
    const balances = await Promise.all(
      accounts.map(async (account: Account) => {
        const res = await this.getLPUnlockedBalance(account.address);
        return res;
      })
    );
    return balances;
  }
  async withdraw({ account, amount }: WithdrawArgs) {
    this.vaultContract.connect(account);
      await this.vaultContract.withdraw_liquidity(amount);
  }

  async deposit({ from, beneficiary, amount }: DepositArgs) {
    this.vaultContract.connect(from);
    try {
      const data = await this.vaultContract.deposit_liquidity(
        amount,
        beneficiary
      );
      data;
    } catch (err) {
      console.log(err);
    }
  }

  async depositAll(depositData: Array<DepositArgs>) {
    for (const depositArgs of depositData) {
      await this.deposit(depositArgs);
    }
  }

  async withdrawAll(withdrawData: Array<WithdrawArgs>) {
    for (const withdrawArgs of withdrawData) {
      await this.withdraw(withdrawArgs);
    }
  }

  //State Transitions
  async startAuction(account: Account) {
    this.vaultContract.connect(account);
    await this.vaultContract.start_auction();
  }

  //@note Only works for katana dev instance with a --dev flag
  async startAuctionBystander(provider: Provider) {
    await accelerateToAuctioning(provider, this.vaultContract);
  }


  async endAuction(account: Account) {
    this.vaultContract.connect(account);
    const res = await this.vaultContract.end_auction();
  }

  async endAuctionBystander(provider: Provider) {
    await accelerateToRunning(provider, this.vaultContract);
  }

  async settleAuction(account:Account){
    this.vaultContract.connect(account);
  }

  async settleAuctionBystander(provider:Provider){
    await accelerateToSettled(provider,this.vaultContract)
  }
}

