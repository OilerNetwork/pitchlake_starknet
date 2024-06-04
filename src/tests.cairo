#[cfg(test)]
mod deployment {
    mod constructor_tests;
    mod initializing_option_round_params_tests;
}

#[cfg(test)]
mod misc {
    //mod eth_test;
    mod pitch_lake_test;
    mod lp_token {
        mod lp_token_tests;
        mod deployment_tests;
    }
}

#[cfg(test)]
mod option_round {
    mod option_buyers {
        mod bidding_tests;
        mod exercise_options_tests;
        mod pending_and_refunded_bids_tests;
    }
    mod state_transition {
        mod auction_start_tests;
        mod calculated_payout_tests;
        mod caller_is_not_vault_tests;
        mod clearing_price_tests;
        mod options_minted_tests;
        mod premium_earned_tests;
    }
}

#[cfg(test)]
mod utils {
    mod structs;
    mod event_helpers;
    mod accelerators;
    mod test_accounts;
    mod variables;
    mod setup;
    mod sanity_checks;
    mod utils;
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
mod vault {
    mod state_transition {
        mod auction_end_tests;
        mod auction_start_tests;
        mod option_settle_tests;
    }

    mod liquidity_providers {
        mod deposit_tests;
        mod withdraw_tests;
    }

    mod unallocated_liquidity_tests;
}

