// old structure
// #[cfg(test)]
// mod eth_test;
#[cfg(test)]
mod pitch_lake_test;
#[cfg(test)]
mod option_auction_bid_test;
#[cfg(test)]
mod option_settle_test;
#[cfg(test)]
mod utils;
#[cfg(test)]
mod vault_facade;
#[cfg(test)]
mod option_round_facade;
#[cfg(test)]
mod vault_premium_to_vault_test;
#[cfg(test)]
mod vault_option_round_test;
#[cfg(test)]
mod mock_market_aggregator;


// Re-org
#[cfg(test)]
mod vault {
    mod withdraw_tests {
        mod while_current_round_is_auctioning;
        mod while_current_round_is_running;
        mod while_current_round_is_settled;
        mod withdraw_tests;
    }
    mod auction_end_tests;
    mod auction_start_tests;
    mod deployment_tests;
    mod deposit_tests;
    mod option_settle_tests;
    mod utils;
}

#[cfg(test)]
mod option_round {
    mod bidding_tests;
    mod clearing_price_tests;
    mod initializing_params_tests;
    mod options_sold_tests;
    mod payout_tests;
    mod state_transition_tests;
}

