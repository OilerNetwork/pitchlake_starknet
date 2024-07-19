mod PeriodTypes {
    const TIME: felt252 = 'TIME';
    const BLOCK: felt252 = 'BLOCK';
}

mod DataTypes {
    const RESERVE_PRICE: felt252 = 'RESERVE PRICE';
    const CAP_LEVEL: felt252 = 'CAP LEVEL';
    const TWAP: felt252 = 'TWAP';
}

mod Errors {
    const VALUE_ALREADY_SET: felt252 = 'Value already set in storage';
    const CAP_LEVEL_TOO_BIG: felt252 = 'Cap level must be <= 10,000';
}

