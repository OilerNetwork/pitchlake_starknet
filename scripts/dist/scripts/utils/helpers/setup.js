import { Contract } from "starknet";
import { stringToHex } from "./common";
import { optionRoundAbi } from "../../abi";
import { OptionRoundFacade } from "../facades/optionRoundFacade";
export const getOptionRoundFacade = async (provider, vault) => {
    const optionRoundContract = await getOptionRoundContract(provider, vault);
    const optionRoundFacade = new OptionRoundFacade(optionRoundContract);
    return optionRoundFacade;
};
export const getOptionRoundContract = async (provider, vault) => {
    const optionRoundId = await vault.current_option_round_id();
    const optionRoundAddressDecimalString = await vault.get_option_round_address(optionRoundId);
    const optionRoundAddress = "0x" + stringToHex(optionRoundAddressDecimalString);
    const optionRoundContract = new Contract(optionRoundAbi, optionRoundAddress, provider).typedv2(optionRoundAbi);
    return optionRoundContract;
};
