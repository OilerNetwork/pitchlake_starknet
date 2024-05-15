use debug::PrintTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, contract_address_try_from_felt252, testing,
    testing::{set_block_timestamp, set_contract_address}
};

use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use openzeppelin::utils::serde::SerializedAppend;
use pitch_lake_starknet::eth::Eth;

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType, VaultTransfer
};
use pitch_lake_starknet::pitch_lake::{
    IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
    IPitchLakeSafeDispatcherTrait
};


use pitch_lake_starknet::tests::{
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
    vault_facade::{VaultFacade, VaultFacadeTrait}
};
use pitch_lake_starknet::option_round;
use pitch_lake_starknet::option_round::{
    OptionRound, OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
    IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundState
};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{MockMarketAggregator};

const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 99999999999999999999999999999999;

// Deploy eth contract for testing
fn deploy_eth() -> IERC20Dispatcher {
    let mut calldata = array![];

    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (contract_address, _) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), false
    )
        .unwrap();
    return IERC20Dispatcher { contract_address };
}

// Deploy market aggregator for testing
fn deploy_market_aggregator() -> IMarketAggregatorDispatcher {
    let mut calldata = array![];

    let (address, _) = deploy_syscall(
        MockMarketAggregator::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_MARKET_AGGREGATOR_FAILED');
    return IMarketAggregatorDispatcher { contract_address: address };
}

// Deploy the vault and market aggregator
fn deploy_vault(vault_type: VaultType) -> IVaultDispatcher {
    let round_class_hash: felt252 = OptionRound::TEST_CLASS_HASH;
    let mut calldata = array![];
    calldata.append_serde(vault_manager());
    calldata.append_serde(vault_type);
    calldata.append_serde(deploy_market_aggregator().contract_address); // needed ?
    calldata.append_serde(round_class_hash);

    let (address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_VAULT_FAILED');
    return IVaultDispatcher { contract_address: address };
}

fn deploy_pitch_lake() -> IPitchLakeDispatcher {
    let mut calldata = array![];
    let ITM: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);
    let OTM: IVaultDispatcher = deploy_vault(VaultType::OutOfMoney);
    let ATM: IVaultDispatcher = deploy_vault(VaultType::AtTheMoney);
    let mkagg = deploy_market_aggregator();
    calldata.append_serde(ITM.contract_address);
    calldata.append_serde(OTM.contract_address);
    calldata.append_serde(ATM.contract_address);
    calldata.append_serde(mkagg.contract_address);

    let (address, _) = deploy_syscall(
        PitchLake::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IPitchLakeDispatcher { contract_address: address };
}

fn setup() -> (IVaultDispatcher, IERC20Dispatcher) {
    let eth_dispatcher: IERC20Dispatcher = deploy_eth();
    let vault_dispatcher: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);
    set_contract_address(weth_owner());
    let deposit_amount_ether: u256 = 1000000;
    let deposit_amount_wei: u256 = deposit_amount_ether * decimals();

    eth_dispatcher.transfer(liquidity_provider_1(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_2(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_3(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_4(), deposit_amount_wei);

    let deposit_amount_ether: u256 = 100000;
    let deposit_amount_wei: u256 = deposit_amount_ether * decimals();

    eth_dispatcher.transfer(option_bidder_buyer_1(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_2(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_3(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_4(), deposit_amount_wei);

    drop_event(zero_address());

    return (vault_dispatcher, eth_dispatcher);
}


fn setup_facade() -> (VaultFacade, IERC20Dispatcher) {
    let eth_dispatcher: IERC20Dispatcher = deploy_eth();
    let vault_dispatcher: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);
    set_contract_address(weth_owner());
    let deposit_amount_ether: u256 = 1000000;
    let deposit_amount_wei: u256 = deposit_amount_ether * decimals();

    eth_dispatcher.transfer(liquidity_provider_1(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_2(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_3(), deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_4(), deposit_amount_wei);

    let deposit_amount_ether: u256 = 100000;
    let deposit_amount_wei: u256 = deposit_amount_ether * decimals();

    eth_dispatcher.transfer(option_bidder_buyer_1(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_2(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_3(), deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_4(), deposit_amount_wei);
    // @def figure out why this is needed
    drop_event(zero_address());

    let vault_facade = VaultFacade { vault_dispatcher };
    return (vault_facade, eth_dispatcher);
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

fn liquidity_provider_3() -> ContractAddress {
    contract_address_const::<'liquidity_provider_3'>()
}

fn liquidity_provider_4() -> ContractAddress {
    contract_address_const::<'liquidity_provider_4'>()
}

fn liquidity_provider_5() -> ContractAddress {
    contract_address_const::<'liquidity_provider_5'>()
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

fn option_bidder_buyer_5() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer5'>()
}

fn option_bidder_buyer_6() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer6'>()
}


fn liquidity_providers_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => contract_address_const::<'liquidity_provider_1'>(),
            1 => contract_address_const::<'liquidity_provider_2'>(),
            2 => contract_address_const::<'liquidity_provider_3'>(),
            3 => contract_address_const::<'liquidity_provider_4'>(),
            4 => contract_address_const::<'liquidity_provider_5'>(),
            5 => contract_address_const::<'liquidity_provider_6'>(),
            _ => contract_address_const::<'liquidity_provider_1'>(),
        };

        data.append(contractAddress);
        index = index + 1;
    };
    data
}

fn option_bidders_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => contract_address_const::<'liquidity_provider_1'>(),
            1 => contract_address_const::<'liquidity_provider_2'>(),
            2 => contract_address_const::<'liquidity_provider_3'>(),
            3 => contract_address_const::<'liquidity_provider_4'>(),
            4 => contract_address_const::<'liquidity_provider_5'>(),
            5 => contract_address_const::<'liquidity_provider_6'>(),
            _ => contract_address_const::<'liquidity_provider_1'>(),
        };

        data.append(contractAddress);
        index = index + 1;
    };
    data
}
fn decimals() -> u256 {
    //10  ** 18
    1000000000000000000
}

fn mock_option_params() -> OptionRoundParams {
    let total_unallocated_liquidity: u256 = 10000 * decimals(); // from LPs ?
    let option_reserve_price_: u256 = 6 * decimals(); // from market aggregator (fossil) ?
    let average_basefee: u256 = 20; // from market aggregator (fossil) ?
    let standard_deviation: u256 = 30; // from market aggregator (fossil) ?
    let cap_level: u256 = average_basefee
        + (3
            * standard_deviation); //per notes from tomasz, we set cap level at 3 standard deviation (captures 99.7% of the data points)

    let in_the_money_strike_price: u256 = average_basefee + standard_deviation;
    //let at_the_money_strike_price: u256 = average_basefee;
    //let out_the_money_strike_price: u256 = average_basefee - standard_deviation;

    let collateral_level: u256 = cap_level - in_the_money_strike_price; // per notes from tomasz
    let total_options_available: u256 = total_unallocated_liquidity / collateral_level;

    let option_reserve_price: u256 = option_reserve_price_; // just an assumption

    // option_expiry_time:u64, // OptionRound cannot settle before this time
    // auction_end_time:u64, // auction cannot settle before this time
    // minimum_bid_amount:u256,  // to prevent a dos vector
    // minimum_collateral_required:u256 // the option round will not start until this much collateral is deposited

    let tmp = OptionRoundParams {
        current_average_basefee: average_basefee,
        strike_price: in_the_money_strike_price,
        standard_deviation: standard_deviation,
        cap_level: cap_level,
        collateral_level: collateral_level,
        reserve_price: option_reserve_price,
        total_options_available: total_options_available,
        // start_time:timestamp_start_month(),
        option_expiry_time: timestamp_end_month(),
        auction_end_time: week_duration(),
        minimum_collateral_required: 10000,
    };
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
    30 * 24 * 60 * 60
}

fn week_duration() -> u64 {
    7 * 24 * 60 * 60
}


fn month_duration() -> u64 {
    30 * 24 * 60 * 60
}

fn SPENDER() -> ContractAddress {
    contract_address_const::<'SPENDER'>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<'RECIPIENT'>()
}

fn OPERATOR() -> ContractAddress {
    contract_address_const::<'OPERATOR'>()
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

fn assert_event_auction_start(total_options_available: u256) {
    let event = pop_log::<option_round::AuctionStart>(zero_address());
    assert(!event.is_none(), 'Could not find event');
    assert(
        event.unwrap().total_options_available == total_options_available,
        'options_available shd match'
    );
    assert_no_events_left(zero_address());
}

fn assert_event_auction_bid(bidder: ContractAddress, amount: u256, price: u256) {
    let event = pop_log::<option_round::AuctionBid>(zero_address());
    assert(!event.is_none(), 'Could not find event');
    let event = event.unwrap();
    assert(event.amount == amount, 'amount shd match');
    assert(event.price == price, 'price shd match');
    assert(event.bidder == bidder, 'bidder shd match');
    assert_no_events_left(zero_address());
}

fn assert_event_auction_settle(auction_clearing_price: u256) {
    let event = pop_log::<option_round::AuctionSettle>(zero_address());
    assert(!event.is_none(), 'Could not find event');
    assert(event.unwrap().clearing_price == auction_clearing_price, 'price shd match');
    assert_no_events_left(zero_address());
}

fn assert_event_option_settle(option_settlement_price: u256) {
    let event = pop_log::<option_round::OptionSettle>(zero_address());
    assert(!event.is_none(), 'Could not find event');
    assert(event.unwrap().settlement_price == option_settlement_price, 'price shd match');
    assert_no_events_left(zero_address());
}

fn assert_event_option_amount_transfer(
    from: ContractAddress, to: ContractAddress, for_user: ContractAddress, amount: u256
) {
    let event = pop_log::<option_round::OptionTransferEvent>(zero_address()).unwrap();
    assert(event.from == from, 'from shd match');
    assert(event.to == to, 'to shd match');
    assert(event.amount == amount, 'amount shd match');
    assert_no_events_left(zero_address());
}

fn assert_event_transfer(from: ContractAddress, to: ContractAddress, amount: u256) {
    let event = pop_log::<VaultTransfer>(zero_address()).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.amount == amount, 'Invalid `amount`');
    assert_no_events_left(zero_address());
}


// Accelerate to the current round auctioning (needs non 0 liquidity to start auction)
fn accelerate_to_auctioning(ref self: VaultFacade) {
    // Deposit liquidity so round 1's auction can start
    self.deposit(100 * decimals(), liquidity_provider_1());
    // Start round 1's auction
    self.start_auction();
}

fn deposit_n(ref self: VaultFacade, providers: u32, amount: u256) {
    let mut index: u32 = 0;
    let lp = liquidity_providers_get(providers);
    while index < providers {
        let amount = 100 * decimals();
        self.deposit(amount, *lp.at(index));
        index+=1;
    };
}

fn deposit_n_custom(ref self: VaultFacade, providers: u32, amount: Array<u256>) {
    let len = amount.len();
    let mut index: u32 = 0;
    let lp = liquidity_providers_get(providers);
    while index < providers {
        if (index < len) {
            self.deposit(*amount[index], *lp.at(index));
        } else {
            self.deposit(*amount[0], *lp.at(index));
        }
        index+=1;
    };
}

fn bid_n(ref self:VaultFacade, bidders:u32, amount:u256,price:u256){
    let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let mut index:u32 = 0;
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let option_bidders = option_bidders_get(bidders);

    assert(price>bid_price && amount>price,'Invalid parameters');
    while index < bidders {
        current_round.place_bid(amount,price,*option_bidders[index]);
        index+=1;
    }
}


fn bid_n_custom(ref self:VaultFacade, bidders:u32, amounts:Array<u256>,prices:Array<u256>){
let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let mut index:u32 = 0;
    let bid_price = params.reserve_price;
    let option_bidders = option_bidders_get(bidders);
   
    while index < bidders {
        assert(*prices[index]>bid_price && *amounts[index]>*prices[index],('Invalid parameters at {}'));
        current_round.place_bid(*amounts[index],*prices[index],*option_bidders[index]);
        index+=1;
    }
}

// Accelerate to the current round's auction end
fn accelerate_to_running(ref self: VaultFacade) {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    // Bid for all options at reserve price
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
}

fn accelerate_to_auctioning_n_linear(ref self: VaultFacade, providers: u32, amount:u256){
    deposit_n(ref self,providers,amount);
    self.start_auction();
}

//Deposit with a gradient 
fn accelerate_to_auctioning_n_gradient(ref self: VaultFacade, providers: u32) -> Array<u256> {
    let mut index: u32 = 0;
    let mut amounts: Array<u256> = array![];
    let mut lp: Array<ContractAddress> = liquidity_providers_get(providers);
    while index < providers {
        let amount = 100 * (index.into() + 1) * decimals();
        amounts.append(amount);
        self.deposit(amount, *lp.at(index));
        index+=1;
    };
    self.start_auction();
    amounts
}

fn accelerate_to_auctioning_n_custom(ref self: VaultFacade, providers: u32, amounts: Array<u256>) {

    deposit_n_custom(ref self, providers, amounts);
    self.start_auction();
}


//Auction with linear bidding
fn accelerate_to_running_n_linear(ref self: VaultFacade, providers: u32, bidders: u32,amount:u256) -> u256 {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price / bidders.into();
    bid_n(ref self,bidders,bid_amount,bid_price);
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
    bid_amount
}


//Applies a gradient to bid price;
fn accelerate_to_running_n_gradient(
    ref self: VaultFacade, providers: u32, bidders: u32
) -> (Array<u256>, Array<u256>) {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    let bidders_array: Array<ContractAddress> = option_bidders_get(bidders);
    let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let mut bid_amounts: Array<u256> = array![];
    let mut bid_prices: Array<u256> = array![];
    let mut index: u32 = 0;
    while index < bidders {
        let bid_quant = (bid_amount / bidders.into()) + 1;
        let bid_price = params.reserve_price + index.into();
        let bid_amount = bid_quant * bid_price;
        bid_amounts.append(bid_amount);
        bid_prices.append(bid_price);
        current_round.place_bid(bid_amount, bid_price, *bidders_array.at(index));
        index+=1;
    };
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
    (bid_amounts, bid_prices)
}

fn accelerate_to_running_n_custom(
    ref self: VaultFacade, providers: u32, bidders: u32, amounts: Array<u256>, prices: Array<u256>
) {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    let params = current_round.get_params();
    bid_n_custom(ref self,bidders,amounts,prices);
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
}

//Auction with partial bidding
fn accelerate_to_running_n_partial(
    ref self: VaultFacade, providers: u32, bidders: u32
) -> (u256, u256) {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_quant = bid_amount / bidders.into() / 2;
    let bid_amount = bid_quant * bid_price;
    bid_n(ref self, bidders,bid_amount,bid_price);
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
    (bid_amount, bid_price)
}


fn accelerate_to_running_partial(ref self: VaultFacade) {
    accelerate_to_auctioning(ref self);
    // Bid for half the options at reserve price
    let mut current_round = self.get_current_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let mut bid_quant = bid_amount / 2;

    //If quant gets 0 ensure minimum bid on 1 option
    if bid_quant < 1 {
        bid_quant += 1;
    }
    let bid_amount = bid_quant * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
}
// @note Might want to add accelerate to settled with args for settlemnt price


