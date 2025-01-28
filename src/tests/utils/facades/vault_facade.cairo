use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use pitch_lake::{
    fossil_client::interface::{JobRequest, L1Data, FossilResult, FossilCallbackReturn, RoundSettledReturn},
    vault::{
        interface::{
            VaultType, IVaultDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcher,
            IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        contract::OptionRound, interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait,}
    },
    tests::{
        utils::{
            lib::{
                test_accounts::{vault_manager, liquidity_provider_1, bystander},
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}, sanity_checks,
                fossil_client_facade::{FossilClientFacade, FossilClientFacadeTrait},
            },
            helpers::{
                setup::{eth_supply_and_approve_all_bidders, FOSSIL_PROCESSOR},
                general_helpers::{assert_two_arrays_equal_length, get_erc20_balance}
            },
        },
    },
    types::{Errors, Bid},
};

#[derive(Drop, Copy)]
struct VaultFacade {
    vault_dispatcher: IVaultDispatcher,
}

#[generate_trait]
impl VaultFacadeImpl of VaultFacadeTrait {
    fn get_safe_dispatcher(ref self: VaultFacade) -> IVaultSafeDispatcher {
        IVaultSafeDispatcher { contract_address: self.contract_address() }
    }


    /// Fossil

    fn get_fossil_client_facade(ref self: VaultFacade) -> FossilClientFacade {
        FossilClientFacade { contract_address: self.vault_dispatcher.get_fossil_client_address() }
    }

    /// Option round
    
    fn get_option_round_facade(ref self: VaultFacade, round_id: u64) -> OptionRoundFacade {
        let contract_address = self.vault_dispatcher.get_round_address(round_id);
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        OptionRoundFacade { option_round_dispatcher }
    }

    /// Writes ///

    /// LP functions
    fn deposit(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) -> u256 {
        // @note Previously, we were setting the contract address to bystander
        set_contract_address(liquidity_provider);
        let updated_unlocked_position = self.vault_dispatcher.deposit(amount, liquidity_provider);
        sanity_checks::deposit(ref self, liquidity_provider, updated_unlocked_position)
    }

    fn deposit_multiple(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        assert_two_arrays_equal_length(liquidity_providers, amounts);
        let mut updated_unlocked_positions = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let amount = amounts.pop_front().unwrap();
                    updated_unlocked_positions.append(self.deposit(*amount, *liquidity_provider));
                },
                Option::None => { break (); }
            };
        };
        updated_unlocked_positions
    }

    #[feature("safe_dispatcher")]
    fn withdraw_expect_error(
        ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress, error: felt252,
    ) {
        set_contract_address(liquidity_provider);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.withdraw(amount).expect_err(error);
    }

    fn withdraw(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) -> u256 {
        set_contract_address(liquidity_provider);
        let updated_unlocked_position = self.vault_dispatcher.withdraw(amount);
        sanity_checks::withdraw(ref self, liquidity_provider, updated_unlocked_position)
    }

    fn queue_withdrawal(ref self: VaultFacade, liquidity_provider: ContractAddress, bps: u128) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.queue_withdrawal(bps);
    }

    #[feature("safe_dispatcher")]
    fn queue_withdrawal_expect_error(
        ref self: VaultFacade, liquidity_provider: ContractAddress, bps: u128, error: felt252,
    ) {
        set_contract_address(liquidity_provider);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.queue_withdrawal(bps).expect_err(error);
    }


    fn withdraw_multiple(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        assert_two_arrays_equal_length(liquidity_providers, amounts);
        let mut unlocked_bals = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let amount = amounts.pop_front().unwrap();
                    unlocked_bals.append(self.withdraw(*amount, *liquidity_provider));
                },
                Option::None => { break (); }
            };
        };
        unlocked_bals
    }

    fn queue_multiple_withdrawals(
        ref self: VaultFacade,
        mut liquidity_providers: Span<ContractAddress>,
        mut bps_multi: Span<u128>
    ) {
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(lp) => {
                    let bps = bps_multi.pop_front().unwrap();
                    self.queue_withdrawal(*lp, *bps);
                },
                Option::None => { break (); }
            };
        };
    }

    fn claim_queued_liquidity(ref self: VaultFacade, account: ContractAddress) -> u256 {
        let expected_stashed_amount = self.get_lp_stashed_balance(account);
        let actual_stashed_amount = self.vault_dispatcher.withdraw_stash(account);
        sanity_checks::claim_queued_liquidity(
            ref self, expected_stashed_amount, actual_stashed_amount
        )
    }


    /// State transition

    fn fossil_client_callback(ref self: VaultFacade, l1_data: L1Data, timestamp: u64) -> FossilCallbackReturn {
        self.vault_dispatcher.fossil_client_callback(l1_data, timestamp)
    }

    #[feature("safe_dispatcher")]
    fn fossil_client_callback_expect_error(
        ref self: VaultFacade, l1_data: L1Data, timestamp: u64, error: felt252
    ) {
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_client_callback(l1_data, timestamp).expect_err(error);
    }

    fn start_auction(ref self: VaultFacade) -> u256 {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let mut current_round = self.get_current_round();
        let total_options_available = self.vault_dispatcher.start_auction();
        sanity_checks::start_auction(ref current_round, total_options_available)
    }

    #[feature("safe_dispatcher")]
    fn start_auction_expect_error(ref self: VaultFacade, error: felt252) {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.start_auction().expect_err(error);
    }

    fn end_auction(ref self: VaultFacade) -> (u256, u256) {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let (clearing_price, total_options_sold) = self.vault_dispatcher.end_auction();
        let mut current_round = self.get_current_round();
        sanity_checks::end_auction(ref current_round, clearing_price, total_options_sold)
    }

    #[feature("safe_dispatcher")]
    fn end_auction_expect_error(ref self: VaultFacade, error: felt252) {
        set_contract_address(bystander());
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.end_auction().expect_err(error);
    }

    // fn settle_option_round(ref self: VaultFacade) -> u256 {
    //     // @dev Using bystander as caller so that gas fees do not throw off balance calculations
    //     set_contract_address(bystander());

    //     // Settle the current round
    //     let mut current_round = self.get_current_round();
    //     let total_payout = self.vault_dispatcher.settle_round();
    //     let total_payout = sanity_checks::settle_option_round(ref current_round, total_payout);

    //     let current_round_address = self.get_option_round_address(self.get_current_round_id());
    //     eth_supply_and_approve_all_bidders(current_round_address, self.get_eth_address());
    //     total_payout
    // }

    // #[feature("safe_dispatcher")]
    // fn settle_option_round_expect_error(ref self: VaultFacade, error: felt252) {
    //     set_contract_address(bystander());
    //     let safe_vault = self.get_safe_dispatcher();
    //     safe_vault.settle_round().expect_err(error);
    // }

    /// Fossil

    fn get_request_to_settle_round(ref self: VaultFacade) -> JobRequest {
        let mut request = self.vault_dispatcher.get_request_to_settle_round();
        Serde::deserialize(ref request).expect('failed to fetch request')
    }

    fn get_request_to_start_first_round(ref self: VaultFacade,) -> JobRequest {
        let mut request = self.vault_dispatcher.get_request_to_start_first_round();
        Serde::deserialize(ref request).expect('failed to fetch request')
    }


    /// Rounds

    fn get_current_round_id(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_current_round_id()
    }

    fn get_option_round_address(ref self: VaultFacade, id: u64) -> ContractAddress {
        self.vault_dispatcher.get_round_address(id)
    }

    fn get_current_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self.get_option_round_address(self.get_current_round_id());
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        OptionRoundFacade { option_round_dispatcher }
    }

    fn get_sold_liquidity(ref self: VaultFacade, round_id: u64) -> u256 {
        let contract_address = self.get_option_round_address(round_id);
        let round = IOptionRoundDispatcher { contract_address };

        round.get_sold_liquidity()
    }


    fn get_unsold_liquidity(ref self: VaultFacade, round_id: u64) -> u256 {
        let contract_address = self.get_option_round_address(round_id);
        let round = IOptionRoundDispatcher { contract_address };

        round.get_unsold_liquidity()
    }


    /// Liquidity

    // For LPs

    fn get_lp_locked_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_locked_balance(liquidity_provider)
    }

    fn get_lp_locked_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_locked_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); }
            };
        };
        balances
    }

    fn get_lp_queued_bps(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u128 {
        self.vault_dispatcher.get_account_queued_bps(liquidity_provider)
    }

    fn get_lp_stashed_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_stashed_balance(liquidity_provider)
    }


    fn get_lp_queued_bps_multi(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u128> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_queued_bps(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); }
            };
        };
        balances
    }

    fn get_lp_stashed_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_stashed_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); }
            }
        };
        balances
    }

    fn get_lp_unlocked_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider)
    }

    fn get_lp_unlocked_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_unlocked_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); }
            };
        };
        balances
    }

    fn get_lp_total_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_total_balance(liquidity_provider)
    }

    fn get_lp_locked_and_unlocked_balance(
        ref self: VaultFacade, liquidity_provider: ContractAddress
    ) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_account_locked_balance(liquidity_provider);
        let unlocked = self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider);
        (locked, unlocked)
    }

    // @note replace this with get_lp_locked_and_unlocked_balances
    fn get_lp_locked_and_unlocked_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>
    ) -> Array<(u256, u256)> {
        let mut spreads = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let locked_and_unlocked = self
                        .get_lp_locked_and_unlocked_balance(*liquidity_provider);
                    spreads.append(locked_and_unlocked);
                },
                Option::None => { break (); }
            };
        };
        spreads
    }

    fn get_lp_locked_and_unlocked_and_stashed_balance(
        ref self: VaultFacade, liquidity_provider: ContractAddress
    ) -> (u256, u256, u256) {
        let locked = self.vault_dispatcher.get_account_locked_balance(liquidity_provider);
        let unlocked = self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider);
        let stashed = self.vault_dispatcher.get_account_stashed_balance(liquidity_provider);
        (locked, unlocked, stashed)
    }

    fn get_lp_locked_and_unlocked_and_stashed_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>
    ) -> Array<(u256, u256, u256)> {
        let mut spreads = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balances = self
                        .get_lp_locked_and_unlocked_and_stashed_balance(*liquidity_provider);
                    spreads.append(balances);
                },
                Option::None => { break (); }
            };
        };
        spreads
    }

    // For Vault

    fn get_total_locked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_vault_locked_balance()
    }

    // @note replace this with get_vault_unlocked_balance
    fn get_total_unlocked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_vault_unlocked_balance()
    }

    fn get_total_stashed_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_vault_stashed_balance()
    }

    fn get_vault_queued_bps(ref self: VaultFacade) -> u128 {
        self.vault_dispatcher.get_vault_queued_bps()
    }

    // @note replace this with get_vault_locked_and_unlocked_balance
    fn get_total_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_vault_total_balance()
    }

    // @note replace this with get_vault_locked_and_unlocked_balances
    fn get_total_locked_and_unlocked_balance(ref self: VaultFacade) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_vault_locked_balance();
        let unlocked = self.vault_dispatcher.get_vault_unlocked_balance();
        (locked, unlocked)
    }

    fn get_total_locked_and_unlocked_and_stashed_balance(
        ref self: VaultFacade
    ) -> (u256, u256, u256) {
        let locked = self.vault_dispatcher.get_vault_locked_balance();
        let unlocked = self.vault_dispatcher.get_vault_unlocked_balance();
        let stashed = self.vault_dispatcher.get_vault_stashed_balance();
        (locked, unlocked, stashed)
    }


    /// Misc

    // @note Would be a lot of grepping, but could match Dispatcher format by making this a struct
    // member instead of an entry point
    fn contract_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.contract_address
    }

    fn get_vault_type(ref self: VaultFacade) -> VaultType {
        self.vault_dispatcher.get_vault_type()
    }

    fn get_alpha(ref self: VaultFacade) -> u128 {
        self.vault_dispatcher.get_alpha()
    }

    fn get_strike_level(ref self: VaultFacade) -> i128 {
        self.vault_dispatcher.get_strike_level()
    }

    // Eth contract address
    fn get_eth_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_eth_address()
    }

    // Get the address of the Fossil Client contract
    fn get_fossil_client_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_fossil_client_address()
    }


    fn get_auction_run_time(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_auction_duration()
    }

    fn get_option_run_time(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_round_duration()
    }

    // Gets the round transition period in seconds, 3 hours is a random number for testing
    // @note TODO impl this in contract later
    fn get_round_transition_period(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_round_transition_duration()
    }

    /// Option Buyer Functions

    fn place_bid(
        ref self: VaultFacade, amount: u256, price: u256, bidder: ContractAddress,
    ) -> Bid {
        set_contract_address(bidder);
        let bid = self.vault_dispatcher.place_bid(amount, price);
        let mut current_round = self.get_current_round();
        sanity_checks::place_bid(ref current_round, bid)
    }

    fn place_bids(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
    ) -> Array<Bid> {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let mut results = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    let bid_id = self.place_bid(*bid_amount, *bid_price, *bidder);
                    results.append(bid_id);
                },
                Option::None => { break (); }
            }
        };
        results
    }

    #[feature("safe_dispatcher")]
    fn place_bid_expect_error(
        ref self: VaultFacade,
        amount: u256,
        price: u256,
        bidder: ContractAddress,
        error: felt252,
    ) {
        set_contract_address(bidder);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.place_bid(amount, price).expect_err(error);
    }

    #[feature("safe_dispatcher")]
    fn place_bids_ignore_errors(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
    ) {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let safe_vault = self.get_safe_dispatcher();

        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    set_contract_address(*bidder);
                    match safe_vault.place_bid(*bid_amount, *bid_price) {
                        Result::Ok(_) => {},
                        Result::Err(_) => {}
                    }
                },
                Option::None => { break (); }
            }
        }
    }

    #[feature("safe_dispatcher")]
    fn place_bids_expect_error(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut prices: Span<u256>,
        mut bidders: Span<ContractAddress>,
        mut errors: Span<felt252>,
    ) {
        assert_two_arrays_equal_length(bidders, amounts);
        assert_two_arrays_equal_length(bidders, prices);
        let safe_vault = self.get_safe_dispatcher();
        
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    set_contract_address(*bidder);
                    let bid_amount = amounts.pop_front().unwrap();
                    let bid_price = prices.pop_front().unwrap();
                    let error = errors.pop_front().unwrap();
                    safe_vault.place_bid(*bid_amount, *bid_price).expect_err(*error);
                },
                Option::None => { break (); }
            }
        };
    }

    fn update_bid(
        ref self: VaultFacade,
        bid_id: felt252,
        price_increase: u256,
    ) -> Bid {
        let mut current_round = self.get_current_round();
        let old_bid = current_round.get_bid_details(bid_id);
        let bidder = old_bid.owner;
        set_contract_address(bidder);
        let new_bid = self.vault_dispatcher.update_bid(bid_id, price_increase);
        sanity_checks::update_bid(ref current_round, old_bid, new_bid)
    }

    #[feature("safe_dispatcher")]
    fn update_bid_expect_error(
        ref self: VaultFacade,
        bid_id: felt252,
        price_increase: u256,
        bidder: ContractAddress,
        error: felt252,
    ) {
        set_contract_address(bidder);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.update_bid(bid_id, price_increase).expect_err(error);
    }

    fn refund_bid(ref self: VaultFacade, option_bidder_buyer: ContractAddress) -> u256 {
        set_contract_address(option_bidder_buyer);
        let mut current_round = self.get_current_round();
        let refundable_balance = current_round.get_refundable_balance_for(option_bidder_buyer);
        let refunded_amount = self.vault_dispatcher.refund_unused_bids(
            current_round.contract_address(), 
            option_bidder_buyer
        );
        sanity_checks::refund_bid(ref current_round, refunded_amount, refundable_balance)
    }

    #[feature("safe_dispatcher")]
    fn refund_bid_expect_error(
        ref self: VaultFacade,
        option_bidder_buyer: ContractAddress,
        error: felt252,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_vault = self.get_safe_dispatcher();
        let mut current_round = self.get_current_round();
        safe_vault.refund_unused_bids(
            current_round.contract_address(),
            option_bidder_buyer
        ).expect_err(error);
    }

    fn refund_bids(ref self: VaultFacade, mut bidders: Span<ContractAddress>) -> Array<u256> {
        let mut refund_amounts = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => {
                    let refund_amount = self.refund_bid(*bidder);
                    refund_amounts.append(refund_amount)
                },
                Option::None => { break (); }
            }
        };
        refund_amounts
    }

    fn exercise_options(ref self: VaultFacade, option_bidder_buyer: ContractAddress, ref round: OptionRoundFacade) -> u256 {
        set_contract_address(option_bidder_buyer);
        let individual_payout = round.get_payout_balance_for(option_bidder_buyer);
        let exercised_amount = self.vault_dispatcher.exercise_options(round.contract_address());
        sanity_checks::exercise_options(ref round, exercised_amount, individual_payout)
    }

    #[feature("safe_dispatcher")]
    fn exercise_options_expect_error(
        ref self: VaultFacade,
        option_bidder_buyer: ContractAddress,
        error: felt252,
        ref round: OptionRoundFacade
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.exercise_options(round.contract_address()).expect_err(error);
    }

    fn exercise_options_multiple(
        ref self: VaultFacade, mut bidders: Span<ContractAddress>, ref round: OptionRoundFacade
    ) -> Array<u256> {
        let mut payouts = array![];
        loop {
            match bidders.pop_front() {
                Option::Some(bidder) => { payouts.append(self.exercise_options(*bidder, ref round)); },
                Option::None => { break (); }
            }
        };
        payouts
    }

    fn mint_options(ref self: VaultFacade, option_bidder_buyer: ContractAddress, ref round: OptionRoundFacade) -> u256 {
        set_contract_address(option_bidder_buyer);
        let option_erc20_balance_before = get_erc20_balance(
            round.contract_address(), 
            option_bidder_buyer
        );
        
        let options_minted = self.vault_dispatcher.mint_options(round.contract_address());
        
        sanity_checks::tokenize_options(
            ref round,
            option_bidder_buyer,
            option_erc20_balance_before,
            options_minted,
        )
    }

    #[feature("safe_dispatcher")]
    fn mint_options_expect_error(
        ref self: VaultFacade,
        option_bidder_buyer: ContractAddress,
        error: felt252,
        ref round: OptionRoundFacade,
    ) {
        set_contract_address(option_bidder_buyer);
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.mint_options(round.contract_address()).expect_err(error);
    }
}

