use fp::{UFixedPoint123x128, UFixedPoint123x128Impl};
use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use pitch_lake::{
    library::constants::PROGRAM_ID, fossil_client::interface::{JobRequest},
    vault::{
        contract::Vault::{L1Data},
        interface::{
            IVaultDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcher, IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        contract::OptionRound, interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait,}
    },
    fossil_client::interface::VerifierData,
    tests::{
        utils::{
            lib::{
                test_accounts::{vault_manager, liquidity_provider_1, bystander},
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}, sanity_checks,
            },
            helpers::{
                setup::{eth_supply_and_approve_all_bidders},
                general_helpers::{assert_two_arrays_equal_length, to_gwei}
            },
        },
    }
};

fn l1_data_to_verifier_data(l1_data: L1Data) -> VerifierData {
    // Convert u256->u128->UFixedPoint123x128->felt252
    let L1Data { twap, reserve_price, max_return } = l1_data;

    // u256 -> felt252
    let twap_result: felt252 = {
        let twap_u128: u128 = twap.try_into().unwrap();
        let twap_fp: UFixedPoint123x128 = twap_u128.into();
        twap_fp.try_into().unwrap()
    };

    // u256 -> felt252
    let reserve_price: felt252 = {
        let reserve_price_u128: u128 = reserve_price.try_into().unwrap();
        let reserve_price_fp: UFixedPoint123x128 = reserve_price_u128.into();
        reserve_price_fp.try_into().unwrap()
    };

    // u128 -> felt252
    // i.e 1234 -> 0.1234 -> 0.1234_felt252
    let max_return: felt252 = {
        let BPS: UFixedPoint123x128 = 10_000_u64.into(); // 10,000.0
        let max_return_fp: UFixedPoint123x128 = max_return.into()
            / BPS; // i.e 1234.0 / 10_000.0 = 0.1234; is 12.34%

        max_return_fp.try_into().unwrap()
    };

    VerifierData {
        reserve_price,
        twap_result,
        max_return,
        start_timestamp: 0xaaaa,
        end_timestamp: 0xbbbb,
        floating_point_tolerance: 'irrelevent',
        reserve_price_tolerance: 'irrelevent',
        twap_tolerance: 'irrelevent',
        gradient_tolerance: 'irrelevent',
    }
}


fn l1_data_to_verifier_data_serialized(l1_data: L1Data) -> Span<felt252> {
    let _v = l1_data_to_verifier_data(l1_data);
    let mut v: Array<felt252> = array![];
    _v.serialize(ref v);
    v.span()
}


#[derive(Drop, Copy)]
struct VaultFacade {
    vault_dispatcher: IVaultDispatcher,
}

#[generate_trait]
impl VaultFacadeImpl of VaultFacadeTrait {
    fn get_safe_dispatcher(ref self: VaultFacade) -> IVaultSafeDispatcher {
        IVaultSafeDispatcher { contract_address: self.contract_address() }
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

    fn fossil_callback(
        ref self: VaultFacade, request: Span<felt252>, result: Span<felt252>
    ) -> u256 {
        set_contract_address(self.get_fossil_client_address());
        self.vault_dispatcher.fossil_callback(request, result)
    }

    fn fossil_callback_using_l1_data(
        ref self: VaultFacade, l1_data: L1Data, timestamp: u64
    ) -> u256 {
        // job span serialized
        let mut j: Array<felt252> = array![];
        let _j = JobRequest {
            program_id: PROGRAM_ID, vault_address: self.contract_address(), timestamp
        };
        _j.serialize(ref j);

        // job result serialized
        let v = l1_data_to_verifier_data_serialized(l1_data);
        set_contract_address(self.get_fossil_client_address());
        self.vault_dispatcher.fossil_callback(j.span(), v)
    }

    #[feature("safe_dispatcher")]
    fn fossil_callback_expect_error(
        ref self: VaultFacade, request: Span<felt252>, result: Span<felt252>, error: felt252
    ) {
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_callback(request, result).expect_err(error);
    }

    #[feature("safe_dispatcher")]
    fn fossil_callback_expect_error_using_l1_data(
        ref self: VaultFacade, l1_data: L1Data, timestamp: u64, error: felt252
    ) {
        // job span serialized
        let mut job_request: Array<felt252> = array![];
        let j = JobRequest {
            program_id: PROGRAM_ID, vault_address: self.contract_address(), timestamp
        };
        j.serialize(ref job_request);

        // job result serialized
        let mut job_result: Array<felt252> = array![];

        // convert l1 data that we want back to UFixedPoint123x128 as felts
        let (twap_fp_felt, reserve_price_fp_felt): (felt252, felt252) = {
            // u256 -> u128
            let (twap_u128, reserve_price_u128): (u128, u128) = {
                (l1_data.twap.try_into().unwrap(), l1_data.reserve_price.try_into().unwrap())
            };
            // u128 -> UFixedPoint123x128
            let (twap_fp, reserve_price_fp): (UFixedPoint123x128, UFixedPoint123x128) = {
                (twap_u128.into(), reserve_price_u128.into())
            };

            // UFixedPoint123x128 -> felt252
            (twap_fp.try_into().unwrap(), reserve_price_fp.try_into().unwrap())
        };

        let max_return_fp: UFixedPoint123x128 = l1_data.max_return.into(); // i.e 1234 for 12.34%
        let BPS: UFixedPoint123x128 = 10_000_u64.into(); // 10,000.0
        let max_return_bps_fp = max_return_fp / BPS; // i.e 1234 / 10,000 = 0.1234.0
        let max_return_bps_int: u128 = max_return_bps_fp.get_integer(); // i.e 0.1234.0 -> 1234
        let max_return_fp_felt: felt252 = max_return_bps_int.into(); // u128 -> felt252

        let v = VerifierData {
            start_timestamp: 'irrelevent'.try_into().unwrap(),
            end_timestamp: 'irrelevent'.try_into().unwrap(),
            reserve_price: reserve_price_fp_felt,
            floating_point_tolerance: 'irrelevent',
            reserve_price_tolerance: 'irrelevent',
            twap_tolerance: 'irrelevent',
            gradient_tolerance: 'irrelevent',
            twap_result: twap_fp_felt,
            max_return: max_return_fp_felt
        };

        v.serialize(ref job_result);

        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_callback(job_request.span(), job_result.span()).expect_err(error);
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
        ref self: VaultFacade, job_request: Span<felt252>, verifier_data: Span<felt252>
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
        error: felt252
    ) {
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.fossil_callback(job_request, verifier_data).expect_err(error);
    }

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
}

