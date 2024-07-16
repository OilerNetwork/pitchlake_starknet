import fs from "fs"
import path from "path"
import {Account} from "starknet"
const constantsPath = path.resolve(__dirname, "./utils/constants.json");

async function declareContract(
  enviornment:string,
  account:Account,
  sierra:any,
  casm:any,
  placeholder:any
) {
  try {
    let constants = JSON.parse(fs.readFileSync(constantsPath, "utf8"));
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
