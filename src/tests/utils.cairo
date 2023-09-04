use option::OptionTrait;
use debug::PrintTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    contract_address_try_from_felt252
};
use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait, OptionParams};


fn allocated_pool_address() -> ContractAddress {
    contract_address_const::<'allocated_pool_address'>()
}

fn unallocated_pool_address() -> ContractAddress {
    contract_address_const::<'unallocated_pool_address'>()
}

fn liquidity_provider_1() -> ContractAddress {
    contract_address_const::<'liquidity_provider_1'>()
}

fn liquidity_provider_2() -> ContractAddress {
    contract_address_const::<'liquidity_provider_2'>()
}

fn option_bidder_buyer_1() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer'>()
}

fn option_bidder_buyer_2() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer'>()
}

fn mock_option_params(start_time:u64, expiry_time:u64, total_liquidity:u128, option_reserve_price_:u128)-> OptionParams{

    let average_basefee :u128 = 20;
    let standard_deviation : u128 = 30;
    let cap_level :u128 = average_basefee + (3 * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation

    let in_the_money_strike_price: u128 = average_basefee + standard_deviation;
    let at_the_money_strike_price: u128 = average_basefee ;
    let out_the_money_strike_price: u128 = average_basefee - standard_deviation;

    let collateral_level = cap_level - in_the_money_strike_price; // per notes from tomasz
    let total_options_available = total_liquidity/ collateral_level;

    let option_reserve_price = option_reserve_price_;// just an assumption

    let tmp = OptionParams{
        strike_price: in_the_money_strike_price,
        standard_deviation: standard_deviation,
        cap_level :cap_level,  
        collateral_level: collateral_level,
        reserve_price: option_reserve_price,
        total_options_available: total_options_available,
        start_time:timestamp_start_month(),
        expiry_time:timestamp_end_month()};
    return tmp;
}

fn vault_manager() -> ContractAddress {
    contract_address_const::<'vault_manager'>()
}

fn weth_owner() -> ContractAddress {
    contract_address_const::<'weth_owner'>()
}

fn timestamp_start_month() -> u64 {
    1
}

fn timestamp_end_month() -> u64 {
    30*24*60*60
}

fn SPENDER() -> ContractAddress {
    contract_address_const::<20>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<30>()
}

fn OPERATOR() -> ContractAddress {
    contract_address_const::<40>()
}

fn user() -> ContractAddress {
    contract_address_try_from_felt252('user').unwrap()
}

fn zero_address() -> ContractAddress {
    contract_address_const::<0>()
}

