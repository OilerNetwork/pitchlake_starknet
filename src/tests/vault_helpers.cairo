use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType
};

use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

fn deposit(ref vault_dispatcher:IVaultDispatcher, amount:u256,liquidity_provider:ContractAddress){
    set_contract_address(liquidity_provider);
    let _:u256 = vault_dispatcher.deposit_liquidity(amount);
}

fn withdraw(ref vault_dispatcher:IVaultDispatcher, amount:u256, liquidity_provider:ContractAddress){

    set_contract_address(liquidity_provider);
    vault_dispatcher.withdraw_liquidity(amount);
}

fn start_auction(ref vault_dispatcher:IVaultDispatcher, amount:u256, vault_manager:ContractAddress)->bool{
    set_contract_address(vault_manager);
    let result:bool = vault_dispatcher.start_auction();
    return result;
}

fn end_auction(ref vault_dispatcher:IVaultDispatcher, amount:u256, vault_manager:ContractAddress)->u256{
    set_contract_address(vault_manager);
    let result:u256 = vault_dispatcher.end_auction();
    return result;
}

fn settle_option_round(ref vault_dispatcher:IVaultDispatcher, amount:u256, address:ContractAddress)->bool{
    
    set_contract_address(address);
    let result:bool = vault_dispatcher.settle_option_round();
    return result;
}

