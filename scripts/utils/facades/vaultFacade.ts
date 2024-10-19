import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { optionRoundABI, vaultABI } from "../../abi";
import { JobRequest, DepositArgs, MarketData, WithdrawArgs } from "./types";
import { convertToBigInt, getAccount, stringToHex } from "../helpers/common";
import { getOptionRoundContract } from "../helpers/setup";

export class VaultFacade {
  vaultContract: TypedContractV2<typeof vaultABI>;
  currentOptionRound?: TypedContractV2<typeof optionRoundABI>;

  constructor(
    vaultAddress: string,
    provider: Provider,
    optionRoundAddress?: string,
  ) {
    this.vaultContract = new Contract(vaultABI, vaultAddress, provider).typedv2(
      vaultABI,
    );
    if (optionRoundAddress)
      this.currentOptionRound = new Contract(
        optionRoundABI,
        optionRoundAddress,
        provider,
      ).typedv2(optionRoundABI);
  }

  async getTotalLocked() {
    const res = await this.vaultContract.get_vault_locked_balance();
    return convertToBigInt(res);
  }

  async getTotalUnLocked() {
    const res = await this.vaultContract.get_vault_unlocked_balance();
    return convertToBigInt(res);
  }

  async getLPLockedBalance(address: string) {
    const res = await this.vaultContract.get_account_locked_balance(address);
    return convertToBigInt(res);
  }

  async getLPUnlockedBalance(address: string) {
    const res = await this.vaultContract.get_account_unlocked_balance(address);
    return convertToBigInt(res);
  }

  async withdraw({ account, amount }: WithdrawArgs) {
    this.vaultContract.connect(account);
    await this.vaultContract.withdraw(amount);
  }

  async deposit({ from, beneficiary, amount }: DepositArgs) {
    this.vaultContract.connect(from);
    try {
      const data = await this.vaultContract.deposit(amount, beneficiary);
      data;
    } catch (err) {
      console.log(err);
    }
  }

  //State Transitions
  async startAuction(account: Account) {
    this.vaultContract.connect(account);
    await this.vaultContract.start_auction();
  }

  async endAuction(account: Account) {
    this.vaultContract.connect(account);
    await this.vaultContract.end_auction();
  }

  async settleOptionRound(account: Account, job_request: JobRequest) {
    this.vaultContract.connect(account);
    await this.vaultContract.settle_round(job_request);
  }
}
