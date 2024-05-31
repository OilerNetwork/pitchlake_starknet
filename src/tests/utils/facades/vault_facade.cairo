use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use pitch_lake_starknet::{
    vault::{IVaultDispatcher, IVaultDispatcherTrait},
    option_round::{OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,},
    market_aggregator::{
        MarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
    },
    tests::{
        utils::{
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait,
            },
            test_accounts::{liquidity_provider_1}, variables::{vault_manager, decimals},
            facades::{option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},}
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
    fn deposit(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.deposit_liquidity(amount);
    }

    fn deposit_mutltiple(
        ref self: VaultFacade, mut lps: Span<ContractAddress>, mut amounts: Span<u256>
    ) -> u256 {
        assert(lps.len() == amounts.len(), 'Incorrect lengths');
        let mut total = 0;
        loop {
            match lps.pop_front() {
                Option::Some(lp) => {
                    let amount = amounts.pop_front().unwrap();
                    total += *amount;
                    self.deposit(*amount, *lp);
                },
                Option::None => { break (); }
            };
        };
        total
    }

    fn withdraw(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.withdraw_liquidity(amount);
    }

    fn withdraw_multiple(
        ref self: VaultFacade, mut amounts: Span<u256>, mut lps: Span<ContractAddress>
    ) {
        assert(lps.len() == amounts.len(), 'Incorrect lengths');
        loop {
            match lps.pop_front() {
                Option::Some(lp) => {
                    let amount = amounts.pop_front().unwrap();
                    self.withdraw(*amount, *lp);
                },
                Option::None => { break (); }
            };
        };
    }

    /// State transition

    fn start_auction(ref self: VaultFacade) -> u256 {
        // @dev Using vault manager as caller so that gas fees do not throw off balance calculations
        set_contract_address(vault_manager());
        let res = self.vault_dispatcher.start_auction();
        match res {
            Result::Ok(total_options_available) => total_options_available,
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    fn end_auction(ref self: VaultFacade) -> (u256, u256) {
        // @dev Using vault manager as caller so that gas fees do not throw off balance calculations
        set_contract_address(vault_manager());
        let res = self.vault_dispatcher.end_auction();
        match res {
            Result::Ok((
                clearing_price, total_options_sold
            )) => (clearing_price, total_options_sold),
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    fn settle_option_round(ref self: VaultFacade) -> u256 {
        // @dev Using vault manager as caller so that gas fees do not throw off balance calculations
        set_contract_address(vault_manager());
        let res = self.vault_dispatcher.settle_option_round();
        match res {
            Result::Ok(total_payout) => total_payout,
            Result::Err(e) => panic(array![e.into()]),
        }
    }

    /// State transition with additional logic

    fn timeskip_and_settle_round(ref self: VaultFacade) -> u256 {
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_params().option_expiry_time + 1);
        self.settle_option_round()
    }

    fn timeskip_and_end_auction(ref self: VaultFacade) -> (u256, u256) {
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_params().auction_end_time + 1);
        self.end_auction()
    }

    /// Fossil

    // Set the mock market aggregator data for the period of the current round
    fn set_market_aggregator_value(ref self: VaultFacade, avg_base_fee: u256) {
        let mut current_round = self.get_current_round();
        let start_date = current_round.get_auction_start_date();
        let end_date = current_round.get_option_expiry_date();
        let market_aggregator = IMarketAggregatorSetterDispatcher {
            contract_address: self.get_market_aggregator(),
        };
        market_aggregator.set_value_without_proof(start_date, end_date, avg_base_fee);
    }

    /// LP token related

    fn convert_position_to_lp_tokens(ref self: VaultFacade, amount: u256, lp: ContractAddress) {
        set_contract_address(lp);
        self.vault_dispatcher.convert_position_to_lp_tokens(amount);
    }

    fn convert_lp_tokens_to_position(
        ref self: VaultFacade, source_round: u256, amount: u256, lp: ContractAddress
    ) {
        set_contract_address(lp);
        self.vault_dispatcher.convert_lp_tokens_to_position(source_round, amount);
    }

    fn convert_lp_tokens_to_newer_lp_tokens(
        ref self: VaultFacade,
        source_round: u256,
        target_round: u256,
        amount: u256,
        lp: ContractAddress
    ) {
        set_contract_address(lp);
        self
            .vault_dispatcher
            .convert_lp_tokens_to_newer_lp_tokens(source_round, target_round, amount);
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

    fn get_lp_locked_balance(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        self.vault_dispatcher.get_lp_locked_balance(lp)
    }

    fn get_lp_unlocked_balance(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        self.vault_dispatcher.get_lp_unlocked_balance(lp)
    }

    fn get_lp_total_balance(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        self.vault_dispatcher.get_lp_total_balance(lp)
    }

    fn get_lp_balance_spread(ref self: VaultFacade, lp: ContractAddress) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_lp_locked_balance(lp);
        let unlocked = self.vault_dispatcher.get_lp_unlocked_balance(lp);
        (locked, unlocked)
    }

    fn get_lp_balance_spreads(
        ref self: VaultFacade, mut lps: Span<ContractAddress>
    ) -> (Array<u256>, Array<u256>) {
        let mut arr_locked: Array<u256> = array![];
        let mut arr_unlocked: Array<u256> = array![];

        match lps.pop_front() {
            Option::Some(lp) => {
                let (locked, unlocked) = self.get_lp_balance_spread(*lp);
                arr_locked.append(locked);
                arr_unlocked.append(unlocked);
            },
            Option::None => { return (arr_locked, arr_unlocked); }
        };

        (arr_locked, arr_unlocked)
    }

    fn get_premiums_for(ref self: VaultFacade, lp: ContractAddress, round_id: u256) -> u256 {
        self.vault_dispatcher.get_premiums_earned(lp, round_id)
    }

    // For Vault

    fn get_unlocked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_unlocked()
    }

    fn get_locked_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_locked()
    }

    fn get_total_balance(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.get_total_balance()
    }

    fn get_balance_spread(ref self: VaultFacade) -> (u256, u256) {
        let locked = self.vault_dispatcher.get_total_locked();
        let unlocked = self.vault_dispatcher.get_total_unlocked();
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

    // Gets the round transition period in seconds, 3 hours is a random number for testing
    // @note TODO impl this in contract later
    fn get_round_transition_period(ref self: VaultFacade) -> u64 {
        let minute = 60;
        let hour = 60 * minute;
        3 * hour
    }
}

