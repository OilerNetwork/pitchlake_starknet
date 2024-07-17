import { Account, Contract, provider, Provider, TypedContractV2 } from "starknet";
import { vaultAbi,optionRoundAbi } from "../../abi";
import { DepositArgs, WithdrawArgs } from "./types";
import { getNow, setAndMineNextBlock } from "../katana";
import { getAccount } from "../helpers/common";

class VaultFacade {
  vaultContract?:TypedContractV2<typeof vaultAbi>;

  constructor(vaultContract?:TypedContractV2<typeof vaultAbi>){
    this.vaultContract=vaultContract

  }
}
export const getLPUnlockedBalance = async (
  address: string,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  try {
    const res = await vaultContract.get_lp_unlocked_balance(address);
    return res;
  } catch (err) {
    console.log(err);
  }
};

export const withdraw = async (
  { account, amount }: WithdrawArgs,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  vaultContract.connect(account);
  try {
    await vaultContract.withdraw_liquidity(amount);
  } catch (err) {
    console.log(err);
  }
};

export const deposit = async (
  { from, beneficiary, amount }: DepositArgs,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  vaultContract.connect(from);
  try {
    await vaultContract.deposit_liquidity(amount, beneficiary);
  } catch (err) {
    console.log(err);
  }
};

export const depositAll = async (
  depositData: Array<DepositArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {
  for (const args of depositData) {
      await deposit(args,vaultContract);
  }
};

export const withdrawAll = async (
  withdrawData: Array<WithdrawArgs>,
  vaultContract: TypedContractV2<typeof vaultAbi>
) => {

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
export const startAuction = async (
  account:Account,
  vaultContract:TypedContractV2<typeof vaultAbi>
)=>{
  vaultContract.connect(account);
  await vaultContract.start_auction();
}


//@note Only works for katana dev instance with a --dev flag
export const startAuctionBystander = async (
  provider:Provider,
  vaultContract:TypedContractV2<typeof vaultAbi>
)=>{
  const devAccount = getAccount("dev",provider); 
  const optionRoundId = await vaultContract.current_option_round_id();
  const optionRoundAddress=await vaultContract.get_option_round_address(optionRoundId);
  const optionRoundContract = new Contract(optionRoundAbi,optionRoundAddress,provider).typedv2(optionRoundAbi);
  
  const currentTime =await getNow(provider);
  const auctionStartDate = await optionRoundContract.get_auction_start_date();
  
  await setAndMineNextBlock(Number(auctionStartDate)-Number(currentTime),provider.channel.nodeUrl);
  vaultContract.connect(devAccount);
  await vaultContract.start_auction();
}