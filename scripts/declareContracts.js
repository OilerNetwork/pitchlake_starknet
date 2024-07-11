const fs = require("fs");
const path = require("path");
const ethSierra = require("../target/dev/pitch_lake_starknet_Eth.contract_class.json");
const ethCasm = require("../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json");
const vaultSierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");
const vaultCasm = require("../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json");
const optionRoundSieraa = require("../target/dev/pitch_lake_starknet_OptionRound.contract_class.json");
const optionRoundCasm = require("../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json");
const marketAggregatorSierra = require("../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json");
const marketAggregatorCasm = require("../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json");

const constantsPath = path.resolve(__dirname, "./utils/constants.json");
let constants = JSON.parse(fs.readFileSync(constantsPath, "utf8"));

const { getAccount, getProvider } = require("./utils/helper");

async function declareContract(
  enviornment,
  account,
  sierra,
  casm,
  placeholder
) {
  try {
    const declareResult = await account.declare({
      contract: sierra,
      casm: casm,
    });
    constants.declaredContractsMapping[enviornment][placeholder] =
      declareResult.class_hash;

    fs.writeFileSync(constantsPath, JSON.stringify(constants, null, 2), "utf8");
    console.log(`Declare result for ${placeholder}: `, declareResult);
  } catch (err) {
    console.log(`Contract ${placeholder} is already declared`, err);
  }
}

async function main(enviornment, port = null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);
  await declareContract(enviornment, account, ethSierra, ethCasm, "eth");
  await declareContract(enviornment, account, vaultSierra, vaultCasm, "vault");
  await declareContract(
    enviornment,
    account,
    optionRoundSieraa,
    optionRoundCasm,
    "optionRound"
  );
  await declareContract(
    enviornment,
    account,
    marketAggregatorSierra,
    marketAggregatorCasm,
    "marketAggregator"
  );
}

main(process.argv[2], process.argv[3]);
