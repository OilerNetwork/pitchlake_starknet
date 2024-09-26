use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};
use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use pitch_lake::{
    vault::{
        interface::{
            IVaultDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcher, IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        contract::OptionRound, interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait,}
    },
    fact_registry::{
        contract::{FactRegistry},
        interface::{JobRequest, IFactRegistryDispatcher, IFactRegistryDispatcherTrait,}
    },
    tests::{
        utils::{
            lib::{
                test_accounts::{vault_manager, liquidity_provider_1, bystander},
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                fact_registry_facade::{FactRegistryFacade, FactRegistryFacadeTrait}, sanity_checks,
            },
            helpers::{
                setup::eth_supply_and_approve_all_bidders,
                general_helpers::{assert_two_arrays_equal_length}
            },
        },
    }
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

    fn queue_withdrawal(ref self: VaultFacade, liquidity_provider: ContractAddress, bps: u16) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.queue_withdrawal(bps);
    }

    #[feature("safe_dispatcher")]
    fn queue_withdrawal_expect_error(
        ref self: VaultFacade, liquidity_provider: ContractAddress, bps: u16, error: felt252,
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
        mut bps_multi: Span<u16>
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

    fn refresh_round_pricing_data(ref self: VaultFacade, job_request: JobRequest) {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        self.vault_dispatcher.refresh_round_pricing_data(job_request);
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

    fn settle_option_round(ref self: VaultFacade, job_request: JobRequest) -> u256 {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());

        let total_payout = if self.get_current_round_id().is_non_zero() {
            let mut current_round = self.get_current_round();
            let total_payout = self.vault_dispatcher.settle_round(job_request);
            sanity_checks::settle_option_round(ref current_round, total_payout)
        } else {
            self.vault_dispatcher.settle_round(job_request)
        };

        // Settle the current round

        let current_round_address = self.get_option_round_address(self.get_current_round_id());
        eth_supply_and_approve_all_bidders(current_round_address, self.get_eth_address());
        total_payout
    }

    #[feature("safe_dispatcher")]
    fn settle_option_round_expect_error(
        ref self: VaultFacade, job_request: JobRequest, error: felt252
    ) {
        set_contract_address(bystander());
        let safe_vault = self.get_safe_dispatcher();
        safe_vault.settle_round(job_request).expect_err(error);
    }

    /// Fossil

    fn get_fact_registry_facade(ref self: VaultFacade) -> FactRegistryFacade {
        FactRegistryFacade { contract_address: self.get_fact_registry_address() }
    }


    /// Rounds

    fn get_current_round_id(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_current_round_id()
    }

    fn get_option_round_address(ref self: VaultFacade, id: u256) -> ContractAddress {
        self.vault_dispatcher.get_round_address(id)
    }

    fn get_current_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self.get_option_round_address(self.get_current_round_id());
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        OptionRoundFacade { option_round_dispatcher }
    }

    fn get_unsold_liquidity(ref self: VaultFacade, round_id: u256) -> u256 {
        // @note Temp fix, can move this function to round facade
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

    fn get_lp_queued_bps(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u16 {
        self.vault_dispatcher.get_account_queued_bps(liquidity_provider)
    }

    fn get_lp_stashed_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_account_stashed_balance(liquidity_provider)
    }


    fn get_lp_queued_bps_multi(
        ref self: VaultFacade, mut liquidity_providers: Span<ContractAddress>,
    ) -> Array<u16> {
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


    // @note replace this with get_lp_locked_and_unlocked_balance
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


    // @note add get_premiums_for_multiple()

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

    fn get_vault_queued_bps(ref self: VaultFacade) -> u16 {
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

    fn get_fact_registry_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_fact_registry_address()
    }

    // Eth contract address
    fn get_eth_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_eth_address()
    }

    fn get_auction_run_time(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_auction_run_time()
    }

    fn get_option_run_time(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_option_run_time()
    }

    // Gets the round transition period in seconds, 3 hours is a random number for testing
    // @note TODO impl this in contract later
    fn get_round_transition_period(ref self: VaultFacade) -> u64 {
        self.vault_dispatcher.get_round_transition_period()
    }
}

