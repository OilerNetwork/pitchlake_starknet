import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { optionRoundAbi, vaultAbi } from "../../abi";
import { DepositArgs, WithdrawArgs } from "./types";
import { getAccount, stringToHex } from "../helpers/common";
import { getNow, setAndMineNextBlock } from "../katana";
import { accelerateToAuctioning } from "../helpers/accelerators";

export class VaultFacade {
  vaultContract: TypedContractV2<typeof vaultAbi>;

  constructor(vaultContract: TypedContractV2<typeof vaultAbi>) {
    this.vaultContract = vaultContract;
  }

  async getTotalLocked() {
    try {
      const res = await this.vaultContract.get_total_locked_balance();
      return res;
    } catch (err) {
      console.log(err);
    }
  }

  async getTotalUnLocked() {
    try {
      const res = await this.vaultContract.get_total_unlocked_balance();
      return res;
    } catch (err) {
      console.log(err);
    }
  }
  async getLPLockedBalance(address: string) {
    try {
      const res = await this.vaultContract.get_lp_locked_balance(address);
      return res;
    } catch (err) {
      console.log(err);
    }
  }
  async getLPUnlockedBalance(address: string) {
    try {
      const res = await this.vaultContract.get_lp_unlocked_balance(address);
      return res;
    } catch (err) {
      console.log(err);
    }
  }

  async withdraw({ account, amount }: WithdrawArgs) {
    this.vaultContract.connect(account);
    try {
      await this.vaultContract.withdraw_liquidity(amount);
    } catch (err) {
      console.log(err);
    }
  }

  async deposit({ from, beneficiary, amount }: DepositArgs) {
    this.vaultContract.connect(from);
    try {
      await this.vaultContract.deposit_liquidity(amount, beneficiary);
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
    try {
      const devAccount = getAccount("dev", provider);
      await accelerateToAuctioning(provider, this.vaultContract);
      this.vaultContract.connect(devAccount);

      await this.vaultContract.start_auction();
    } catch (err) {
      console.log("ERROR IS HERE YES", err);
    }
  }
}
