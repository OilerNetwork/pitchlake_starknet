// constants.js

require("dotenv").config();

const nodeUrlMapping = {
  production: "",
  staging: "",
  dev: (port) => `http://localhost:${port}`,
};

const accountDetailsMapping = {
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

module.exports = {
  nodeUrlMapping,
  accountDetailsMapping,
  declaredContractsMapping,
};
