use starknet::{ContractAddress, contract_address_const};

fn vault_manager() -> ContractAddress {
    contract_address_const::<'vault_manager'>()
}

fn weth_owner() -> ContractAddress {
    contract_address_const::<'weth_owner'>()
}

// Bystander, perform state transition functions on vault so all gas costs are on it
fn bystander() -> ContractAddress {
    contract_address_const::<'bystander'>()
}

// Get an array of liquiditiy providers
fn liquidity_providers_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => contract_address_const::<'liquidity_provider_1'>(),
            1 => contract_address_const::<'liquidity_provider_2'>(),
            2 => contract_address_const::<'liquidity_provider_3'>(),
            3 => contract_address_const::<'liquidity_provider_4'>(),
            4 => contract_address_const::<'liquidity_provider_5'>(),
            5 => contract_address_const::<'liquidity_provider_6'>(),
            _ => contract_address_const::<'liquidity_provider_1'>(),
        };

        data.append(contractAddress);
        index = index + 1;
    };
    data
}

// Get an array of option bidders/buyers
fn option_bidders_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => contract_address_const::<'option_bidder_buyer_1'>(),
            1 => contract_address_const::<'option_bidder_buyer_2'>(),
            2 => contract_address_const::<'option_bidder_buyer_3'>(),
            3 => contract_address_const::<'option_bidder_buyer_4'>(),
            4 => contract_address_const::<'option_bidder_buyer_5'>(),
            5 => contract_address_const::<'option_bidder_buyer_6'>(),
            _ => contract_address_const::<'option_bidder_buyer_1'>(),
        };

        data.append(contractAddress);
        index = index + 1;
    };
    data
}

// Individual liquidity providers and option bidders/buyers
fn liquidity_provider_1() -> ContractAddress {
    contract_address_const::<'liquidity_provider_1'>()
}
fn liquidity_provider_2() -> ContractAddress {
    contract_address_const::<'liquidity_provider_2'>()
}
fn liquidity_provider_3() -> ContractAddress {
    contract_address_const::<'liquidity_provider_3'>()
}
fn liquidity_provider_4() -> ContractAddress {
    contract_address_const::<'liquidity_provider_4'>()
}
fn liquidity_provider_5() -> ContractAddress {
    contract_address_const::<'liquidity_provider_5'>()
}
fn option_bidder_buyer_1() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer1'>()
}
fn option_bidder_buyer_2() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer2'>()
}
fn option_bidder_buyer_3() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer3'>()
}
fn option_bidder_buyer_4() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer4'>()
}
fn option_bidder_buyer_5() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer5'>()
}
fn option_bidder_buyer_6() -> ContractAddress {
    contract_address_const::<'option_bidder_buyer6'>()
}
// Owners/Admins for contracts


