// deployContracts.js
import { CallData, CairoCustomEnum } from "starknet";
import vaultSierra from "../../../target/dev/pitch_lake_starknet_Vault.contract_class.json" assert { type: "json" };
import { constructorArgs } from "../constants";
async function deployEthContract(enviornment, account, classHash) {
    let constructorArgsEth = [...Object.values(constructorArgs[enviornment].eth)];
    const deployResult = await account.deploy({
        classHash,
        constructorCalldata: constructorArgsEth,
    });
    console.log("ETH contract is deployed successfully at - ", deployResult);
    return deployResult.contract_address[0];
}
async function deployVaultContract(enviornment, account, contractAddresses, hashes) {
    const contractCallData = new CallData(vaultSierra.abi);
    let constants = constructorArgs[enviornment].vault;
    const constructorCalldata = contractCallData.compile("constructor", {
        round_transition_period: constants.roundTransitionPeriod,
        auction_run_time: constants.auctionRunTime,
        option_run_time: constants.optionRunTime,
        eth_address: contractAddresses.ethContract,
        vault_manager: contractAddresses.vaultManager,
        vault_type: new CairoCustomEnum({ InTheMoney: {} }),
        market_aggregator: contractAddresses.marketAggregatorContract,
        option_round_class_hash: hashes.optionRound,
    });
    const deployResult = await account.deploy({
        classHash: hashes.vault,
        constructorCalldata: constructorCalldata,
    });
    console.log("Vault contract is deployed successfully at - ", deployResult);
    return deployResult.contract_address[0];
}
async function deployMarketAggregator(enviornment, account, marketAggregatorClassHash) {
    const deployResult = await account.deploy({
        classHash: marketAggregatorClassHash,
    });
    console.log("Market Aggregator contract is deployed successfully at - ", deployResult);
    return deployResult.contract_address[0];
}
async function deployContracts(enviornment, account, hashes) {
    let ethAddress = await deployEthContract(enviornment, account, hashes.ethHash);
    if (!ethAddress) {
        throw Error("Eth deploy failed");
    }
    let marketAggregatorAddress = await deployMarketAggregator(enviornment, account, hashes.marketAggregatorHash);
    if (!marketAggregatorAddress) {
        throw Error("MktAgg deploy failed");
    }
    let vaultAddress = await deployVaultContract(enviornment, account, {
        marketAggregatorContract: marketAggregatorAddress,
        ethContract: ethAddress,
        vaultManager: account.address,
    }, { optionRound: hashes.optionRoundHash, vault: hashes.vaultHash });
    if (!vaultAddress) {
        throw Error("Eth deploy failed");
    }
    return {
        ethAddress,
        marketAggregatorAddress,
        vaultAddress,
    };
}
export { deployEthContract, deployMarketAggregator, deployVaultContract, deployContracts, };
