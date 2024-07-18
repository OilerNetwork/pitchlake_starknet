import { Provider } from "starknet";
import { getAccount } from "../../utils/helpers/common";
import { VaultFacade } from "../../utils/facades/vaultFacade";
import { EthFacade } from "../../utils/facades/ethFacade";
import {
  getOptionRoundERC20Facade,
  getOptionRoundFacade,
} from "../../utils/helpers/setup";
import assert from "assert";
import { Constants } from "../../utils/facades/types";
import { ethAbi } from "../../abi";
import {
  getLiquidityProviderAccounts,
  getOptionBidderAccounts,
} from "../../utils/helpers/accounts";

export const smokeTest = async (
  provider: Provider,
  vaultFacade: VaultFacade,
  ethFacade: EthFacade,
  constants: Constants
) => {
  const optionRoundFacade = await getOptionRoundFacade(
    provider,
    vaultFacade.vaultContract
  );

  const optionRoundERC20Contract = await getOptionRoundERC20Facade(
    provider,
    optionRoundFacade.optionRoundContract
  );
  const devAccount = getAccount("dev", provider);

  const totalOptionAvailable =
    await optionRoundFacade.getTotalOptionsAvailable();
  const reservePrice = await optionRoundFacade.getReservePrice();
  const optionBidderAccounts = getOptionBidderAccounts(provider, 3);

  const balanceBeforeRefundC = await ethFacade.getBalance(
    optionBidderAccounts[0].address
  );
  const balanceBeforeRefundD = await ethFacade.getBalance(
    optionBidderAccounts[0].address
  );
  try {
    await optionRoundFacade.refundUnusedBids({
      from: devAccount,
      optionBidder: optionBidderAccounts[0].address,
    });
    await optionRoundFacade.refundUnusedBids({
      from: devAccount,
      optionBidder: optionBidderAccounts[1].address,
    });
  } catch (err) {
    console.log("Error while refunding the unused bids", err);
  }

  const balanceAfterRefundC = await ethFacade.getBalance(
    optionBidderAccounts[0].address
  );
  const balanceAfterRefundD = await ethFacade.getBalance(
    optionBidderAccounts[1].address
  );

  checkpoint1({
    balanceBeforeRefundC,
    balanceBeforeRefundD,
    balanceAfterRefundC,
    balanceAfterRefundD,
    totalOptionAvailable,
    reservePrice,
  });

  const optionAvailableBeforeTransferC =
    await optionRoundFacade.getTotalOptionsBalanceFor({
      optionBuyer: optionBidderAccounts[0].address,
    });
  const optionAvailableBeforeTransferD =
    await optionRoundFacade.getTotalOptionsBalanceFor({
      optionBuyer: optionBidderAccounts[1].address,
    });

  try {
    await optionRoundFacade.tokenizeOptions({
      from: optionBidderAccounts[0],
    });
  } catch (err) {
    console.log("Error while tokenizing the option", err);
  }

  try {
    optionRoundERC20Contract.connect(optionBidderAccounts[0]);
    await optionRoundERC20Contract.transfer(
      optionBidderAccounts[1].address,
      BigInt(totalOptionAvailable) / BigInt(4)
    );
  } catch (err) {
    console.log("Error while transferring the tokenized options", err);
  }

  const optionAvailableAfterTransferC =
    await optionRoundFacade.getTotalOptionsBalanceFor({
      optionBuyer: optionBidderAccounts[0].address,
    });
  const optionAvailableAfterTransferD =
    await optionRoundFacade.getTotalOptionsBalanceFor({
      optionBuyer: optionBidderAccounts[1].address,
    });
};

async function checkpoint1({
  balanceBeforeRefundC,
  balanceBeforeRefundD,
  balanceAfterRefundC,
  balanceAfterRefundD,
  totalOptionAvailable,
  reservePrice,
}: {
  balanceBeforeRefundC: bigint | number;
  balanceBeforeRefundD: bigint | number;
  balanceAfterRefundC: bigint | number;
  balanceAfterRefundD: bigint | number;
  totalOptionAvailable: bigint | number;
  reservePrice: bigint | number;
}) {
  assert(
    BigInt(balanceBeforeRefundC) +
      (BigInt(totalOptionAvailable) / BigInt(2)) * BigInt(reservePrice) ===
      BigInt(balanceAfterRefundC),
    "Unused bids balance fail"
  );
  assert(
    BigInt(balanceBeforeRefundD) +
      (BigInt(totalOptionAvailable) / BigInt(2)) * BigInt(reservePrice) ===
      BigInt(balanceAfterRefundD),
    "Unused bids balance fail"
  );
}

async function checkpoint2({
  optionAvailableBeforeTransferC,
  optionAvailableBeforeTransferD,
  optionAvailableAfterTransferC,
  optionAvailableAfterTransferD,
  totalOptionAvailable,
}: {
  optionAvailableBeforeTransferC: bigint | number;
  optionAvailableBeforeTransferD: bigint | number;
  optionAvailableAfterTransferC: bigint | number;
  optionAvailableAfterTransferD: bigint | number;
  totalOptionAvailable: bigint | number;
}) {
  assert(
    BigInt(optionAvailableBeforeTransferC) ===
      BigInt(optionAvailableBeforeTransferD),
    "Intial options should be equal"
  );

  assert(
    BigInt(optionAvailableBeforeTransferC) +
      BigInt(optionAvailableBeforeTransferD) ===
      BigInt(totalOptionAvailable),
    "Intial sum of options should be total options available"
  );

  assert(
    BigInt(optionAvailableAfterTransferC) +
      BigInt(optionAvailableAfterTransferD) ===
      BigInt(totalOptionAvailable),
    "After transfer sum of options should be total options available"
  );
  assert(
    BigInt(optionAvailableBeforeTransferC) / BigInt(2) ===
      BigInt(optionAvailableAfterTransferC),
    "Final option balance of C should be half of initial"
  );

  assert(
    BigInt(optionAvailableBeforeTransferD) +
      BigInt(optionAvailableBeforeTransferC) / BigInt(2) ===
      BigInt(optionAvailableAfterTransferD),
    "Final option balance of D should be inital + half of C"
  );
}
