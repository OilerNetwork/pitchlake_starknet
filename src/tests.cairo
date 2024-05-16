mod utils;
mod vault_facade;
mod option_round_facade;
mod lp_token_facade;
mod mocks {
    mod mock_market_aggregator;
}

#[cfg(test)]
mod extra {
    //mod eth_test;
    mod pitch_lake_test;
}

#[cfg(test)]
mod vault {
    mod withdraw_tests {
        mod while_current_round_is_auctioning;
        mod while_current_round_is_running;
        mod while_current_round_is_settled;
        mod withdraw_tests;
    }
    mod unallocated_liquidity_tests;
    mod auction_end_tests;
    mod auction_start_tests;
    mod deployment_tests;
    mod deposit_tests;
    mod option_settle_tests;
    mod utils;
}

#[cfg(test)]
mod option_round {
    mod premium_tests;
    mod bidding_tests;
    mod clearing_price_tests;
    mod initializing_params_tests;
    mod options_sold_tests;
    mod payout_tests;
    mod state_transition_tests;
    mod unused_bids_tests;
}

#[cfg(test)]
mod lp_token {
    mod lp_token_tests;
    mod deployment_tests;
}

