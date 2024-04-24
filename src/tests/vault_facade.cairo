use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultDispatcherTrait};

use pitch_lake_starknet::option_round::{
    OptionRound, OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, testing::{set_contract_address,set_block_timestamp}};

use pitch_lake_starknet::tests::utils::{
    liquidity_provider_1, vault_manager, decimals, assert_event_transfer
};

use pitch_lake_starknet::market_aggregator::{
    IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait
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

    fn timeskip_and_settle_round(ref self:VaultFacade)-> bool {
        let mut current_round = self.get_current_round();
         set_block_timestamp(current_round.get_params().option_expiry_time + 1);
         self.vault_dispatcher.settle_option_round()

    }

    fn timeskip_and_end_auction(ref self:VaultFacade)-> u256 {
        let mut current_round = self.get_current_round();
        set_block_timestamp(current_round.get_params().auction_end_time + 1);
        self.vault_dispatcher.end_auction()
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

    fn get_market_aggregator(ref self: VaultFacade) -> ContractAddress {
        self.vault_dispatcher.get_market_aggregator()
    }
}

