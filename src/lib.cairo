mod vault {
    mod interface;
    mod contract;
}

mod option_round {
    mod interface;
    mod contract;
}

mod market_aggregator {
    mod interface;
    mod contract;
    mod types;
}

mod library {
    mod eth;
    mod red_black_tree;
    mod utils;
}

mod types;

#[cfg(test)]
mod tests;


// @note Refactor these into their own modules
mod contracts {
    mod pitch_lake;
    mod market_aggregator;
    mod lp_token;
}
