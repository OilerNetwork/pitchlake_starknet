const fs = require("fs");
const path = require("path");

const constantsPath = path.resolve(__dirname, "./utils/constants.json");
let constants = JSON.parse(fs.readFileSync(constantsPath, "utf8"));

// const { getAccount, getProvider } = require("./utils/helper");

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

module.exports = {
  declareContract,
};
