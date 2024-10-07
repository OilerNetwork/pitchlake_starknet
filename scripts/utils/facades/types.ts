import { Account } from "starknet";

// Fossil

export type JobRequest = {
  identifiers: string[];
  params: {
    twap: [number, number];
    volatility: [number, number];
    reserve_price: [number, number];
  };
};

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
  amount: number | bigint;
};

export type WithdrawArgs = {
  account: Account;
  amount: number | bigint;
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

export type RefundableBidsArgs = {
  optionBuyer: string;
};

export type PayoutBalanceArgs = {
  optionBuyer: string;
};

export type OptionBalanceArgs = {
  optionBuyer: Account;
};

export type TokenizableOptionsArgs = {
  optionBuyer: string;
};

export type RefundUnusedBidsArgs = {
  from: Account;
  optionBidder: string;
};

export type ExerciseOptionArgs = {
  from: Account;
};

export type TokenizeOptionArgs = {
  from: Account;
};

export type Bid = {
  id: string | number | bigint;
  nonce: number | bigint;
  owner: string;
  amount: number | bigint;
  price: number | bigint;
};

//Smoke Test types

export type Constants = {
  depositAmount: number | bigint;
  reservePrice: number | bigint;
  settlementPrice: number | bigint;
  strikePrice: number | bigint;
  capLevel: number | bigint;
  volatility: number | bigint;
};

//Simulation Types
export type MarketData = {
  settlementPrice: number | bigint;
  volatility: number | bigint;
  reservePrice: number | bigint;
  strikePrice?: number | bigint;
  capLevel?: number | bigint;
  startTime?: number | bigint;
  endTime?: number | bigint;
};
