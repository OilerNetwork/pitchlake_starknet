const { getAccount, getProvider } = require("./utils/helper/common");
const {
  deployEthContract,
  deployMarketAggregator,
  deployVaultContract,
} = require("./deployments/deployContracts");

const { declareContract } = require("./deployments/declareContracts");
const ethSierra = require("../target/dev/pitch_lake_starknet_Eth.contract_class.json");
const ethCasm = require("../target/dev/pitch_lake_starknet_Eth.compiled_contract_class.json");
const vaultSierra = require("../target/dev/pitch_lake_starknet_Vault.contract_class.json");
const vaultCasm = require("../target/dev/pitch_lake_starknet_Vault.compiled_contract_class.json");
const optionRoundSieraa = require("../target/dev/pitch_lake_starknet_OptionRound.contract_class.json");
const optionRoundCasm = require("../target/dev/pitch_lake_starknet_OptionRound.compiled_contract_class.json");
const marketAggregatorSierra = require("../target/dev/pitch_lake_starknet_MarketAggregator.contract_class.json");
const marketAggregatorCasm = require("../target/dev/pitch_lake_starknet_MarketAggregator.compiled_contract_class.json");
const { supply } = require("./utils/helper/eth");
const { liquidityProviders, optionBidders } = require("./utils/constants");

async function declareContracts(enviornment, port = null) {
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

async function deployContracts(enviornment, port = null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);

  await deployEthContract(enviornment, account);
  await deployMarketAggregator(enviornment, account);
  await deployVaultContract(enviornment, account);
}

async function supplyEth(enviornment, port = null) {
  const provider = getProvider(enviornment, port);
  const account = getAccount(enviornment, provider);

  for (let i = 0; i < 10; i++) {
    await supply(
      enviornment,
      provider,
      account,
      liquidityProviders[i].account,
      1000000
    );
    await supply(
      enviornment,
      provider,
      account,
      optionBidders[i].account,
      1000000
    );
  }
}

async function main(enviornment, port = null) {
  await declareContracts(enviornment, port);

  await deployContracts(enviornment, port);

  await supplyEth(enviornment, port);
}

main(process.argv[2], process.argv[3]);
