use option::OptionTrait;
use debug::PrintTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    contract_address_try_from_felt252
};

fn allocated_pool_address() -> ContractAddress {
    contract_address_const::<'allocated_pool_address'>()
}

fn unallocated_pool_address() -> ContractAddress {
    contract_address_const::<'unallocated_pool_address'>()
}

fn liquiduty_provider_1() -> ContractAddress {
    contract_address_const::<'liquiduty_provider_1'>()
}

fn liquiduty_provider_2() -> ContractAddress {
    contract_address_const::<'liquiduty_provider_2'>()
}

fn option_bidder_buyer_1() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer'>()
}

fn option_bidder_buyer_2() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer'>()
}


fn vault_manager() -> ContractAddress {
    contract_address_const::<'vault_manager'>()
}

fn weth_owner() -> ContractAddress {
    contract_address_const::<'weth_owner'>()
}

fn timestamp_start_month() -> u64 {
    1
}

fn timestamp_end_month() -> u64 {
    30*24*60*60
}


fn SPENDER() -> ContractAddress {
    contract_address_const::<20>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<30>()
}

fn OPERATOR() -> ContractAddress {
    contract_address_const::<40>()
}

fn user() -> ContractAddress {
    contract_address_try_from_felt252('user').unwrap()
}

fn zero_address() -> ContractAddress {
    contract_address_const::<0>()
}

