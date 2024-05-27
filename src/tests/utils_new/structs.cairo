#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundParams {
    // @note Discuss if we should set these when previous round settles, or shortly after when this round's auction starts
    current_average_basefee: u256, // average basefee the last few months, used to calculate the strike
    standard_deviation: u256, // used to calculate k (-σ or 0 or σ if vault is: ITM | ATM | OTM)
    strike_price: u256, // K = current_average_basefee * (1 + k)
    cap_level: u256, // cl, percentage points of K that the options will pay out at most. Payout = min(cl*K, BF-K). Might not be set until auction settles if we use alternate cap design (see DOCUMENTATION.md)
    collateral_level: u256, // total deposits now locked in the round
    reserve_price: u256, // minimum price per option in the auction
    total_options_available: u256,
    minimum_collateral_required: u256, // the auction will not start unless this much collateral is deposited, needed ?
    // @dev should we consider setting this upon auction start ?
    // that way if the round's auction start is delayed (due to collateral requirements), we can set a proper auction end time
    // when it eventually starts ?
    auction_end_time: u64, // when an auction can end
    // @dev same as auction end time, wait to set when round acutally starts ?
    option_expiry_time: u64, // when the options can be settled
}
