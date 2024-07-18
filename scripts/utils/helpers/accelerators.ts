import {  Provider, TypedContractV2 } from "starknet";
import { getAccount } from "./common";
import {  vaultAbi } from "../../abi";
import { getNow, timeskipNextBlock } from "../katana";
import { getOptionRoundContract } from "./setup";

async function accelerateToAuctioning(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>
) {

    const optionRoundContract = await getOptionRoundContract(provider,vaultContract)
    const currentTime = await getNow(provider);
    const auctionStartDate = await optionRoundContract.get_auction_start_date();

    await timeskipNextBlock(
      Number(auctionStartDate) - Number(currentTime),
      provider.channel.nodeUrl
    );

    const devAccount = getAccount("dev", provider);
    vaultContract.connect(devAccount);
    await vaultContract.start_auction();
}

async function accelerateToRunning(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>
) {
  const optionRoundContract = await getOptionRoundContract(provider,vaultContract)

  const currentTime = await getNow(provider);
  const auctionEndDate = await optionRoundContract.get_auction_end_date();

  await timeskipNextBlock(
    Number(auctionEndDate) - Number(currentTime),
    provider.channel.nodeUrl
  );
  const devAccount = getAccount("dev", provider);
  vaultContract.connect(devAccount);
  await vaultContract.end_auction();
}
export { accelerateToAuctioning, accelerateToRunning };
