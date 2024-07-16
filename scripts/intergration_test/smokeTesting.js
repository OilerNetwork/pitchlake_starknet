const { liquidityProviders } = require("../utils/constants");
const { getProvider, getCustomAccount } = require("../utils/helper/common");
const { getLPUnlockedBalance, deposit } = require("../utils/vault");

async function smokeTesting0(enviornment, provider) {
  const lp = getCustomAccount(
    provider,
    liquidityProviders[0].account,
    liquidityProviders[0].privateKey
  );
  const liquidityBefore = await getLPUnlockedBalance(
    enviornment,
    provider,
    lp,
    liquidityProviders[0].account
  );
  await deposit(enviornment, provider, lp, liquidityProviders[0].account, 1000);
  const liquidityAfter = await getLPUnlockedBalance(
    enviornment,
    provider,
    lp,
    liquidityProviders[0].account
  );

  console.log("difference between both are: ", liquidityBefore, liquidityAfter);
}

async function smokeTesting(enviornment, port = null) {
  const provider = getProvider(enviornment, port);
  await smokeTesting0(enviornment, provider);
}

module.exports = {
  smokeTesting,
};
