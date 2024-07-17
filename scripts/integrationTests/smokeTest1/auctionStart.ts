import { Contract, Provider, TypedContractV2 } from "starknet";
import { ABI as vaultAbi } from "../../abi/vaultAbi";
import { ABI as ethAbi } from "../../abi/ethAbi";
import { ABI as optionRoundAbi} from "../../abi/optionRoundAbi";
import { getCustomAccount } from "../../utils/helpers/common";
import { optionBidders } from "../../utils/constants";
import { approval } from "../../utils/facades/eth";
import { getNow, setAndMineNextBlock } from "../../utils/katana";
import { deposit } from "../../utils/facades/vault";
export const smokeTest = async (
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>,
  ethContract: TypedContractV2<typeof ethAbi>
) => {

  const optionRoundId = await vaultContract.current_option_round_id();
  const optionRoundAddress=await vaultContract.get_option_round_address(optionRoundId);
  const optionRoundContract = new Contract(optionRoundAbi,optionRoundAddress,provider).typedv2(optionRoundAbi);
  
  const currentTime =await getNow(provider);
  const auctionStartDate = await optionRoundContract.get_auction_start_date();
  
  setAndMineNextBlock(Number(auctionStartDate)-Number(currentTime),provider.channel.nodeUrl);
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

  approval({owner:optionBidderA,spender:vaultContract.address,amount:10000},ethContract)
  deposit({from:optionBidderA,beneficiary:optionBidderA.address,amount:1000},vaultContract)
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
