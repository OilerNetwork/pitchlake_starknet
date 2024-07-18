import { Account } from "starknet";

//EthTypes
export type ApprovalArgs = {
  owner: Account;
  amount: number | bigint;
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
  amount: number | bigint;
  price: number | bigint;
};
export type UpdateBidArgs = {
  bidId: string;
  from: Account;
  amount: number;
  price: number;
};

//Smoke Test types

export type Constants = {
  depositAmount: number;
};

export type Bid = {
  id: string | number | bigint;
  nonce: number | bigint;
  owner: string;
  amount: number | bigint ;
  price: number | bigint ;
  isTokenized: boolean;
  isRefunded: boolean;
};
