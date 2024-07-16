import { Account, Provider, RpcProvider } from "starknet";

import { nodeUrlMapping, accountDetailsMapping } from "./constants";
function getProvider(environment: string, port: string | null) {
  const nodeUrl = nodeUrlMapping[environment] + `${port ? ":port" : ""}`;

  if (environment === "dev" && port === null) {
    throw new Error("Port must be provided for dev environment");
  }

  if (!nodeUrl) {
    throw new Error("Invalid environment");
  }

  const provider: RpcProvider = new RpcProvider({
    nodeUrl: nodeUrl,
  });

  return provider;
}

function getAccount(environment: any, provider: Provider) {
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

  const account = new Account(
    provider,
    accountDetails.accountAddress,
    accountDetails.privateKey
  );

  return account;
}

export { getProvider, getAccount };
