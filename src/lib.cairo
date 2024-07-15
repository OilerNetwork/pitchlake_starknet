mod contracts {
    mod utils {
        mod utils;
    }
    mod components {
        mod eth;
        mod red_black_tree;
    }
    mod pitch_lake;
    mod vault {
        mod contract;
        mod interface;
        mod types;
    }
    mod option_round {
        mod contract;
        mod interface;
        mod types;
    }

    mod market_aggregator;
    mod lp_token;
}

#[cfg(test)]
mod tests;
