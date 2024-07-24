import { Provider, TypedContractV2 } from "starknet";
import { getAccount } from "./common";
import { vaultABI } from "../../abi";
import { getNow, timeskipNextBlock } from "../katana";
import { getOptionRoundContract } from "./setup";

async function accelerateToAuctioning(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultABI>
) {
  const optionRoundContract = await getOptionRoundContract(
    provider,
    vaultContract
  );
  const currentTime = await getNow(provider);
  const auctionStartDate = await optionRoundContract.get_auction_start_date();

  console.log("currentTime:",currentTime,"\nauctionStartDate:",auctionStartDate);;
  await timeskipNextBlock(
    Number(auctionStartDate) - Number(currentTime),
    provider.channel.nodeUrl
  );

}

async function accelerateToRunning(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultABI>
) {
  const optionRoundContract = await getOptionRoundContract(
    provider,
    vaultContract
  );

  const currentTime = await getNow(provider);
  const auctionEndDate = await optionRoundContract.get_auction_end_date();

  await timeskipNextBlock(
    Number(auctionEndDate) - Number(currentTime)+1,
    provider.channel.nodeUrl
  );
}

async function accelerateToSettled(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultABI>
) {
  const optionRoundContract = await getOptionRoundContract(
    provider,
    vaultContract
  );

  const currentTime = await getNow(provider);
  const optionSettleDate =
    await optionRoundContract.get_option_settlement_date();

  await timeskipNextBlock(
    Number(optionSettleDate) - Number(currentTime),
    provider.channel.nodeUrl
  );
 
}
export { accelerateToAuctioning, accelerateToRunning, accelerateToSettled };
