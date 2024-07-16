// constants.js

import { config } from "dotenv";

type AccountDetailsType = {
  accountAddress: string | undefined;
  privateKey: string | undefined;
  ethAddress?: string;
};
type EthConstructorArgs = {
  supplyValueLow: number;
  supplyValueHigh: number;
  recipientContractAddress: string;
};

type VaultConstructorArgs = {
  vaultManager: string;
  ethContract: string;
  marketAggregatorContract: string;
};

type ConstructorArgs = {
  eth: EthConstructorArgs;
  vault: VaultConstructorArgs;
  optionRound: string;
  marketAggregator: string;
};

export const nodeUrlMapping: { [key: string]: string } = {
  production: "",
  staging: "",
  dev: "http://localhost",
};

const constructorArgs: { [key: string]: ConstructorArgs } = {
  dev: {
    eth: {
      supplyValueLow: 1,
      supplyValueHigh: 0,
      recipientContractAddress:
        "0x4d75495e10ee26cae76478b6e491646ff0a10e0a062db1555131e47b07b7d24",
    },
    vault: {
      vaultManager:
        "0x4d75495e10ee26cae76478b6e491646ff0a10e0a062db1555131e47b07b7d24",
      ethContract:
        "0x1c839470058b5864ffb47d975881ca2fefcd963c7473bead870ab24c9752ad8",
      marketAggregatorContract:
        "0x3dfacc4ae87e3b36fad25dd9e1bbc11ebc58210fadfa44dce06d9a694bfac5e",
    },
    optionRound: "",
    marketAggregator: "",
  },
};
export const accountDetailsMapping: { [key: string]: AccountDetailsType } = {
  production: {
    accountAddress: process.env.PRODUCTION_ACCOUNT_ADDRESS,
    privateKey: process.env.PRODUCTION_PRIVATE_KEY,
    ethAddress: "PRODUCTION_ETH_ADDRESS",
  },
  staging: {
    accountAddress: process.env.STAGING_ACCOUNT_ADDRESS,
    privateKey: process.env.STAGING_PRIVATE_KEY,
    ethAddress: "STAGING_ETH_ADDRESS",
  },
  dev: {
    accountAddress:
      "0x4d75495e10ee26cae76478b6e491646ff0a10e0a062db1555131e47b07b7d24",
    privateKey:
      "0x100801800000000310080180000000010030000000000005106801800206800",
  },
};

let declaredContractsMapping = {
  production: {},
  staging: {},
  dev: {},
};

export { declaredContractsMapping, constructorArgs };
