use fp::{UFixedPoint123x128, UFixedPoint123x128Impl};
use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::sanity_checks;
use pitch_lake::tests::utils::helpers::general_helpers::{assert_two_arrays_equal_length, to_gwei};
use pitch_lake::tests::utils::helpers::setup::eth_supply_and_approve_all_bidders;
use pitch_lake::tests::utils::lib::test_accounts::bystander;
use pitch_lake::vault::interface::{
    IVaultDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcher, IVaultSafeDispatcherTrait,
    JobRequest, L1Data,
};
use starknet::ContractAddress;
use starknet::testing::set_contract_address;

fn pow(base: u256, exp: u256) -> u256 {
    if exp == 0_u256 {
        return 1_u256;
    }
    let mut result = base;
    let mut e = exp - 1_u256;
    while e > 0_u256 {
        result = result * base;
        e = e - 1_u256;
    }
    result
}

#[derive(Drop, Copy)]
pub struct VaultFacade {
    pub vault_dispatcher: IVaultDispatcher,
}

// 1234_u256 -> 1234_u128 -> 1234.0 -> 1234.0_felt
fn u256_to_fp_felt(value: u256) -> felt252 {
    let value_u128: u128 = value.try_into().expect('value larger than u128');

    let value_fp: UFixedPoint123x128 = value_u128.into();

    let value_felt: felt252 = value_fp.try_into().expect('value failed from fp -> felt');

    value_felt
}

// Rounds value to ensure same bps <-> fp
// 1234 -> {low: 1234: high: 0} -> {low: 0, high: 1234} -> {low: 5_000, high: 1234}
//  -> {low: 12340000....0, high: 0} -> 0.1234.0 -> 0.1234.0_felt
// @dev without rounding, converting 1009 bps should give 0.1009, but gives 0.1008..., this ensures
// symmetry
fn u128_to_bps_fp_felt(value: u128) -> felt252 {
    // 2^128
    let TWO_POW_128: u256 = pow(2_u256, 128_u256);

    let value_u256: u256 = value.into();
    let value_scaled: u256 = value_u256 * TWO_POW_128;
    let value_rounded: u256 = value_scaled + 5_000;
    let raw: u256 = value_rounded / 10_000;

    let raw_fp: UFixedPoint123x128 = raw.into();

    let raw_fp_felt: felt252 = raw_fp.try_into().unwrap();

    raw_fp_felt
}


#[generate_trait]
pub impl VaultFacadeImpl of VaultFacadeTrait {
    fn get_safe_dispatcher(ref self: VaultFacade) -> IVaultSafeDispatcher {
        IVaultSafeDispatcher { contract_address: self.contract_address() }
    }

    // Generate a JobRequest with custom timestamp and serialize it
    fn generate_custom_job_request_serialized(
        ref self: VaultFacade, timestamp: u64,
    ) -> Span<felt252> {
        let j = JobRequest {
            program_id: self.get_program_id(),
            timestamp: timestamp,
            vault_address: self.contract_address(),
        };

        let mut serialized: Array<felt252> = array![];
        j.serialize(ref serialized);
        serialized.span()
    }

    fn generate_custom_job_result_from_l1_data_serialized(
        ref self: VaultFacade, l1_data: L1Data,
    ) -> Span<felt252> {
        let mut current_round = self.get_current_round();
        let upper_bound = current_round.get_option_settlement_date();

        let twap_range = self.get_option_run_time();
        let other_range = 3 * twap_range;

        let mut serialized: Array<felt252> = array![];

        // Add reserve price range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.reserve_price));
        // Add Twap range and value
        serialized.append((upper_bound - twap_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.twap));
        // Add max return range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u128_to_bps_fp_felt(l1_data.max_return));

        serialized.span()
    }

    fn generate_first_round_result_serialized(
        ref self: VaultFacade, l1_data: L1Data,
    ) -> Span<felt252> {
        let mut current_round = self.get_current_round();
        let upper_bound = current_round.get_deployment_date();

        let twap_range = self.get_option_run_time();
        let other_range = 3 * twap_range;

        let mut serialized: Array<felt252> = array![];

        // Add reserve price range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.reserve_price));
        // Add Twap range and value
        serialized.append((upper_bound - twap_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.twap));
        // Add max return range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u128_to_bps_fp_felt(l1_data.max_return));

        serialized.span()
    }

    fn generate_settle_round_result_serialized(
        ref self: VaultFacade, l1_data: L1Data,
    ) -> Span<felt252> {
        let mut current_round = self.get_current_round();
        let upper_bound = current_round.get_option_settlement_date();

        let twap_range = self.get_option_run_time();
        let other_range = 3 * twap_range;

        let mut serialized: Array<felt252> = array![];

        // Add reserve price range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.reserve_price));
        // Add Twap range and value
        serialized.append((upper_bound - twap_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u256_to_fp_felt(l1_data.twap));
        // Add max return range and value
        serialized.append((upper_bound - other_range).into());
        serialized.append(upper_bound.into());
        serialized.append(u128_to_bps_fp_felt(l1_data.max_return));

        serialized.span()
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
        mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u256> {
        assert_two_arrays_equal_length(liquidity_providers, amounts);
        let mut updated_unlocked_positions = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let amount = amounts.pop_front().unwrap();
                    updated_unlocked_positions.append(self.deposit(*amount, *liquidity_provider));
                },
                Option::None => { break (); },
            };
        }
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
        mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u256> {
        assert_two_arrays_equal_length(liquidity_providers, amounts);
        let mut unlocked_bals = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let amount = amounts.pop_front().unwrap();
                    unlocked_bals.append(self.withdraw(*amount, *liquidity_provider));
                },
                Option::None => { break (); },
            };
        }
        unlocked_bals
    }

    fn queue_multiple_withdrawals(
        ref self: VaultFacade,
        mut liquidity_providers: Span<ContractAddress>,
        mut bps_multi: Span<u128>,
    ) {
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(lp) => {
                    let bps = bps_multi.pop_front().unwrap();
                    self.queue_withdrawal(*lp, *bps);
                },
                Option::None => { break (); },
            };
        };
    }

    fn claim_queued_liquidity(ref self: VaultFacade, account: ContractAddress) -> u256 {
        let expected_stashed_amount = self.get_lp_stashed_balance(account);
        let actual_stashed_amount = self.vault_dispatcher.withdraw_stash(account);
        sanity_checks::claim_queued_liquidity(
            ref self, expected_stashed_amount, actual_stashed_amount,
        )
    }


    /// State transition

    fn fossil_callback(
        ref self: VaultFacade, request: Span<felt252>, result: Span<felt252>,
    ) -> u256 {
        set_contract_address(self.get_fossil_client_address());
        let payout = self.vault_dispatcher.fossil_callback(request, result);

        let mut current_round = self.get_current_round();
        eth_supply_and_approve_all_bidders(
            current_round.contract_address(), self.get_eth_address(),
        );

        payout
    }

    #[feature("safe_dispatcher")]
    fn fossil_callback_expect_error(
        ref self: VaultFacade, request: Span<felt252>, result: Span<felt252>, error: felt252,
    ) {
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_callback(request, result).expect_err(error);
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

    fn get_mock_l1_data() -> L1Data {
        L1Data { twap: to_gwei(33) / 100, max_return: 1009, reserve_price: to_gwei(11) / 10 }
    }


    fn settle_option_round(
        ref self: VaultFacade, job_request: Span<felt252>, verifier_data: Span<felt252>,
    ) -> u256 {
        // Settle the current round

        set_contract_address(self.get_fossil_client_address());

        let mut current_round = self.get_current_round();
        let total_payout = self.vault_dispatcher.fossil_callback(job_request, verifier_data);
        let total_payout = sanity_checks::settle_option_round(ref current_round, total_payout);

        let current_round_address = self.get_option_round_address(self.get_current_round_id());
        eth_supply_and_approve_all_bidders(current_round_address, self.get_eth_address());
        total_payout
    }

    #[feature("safe_dispatcher")]
    fn settle_option_round_expect_error(
        ref self: VaultFacade,
        job_request: Span<felt252>,
        verifier_data: Span<felt252>,
        error: felt252,
    ) {
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_callback(job_request, verifier_data).expect_err(error);
    }

    /// Fossil

    fn get_request_to_start_first_round_serialized(ref self: VaultFacade) -> Span<felt252> {
        self.vault_dispatcher.get_request_to_start_first_round()
    }

    fn get_request_to_settle_round_serialized(ref self: VaultFacade) -> Span<felt252> {
        self.vault_dispatcher.get_request_to_settle_round()
    }

    fn get_request_to_settle_round(ref self: VaultFacade) -> JobRequest {
        let mut request = self.get_request_to_settle_round_serialized();
        Serde::deserialize(ref request).expect('failed to fetch request')
    }

    fn get_request_to_start_first_round(ref self: VaultFacade) -> JobRequest {
        let mut request = self.get_request_to_start_first_round_serialized();
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
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_locked_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); },
            };
        }
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
                Option::None => { break (); },
            };
        }
        balances
    }

    fn get_lp_stashed_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_stashed_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); },
            }
        }
        balances
    }

    fn get_lp_unlocked_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider)
    }

    fn get_lp_unlocked_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u256> {
        let mut balances = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balance = self.get_lp_unlocked_balance(*liquidity_provider);
                    balances.append(balance);
                },
                Option::None => { break (); },
            };
        }
        balances
    }

    fn get_lp_total_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_total_balance(liquidity_provider)
    }

    fn get_lp_locked_and_unlocked_balance(
        ref self: VaultFacade, liquidity_provider: ContractAddress,
    ) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_account_locked_balance(liquidity_provider);
        let unlocked = self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider);
        (locked, unlocked)
    }

    // @note replace this with get_lp_locked_and_unlocked_balances
    fn get_lp_locked_and_unlocked_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<(u256, u256)> {
        let mut spreads = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let locked_and_unlocked = self
                        .get_lp_locked_and_unlocked_balance(*liquidity_provider);
                    spreads.append(locked_and_unlocked);
                },
                Option::None => { break (); },
            };
        }
        spreads
    }

    fn get_lp_locked_and_unlocked_and_stashed_balance(
        ref self: VaultFacade, liquidity_provider: ContractAddress,
    ) -> (u256, u256, u256) {
        let locked = self.vault_dispatcher.get_account_locked_balance(liquidity_provider);
        let unlocked = self.vault_dispatcher.get_account_unlocked_balance(liquidity_provider);
        let stashed = self.vault_dispatcher.get_account_stashed_balance(liquidity_provider);
        (locked, unlocked, stashed)
    }

    fn get_lp_locked_and_unlocked_and_stashed_balances(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<(u256, u256, u256)> {
        let mut spreads = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let balances = self
                        .get_lp_locked_and_unlocked_and_stashed_balance(*liquidity_provider);
                    spreads.append(balances);
                },
                Option::None => { break (); },
            };
        }
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
        ref self: VaultFacade,
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
        self.vault_dispatcher.get_verifier_address()
    }

    fn get_deployment_block(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_deployment_block()
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

    fn get_program_id(ref self: VaultFacade) -> felt252 {
        self.vault_dispatcher.get_program_id()
    }

    fn get_proving_delay(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_proving_delay()
    }
}
