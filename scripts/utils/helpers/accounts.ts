import { Account, Provider } from "starknet";
import { liquidityProviders, optionBidders } from "../constants";
import { getCustomAccount } from "./common";

export const getLiquidityProviderAccounts = (
  provider: Provider,
  length: number
) => {
  const liquidityProviderAccounts: Array<Account> = [];
  for (let i = 0; i < length; i++) {
    liquidityProviderAccounts.push(
      getCustomAccount(
        provider,
        liquidityProviders[i].account,
        liquidityProviders[i].privateKey
      )
    );
  }
  return liquidityProviderAccounts;
};

export const getOptionBidderAccounts = (provider: Provider, length: number) => {
  const optionBidderAccounts: Array<Account> = [];
  for (let i = 0; i < length; i++) {
    optionBidderAccounts.push(
      getCustomAccount(
        provider,
        optionBidders[i].account,
        optionBidders[i].privateKey
      )
    );
  }
  return optionBidderAccounts;
};
