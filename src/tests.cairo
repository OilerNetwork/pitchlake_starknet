#[cfg(test)]
pub mod pitchlake_verifier {
    pub mod verifier_tests;
}

#[cfg(test)]
pub mod vault {
    pub mod state_transition {
        pub mod auction_end_tests;
        pub mod auction_start_tests;
        pub mod option_settle_tests;
    }

    pub mod liquidity_providers {
        pub mod deposit_tests;
        pub mod withdraw_tests;
        pub mod withdrawal_queue_tests;
    }
}

#[cfg(test)]
pub mod option_round {
    pub mod option_buyers {
        pub mod bidding_tests;
        pub mod exercise_options_tests;
        pub mod refunding_bids_tests;
        pub mod tokenizing_options_tests;
        pub mod update_bids_tests;
    }
    pub mod rb_tree {
        pub mod rb_tree_mock_contract;
        pub mod rb_tree_stress_tests;
        pub mod rb_tree_tests;
    }
    pub mod state_transition {
        pub mod auction_end {
            pub mod auction_end_tests;
            pub mod clearing_price_tests;
            pub mod option_distribution_tests;
            pub mod premium_earned_tests;
            pub mod refundable_bids_tests;
            pub mod unsold_liquidity_tests;
        }
        pub mod auction_start {
            pub mod auction_start_tests;
        }
        pub mod option_settle {
            pub mod calculated_payout_tests;
            pub mod option_settle_tests;
        }
        pub mod caller_is_not_vault_tests;
        pub mod fulfill_request_tests;
    }
}

#[cfg(test)]
pub mod deployment {
    pub mod constructor_tests;
    pub mod initializing_option_round_params_tests;
}

#[cfg(test)]
mod misc {
    //mod eth_test;
}

#[cfg(test)]
pub mod utils {
    pub mod facades {
        pub mod option_round_facade;
        pub mod sanity_checks;
        pub mod vault_facade;
    }

    pub mod helpers {
        pub mod accelerators;
        pub mod event_helpers;
        pub mod general_helpers;
        pub mod setup;
    }

    pub mod lib {
        pub mod test_accounts;
        pub mod variables;
    }
}
