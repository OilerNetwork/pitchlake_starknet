import { Provider } from "starknet";
import { getCustomAccount } from "../../utils/helpers/common";
import { optionBidders } from "../../utils/constants";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
export const smokeTest = async (
  provider: Provider,
  vaultFacade: VaultFacade,
  ethFacade: EthFacade
) => {


  await vaultFacade.startAuctionBystander(provider);
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
  
};
