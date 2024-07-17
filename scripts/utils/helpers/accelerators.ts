import { Account, Contract, Provider, TypedContractV2 } from "starknet";
import { stringToHex } from "./common";
import { optionRoundAbi, vaultAbi } from "../../abi";
import { getNow, mineNextBlock, setAndMineNextBlock } from "../katana";

async function accelerateToAuctioning(
  provider: Provider,
  vaultContract: TypedContractV2<typeof vaultAbi>
) {
  try {
    const optionRoundId = await vaultContract.current_option_round_id();
    const optionRoundAddressDecimalString =
      await vaultContract.get_option_round_address(optionRoundId);
    const optionRoundAddressHexString: string =
      "0x" + stringToHex(optionRoundAddressDecimalString);

    const optionRoundContract = new Contract(
      optionRoundAbi,
      optionRoundAddressHexString,
      provider
    ).typedv2(optionRoundAbi);

    const currentTime = await getNow(provider);
    const auctionStartDate = await optionRoundContract.get_auction_start_date();

    await setAndMineNextBlock(
      provider,
      Number(auctionStartDate) - Number(currentTime),
      provider.channel.nodeUrl
    );
  } catch (err) {
    console.log(err);
  }
}

export { accelerateToAuctioning };
