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
    mod unallocated_liquidity_tests;
}

#[cfg(test)]
mod option_round {
    mod option_buyers {
        mod bidding_tests;
        mod exercise_options_tests;
        mod refunding_bids_tests;
        mod update_bids_tests;
        mod tokenizing_options_tests;
    }
    mod state_transition {
        mod auction_end {
            mod auction_end_tests;
            mod pending_to_refundable_bids_tests;
            mod clearing_price_tests;
            mod option_distribution_tests;
            mod premium_earned_tests;
            mod unsold_liquidity_tests;
        }
        mod auction_start {
            mod auction_start_tests;
        }
        mod option_settle {
            mod calculated_payout_tests;
            mod option_settle_tests;
        }
        mod caller_is_not_vault_tests;
    }
}

#[cfg(test)]
mod utils {
    mod mocks {
        mod mock_market_aggregator;
    }
    mod facades {
        mod vault_facade;
        mod option_round_facade;
        mod lp_token_facade;
        mod sanity_checks;
    }

    mod helpers {
        mod accelerators;
        mod event_helpers;
        mod general_helpers;
        mod setup;
    }

    mod lib {
        mod structs;
        mod test_accounts;
        mod variables;
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
}

