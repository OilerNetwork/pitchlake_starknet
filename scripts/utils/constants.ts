// constants.js

import { config } from "dotenv";
import { cairo, Uint256 } from "starknet";

type AccountDetailsType = {
  accountAddress: string | undefined;
  privateKey: string | undefined;
  ethAddress?: string;
};
type EthConstructorArgs = {
  supply: Uint256;
  recipientContractAddress: string;
};

type VaultConstructorArgs = {
  roundTransitionPeriod:string;
  auctionRunTime:string;
  optionRunTime:string;
};

type ConstructorArgs = {
  eth: EthConstructorArgs;
  vault: VaultConstructorArgs;
  optionRound: string;
  marketAggregator: string;
};
const nodeUrlMapping: { [key: string]: string } = {
  production: "",
  staging: "",
  dev: `http://localhost`,
};

const constructorArgs: { [key: string]: ConstructorArgs } = {
  dev: {
    eth: {
      supply:  cairo.uint256(1e32),
      recipientContractAddress:
        "0x7ce7089cb75a590b9485f6851d8998fa885494cc7a70dbae8f3db572586b8a8",
    },
    vault: {
      roundTransitionPeriod: "0x30",
      auctionRunTime: "0x22",
      optionRunTime: "0x3",
    },
    optionRound: "",
    marketAggregator: "",
  },
};
const accountDetailsMapping: { [key: string]: AccountDetailsType } = {
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
      "0x7ce7089cb75a590b9485f6851d8998fa885494cc7a70dbae8f3db572586b8a8",
    privateKey:
      "0x74dfaa5aee853a8eb8033a31fa71e41c92d65a0abed9adc686bea9d28e2aed2",
  },
};

const liquidityProviders = [
  {
    account: "0x55df044c093d7b2408f6ad897f6d71a996afab8e1b17932e9c6438cb99593f",
    privateKey:
      "0x33b46925f150922d9d459a4b29bd730db2106009bcde7030bca0c3762b67e0a",
  },
  {
    account: "0xdf31182cb5970fb2c2307bffa9efe43cfbe236ba55798be43f93e03c4ce8e8",
    privateKey:
      "0x1ff4988a92b4fe18c70ff0d36ec8a84ae6b8980b436ede71d4735aac2142ce1",
  },
  {
    account:
      "0x14378f698a983f485552f8c6e645322cf6b54b605a7c274348c76f2a62967cd",
    privateKey:
      "0x7e5c19e2beed021063f11e2b9fb30a13e2c3295ad77c2edd107da9dae415d8",
  },
  {
    account:
      "0x19c2021c2f95585dd079c6fea41e15fd6a92949054d0f56fc31e404558b3e3b",
    privateKey:
      "0x381a747c5946b0d52ebe9fa9e90f8592c0fd37a1552bc7dea6bbc9409ffdbd6",
  },
  {
    account:
      "0x21c3596839d203b6ea83c7e7197a1640343b8111c7ce017767265ce0dbd2d88",
    privateKey:
      "0x31cc6964f0fef400ceb51f9c82ba8a03a502d722be52d9e1ba2ec327f997327",
  },
  {
    account:
      "0x227bd40428ec6524d7431d53f7fb7e8b71b2d31fc08c87af6b1a9c1e2a77f22",
    privateKey:
      "0xc90555ebd3c579f47e170426363830b7f07aa30fe2b69e4c11e080e9aadd7",
  },
  {
    account:
      "0x2be5a46e87d3882f242dd06e9dab68adca7b5cf18eee96ab21da39ecc5a61c6",
    privateKey:
      "0x1b087397797b3cca4fd190e3c7d9029faedc71a57f1fbcac38da54af603ad47",
  },
  {
    account:
      "0x34c28bf49ac34bbb688e24b22bc25f63d3323a3d2ee78dced10a0e9b0a8ec13",
    privateKey:
      "0x6c375c58c237617ca994ac0e348f9a6f69a27f584f534197add860ece9808ad",
  },
  {
    account:
      "0x3b4022611857234b93f9eb5e0ff4728bdc7390f9bf1446d96b5f05679a0d4f3",
    privateKey:
      "0x4ceb7dd0adbf5139450e0cae092b54399c3e3d290195cb8b30ac19d6640ce8b",
  },
  {
    account:
      "0x4087745e395c247d305bed3af8c0be84a103d25c78f00f65d1a6369c63adb6f",
    privateKey:
      "0x5e4eab06ea2fc5f4d98a563c573b67e624e212575bc716e44fb4acf7f2555ea",
  },
];

const optionBidders = [
  {
    account:
      "0x430861531f7d3536e3c3b77abda9b83d7b4d3e1ddc525583a58c0d528fe2a0b",
    privateKey:
      "0x6e0911b16ae7583510ed4fb417425654762cb7eb36a29d424d156f2a2d1932e",
  },
  {
    account:
      "0x4798b763f1ae27b565da46e3b37db08095437de92db9ca33a0eb739f3abaf12",
    privateKey:
      "0x13480410380180071a000490360f606518900fddf60f213a9649e6b7eb4b78b",
  },
  {
    account:
      "0x4d72d82b12efdceb0516af7cede2aa95e23d17eadfe2462ebc57d466b665c06",
    privateKey:
      "0x402d805dd21e044b0168cd341d32aacbdf11a8e1038e559fce467f8b749caf3",
  },
  {
    account:
      "0x4d75495e10ee26cae76478b6e491646ff0a10e0a062db1555131e47b07b7d24",
    privateKey:
      "0x100801800000000310080180000000010030000000000005106801800206800",
  },
  {
    account:
      "0x4ec7e8ce634b297c8d04ae0fb2ac49eb8151c04b2ca8e3be0f0341b01e4dac0",
    privateKey:
      "0x13cab974c6b681790b669f48b24f18d7ddfd9bc1cba5bef5a44c583b3eea57d",
  },
  {
    account:
      "0x4f6b7ea31871dc220a7b5db702b094362beae1b68cf38bb179a83a89073fbd1",
    privateKey:
      "0x66b06dd599390080d61b680aaa4c8b981a3659547dcf5e3cf7f3141c7864947",
  },
  {
    account:
      "0x50b92a5d75d89087e9d8b60eb3c67a571d543ddfdaac5a0053ba7be26a910e9",
    privateKey:
      "0x4a499bebbc6d9f4c1318becc9ed941de4cc23b06706372bd1a68bb7dc10eaaa",
  },
  {
    account:
      "0x54ad5b2d856fc356e7509ba9f0a60b7e5aa7b8143f35144f757c5aef74ed780",
    privateKey:
      "0x5f62f386261ba7f87c28dbf2c1bef150080d1bd2e6c9dc9af043865e23bd1ac",
  },
  {
    account:
      "0x58a65d5fc02f15b02a415e45150b5df47ddb31094b848732e9cab4efe6e5c3a",
    privateKey:
      "0x1813b15096512db81553fc50b428d2cd436e3e4ce1c70a017ec9f18b2596029",
  },
  {
    account:
      "0x5a4ca27c7aba179075ef36586beeda4d7c5a326be6990f573639211f4f20763",
    privateKey:
      "0x157f485d0415f0f6b9500118684a1ae060b903448a37df81d1a52e0c6fff57e",
  },
];

const extras = [
  {
    account:
      "0x5ab6259fccae957ce89be7e08c32d0b9ea5e2382da49c5bea57d33ee9eac379",
    privateKey:
      "0xba3da1bf52a938b65196eeea873596bd90e893cbc2b18c777a432de08aba58",
  },
  {
    account:
      "0x6eea757999bebad427b0934c16dde89ef55fbb040094c48d792db3b71006523",
    privateKey:
      "0x36048b7b1ba18597af8d1e5738d486cb98a0e0a0872f2d8fe00058c9b491376",
  },
  {
    account:
      "0x7886105c0bd55d4bd38b3b227b4c6ef9ca5751c4bdf32c0277456a02282b79a",
    privateKey:
      "0x26a2bd3465580814a280f3bd688c01cdcc7f37a8b01362dc66b9f5d689e6cb8",
  },
  {
    account:
      "0x7cd5acf17d2fbd26519ea338c88791dcf6c7fc76980f514a7e89050ecb13fab",
    privateKey:
      "0x785692961d914c1bd77c41f9ed90993f284935b59c52ec74c468ead1f7eb5c2",
  },
];

let declaredContractsMapping = {
  production: {},
  staging: {},
  dev: {},
};

export {
  nodeUrlMapping,
  constructorArgs,
  accountDetailsMapping,
  declaredContractsMapping,
  liquidityProviders,
  optionBidders,
  extras,
};
