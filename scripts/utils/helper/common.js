const starknet = require("starknet");
const { nodeUrlMapping, accountDetailsMapping } = require("../constants");

function getProvider(environment, port = null) {
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

  const provider = new starknet.RpcProvider({
    nodeUrl: nodeUrl,
  });

  return provider;
}

function getAccount(environment, provider) {
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

function getCustomAccount(provider, accountAddress, privateKey) {
  if (!accountAddress || !privateKey) {
    throw new Error("Invalid or missing account details");
  }

  const account = new starknet.Account(provider, accountAddress, privateKey);

  return account;
}

async function getContract(provider, account, contractAddress) {
  const { abi: contractAbi } = await provider.getClassAt(contractAddress);
  if (contractAbi === undefined) {
    throw new Error("No ABI.");
  }

  const contract = new starknet.Contract(
    contractAbi,
    contractAddress,
    provider
  );

  contract.connect(account);

  return contract;
}

module.exports = {
  getProvider,
  getAccount,
  getContract,
  getCustomAccount,
};
