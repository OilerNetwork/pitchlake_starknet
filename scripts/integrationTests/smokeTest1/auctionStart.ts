import { Contract, Provider } from "starknet";
import { ABI as optionRoundAbi } from "../../abi/optionRoundAbi";
import { getCustomAccount } from "../../utils/helpers/common";
import { optionBidders } from "../../utils/constants";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
export const smokeTest = async (
  provider: Provider,
  vaultFacade: VaultFacade,
  ethFacade: EthFacade
) => {
  const optionRoundId =
    await vaultFacade.vaultContract.current_option_round_id();
  const optionRoundAddress =
    await vaultFacade.vaultContract.get_option_round_address(optionRoundId);
  const optionRoundContract = new Contract(
    optionRoundAbi,
    optionRoundAddress,
    provider
  ).typedv2(optionRoundAbi);

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

  await ethFacade.approval({
    owner: optionBidderA,
    spender: vaultFacade.vaultContract.address,
    amount: 10000,
  });
  await vaultFacade.deposit({
    from: optionBidderA,
    beneficiary: optionBidderA.address,
    amount: 1000,
  });
  //@note Wrap this into a try catch to avoid breaking thread and log errors correctly
  //Approve A for depositing
  await ethFacade.approval({
    owner: optionBidderA,
    amount: 1000000,
    spender: optionRoundContract.address,
  });
};
