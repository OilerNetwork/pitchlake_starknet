use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use pitch_lake_starknet::{
    contracts::{
        vault::{VaultError, IVaultDispatcher, IVaultDispatcherTrait},
        option_round::{OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
        market_aggregator::{
            MarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
        },
    },
    tests::{
        utils::{
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait,
            },
            lib::{
                test_accounts::{vault_manager, liquidity_provider_1, bystander},
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}, sanity_checks,
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
    /// Writes ///

    /// LP functions
    fn deposit(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) -> u256 {
        // @note Previously, we were setting the contract address to bystander
        set_contract_address(liquidity_provider);
        let res = self.vault_dispatcher.deposit_liquidity(amount, liquidity_provider);

        match res {
            Result::Ok(updated_unlocked_position) => {
                sanity_checks::deposit(ref self, liquidity_provider, updated_unlocked_position)
            },
            Result::Err(e) => panic(array![e.into()]),
        }
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

    fn withdraw_raw(
        ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress
    ) -> Result<u256, VaultError> {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.withdraw_liquidity(amount)
    }

    fn withdraw(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) -> u256 {
        match self.withdraw_raw(amount, liquidity_provider) {
            Result::Ok(updated_unlocked_position) => sanity_checks::withdraw(
                ref self, liquidity_provider, updated_unlocked_position
            ),
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    fn withdraw_multiple(
        ref self: VaultFacade,
        mut amounts: Span<u256>,
        mut liquidity_providers: Span<ContractAddress>
    ) -> Array<u256> {
        assert_two_arrays_equal_length(liquidity_providers, amounts);
        let mut spreads = array![];
        loop {
            match liquidity_providers.pop_front() {
                Option::Some(liquidity_provider) => {
                    let amount = amounts.pop_front().unwrap();
                    spreads.append(self.withdraw(*amount, *liquidity_provider));
                },
                Option::None => { break (); }
            };
        };
        spreads
    }

    /// State transition

    fn start_auction(ref self: VaultFacade) -> u256 {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let res = self.vault_dispatcher.start_auction();
        match res {
            Result::Ok(total_options_available) => {
                let mut current_round = self.get_current_round();
                sanity_checks::start_auction(ref current_round, total_options_available)
            },
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    fn start_auction_raw(ref self: VaultFacade) -> Result<u256, VaultError> {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        self.vault_dispatcher.start_auction()
    }

    fn end_auction(ref self: VaultFacade) -> (u256, u256) {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let res = self.vault_dispatcher.end_auction();
        match res {
            Result::Ok((
                clearing_price, total_options_sold
            )) => {
                let mut current_round = self.get_current_round();
                sanity_checks::end_auction(ref current_round, clearing_price, total_options_sold)
            },
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    fn end_auction_raw(ref self: VaultFacade) -> Result<(u256, u256), VaultError> {
        set_contract_address(bystander());
        self.vault_dispatcher.end_auction()
    }

    fn settle_option_round(ref self: VaultFacade) -> u256 {
        // @dev Using bystander as caller so that gas fees do not throw off balance calculations
        set_contract_address(bystander());
        let mut current_round = self.get_current_round();
        let res = self.vault_dispatcher.settle_option_round();

        let res = match res {
            Result::Ok(total_payout) => sanity_checks::settle_option_round(
                ref current_round, total_payout
            ),
            Result::Err(e) => panic(array![e.into()]),
        };

        let next_round_address = self.get_option_round_address(current_round.get_round_id() + 1);
        eth_supply_and_approve_all_bidders(next_round_address, self.get_eth_address());
        res
    }

    fn settle_option_round_raw(ref self: VaultFacade) -> Result<u256, VaultError> {
        set_contract_address(bystander());
        self.vault_dispatcher.settle_option_round()
    }
    /// Fossil

    // Set the mock market aggregator data for the period of the current round
    fn set_market_aggregator_value(ref self: VaultFacade, avg_base_fee: u256) {
        set_contract_address(bystander());
        let mut current_round = self.get_current_round();
        let start_date = current_round.get_auction_start_date();
        let end_date = current_round.get_option_expiry_date();
        let market_aggregator = IMarketAggregatorSetterDispatcher {
            contract_address: self.get_market_aggregator(),
        };
        market_aggregator.set_value_without_proof(start_date, end_date, avg_base_fee);
    }

    /// LP token related

    fn convert_position_to_lp_tokens(
        ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress
    ) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.convert_position_to_lp_tokens(amount);
    }

    fn convert_lp_tokens_to_position(
        ref self: VaultFacade, source_round: u256, amount: u256, liquidity_provider: ContractAddress
    ) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.convert_lp_tokens_to_position(source_round, amount);
    }

    fn convert_lp_tokens_to_newer_lp_tokens(
        ref self: VaultFacade,
        source_round: u256,
        target_round: u256,
        amount: u256,
        liquidity_provider: ContractAddress
    ) -> u256 {
        set_contract_address(liquidity_provider);
        let res = self
            .vault_dispatcher
            .convert_lp_tokens_to_newer_lp_tokens(source_round, target_round, amount);

        match res {
            Result::Ok(lp_tokens) => lp_tokens,
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    /// Reads ///

    /// Rounds

    fn get_current_round_id(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.current_option_round_id()
    }

    fn get_option_round_address(ref self: VaultFacade, id: u256) -> ContractAddress {
        self.vault_dispatcher.get_option_round_address(id)
    }

    fn get_current_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self
            .vault_dispatcher
            .get_option_round_address(self.vault_dispatcher.current_option_round_id());
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        OptionRoundFacade { option_round_dispatcher }
    }

    fn get_next_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self
            .vault_dispatcher
            .get_option_round_address(self.vault_dispatcher.current_option_round_id() + 1);
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        OptionRoundFacade { option_round_dispatcher }
    }

    fn get_current_and_next_rounds(
        ref self: VaultFacade
    ) -> (OptionRoundFacade, OptionRoundFacade) {
        (self.get_current_round(), self.get_next_round())
    }

    /// Liquidity

    // For LPs

    fn get_lp_locked_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_lp_locked_balance(liquidity_provider)
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

    fn get_lp_unlocked_balance(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_lp_unlocked_balance(liquidity_provider)
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
        self.vault_dispatcher.get_lp_total_balance(liquidity_provider)
    }


    // @note replace this with get_lp_locked_and_unlocked_balance
    fn get_lp_locked_and_unlocked_balance(
        ref self: VaultFacade, liquidity_provider: ContractAddress
    ) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_lp_locked_balance(liquidity_provider);
        let unlocked = self.vault_dispatcher.get_lp_unlocked_balance(liquidity_provider);
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

    fn get_premiums_for(
        ref self: VaultFacade, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256 {
        self.vault_dispatcher.get_premiums_earned(liquidity_provider, round_id)
    }

    // @note add get_premiums_for_multiple()

    // For Vault

    fn get_total_locked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_locked_balance()
    }

    // @note replace this with get_vault_unlocked_balance
    fn get_total_unlocked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_unlocked_balance()
    }

    // @note replace this with get_vault_locked_and_unlocked_balance
    fn get_total_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_balance()
    }

    // @note replace this with get_vault_locked_and_unlocked_balances
    fn get_total_locked_and_unlocked_balance(ref self: VaultFacade) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_total_locked_balance();
        let unlocked = self.vault_dispatcher.get_total_unlocked_balance();
        (locked, unlocked)
    }


    /// Misc

    // @note Would be a lot of grepping, but could match Dispatcher format by making this a struct member instead of an entry point
    fn contract_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.contract_address
    }

    fn get_market_aggregator(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_market_aggregator()
    }

    // Get the market aggregator data for the period of the current round
    fn get_market_aggregator_value(ref self: VaultFacade) -> u256 {
        let market_aggregator = IMarketAggregatorDispatcher {
            contract_address: self.get_market_aggregator(),
        };
        let mut current_round = self.get_current_round();
        let start_date = current_round.get_auction_start_date();
        let end_date = current_round.get_option_expiry_date();

        match market_aggregator.get_value(start_date, end_date) {
            Result::Ok((value, _)) => value,
            Result::Err(e) => panic(array![e]),
        }
    }

    // Manager of the vault
    // @note implementation not discussed yet
    fn get_vault_manager(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.vault_manager()
    }

    // Eth contract address
    fn get_eth_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.eth_address()
    }

    // Gets the round transition period in seconds, 3 hours is a random number for testing
    // @note TODO impl this in contract later
    fn get_round_transition_period(ref self: VaultFacade) -> u64 {
        self.get_round_transition_period()
    }
}

