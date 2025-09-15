use core::array::SpanTrait;
use openzeppelin_token::erc20::ERC20Component;
use openzeppelin_token::erc20::ERC20Component::Transfer;
use pitch_lake::option_round::contract::OptionRound;
use pitch_lake::option_round::interface::PricingData;
use pitch_lake::vault::contract::Vault;
use pitch_lake::vault::interface::L1Data;
use starknet::{ContractAddress, testing};

/// Helpers ///

// Pop the earliest unpopped logged event for the contract as the requested type
// and checks there's no more data left on the event, preventing unaccounted params.
// Indexed event members are currently not supported, so they are ignored.
pub fn pop_log<T, +Drop<T>, impl TEvent: starknet::Event<T>>(
    address: ContractAddress,
) -> Option<T> {
    let (mut keys, mut data) = testing::pop_log_raw(address)?;
    //println!("keys: {:?}\ndata: {:?}", keys.clone(), data.clone());
    let ret = starknet::Event::deserialize(ref keys, ref data);
    assert(data.is_empty(), 'Event has extra data');
    ret
}

// Clear event logs for an array of contracts
// @dev Drops each event
pub fn clear_event_logs(mut addresses: Array<ContractAddress>) {
    loop {
        match addresses.pop_front() {
            Option::Some(addr) => {
                loop {
                    match testing::pop_log_raw(addr) {
                        Option::Some(_) => { continue; },
                        Option::None => { break; },
                    }
                }
                assert_no_events_left(addr);
            },
            Option::None => { break; },
        }
    }
}

// Assert a contract's event log is empty
pub fn assert_no_events_left(address: ContractAddress) {
    assert(testing::pop_log_raw(address).is_none(), 'Events remaining on queue');
}

// Assert 2 events of the same type are equal
pub fn assert_events_equal<T, +PartialEq<T>, +Drop<T>>(actual: T, expected: T) {
    assert(actual == expected, 'Event does not match expected');
}

/// Fossil Client Events ///
pub fn assert_fossil_callback_success_event(
    vault_address: ContractAddress, l1_data: L1Data, timestamp: u64,
) {
    // Remove the OptionRoundDeployed event that is fired before the callback success event
    let _ = pop_log::<
        Vault::OptionRoundDeployed,
    >(vault_address); // Pop the first (round deployed event)

    match pop_log::<Vault::Event>(vault_address) {
        Option::Some(e) => {
            let expected = Vault::Event::FossilCallbackSuccess(
                Vault::FossilCallbackSuccess { l1_data, timestamp },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}

/// OptionRound Events ///

// Check AuctionStart emits correctly
pub fn assert_event_auction_start(
    option_round_address: ContractAddress, starting_liquidity: u256, options_available: u256,
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::AuctionStarted(
                OptionRound::AuctionStarted { starting_liquidity, options_available },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

// Check AuctionAcceptedBid emits correctly
pub fn assert_event_auction_bid_placed(
    contract: ContractAddress,
    account: ContractAddress,
    bid_id: felt252,
    amount: u256,
    price: u256,
    bid_tree_nonce_now: u64,
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::BidPlaced(
                OptionRound::BidPlaced { account, bid_id, amount, price, bid_tree_nonce_now },
            );
            //println!("expected:\n{}\n{}\n{}\n{}\n{}", Into::<ContractAddress,
            //felt252>::into(account), bid_id, amount, price, bid_tree_nonce_now);
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

pub fn assert_event_auction_bid_updated(
    contract: ContractAddress,
    account: ContractAddress,
    bid_id: felt252,
    price_increase: u256,
    bid_tree_nonce_before: u64,
    bid_tree_nonce_now: u64,
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::BidUpdated(
                OptionRound::BidUpdated {
                    account, bid_id, price_increase, bid_tree_nonce_before, bid_tree_nonce_now,
                },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

// Check PricingDataSet emits correctly
pub fn assert_event_pricing_data_set(
    option_round_address: ContractAddress, strike_price: u256, cap_level: u128, reserve_price: u256,
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::PricingDataSet(
                OptionRound::PricingDataSet {
                    pricing_data: PricingData { strike_price, cap_level, reserve_price },
                },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}
// Check AuctionEnd emits correctly
pub fn assert_event_auction_end(
    option_round_address: ContractAddress,
    options_sold: u256,
    clearing_price: u256,
    unsold_liquidity: u256,
    clearing_bid_tree_nonce: u64,
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::AuctionEnded(
                OptionRound::AuctionEnded {
                    options_sold, clearing_price, unsold_liquidity, clearing_bid_tree_nonce,
                },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}

// Check OptionSettle emits correctly
pub fn assert_event_option_settle(
    option_round_address: ContractAddress, settlement_price: u256, payout_per_option: u256,
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::OptionRoundSettled(
                OptionRound::OptionRoundSettled { settlement_price, payout_per_option },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}

// Check UnusedBidsRefunded emits correctly
pub fn assert_event_unused_bids_refunded(
    contract: ContractAddress, account: ContractAddress, refunded_amount: u256,
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::UnusedBidsRefunded(
                OptionRound::UnusedBidsRefunded { account, refunded_amount },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

pub fn assert_event_options_tokenized(
    contract: ContractAddress, account: ContractAddress, minted_amount: u256,
) {
    // We pop here twice since the method fires a ERC20 transfer event before the OptionsTokenized
    // event
    match pop_log::<ERC20Component::Transfer>(contract) {
        Option::Some(_) => {
            match pop_log::<OptionRound::Event>(contract) {
                Option::Some(e) => {
                    let expected = OptionRound::Event::OptionsMinted(
                        OptionRound::OptionsMinted { account, minted_amount },
                    );
                    assert_events_equal(e, expected);
                },
                Option::None => { panic(array!['No events found']); },
            }
        },
        Option::None => { panic!("ERC20 event not found") },
    }
}
// Check OptionsExercised emits correctly
pub fn assert_event_options_exercised(
    contract: ContractAddress,
    account: ContractAddress,
    total_options_exercised: u256,
    mintable_options_exercised: u256,
    exercised_amount: u256,
) {
    // If the account burned erc20 tokens, we need to remove that event from the log
    if total_options_exercised > mintable_options_exercised {
        let _ = pop_log::<ERC20Component::Event>(contract);
    }

    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::OptionsExercised(
                OptionRound::OptionsExercised {
                    account, total_options_exercised, mintable_options_exercised, exercised_amount,
                },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}

/// ERC20 Events ///

// Test transfer event (ERC20 structure) emits correctly
// @note Can remove all instances of this test that are testing eth transfers, just testing the
// balance changes is enough @note Add tests using this helper for erc20 transfer tests for options,
// lp tokens later
pub fn assert_event_transfer(
    contract: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256,
) {
    match pop_log::<ERC20Component::Event>(contract) {
        Option::Some(e) => {
            let expected = ERC20Component::Event::Transfer(Transfer { from, to, value });
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

/// Vault Events ///

pub fn assert_event_option_round_deployed(
    contract: ContractAddress,
    round_id: u64,
    address: ContractAddress,
    auction_start_date: u64,
    auction_end_date: u64,
    option_settlement_date: u64,
    pricing_data: PricingData,
) {
    match pop_log::<Vault::Event>(contract) {
        Option::Some(_) => {
            assert_event_option_round_deployed_single(
                contract,
                round_id,
                address,
                auction_start_date,
                auction_end_date,
                option_settlement_date,
                pricing_data,
            );
        },
        Option::None => { panic(array!['No events found1']); },
    }
}

// Test OptionRoundCreated event emits correctly
pub fn assert_event_option_round_deployed_single(
    contract: ContractAddress,
    round_id: u64,
    address: ContractAddress,
    auction_start_date: u64,
    auction_end_date: u64,
    option_settlement_date: u64,
    pricing_data: PricingData,
) {
    match pop_log::<Vault::Event>(contract) {
        Option::Some(e) => {
            let expected = Vault::Event::OptionRoundDeployed(
                Vault::OptionRoundDeployed {
                    round_id,
                    address,
                    auction_start_date,
                    auction_end_date,
                    option_settlement_date,
                    pricing_data,
                },
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found2']); },
    };
}

// Test deposit event emits correctly
pub fn assert_event_vault_deposit(
    vault: ContractAddress,
    account: ContractAddress,
    amount: u256,
    account_unlocked_balance_now: u256,
    vault_unlocked_balance_now: u256,
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::Deposit(
                Vault::Deposit {
                    account, amount, account_unlocked_balance_now, vault_unlocked_balance_now,
                },
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Test withdrawal event emits correctly
pub fn assert_event_vault_withdrawal(
    vault: ContractAddress,
    account: ContractAddress,
    amount: u256,
    account_unlocked_balance_now: u256,
    vault_unlocked_balance_now: u256,
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::Withdrawal(
                Vault::Withdrawal {
                    account, amount, account_unlocked_balance_now, vault_unlocked_balance_now,
                },
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Test collect queued liquidity event emits correctly
pub fn assert_event_queued_liquidity_collected(
    vault: ContractAddress, account: ContractAddress, amount: u256, vault_stashed_balance_now: u256,
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::StashWithdrawn(
                Vault::StashWithdrawn { account, amount, vault_stashed_balance_now },
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Test withdrawal queued event emits correctly
pub fn assert_event_withdrawal_queued(
    vault: ContractAddress,
    account: ContractAddress,
    bps: u128,
    round_id: u64,
    account_queued_liquidity_before: u256,
    account_queued_liquidity_now: u256,
    vault_queued_liquidity_now: u256,
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::WithdrawalQueued(
                Vault::WithdrawalQueued {
                    account,
                    bps,
                    round_id,
                    account_queued_liquidity_before,
                    account_queued_liquidity_now,
                    vault_queued_liquidity_now,
                },
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}
