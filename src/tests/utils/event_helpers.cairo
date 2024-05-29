use starknet::{testing, ContractAddress,};
use pitch_lake_starknet::{vault::{Vault}, option_round::{OptionRound}};
use openzeppelin::token::erc20::{ERC20Component, ERC20Component::Transfer};

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

// Pop the earlist event for a contract and return its details
fn pop_event_details(address: ContractAddress) -> Option<(Span<felt252>, Span<felt252>)> {
    Option::Some(testing::pop_log_raw(address)?)
}

// OptionRound Events

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

// Check AuctionAcceptedBid emits correctly
fn assert_event_auction_bid_accepted(
    contract: ContractAddress, account: ContractAddress, amount: u256, price: u256,
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => {
            let expected = OptionRound::Event::AuctionAcceptedBid(
                OptionRound::AuctionAcceptedBid { account, amount, price }
            );
            let e = OptionRound::Event::AuctionAcceptedBid(
                OptionRound::AuctionAcceptedBid {
                    account: (*keys.at(1)).try_into().unwrap(),
                    amount: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap(),
                    },
                    price: u256 {
                        low: (*data.at(2)).try_into().unwrap(),
                        high: (*data.at(3)).try_into().unwrap(),
                    },
                }
            );
            // Assert events are equal
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); }
    };
}

// Check AuctionRejectedBid emits correctly
fn assert_event_auction_bid_rejected(
    contract: ContractAddress, account: ContractAddress, amount: u256, price: u256,
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => {
            let expected = OptionRound::Event::AuctionRejectedBid(
                OptionRound::AuctionRejectedBid { account, amount, price }
            );
            let e = OptionRound::Event::AuctionRejectedBid(
                OptionRound::AuctionRejectedBid {
                    account: (*keys.at(1)).try_into().unwrap(),
                    amount: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap(),
                    },
                    price: u256 {
                        low: (*data.at(2)).try_into().unwrap(),
                        high: (*data.at(3)).try_into().unwrap(),
                    },
                }
            );
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

// Check UnusedBidsRefunded emits correctly
fn assert_event_unused_bids_refunded(
    contract: ContractAddress, account: ContractAddress, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => {
            let expected = OptionRound::Event::UnusedBidsRefunded(
                OptionRound::UnusedBidsRefunded { account, amount }
            );
            let e = OptionRound::Event::UnusedBidsRefunded(
                OptionRound::UnusedBidsRefunded {
                    account: (*keys.at(1)).try_into().unwrap(),
                    amount: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap(),
                    }
                }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// Check OptionsExercised emits correctly
fn assert_event_options_exercised(
    contract: ContractAddress, account: ContractAddress, num_options: u256, amount: u256
) {
    match pop_event_details(contract) {
        Option::Some((
            keys, data
        )) => {
            let expected = OptionRound::Event::OptionsExercised(
                OptionRound::OptionsExercised { account, num_options, amount }
            );
            let e = OptionRound::Event::OptionsExercised(
                OptionRound::OptionsExercised {
                    account: (*keys.at(1)).try_into().unwrap(),
                    num_options: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap(),
                    },
                    amount: u256 {
                        low: (*data.at(2)).try_into().unwrap(),
                        high: (*data.at(3)).try_into().unwrap(),
                    }
                }
            );
            assert_events_equal(e, expected);
        },
        Option::None => { panic(array!['No events found']); },
    }
}

// ERC20 Events

// Test transfer event (ERC20 structure) emits correctly
// @note Can remove all instances of this test that are testing eth transfers, just testing the balance changes is enough
// @note Add tests using this helper for erc20 transfer tests for options, lp tokens later
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

// Vault Events

// Test OptionRoundCreated event emits correctly
fn assert_event_option_round_deployed(
    contract: ContractAddress, round_id: u256, address: ContractAddress,
) {
    match pop_log::<Vault::OptionRoundDeployed>(contract) {
        Option::Some(e) => {
            let e = Vault::Event::OptionRoundDeployed(e);
            let expected = Vault::Event::OptionRoundDeployed(
                Vault::OptionRoundDeployed { round_id, address, }
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
    position_balance_before: u256,
    position_balance_after: u256,
) {
    match pop_event_details(vault) {
        Option::Some((
            keys, data
        )) => {
            let e = Vault::Event::Deposit(
                Vault::Deposit {
                    account: (*keys.at(1)).try_into().unwrap(),
                    position_balance_before: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap()
                    },
                    position_balance_after: u256 {
                        low: (*data.at(2)).try_into().unwrap(),
                        high: (*data.at(3)).try_into().unwrap()
                    }
                }
            );
            assert_events_equal(
                e,
                Vault::Event::Deposit(
                    Vault::Deposit { account, position_balance_before, position_balance_after }
                )
            );
        },
        Option::None => { panic(array!['No events found']); }
    }
}

// Test withdrawal event emits correctly
fn assert_event_vault_withdrawal(
    vault: ContractAddress,
    account: ContractAddress,
    position_balance_before: u256,
    position_balance_after: u256,
) {
    match pop_event_details(vault) {
        Option::Some((
            keys, data
        )) => {
            let e = Vault::Event::Withdrawal(
                Vault::Withdrawal {
                    account: (*keys.at(1)).try_into().unwrap(),
                    position_balance_before: u256 {
                        low: (*data.at(0)).try_into().unwrap(),
                        high: (*data.at(1)).try_into().unwrap()
                    },
                    position_balance_after: u256 {
                        low: (*data.at(2)).try_into().unwrap(),
                        high: (*data.at(3)).try_into().unwrap()
                    }
                }
            );
            assert_events_equal(
                e,
                Vault::Event::Withdrawal(
                    Vault::Withdrawal { account, position_balance_before, position_balance_after }
                )
            );
        },
        Option::None => { panic(array!['No events found']); }
    }
}
