use core::array::ArrayTrait;
use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultDispatcherTrait};

use pitch_lake_starknet::option_round::{
    OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, testing::{set_contract_address, set_block_timestamp}};

use pitch_lake_starknet::tests::{
    utils::{liquidity_provider_1, vault_manager, decimals, assert_event_transfer},
};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait,
};
use pitch_lake_starknet::market_aggregator::{
    MarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
};

use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
#[derive(Drop, Copy)]
struct VaultFacade {
    vault_dispatcher: IVaultDispatcher,
}
#[generate_trait]
impl VaultFacadeImpl of VaultFacadeTrait {
    fn contract_address(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.contract_address
    }

    fn deposit(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.deposit_liquidity(amount);
    }

    fn withdraw(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.withdraw_liquidity(amount);
    }

    // @dev might clash when repo syncs
    // @note should return the amount of premiums/unsold liq. collected
    fn collect_premiums(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        set_contract_address(liquidity_provider);
        //self.vault_dispatcher.collect_premiums();
        100
    }

    //@note Vault manager is set as caller here so the balances are not affected for previously set addresses for provider/bidder
    //Anyone can call this function on the vault
    fn start_auction(ref self: VaultFacade) -> bool {
        set_contract_address(vault_manager());
        self.vault_dispatcher.start_auction()
    }

    fn end_auction(ref self: VaultFacade) -> u256 {
        set_contract_address(vault_manager());
        self.vault_dispatcher.end_auction()
    }

    fn settle_option_round(ref self: VaultFacade, address: ContractAddress) -> bool {
        set_contract_address(address);
        self.vault_dispatcher.settle_option_round()
    }

    fn timeskip_and_settle_round(ref self: VaultFacade) -> bool {
        set_contract_address(vault_manager());
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_params().option_expiry_time + 1);
        self.vault_dispatcher.settle_option_round()
    }

    fn timeskip_and_end_auction(ref self: VaultFacade) -> u256 {
        set_contract_address(vault_manager());
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_params().auction_end_time + 1);
        self.vault_dispatcher.end_auction();
        current_round.get_auction_clearing_price()
    }

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

    fn current_option_round_id(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.current_option_round_id()
    }

    fn get_option_round_address(ref self: VaultFacade, id: u256) -> ContractAddress {
        self.vault_dispatcher.get_option_round_address(id)
    }

    fn get_current_round_id(ref self: VaultFacade) -> u256 {
        self.vault_dispatcher.current_option_round_id()
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

    fn get_locked_liquidity(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_collateral_balance_for(liquidity_provider)
    }

    fn get_unlocked_liquidity(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        self.vault_dispatcher.get_unallocated_balance_for(liquidity_provider)
    }

    // Get lps liquidity spread (collateral, unallocated)
    fn get_all_lp_liquidity(ref self: VaultFacade, lp: ContractAddress) -> (u256, u256) {
        let collateral = self.vault_dispatcher.get_collateral_balance_for(lp);
        let unallocated = self.vault_dispatcher.get_unallocated_balance_for(lp);
        (collateral, unallocated)
    }

    // Get lps (multiple) liquidity (collateral, unallocated)
    fn get_all_liquidity_for_n(
        ref self: VaultFacade, lps: Span<ContractAddress>
    ) -> (Array<u256>, Array<u256>) {
        let mut index = 0;
        let mut arr_collateral: Array<u256> = array![];
        let mut arr_unallocated: Array<u256> = array![];
        while index < lps
            .len() {
                let collateral = self.vault_dispatcher.get_collateral_balance_for(*lps[index]);
                let unallocated = self.vault_dispatcher.get_unallocated_balance_for(*lps[index]);
                arr_collateral.append(collateral);
                arr_unallocated.append(unallocated);
            };
        (arr_collateral, arr_unallocated)
    }
    fn get_collateral_balance_for(
        ref self: VaultFacade, liquidity_provider: ContractAddress
    ) -> u256 {
        self.vault_dispatcher.get_collateral_balance_for(liquidity_provider)
    }

    fn get_unallocated_balance_for(
        ref self: VaultFacade, liquidity_provider: ContractAddress
    ) -> u256 {
        self.vault_dispatcher.get_unallocated_balance_for(liquidity_provider)
    }

    // @note Dhruv might be adding these as well

    fn get_lp_locked_balance(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        // @note update vault entry point name
        self.vault_dispatcher.get_lp_locked_balance(lp)
    }

    fn get_lp_unlocked_balance(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        // @note update vault entry point name
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

    fn get_unlocked_balance(ref self: VaultFacade) -> u256 {
      self.vault_dispatcher.get_unlocked_balance()
    }

    fn get_locked_balance(ref self: VaultFacade) -> u256 {
      self.vault_dispatcher.get_unlocked_balance()
    }

    fn get_total_balance(ref self: VaultFacade) -> u256 {
      self.vault_dispatcher.get_total_balance()
    }

    fn get_balance_spread(ref self: VaultFacade) -> (u256, u256) {
      let locked = self.vault_dispatcher.get_locked_balance();
      let unlocked = self.vault_dispatcher.get_unlocked_balance();
      (locked, unlocked)
    }

    //

    fn get_market_aggregator(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_market_aggregator()
    }


    // Gets the round transition period in seconds, 3 hours is a random number for testing
    // @note TODO impl this in contract later
    fn get_round_transition_period(ref self: VaultFacade) -> u64 {
        let minute = 60;
        let hour = 60 * minute;
        3 * hour
    }

    // might be duplicated when repo syncs
    fn get_premiums_for(ref self: VaultFacade, lp: ContractAddress) -> u256 {
        self.vault_dispatcher.get_premiums_for(lp)
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

    // Set the mock market aggregators value for the period of the current round
    fn set_market_aggregator_value(ref self: VaultFacade, avg_base_fee: u256) {
        let mut current_round = self.get_current_round();
        let start_date = current_round.round_start_date();
        let end_date = current_round.round_end_date();
        let market_aggregator = IMarketAggregatorSetterDispatcher {
            contract_address: self.get_market_aggregator(),
        };
        market_aggregator.set_value_without_proof(start_date, end_date, avg_base_fee);
    }

    fn get_market_aggregator_value(ref self: VaultFacade) -> u256 {
        let market_aggregator = IMarketAggregatorDispatcher {
            contract_address: self.get_market_aggregator(),
        };
        let mut current_round = self.get_current_round();
        let start_date = current_round.round_start_date();
        let end_date = current_round.round_end_date();

        match market_aggregator.get_value(start_date, end_date) {
            Result::Ok((value, _)) => value,
            Result::Err(e) => panic(array![e]),
        }
    }
}

