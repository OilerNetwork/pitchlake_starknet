import ethSierra from "../../../target/dev/pitch_lake_Eth.contract_class.json" assert { type: "json" };
import ethCasm from "../../../target/dev/pitch_lake_Eth.compiled_contract_class.json" assert { type: "json" };
import vaultSierra from "../../../target/dev/pitch_lake_Vault.contract_class.json" assert { type: "json" };
import vaultCasm from "../../../target/dev/pitch_lake_Vault.compiled_contract_class.json" assert { type: "json" };
import optionRoundSieraa from "../../../target/dev/pitch_lake_OptionRound.contract_class.json" assert { type: "json" };
import optionRoundCasm from "../../../target/dev/pitch_lake_OptionRound.compiled_contract_class.json" assert { type: "json" };
import factRegistrySierra from "../../../target/dev/pitch_lake_FactRegistry.contract_class.json" assert { type: "json" };
import factRegistryCasm from "../../../target/dev/pitch_lake_FactRegistry.compiled_contract_class.json" assert { type: "json" };
async function declareContract(account, sierra, casm, placeholder) {
    try {
        const declareResult = await account.declare({
            contract: sierra,
            casm: casm,
        });
        console.log(`Declare result for ${placeholder}: `, declareResult);
        return declareResult.class_hash;
    }
    catch (err) {
        console.log(`Contract ${placeholder} is already declared`, err);
    }
}
async function declareContracts(account) {
    let ethHash = await declareContract(account, ethSierra, ethCasm, "eth");
    if (!ethHash) {
        throw Error("Eth Deploy Failed");
    }
    let vaultHash = await declareContract(account, vaultSierra, vaultCasm, "vault");
    if (!vaultHash) {
        throw Error("Vault Deploy Failed");
    }
    let optionRoundHash = await declareContract(account, optionRoundSieraa, optionRoundCasm, "optionRound");
    if (!optionRoundHash) {
        throw Error("OptionRound Deploy Failed");
    }
    let factRegistryHash = await declareContract(account, factRegistrySierra, factRegistryCasm, "factRegistry");
    if (!factRegistryHash) {
        throw Error("FactRegistry Deploy Failed");
    }
    return {
        ethHash,
        vaultHash,
        optionRoundHash,
        factRegistryHash,
    };
}
export { declareContract, declareContracts };
