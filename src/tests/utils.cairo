use option::OptionTrait;
use debug::PrintTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    contract_address_try_from_felt252 ,
    testing::{set_block_timestamp, set_contract_address}
};
use starknet::testing;

use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use openzeppelin::utils::serde::SerializedAppend;
use pitch_lake_starknet::eth::Eth;

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait, VaultType};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams, OptionRound};

const NAME: felt252 = 'WETH';
const SYMBOL: felt252 = 'WETH';
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 99999999999999999999999999999; 

fn deployEth() ->  IERC20Dispatcher {

    
    let mut calldata = array![];

    calldata.append_serde(NAME);
    calldata.append_serde(SYMBOL);
    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (address, _) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IERC20Dispatcher{contract_address: address};
}

fn deployOptionRound(owner:ContractAddress) ->  IOptionRoundDispatcher {
    let mut calldata = array![];

    calldata.append_serde(owner);
    calldata.append_serde(owner); // TODO upadte it to the erco 20 collaterized pool
    calldata.append_serde(mock_option_params());
    let (address, _) = deploy_syscall(
        OptionRound::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IOptionRoundDispatcher{contract_address: address};
}


fn deployVault() ->  IVaultDispatcher {
    let mut calldata = array![];

    calldata.append_serde(OptionRound::TEST_CLASS_HASH);
    calldata.append_serde(VaultType::InTheMoney);

    let (address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IVaultDispatcher{contract_address: address};
}

fn setup() -> (IVaultDispatcher, IERC20Dispatcher){

    let eth_dispatcher : IERC20Dispatcher = deployEth();
    let vault_dispatcher : IVaultDispatcher = deployVault();
    set_contract_address(weth_owner());
    let deposit_amount_ether : u256 = 1000000;
    let deposit_amount_wei: u256 = deposit_amount_ether  * eth_dispatcher.decimals().into();

    eth_dispatcher.transfer(liquidity_provider_1(),deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_2(),deposit_amount_wei);

    let deposit_amount_ether : u256 = 100000;
    let deposit_amount_wei: u256 = deposit_amount_ether  * eth_dispatcher.decimals().into();

    eth_dispatcher.transfer(option_bidder_buyer_1(),deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_2(),deposit_amount_wei);

    return (vault_dispatcher, eth_dispatcher);
}

fn option_round_test_owner() -> ContractAddress {
    contract_address_const::<'option_round_test_owner'>()
}

fn allocated_pool_address() -> ContractAddress {
    contract_address_const::<'allocated_pool_address'>()
}

fn unallocated_pool_address() -> ContractAddress {
    contract_address_const::<'unallocated_pool_address'>()
}

fn option_round_contract_address() -> ContractAddress {
    contract_address_const::<'option_round_contract_address'>()
}

fn liquidity_provider_1() -> ContractAddress {
    contract_address_const::<'liquidity_provider_1'>()
}

fn liquidity_provider_2() -> ContractAddress {
    contract_address_const::<'liquidity_provider_2'>()
}

fn option_bidder_buyer_1() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer1'>()
}

fn option_bidder_buyer_2() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer2'>()
}

fn option_bidder_buyer_3() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer3'>()
}

fn option_bidder_buyer_4() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer4'>()
}

fn decimals() -> u256 {
    //10  ** 18
    1000000000000000000
}

fn mock_option_params()-> OptionRoundParams{
    let total_unallocated_liquidity:u256 = 10000 * decimals() ;
    let option_reserve_price_:u256 = 6 * decimals();
    let average_basefee :u256 = 20;
    let standard_deviation : u256 = 30;
    let cap_level :u256 = average_basefee + (3 * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation

    let in_the_money_strike_price: u256 = average_basefee + standard_deviation;
    let at_the_money_strike_price: u256 = average_basefee ;
    let out_the_money_strike_price: u256 = average_basefee - standard_deviation;

    let collateral_level = cap_level - in_the_money_strike_price; // per notes from tomasz
    let total_options_available = total_unallocated_liquidity/ collateral_level;

    let option_reserve_price = option_reserve_price_;// just an assumption

    let tmp = OptionRoundParams{
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

fn month_duration() -> u64 {
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

/// Pop the earliest unpopped logged event for the contract as the requested type
/// and checks there's no more data left on the event, preventing unaccounted params.
/// Indexed event members are currently not supported, so they are ignored.
fn pop_log<T, impl TDrop: Drop<T>, impl TEvent: starknet::Event<T>>(
    address: ContractAddress
) -> Option<T> {
    let (mut keys, mut data) = testing::pop_log_raw(address)?;
    let ret = starknet::Event::deserialize(ref keys, ref data);
    assert(data.is_empty(), 'Event has extra data');
    ret
}



fn assert_no_events_left(address: ContractAddress) {
    assert(testing::pop_log_raw(address).is_none(), 'Events remaining on queue');
}

fn drop_event(address: ContractAddress) {
    testing::pop_log_raw(address);
}
