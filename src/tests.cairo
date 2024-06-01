#[cfg(test)]
mod utils {
    mod structs;
    mod event_helpers;
    mod accelerators;
    mod test_accounts;
    mod variables;
    mod setup;
    mod sanity_checks;
    mod mocks {
        mod mock_market_aggregator;
    }
    mod facades {
        mod vault_facade;
        mod option_round_facade;
        mod lp_token_facade;
    }
}

#[cfg(test)]
mod misc {
    //mod eth_test;
    mod pitch_lake_test;
}

#[cfg(test)]
mod vault {
    mod unallocated_liquidity_tests;
    mod auction_end_tests;
    mod auction_start_tests;
    mod deployment_tests;
    mod deposit_tests;
    mod option_settle_tests;
    mod round_open_tests;
    mod withdraw_tests;
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

