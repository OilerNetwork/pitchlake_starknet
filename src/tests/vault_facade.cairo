use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultDispatcherTrait};

use pitch_lake_starknet::option_round::{
    OptionRound, OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
};

use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

use starknet::{ContractAddress, testing::{set_contract_address}};

use pitch_lake_starknet::tests::utils::{
    liquidity_provider_1, vault_manager, decimals, assert_event_transfer
};

use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
#[derive(Drop)]
struct VaultFacade {
    vault_dispatcher: IVaultDispatcher,
    eth_dispatcher: IERC20Dispatcher,
}
#[generate_trait]
impl VaultFacadeImpl of VaultFacadeTrait {
    fn contract_address(ref self: VaultFacade) -> ContractAddress {
        return self.vault_dispatcher.contract_address;
    }

    fn deposit(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        let _: u256 = self.vault_dispatcher.deposit_liquidity(amount);
    }

    fn withdraw(ref self: VaultFacade, amount: u256, liquidity_provider: ContractAddress) {
        set_contract_address(liquidity_provider);
        self.vault_dispatcher.withdraw_liquidity(amount);
    }

    fn start_auction(ref self: VaultFacade) -> bool {
        set_contract_address(vault_manager());
        let result: bool = self.vault_dispatcher.start_auction();
        return result;
    }

    fn end_auction(ref self: VaultFacade) -> u256 {
        set_contract_address(vault_manager());
        let result: u256 = self.vault_dispatcher.end_auction();
        return result;
    }

    fn settle_option_round(ref self: VaultFacade, address: ContractAddress) -> bool {
        set_contract_address(address);
        let result: bool = self.vault_dispatcher.settle_option_round();
        return result;
    }
    
    fn current_option_round_id(ref self:VaultFacade)->u256 {
         return self.vault_dispatcher.current_option_round_id();
    }

    fn get_option_round_address(ref self:VaultFacade, id:u256)->ContractAddress {
        return self.vault_dispatcher.get_option_round_address(id);
    }
    fn get_current_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self
            .vault_dispatcher
            .get_option_round_address(self.vault_dispatcher.current_option_round_id());
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        return OptionRoundFacade { option_round_dispatcher };
    }
    fn get_next_round(ref self: VaultFacade) -> OptionRoundFacade {
        let contract_address = self
            .vault_dispatcher
            .get_option_round_address(self.vault_dispatcher.current_option_round_id() + 1);
        let option_round_dispatcher = IOptionRoundDispatcher { contract_address };

        return OptionRoundFacade { option_round_dispatcher };
    }

    fn get_locked_liquidity(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        return self.vault_dispatcher.get_collateral_balance_for(liquidity_provider);
    }

    fn get_unlocked_liquidity(ref self: VaultFacade, liquidity_provider: ContractAddress) -> u256 {
        return self.vault_dispatcher.get_unallocated_balance_for(liquidity_provider);
    }

    fn get_collateral_balance_for(ref self:VaultFacade, liquidity_provider:ContractAddress)->u256{
        return self.vault_dispatcher.get_collateral_balance_for(liquidity_provider);
    }

     fn get_unallocated_balance_for(ref self:VaultFacade, liquidity_provider:ContractAddress)->u256{
        return self.vault_dispatcher.get_unallocated_balance_for(liquidity_provider);
    }
}

