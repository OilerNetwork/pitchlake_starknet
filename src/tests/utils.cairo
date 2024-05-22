use core::array::ArrayTrait;
use debug::PrintTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, contract_address_try_from_felt252, testing,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
};
use openzeppelin::token::erc20::{ERC20Component, ERC20Component::{Transfer}};
use openzeppelin::utils::serde::SerializedAppend;

use pitch_lake_starknet::{
    pitch_lake::{
        IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
        IPitchLakeSafeDispatcherTrait
    },
    market_aggregator::{
        IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
        IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
    },
    vault::{IVaultDispatcher, IVaultDispatcherTrait, Vault, VaultType}, option_round,
    option_round::{
        OptionRound, OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundState,
    },
    tests::{
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        vault_facade::{VaultFacade, VaultFacadeTrait},
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        }
    },
    eth::Eth,
};

const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 99999999999999999999999999999999;

// Deploy eth contract for testing
fn deploy_eth() -> IERC20Dispatcher {
    let mut calldata = array![];

    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (contract_address, _): (ContractAddress, Span<felt252>) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), false
    )
        .unwrap();

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return IERC20Dispatcher { contract_address };
}

// Deploy market aggregator for testing
fn deploy_market_aggregator() -> IMarketAggregatorDispatcher {
    let mut calldata = array![];

    let (contract_address, _) = deploy_syscall(
        MockMarketAggregator::TEST_CLASS_HASH.try_into().unwrap(),
        'some salt',
        calldata.span(),
        true
    )
        .expect('DEPLOY_MARKET_AGGREGATOR_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);
    return IMarketAggregatorDispatcher { contract_address };
}

// Deploy the vault and market aggregator
fn deploy_vault(vault_type: VaultType) -> IVaultDispatcher {
    let mut calldata = array![];
    calldata.append_serde(vault_manager());
    calldata.append_serde(vault_type);
    calldata.append_serde(deploy_market_aggregator().contract_address); // needed ?
    calldata.append_serde(OptionRound::TEST_CLASS_HASH);

    let (contract_address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 'some salt', calldata.span(), true
    )
        .expect('DEPLOY_VAULT_FAILED');

    // Clear the event log
    clear_event_logs(array![contract_address]);

    return IVaultDispatcher { contract_address };
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

    let (contract_address, _) = deploy_syscall(
        PitchLake::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');

    // Clear event logs
    clear_event_logs(
        array![
            ITM.contract_address,
            OTM.contract_address,
            ATM.contract_address,
            mkagg.contract_address,
            contract_address
        ]
    );

    return IPitchLakeDispatcher { contract_address };
}

fn setup_facade() -> (VaultFacade, IERC20Dispatcher) {
    let eth_dispatcher: IERC20Dispatcher = deploy_eth();
    let vault_dispatcher: IVaultDispatcher = deploy_vault(VaultType::InTheMoney);

    // Supply eth to test users
    set_contract_address(weth_owner());
    let mut lps = liquidity_providers_get(5);
    loop {
        match lps.pop_front() {
            Option::Some(lp) => {
                let lp_amount_wei: u256 = 1000000 * decimals(); // 1,000,000 ETH
                eth_dispatcher.transfer(lp, lp_amount_wei);
            },
            Option::None => { break (); },
        };
    };

    // Give OBs eth
    let mut obs = option_bidders_get(5);
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let ob_amount_wei: u256 = 100000 * decimals(); // 100,000 ETH

                eth_dispatcher.transfer(ob, ob_amount_wei);
            },
            Option::None => { break; },
        };
    };

    // Clear eth transfer events
    clear_event_logs(array![eth_dispatcher.contract_address]);

    return (VaultFacade { vault_dispatcher }, eth_dispatcher);
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
            0 => contract_address_const::<'option_bidder_buyer_1'>(),
            1 => contract_address_const::<'option_bidder_buyer_2'>(),
            2 => contract_address_const::<'option_bidder_buyer_3'>(),
            3 => contract_address_const::<'option_bidder_buyer_4'>(),
            4 => contract_address_const::<'option_bidder_buyer_5'>(),
            5 => contract_address_const::<'option_bidder_buyer_6'>(),
            _ => contract_address_const::<'option_bidder_buyer_1'>(),
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


/// EVENTS ///

// Pop the earliest unpopped logged event for the contract as the requested type
// and checks there's no more data left on the event, preventing unaccounted params.
// Indexed event members are currently not supported, so they are ignored.
fn pop_log<T, impl TDrop: Drop<T>, impl TEvent: starknet::Event<T>>(
    address: ContractAddress
) -> Option<T> {
    let (mut keys, mut data) = testing::pop_log_raw(address)?;
    let ret = starknet::Event::deserialize(ref keys, ref data);
    assert(data.is_empty(), 'Event has extra data');
    ret
}

// Clear event logs for an array of contracts
// @dev Drops each event
fn clear_event_logs(mut addresses: Array<ContractAddress>) {
    loop {
        match addresses.pop_front() {
            Option::Some(addr) => {
                loop {
                    match testing::pop_log_raw(addr) {
                        Option::Some(_) => { continue; },
                        Option::None => { break; }
                    }
                };
                assert_no_events_left(addr);
            },
            Option::None => { break; }
        }
    }
}

// Assert a contract's event log is empty
fn assert_no_events_left(address: ContractAddress) {
    assert(testing::pop_log_raw(address).is_none(), 'Events remaining on queue');
}

// Assert 2 events of the same type are equal
fn assert_events_equal<T, +PartialEq<T>, +Drop<T>>(actual: T, expected: T) {
    assert(actual == expected, 'Event does not match expected');
}

// Pop the earlist event for a contract and return its details
fn pop_event_details(address: ContractAddress) -> Option<(Span<felt252>, Span<felt252>)> {
    Option::Some(testing::pop_log_raw(address)?)
}

// Check AuctionStart emits correctly
// @dev Example of Result type
fn assert_event_auction_start(
    option_round_address: ContractAddress, total_options_available: u256
) {
    match pop_log::<OptionRound::AuctionStart>(option_round_address) {
        Option::Some(e) => {
            let e = OptionRound::Event::AuctionStart(e);
            let expected = OptionRound::Event::AuctionStart(
                OptionRound::AuctionStart { total_options_available }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

// Check AuctionBid emits correctly
// @note AuctionAcceptedBid and AuctionRejectedBid both fire this event type/struct.
//  - Research more about different contract events sharing struct type but different names (see vault.cairo -> AuctionAcceptedBid|AuctionRejectedBid)
fn assert_event_auction_bid(
    contract: ContractAddress, bidder: ContractAddress, amount: u256, price: u256, is_accepted: bool
) { //
    // @note, Until the #[key] issue is fixed, we are manually building the event
    //   match pop_log::<OptionRound::AuctionBid>(contract) {
    //        Option::Some(e) => {
    //           let e = match is_accepted {
    //              true => OptionRound::Event::AuctionAcceptedBid(e),
    //             false => OptionRound::Event::AuctionRejectedBid(e)
    //        };
    //       let expected = match is_accepted {
    //          true => OptionRound::Event::AuctionAcceptedBid(
    //             OptionRound::AuctionBid { bidder, amount, price }
    //        ),
    //       false => OptionRound::Event::AuctionRejectedBid(
    //          OptionRound::AuctionBid { bidder, amount, price }
    //     )
    //            };
    //           assert_events_equal(e, expected);
    //      },
    //     Option::None => { panic(array!['Could not find event']); },
    //    }
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => {
            let expected_inner = OptionRound::AuctionBid { bidder, amount, price };
            let e_inner = OptionRound::AuctionBid {
                bidder: (*keys.at(1)).try_into().unwrap(),
                amount: u256 {
                    low: (*data.at(0)).try_into().unwrap(), high: (*data.at(1)).try_into().unwrap(),
                },
                price: u256 {
                    low: (*data.at(2)).try_into().unwrap(), high: (*data.at(3)).try_into().unwrap(),
                },
            };
            // Match event variant based on bid acceptance
            let (e, expected) = match is_accepted {
                true => (
                    OptionRound::Event::AuctionAcceptedBid(e_inner),
                    OptionRound::Event::AuctionAcceptedBid(expected_inner)
                ),
                false => (
                    OptionRound::Event::AuctionRejectedBid(e_inner),
                    OptionRound::Event::AuctionRejectedBid(expected_inner)
                ),
            };
            // Assert events are equal
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check AuctionEnd emits correctly
fn assert_event_auction_end(option_round_address: ContractAddress, clearing_price: u256) {
    match pop_log::<OptionRound::AuctionEnd>(option_round_address) {
        Option::Some(e) => {
            let e = OptionRound::Event::AuctionEnd(e);
            let expected = OptionRound::Event::AuctionEnd(
                OptionRound::AuctionEnd { clearing_price }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check OptionSettle emits correctly
// @dev Settlment price is the price determining the payout for the round
fn assert_event_option_settle(option_round_address: ContractAddress, settlement_price: u256) {
    match pop_log::<OptionRound::OptionSettle>(option_round_address) {
        Option::Some(e) => {
            let e = OptionRound::Event::OptionSettle(e);
            let expected = OptionRound::Event::OptionSettle(
                OptionRound::OptionSettle { settlement_price }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check OptionTransfer::DepositLiquidty emits correctly
fn assert_event_option_deposit_liquidity(
    contract: ContractAddress, user: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => { _assert_event_option_transfer_helper(contract, keys, data, user, amount, 0); },
        Option::None => { panic(array!['No events found']); },
    }
}

// Check OptionTransfer::WithdrawPremium emits correctly
fn assert_event_option_withdraw_premium(
    contract: ContractAddress, user: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => { _assert_event_option_transfer_helper(contract, keys, data, user, amount, 1); },
        Option::None => { panic(array!['No events found']); },
    }
}

// Check OptionTransfer::WithdrawPayout emits correctly
fn assert_event_option_withdraw_payout(
    contract: ContractAddress, user: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => { _assert_event_option_transfer_helper(contract, keys, data, user, amount, 2); },
        Option::None => { panic(array!['No events found']); },
    }
}

// Check OptionTransfer::WithdrawLiquidity emits correctly
// @note Note used anywhere yet, see withdraw_tests.cairo
fn assert_event_option_withdraw_liquidity(
    contract: ContractAddress, user: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => { _assert_event_option_transfer_helper(contract, keys, data, user, amount, 3); },
        Option::None => { panic(array!['No events found']); },
    }
}

// Check OptionTransfer::WithdrawUnusedBids emits correctly
fn assert_event_option_withdraw_unused_bids(
    contract: ContractAddress, user: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => { _assert_event_option_transfer_helper(contract, keys, data, user, amount, 4); },
        Option::None => { panic(array!['No events found']); },
    }
}

// Internal helper function to test all option transfer event variants
fn _assert_event_option_transfer_helper(
    contract: ContractAddress,
    keys: Span<felt252>,
    data: Span<felt252>,
    user: ContractAddress,
    amount: u256,
    event_type: u8
) {
    let e_inner = OptionRound::OptionTransferEvent {
        user: (*keys.at(1)).try_into().unwrap(),
        amount: u256 {
            low: (*data.at(0)).try_into().unwrap(), high: (*data.at(1)).try_into().unwrap()
        },
    };
    let expected_inner = OptionRound::OptionTransferEvent { user, amount };
    let (e, expected) = match event_type {
        0 => (
            OptionRound::Event::DepositLiquidity(e_inner),
            OptionRound::Event::DepositLiquidity(expected_inner)
        ),
        1 => (
            OptionRound::Event::WithdrawPremium(e_inner),
            OptionRound::Event::WithdrawPremium(expected_inner)
        ),
        2 => (
            OptionRound::Event::WithdrawPayout(e_inner),
            OptionRound::Event::WithdrawPayout(expected_inner)
        ),
        3 => (
            OptionRound::Event::WithdrawLiquidity(e_inner),
            OptionRound::Event::WithdrawLiquidity(expected_inner)
        ),
        4 => (
            OptionRound::Event::WithdrawUnusedBids(e_inner),
            OptionRound::Event::WithdrawUnusedBids(expected_inner)
        ),
        _ => panic(array!['Invalid event type']),
    };
    assert_events_equal(e, expected);
}


// Test transfer event (ERC20 structure) emits correctly
// @note Can remove all instances of this test that are testing eth transfers, just testing the balance changes is enough
// @note Add tests using this helper for erc20 transfer tests for options, lp tokens?
fn assert_event_transfer(
    contract: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            mut keys, mut data
        )) => {
            // Build expected event
            let expected = ERC20Component::Event::Transfer(Transfer { from, to, value });
            // Build event from details
            let event = ERC20Component::Event::Transfer(
                Transfer {
                    from: (*keys.at(1)).try_into().unwrap(),
                    to: (*keys.at(2)).try_into().unwrap(),
                    value: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: {
                            (*data.at(1)).try_into().unwrap()
                        }
                    }
                }
            );
            // Assert events are equal
            assert_events_equal(event, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Test OptionRoundCreated event emits correctly
fn assert_event_option_round_created(
    contract: ContractAddress,
    prev_round: ContractAddress,
    new_round: ContractAddress,
    //collaterized_amount: u256,
    option_round_params: OptionRoundParams
) {
    match pop_log::<Vault::OptionRoundCreated>(contract) {
        Option::Some(e) => {
            let e = Vault::Event::OptionRoundCreated(e);
            let expected = Vault::Event::OptionRoundCreated(
                Vault::OptionRoundCreated {
                    prev_round, new_round, //collaterized_amount,
                     option_round_params
                }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}


// Test VaultTransfer event emits correctly (deposit and withdraw)
// is_deposit == true for Deposit event, false for Withdrawal event
fn assert_event_vault_transfer(
    vault: ContractAddress,
    user: ContractAddress,
    total_balance_before: u256,
    total_balance_now: u256,
    is_deposit: bool
) {
    match pop_event_details(vault) {
        Option::Some((
            keys, data
        )) => {
            let e_inner: Vault::VaultTransfer = Vault::VaultTransfer {
                user: (*keys.at(1)).try_into().unwrap(),
                total_balance_before: u256 {
                    low: (*data.at(0)).try_into().unwrap(), high: (*data.at(1)).try_into().unwrap()
                },
                total_balance_now: u256 {
                    low: (*data.at(2)).try_into().unwrap(), high: (*data.at(3)).try_into().unwrap()
                }
            };
            let expected_inner = Vault::VaultTransfer {
                user, total_balance_before, total_balance_now
            };
            let (e, expected) = match is_deposit {
                true => { (Vault::Event::Deposit(e_inner), Vault::Event::Deposit(expected_inner)) },
                false => {
                    (Vault::Event::Withdrawal(e_inner), Vault::Event::Withdrawal(expected_inner))
                },
            };
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    }
}


// Accelerate to the current round auctioning (needs non 0 liquidity to start auction)
fn accelerate_to_auctioning(ref self: VaultFacade) {
    // Deposit liquidity so round 1's auction can start
    self.deposit(100 * decimals(), liquidity_provider_1());
    // Start round 1's auction
    self.start_auction();
}

// Accelerate to the current round's auction end
fn accelerate_to_running(ref self: VaultFacade) -> u256 {
    let mut current_round = self.get_current_round();
    if (current_round.get_state() != OptionRoundState::Auctioning) {
        accelerate_to_auctioning(ref self);
    }
    // Bid for all options at reserve price
    let params = current_round.get_params();
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction()
}

fn accelerate_to_settle(ref self: VaultFacade, base_fee: u256) {
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: self.get_market_aggregator()
    };
    mock_maket_aggregator_setter.set_current_base_fee(base_fee);
    self.timeskip_and_settle_round();
}


fn accelerate_to_auctioning_custom(
    ref self: VaultFacade, lps: Span<ContractAddress>, amounts: Span<u256>
) -> u256 {
    let deposit_total = self.deposit_mutltiple(lps, amounts);
    set_contract_address(vault_manager());
    self.start_auction();
    deposit_total
}

fn accelerate_to_running_custom(
    ref self: VaultFacade,
    bidders: Span<ContractAddress>,
    max_amounts: Span<u256>,
    prices: Span<u256>
) -> u256 {
    let mut current_round = self.get_current_round();
    current_round.bid_multiple(bidders, max_amounts, prices);
    let clearing_price = self.timeskip_and_end_auction();
    clearing_price
}

fn accelerate_to_settled(ref self: VaultFacade, base_fee: u256) {
    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: self.get_market_aggregator()
    };
    mock_maket_aggregator_setter.set_current_base_fee(base_fee);
    self.timeskip_and_settle_round();
}


//Create various amounts array (For bids use the function twice for price and amount)
fn create_array_linear(amount: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index = 0;
    while (index < len) {
        arr.append(amount);
        index += 1;
    };
    arr
}

fn create_array_gradient(amount: u256, step: u256, len: u32) -> Array<u256> {
    let mut arr: Array<u256> = array![];
    let mut index: u32 = 0;
    while (index < len) {
        arr.append(amount + index.into() * step);
        index += 1;
    };
    arr
}
// fn accelerate_to_auctioning_n_linear(ref self: VaultFacade, providers: u32, amount:u256){
//     deposit_n(ref self,providers,amount);
//     self.start_auction();
// }

// fn accelerate_to_auctioning_n_custom(ref self: VaultFacade, providers: u32, amounts: Array<u256>) {

//     deposit_n_custom(ref self, providers, amounts);
//     self.start_auction();
// }

// //Auction with linear bidding
// fn accelerate_to_running_n_linear(ref self: VaultFacade, providers: u32, bidders: u32,amount:u256) -> u256 {
//     let mut current_round = self.get_current_round();
//     if (current_round.get_state() != OptionRoundState::Auctioning) {
//         accelerate_to_auctioning(ref self);
//     }
//     let mut current_round = self.get_current_round();
//     let params = current_round.get_params();
//     let bid_amount = params.total_options_available;
//     let bid_price = params.reserve_price;
//     let bid_amount = bid_amount * bid_price / bidders.into();
//     bid_n(ref self,bidders,bid_amount,bid_price);
//     set_block_timestamp(params.auction_end_time + 1);
//     current_round.end_auction();
//     bid_amount
// }

// //Applies a gradient to bid price;

// fn accelerate_to_running_n_custom(
//     ref self: VaultFacade, providers: u32, bidders: u32, amounts: Array<u256>, prices: Array<u256>
// ) {
//     let mut current_round = self.get_current_round();
//     if (current_round.get_state() != OptionRoundState::Auctioning) {
//         accelerate_to_auctioning(ref self);
//     }
//     let params = current_round.get_params();
//     bid_n_custom(ref self,bidders,amounts,prices);
//     set_block_timestamp(params.auction_end_time + 1);
//     current_round.end_auction();
// }

//Auction with partial bidding

////@dev Should we create more complex helpers for creating conditions like this directly?
//fn accelerate_to_running_n_partial(
//   ref self: VaultFacade, providers: u32, bidders: u32
//) -> (u256, u256) {
//    let mut current_round = self.get_current_round();
//   if (current_round.get_state() != OptionRoundState::Auctioning) {
//      accelerate_to_auctioning(ref self);
// }
//    let params = current_round.get_params();
//   let bid_amount = params.total_options_available;
//  let bid_price = params.reserve_price;
// let bid_quant = bid_amount / bidders.into() / 2;
//    let bid_amount = bid_quant * bid_price;
//   bid_n(ref self, bidders, bid_amount, bid_price);
//  set_block_timestamp(params.auction_end_time + 1);
// current_round.end_auction();
//(bid_amount, bid_price)
//}

//fn accelerate_to_running_partial(ref self: VaultFacade) {
//   // Bid for half the options at reserve price
//  let mut current_round = self.get_current_round();
// let params = current_round.get_params();
//let bid_amount = params.total_options_available;
//    let bid_price = params.reserve_price;
//   let mut bid_quant = bid_amount / 2;
//
//   //If quant gets 0 ensure minimum bid on 1 option
//  if bid_quant < 1 {
//     bid_quant += 1;
//    }
//   let bid_amount = bid_quant * bid_price;
//  current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
//    // End auction
//   set_block_timestamp(params.auction_end_time + 1);
//  current_round.end_auction();
//}
// @note Might want to add accelerate to settled with args for settlemnt price


