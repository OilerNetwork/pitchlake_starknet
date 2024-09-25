mod types;

mod library {
    mod eth;
    mod red_black_tree;
    mod utils;
}


mod vault {
    mod interface;
    mod contract;
}

mod option_round {
    mod interface;
    mod contract;
}

mod fact_registry {
    mod contract;
    mod interface;
}

#[cfg(test)]
mod tests;
