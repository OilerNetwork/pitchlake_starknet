import { Provider, RpcProvider } from "starknet";

const starknet = require("starknet");
const { nodeUrlMapping, accountDetailsMapping } = require("./constants");
function getProvider(environment:any, port:string|null) {
  const nodeUrl =
    environment === "dev"
      ? nodeUrlMapping[environment](port)
      : nodeUrlMapping[environment];

  if (environment === "dev" && port === null) {
    throw new Error("Port must be provided for dev environment");
  }

  if (!nodeUrl) {
    throw new Error("Invalid environment");
  }

  const provider:RpcProvider = new starknet.RpcProvider({
    nodeUrl: nodeUrl,
  });

  return provider;
}

function getAccount(environment:any, provider:Provider) {
  const accountDetails = accountDetailsMapping[environment];

  if (
    !accountDetails ||
    !accountDetails.accountAddress ||
    !accountDetails.privateKey
  ) {
    throw new Error(
      "Invalid environment or missing account details in environment variables"
    );
  }

  const account = new starknet.Account(
    provider,
    accountDetails.accountAddress,
    accountDetails.privateKey
  );

  return account;
}

export {
  getProvider,
  getAccount,
};
