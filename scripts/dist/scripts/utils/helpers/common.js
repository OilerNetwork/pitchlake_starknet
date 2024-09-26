import { Account, CairoUint256, Contract, RpcProvider } from "starknet";
import { nodeUrlMapping, accountDetailsMapping } from "../constants";
function getProvider(environment, port) {
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
function getAccount(environment, provider) {
    const accountDetails = accountDetailsMapping[environment];
    if (!accountDetails ||
        !accountDetails.accountAddress ||
        !accountDetails.privateKey) {
        throw new Error("Invalid environment or missing account details in environment variables");
    }
    const account = new Account(provider, accountDetails.accountAddress, accountDetails.privateKey);
    return account;
}
function getCustomAccount(provider, accountAddress, privateKey) {
    if (!accountAddress || !privateKey) {
        throw new Error("Invalid or missing account details");
    }
    const account = new Account(provider, accountAddress, privateKey);
    return account;
}
async function getContract(provider, account, contractAddress) {
    const { abi: contractAbi } = await provider.getClassAt(contractAddress);
    if (contractAbi === undefined) {
        throw new Error("No ABI.");
    }
    const contract = new Contract(contractAbi, contractAddress, provider);
    contract.connect(account);
    return contract;
}
function stringToHex(decimalString) {
    decimalString = String(decimalString);
    const num = BigInt(decimalString);
    return num.toString(16);
}
function convertToBigInt(quantity) {
    if (typeof quantity !== "bigint" && typeof quantity !== "number") {
        const res = new CairoUint256(quantity);
        quantity = res.toBigInt();
    }
    return quantity;
}
export { getProvider, getAccount, getContract, getCustomAccount, stringToHex, convertToBigInt };
