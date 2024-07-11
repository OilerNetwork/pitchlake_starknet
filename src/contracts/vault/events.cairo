use starknet::ContractAddress;


#[derive(Drop, starknet::Event, PartialEq)]
struct Deposit {
    #[key]
    account: ContractAddress,
    position_balance_before: u256,
    position_balance_after: u256,
}

#[derive(Drop, starknet::Event, PartialEq)]
struct Withdrawal {
    #[key]
    account: ContractAddress,
    position_balance_before: u256,
    position_balance_after: u256,
}


#[derive(Drop, starknet::Event, PartialEq)]
struct OptionRoundDeployed {
    // might not need
    round_id: u256,
    address: ContractAddress,
// option_round_params: OptionRoundParams
// possibly more members to this event
}
