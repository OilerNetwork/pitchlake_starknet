import { Contract, Provider, TypedContractV2 } from "starknet";
import { ABI as vaultAbi } from "../../abi/vaultAbi";
import { ABI as ethAbi } from "../../abi/ethAbi";
import { ABI as optionRoundAbi} from "../../abi/optionRoundAbi";
import { getCustomAccount } from "../../utils/helper/common";
import { optionBidders } from "../../utils/constants";
import { approval } from "../../utils/facades/eth";
export const smokeTest = async (
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>,
  ethContract: TypedContractV2<typeof ethAbi>
) => {

  const optionRoundId = await vaultContract.current_option_round_id();
  const optionRoundAddress=await vaultContract.get_option_round_address(optionRoundId);
  const optionRoundContract = new Contract(optionRoundAbi,optionRoundAddress,provider).typedv2(optionRoundAbi);
  
  
  const depositAmount = 1000;
  const optionBidderA = getCustomAccount(
    provider,
    optionBidders[0].account,
    optionBidders[0].privateKey
  );
  const optionBidderB = getCustomAccount(
    provider,
    optionBidders[1].account,
    optionBidders[1].privateKey
  );

  //@note Wrap this into a try catch to avoid breaking thread and log errors correctly
  //Approve A for depositing
  await approval(
    {
      owner: optionBidderA,
      amount: 1000000,
      spender: optionRoundContract.address,
    },
    ethContract
  );

};
