import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { optionRoundAbi, vaultAbi } from "../../abi";
import { DepositArgs, WithdrawArgs } from "./types";
import { getAccount } from "../helpers/common";
import { getNow, setAndMineNextBlock } from "../katana";

class VaultFacade {
    vaultContract:TypedContractV2<typeof vaultAbi>;
  
    constructor(vaultContract:TypedContractV2<typeof vaultAbi>){
      this.vaultContract=vaultContract
  
    }
    async getLPUnlockedBalance(
        address: string,
      ){
        try {
          const res = await this.vaultContract.get_lp_unlocked_balance(address);
          return res;
        } catch (err) {
          console.log(err);
        }
      };
      
    async withdraw (
        { account, amount }: WithdrawArgs,
      )  {
        this.vaultContract.connect(account);
        try {
          await this.vaultContract.withdraw_liquidity(amount);
        } catch (err) {
          console.log(err);
        }
      };
      
    async deposit (
        { from, beneficiary, amount }: DepositArgs,
      ) {
        this.vaultContract.connect(from);
        try {
          await this.vaultContract.deposit_liquidity(amount, beneficiary);
        } catch (err) {
          console.log(err);
        }
      };
      
    async depositAll (
        depositData: Array<DepositArgs>,
      ){
        for (const args of depositData) {
            await this.deposit(args);
        }
      };
      
    async withdrawAll (
        withdrawData: Array<WithdrawArgs>,
        vaultContract: TypedContractV2<typeof vaultAbi>
      ){
      
        for (const data of withdrawData){
          vaultContract.connect(data.account);
          try {
            await vaultContract.withdraw_liquidity(data.amount);
          } catch (err) {
            console.log(err);
          }
        }
      };
      
      
      
      //State Transitions
    async startAuction (
        account:Account,
      ){
        this.vaultContract.connect(account);
        await this.vaultContract.start_auction();
      }
      
      
      //@note Only works for katana dev instance with a --dev flag
    async startAuctionBystander(
        provider:Provider,
      ){
        const devAccount = getAccount("dev",provider); 
        const optionRoundId = await this.vaultContract.current_option_round_id();
        const optionRoundAddress=await this.vaultContract.get_option_round_address(optionRoundId);
        const optionRoundContract = new Contract(optionRoundAbi,optionRoundAddress,provider).typedv2(optionRoundAbi);
        
        const currentTime =await getNow(provider);
        const auctionStartDate = await optionRoundContract.get_auction_start_date();
        
        await setAndMineNextBlock(Number(auctionStartDate)-Number(currentTime),provider.channel.nodeUrl);
        this.vaultContract.connect(devAccount);
        await this.vaultContract.start_auction();
      }
  }