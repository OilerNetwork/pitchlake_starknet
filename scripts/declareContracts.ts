import fs from "fs"
import path from "path"
import {Account, CairoAssembly, CompiledContract} from "starknet"
const constantsPath = path.resolve(__dirname, "./utils/constants.json");

async function declareContract(
  enviornment:string,
  account:Account,
  sierra:CompiledContract,
  casm:CairoAssembly,
  placeholder:string
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
    return declareResult.class_hash
  } catch (err) {
    console.log(`Contract ${placeholder} is already declared`, err);
  }
  
}

 export {
  declareContract,
};
