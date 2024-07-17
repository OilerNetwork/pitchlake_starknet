import { Account } from "starknet";

//EthTypes
export type ApprovalArgs = {
  owner: Account;
  amount: number;
  spender: string;
};

//VaultTypes

export type DepositArgs = {
    from: Account;
    beneficiary: string;
    amount: number;
  };
  
  export type WithdrawArgs = {
    account: Account;
    amount: number;
  };
  
//OptionRoundTypes
export type PlaceBidArgs = {
  from: Account;
  beneficiary: string;
  amount: number;
  price: number;
};
export type UpdateBidArgs = {
  bidId: string;
  from: Account;
  amount: number;
  price: number;
};
