use starknet::ContractAddress;

pub fn vault_manager() -> ContractAddress {
    'vault_manager'.try_into().unwrap()
}

pub fn weth_owner() -> ContractAddress {
    'weth_owner'.try_into().unwrap()
}

// Bystander, perform state transition functions on vault so all gas costs are on it
pub fn bystander() -> ContractAddress {
    'bystander'.try_into().unwrap()
}


// Get an array of liquiditiy providers
pub fn liquidity_providers_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => liquidity_provider_1(),
            1 => liquidity_provider_2(),
            2 => liquidity_provider_3(),
            3 => liquidity_provider_4(),
            4 => liquidity_provider_5(),
            5 => liquidity_provider_6(),
            _ => liquidity_provider_1(),
        };

        data.append(contractAddress);
        index = index + 1;
    }
    data
}

// Get an array of option bidders/buyers
pub fn option_bidders_get(number: u32) -> Array<ContractAddress> {
    let mut data: Array<ContractAddress> = array![];
    let mut index = 0;
    while index < number {
        let contractAddress = match index {
            0 => option_bidder_buyer_1(),
            1 => option_bidder_buyer_2(),
            2 => option_bidder_buyer_3(),
            3 => option_bidder_buyer_4(),
            4 => option_bidder_buyer_5(),
            5 => option_bidder_buyer_6(),
            _ => option_bidder_buyer_1(),
        };

        data.append(contractAddress);
        index = index + 1;
    }
    data
}

// Individual liquidity providers and option bidders/buyers
pub fn liquidity_provider_1() -> ContractAddress {
    'liquidity_provider_1'.try_into().unwrap()
}

pub fn liquidity_provider_2() -> ContractAddress {
    'liquidity_provider_2'.try_into().unwrap()
}

pub fn liquidity_provider_3() -> ContractAddress {
    'liquidity_provider_3'.try_into().unwrap()
}

pub fn liquidity_provider_4() -> ContractAddress {
    'liquidity_provider_4'.try_into().unwrap()
}
pub fn liquidity_provider_5() -> ContractAddress {
    'liquidity_provider_5'.try_into().unwrap()
}
pub fn liquidity_provider_6() -> ContractAddress {
    'liquidity_provider_6'.try_into().unwrap()
}
pub fn option_bidder_buyer_1() -> ContractAddress {
    'option_bidder_buyer1'.try_into().unwrap()
}

pub fn option_bidder_buyer_2() -> ContractAddress {
    'option_bidder_buyer2'.try_into().unwrap()
}
pub fn option_bidder_buyer_3() -> ContractAddress {
    'option_bidder_buyer3'.try_into().unwrap()
}
pub fn option_bidder_buyer_4() -> ContractAddress {
    'option_bidder_buyer4'.try_into().unwrap()
}
pub fn option_bidder_buyer_5() -> ContractAddress {
    'option_bidder_buyer5'.try_into().unwrap()
}
pub fn option_bidder_buyer_6() -> ContractAddress {
    'option_bidder_buyer6'.try_into().unwrap()
}

