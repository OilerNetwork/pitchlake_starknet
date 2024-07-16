
import {Account} from "starknet"

async function declareContract(
  account:Account,
  sierra:any,
  casm:any,
  placeholder:string
) {
  try {
    const declareResult = await account.declare({
      contract: sierra,
      casm: casm,
    });
    console.log(`Declare result for ${placeholder}: `, declareResult);
    return declareResult.class_hash
  } catch (err) {
    console.log(`Contract ${placeholder} is already declared`, err);
  }

}

 export {
  declareContract,
};