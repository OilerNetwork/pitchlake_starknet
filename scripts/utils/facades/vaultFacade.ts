import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { optionRoundAbi, vaultAbi } from "../../abi";
import { DepositArgs, WithdrawArgs } from "./types";
import { getAccount } from "../helpers/common";
import { getNow, setAndMineNextBlock } from "../katana";

export class VaultFacade {
  vaultContract: TypedContractV2<typeof vaultAbi>;

  constructor(vaultContract: TypedContractV2<typeof vaultAbi>) {
    this.vaultContract = vaultContract;
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
        console.log("1")
      const devAccount = getAccount("dev", provider);
      console.log("2")
      const optionRoundId = await this.vaultContract.current_option_round_id();
      console.log("3")
      const optionRoundAddress =
        await this.vaultContract.get_option_round_address(optionRoundId);
        console.log("4",("0x"+optionRoundAddress.toString(16)));
      
      const optionRoundContract = new Contract(
        optionRoundAbi,
        optionRoundAddress,
        provider
      ).typedv2(optionRoundAbi);

      console.log("5")
      const currentTime = await getNow(provider);
      const auctionStartDate =
        await optionRoundContract.get_auction_start_date();

        console.log("6")
      await setAndMineNextBlock(
        Number(auctionStartDate) - Number(currentTime),
        provider.channel.nodeUrl
      );
      console.log("7");
      this.vaultContract.connect(devAccount);
      console.log("8");
      await this.vaultContract.start_auction();
    } catch (err) {
      console.log("ERROR IS HERE YES");
    }
  }
}
