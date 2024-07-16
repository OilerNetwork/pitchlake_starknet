import { Account, Contract, Provider, RpcProvider } from "starknet";
import { nodeUrlMapping, accountDetailsMapping } from "../constants";

function getProvider(environment: string, port?: string) {
  const nodeUrl = nodeUrlMapping[environment] + `${port ? `:${port}` : ""}`;

  if (environment === "dev" && port === null) {
    throw new Error("Port must be provided for dev environment");
  }

  if (!nodeUrl) {
    throw new Error("Invalid environment");
  }

  const provider = new RpcProvider({
    nodeUrl: nodeUrl,
  });

  return provider;
}

function getAccount(environment: string, provider: Provider) {
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

function getCustomAccount(
  provider: Provider,
  accountAddress: string,
  privateKey: string
) {
  if (!accountAddress || !privateKey) {
    throw new Error("Invalid or missing account details");
  }

  const account = new Account(provider, accountAddress, privateKey);

  return account;
}

async function getContract(
  provider: Provider,
  account: Account,
  contractAddress: string
) {
  const { abi: contractAbi } = await provider.getClassAt(contractAddress);
  if (contractAbi === undefined) {
    throw new Error("No ABI.");
  }

  const contract = new Contract(contractAbi, contractAddress, provider);

  contract.connect(account);

  return contract;
}

export { getProvider, getAccount, getContract, getCustomAccount };
