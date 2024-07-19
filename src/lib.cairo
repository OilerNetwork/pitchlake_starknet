mod vault {
    mod contract;
    mod interface;
}

mod option_round {
    mod contract;
    mod interface;
}

mod market_aggregator {
    mod contract;
    mod interface;
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
