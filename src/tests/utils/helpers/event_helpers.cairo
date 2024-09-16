use core::array::SpanTrait;
use starknet::{testing, ContractAddress,};
use openzeppelin::{
    utils::serde::SerializedAppend, token::erc20::{ERC20Component, ERC20Component::Transfer}
};
use pitch_lake_starknet::{vault::contract::Vault, option_round::contract::OptionRound,};
use debug::PrintTrait;
// Helpers

// Pop the earliest unpopped logged event for the contract as the requested type
// and checks there's no more data left on the event, preventing unaccounted params.
// Indexed event members are currently not supported, so they are ignored.
fn pop_log<T, +Drop<T>, impl TEvent: starknet::Event<T>>(address: ContractAddress) -> Option<T> {
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

// OptionRound Events

// Check AuctionStart emits correctly
fn assert_event_auction_start(
    option_round_address: ContractAddress, starting_liquidity: u256, options_available: u256
) {
    // @note Confirm this works (fix from discord), then work into other event assertions (should handle manual ones as well)
    // @note Reminder to clear event logs at the end of the accelerators
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::AuctionStarted(
                OptionRound::AuctionStarted { starting_liquidity, options_available }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

// Check AuctionAcceptedBid emits correctly
fn assert_event_auction_bid_placed(
    contract: ContractAddress,
    account: ContractAddress,
    bid_id: felt252,
    amount: u256,
    price: u256,
    bid_tree_nonce_now: u64
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::BidPlaced(
                OptionRound::BidPlaced { account, bid_id, amount, price, bid_tree_nonce_now }
            );
            //println!("expected:\n{}\n{}\n{}\n{}\n{}", Into::<ContractAddress, felt252>::into(account), bid_id, amount, price, bid_tree_nonce_now);
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); },
    }
}

fn assert_event_auction_bid_updated(
    contract: ContractAddress,
    account: ContractAddress,
    bid_id: felt252,
    price_increase: u256,
    bid_tree_nonce_now: u64,
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::BidUpdated(
                OptionRound::BidUpdated { account, bid_id, price_increase, bid_tree_nonce_now }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['Could not find event']); }
    }
}

// Check AuctionRejectedBid emits correctly
//fn assert_event_auction_bid_rejected(
//    contract: ContractAddress, account: ContractAddress, amount: u256, price: u256,
//) {
//    match pop_log::<OptionRound::Event>(contract) {
//        Option::Some(e) => {
//            let expected = OptionRound::Event::BidRejected(
//                OptionRound::BidRejected { account, amount, price }
//            );
//            assert_events_equal(e, expected);
//        },
//        Option::None => { panic(array!['Could not find event']); },
//    }
//}

// Check AuctionEnd emits correctly
fn assert_event_auction_end(
    option_round_address: ContractAddress,
    options_sold: u256,
    clearing_price: u256,
    unsold_liquidity: u256
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::AuctionEnded(
                OptionRound::AuctionEnded { options_sold, clearing_price, unsold_liquidity }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check OptionSettle emits correctly
// @dev Settlment price is the price determining the payout for the round
fn assert_event_option_settle(
    option_round_address: ContractAddress, settlement_price: u256, payout_per_option: u256,
) {
    match pop_log::<OptionRound::Event>(option_round_address) {
        Option::Some(e) => {
            let expected = OptionRound::Event::OptionRoundSettled(
                OptionRound::OptionRoundSettled { settlement_price, payout_per_option }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check UnusedBidsRefunded emits correctly
fn assert_event_unused_bids_refunded(
    contract: ContractAddress, account: ContractAddress, refunded_amount: u256
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::UnusedBidsRefunded(
                OptionRound::UnusedBidsRefunded { account, refunded_amount }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

fn assert_event_options_tokenized(
    contract: ContractAddress, account: ContractAddress, minted_amount: u256
) {
    // We pop here twice since the method fires a ERC20 transfer event before the OptionsTokenized event
    match pop_log::<ERC20Component::Transfer>(contract) {
        Option::Some(_) => {
            match pop_log::<OptionRound::Event>(contract) {
                Option::Some(e) => {
                    let expected = OptionRound::Event::OptionsMinted(
                        OptionRound::OptionsMinted { account, minted_amount }
                    );
                    assert_events_equal(e, expected);
                },
                Option::None => { panic(array!['No events found']); },
            }
        },
        Option::None => { panic!("ERC20 event not found") }
    }
}
// Check OptionsExercised emits correctly
fn assert_event_options_exercised(
    contract: ContractAddress,
    account: ContractAddress,
    number_of_options: u256,
    exercised_amount: u256
) {
    match pop_log::<OptionRound::Event>(contract) {
        Option::Some(e) => {
            let expected = OptionRound::Event::OptionsExercised(
                OptionRound::OptionsExercised { account, number_of_options, exercised_amount }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    };
}

// ERC20 Events

// Test transfer event (ERC20 structure) emits correctly
// @note Can remove all instances of this test that are testing eth transfers, just testing the balance changes is enough
// @note Add tests using this helper for erc20 transfer tests for options, lp tokens later
fn assert_event_transfer(
    contract: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    match pop_log::<ERC20Component::Event>(contract) {
        Option::Some(e) => {
            let expected = ERC20Component::Event::Transfer(Transfer { from, to, value });
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Vault Events

// Test OptionRoundCreated event emits correctly
fn assert_event_option_round_deployed(
    contract: ContractAddress,
    round_id: u256,
    address: ContractAddress,
    reserve_price: u256,
    strike_price: u256,
    cap_level: u128,
    auction_start_date: u64,
    auction_end_date: u64,
    option_settlement_date: u64,
) {
    match pop_log::<Vault::Event>(contract) {
        Option::Some(e) => {
            let expected = Vault::Event::OptionRoundDeployed(
                Vault::OptionRoundDeployed {
                    round_id,
                    address,
                    reserve_price,
                    strike_price,
                    cap_level,
                    auction_start_date,
                    auction_end_date,
                    option_settlement_date
                }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Test deposit event emits correctly
fn assert_event_vault_deposit(
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
                    account, amount, account_unlocked_balance_now, vault_unlocked_balance_now
                }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    }
}

// Test withdrawal event emits correctly
fn assert_event_vault_withdrawal(
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
                    account, amount, account_unlocked_balance_now, vault_unlocked_balance_now
                }
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    }
}

// Test collect queued liquidity event emits correctly
fn assert_event_queued_liquidity_collected(
    vault: ContractAddress, account: ContractAddress, amount: u256, vault_stashed_balance_now: u256,
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::StashWithdrawn(
                Vault::StashWithdrawn { account, amount, vault_stashed_balance_now }
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    }
}

// Test withdrawal queued event emits correctly
fn assert_event_withdrawal_queued(
    vault: ContractAddress,
    account: ContractAddress,
    bps: u16,
    account_queued_liquidity_now: u256,
    vault_queued_liquidity_now: u256
) {
    match pop_log::<Vault::Event>(vault) {
        Option::Some(e) => {
            let expected = Vault::Event::WithdrawalQueued(
                Vault::WithdrawalQueued {
                    account, bps, account_queued_liquidity_now, vault_queued_liquidity_now
                }
            );

            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    }
}
