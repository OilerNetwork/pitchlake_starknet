use core::clone::Clone;
use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultDispatcherTrait,
};


use pitch_lake_starknet::option_round::{
    OptionRound, OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
    IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait
};

use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use starknet::{
    ContractAddress,
    testing::{ set_contract_address}
};

use pitch_lake_starknet::tests::utils::{
    liquidity_provider_1,  vault_manager, decimals, assert_event_transfer
};


#[derive(Drop)]
struct VaultFacade{
    vault_dispatcher:IVaultDispatcher,
    eth_dispatcher: IERC20Dispatcher,
}
#[generate_trait]
impl VaultFacadeImpl of VaultFacadeTrait {
    fn deposit(ref self:VaultFacade, amount:u256, liquidity_provider:ContractAddress){
    set_contract_address(liquidity_provider);
     let _:u256 = self.vault_dispatcher.deposit_liquidity(amount);
    }
    fn withdraw(ref self:VaultFacade, amount:u256, liquidity_provider:ContractAddress){

    set_contract_address(liquidity_provider);
    self.vault_dispatcher.withdraw_liquidity(amount);
}

fn start_auction(ref self:VaultFacade)->bool{
    set_contract_address(vault_manager());
    let result:bool = self.vault_dispatcher.start_auction();
    return result;
}

fn end_auction(ref self:VaultFacade)->u256{
    set_contract_address(vault_manager());
    let result:u256 = self.vault_dispatcher.end_auction();
    return result;
}

fn settle_option_round(ref self:VaultFacade, address:ContractAddress)->bool{
    
    set_contract_address(address);
    let result:bool = self.vault_dispatcher.settle_option_round();
    return result;
}

fn checkDeposit(ref self:VaultFacade, amount:u256,liquidity_provider:ContractAddress){
    
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: self.vault_dispatcher
            .get_option_round_address(self.vault_dispatcher.current_option_round_id() + 1)
    };
    let initial_lp_balance: u256 = self.eth_dispatcher.balance_of(liquidity_provider_1());
    let initial_round_balance: u256 = self.eth_dispatcher.balance_of(option_round.contract_address);
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    set_contract_address(liquidity_provider_1());
    self.vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Final balances
    let final_lp_balance: u256 = self.eth_dispatcher.balance_of(liquidity_provider_1());
    let final_round_balance: u256 = self.eth_dispatcher.balance_of(option_round.contract_address);
    // Assertions
    assert(
        final_lp_balance == initial_lp_balance - deposit_amount_wei, 'LP balance should decrease'
    );
    assert(
        final_round_balance == initial_round_balance + deposit_amount_wei,
        'Round balance should increase'
    );
    assert_event_transfer(
        liquidity_provider_1(), option_round.contract_address, deposit_amount_wei
    );
}

}

