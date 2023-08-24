// mocking erc20 here...
// seems that the Cairo 0 was camelCase
// what will the Cairo 1 ERC20? are we redeploying in regenesis?
// better implementation: https://github.com/enitrat/cairo1-template
// can experiment next with the cross-contract call testing
// deploy contracts at different addresses like in governance

use starknet::{
    ContractAddress,
};

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> felt252;
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: felt252) -> u256;
    fn allowance(self: @TContractState, owner: felt252, spender: felt252) -> u256;
    fn transfer(ref self: TContractState, recipient: felt252, amount: u256) -> bool;
    fn transferFrom(ref self: TContractState, sender: felt252, recipient: felt252, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: felt252, amount: u256) -> bool;
}

#[starknet::contract]
mod Eth {   
    use array::ArrayTrait;
    use option::OptionTrait;
    use starknet::{
        ContractAddress,
        get_caller_address,
    };
    use traits::Into;
    use traits::TryInto;

    #[storage]
    struct Storage {
        balance: LegacyMap::<ContractAddress, u256>, 
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>, 
    }

    fn _panic_not_implemented() {
        let mut data = ArrayTrait::new();
        data.append('not implemented');
        panic(data);
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _get_allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            return self.allowances.read((owner, spender));
        }
    }

    #[external(v0)]
    impl Eth of super::IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            'ETH'
        }

        fn symbol(self: @ContractState) -> felt252 {
            'ETH'
        }

        fn decimals(self: @ContractState) -> felt252 {
            18
        }

        fn totalSupply(self: @ContractState) -> u256 {
            1000000000
        }

        fn balanceOf(self: @ContractState, account: felt252) -> u256 {
            return self.balance.read(account.try_into().unwrap());
        }

        fn allowance(self: @ContractState, owner: felt252, spender: felt252) -> u256 {
            let owner_address: ContractAddress = owner.try_into().unwrap();
            let spender_address: ContractAddress = spender.try_into().unwrap();
            let allowance_amount: u256 = self._get_allowance(owner_address, spender_address);
            return allowance_amount;
        }

        fn transfer(ref self: ContractState, recipient: felt252, amount: u256) -> bool {
            let sender_address: ContractAddress = get_caller_address();
            let sender_balance: u256 = self.balance.read(sender_address);
            if sender_balance < amount {
                false
            } else {
                self.balance.write(sender_address, sender_balance - amount);
                self.balance.write(recipient.try_into().unwrap(), sender_balance + amount);
                true
            }
        }

        fn transferFrom(ref self: ContractState, sender: felt252, recipient: felt252, amount: u256) -> bool {
            let caller_address: ContractAddress = get_caller_address();
            let sender_address: ContractAddress = sender.try_into().unwrap();
            let allowance_amount: u256 = self._get_allowance(sender_address, caller_address);
            if allowance_amount < amount {
                false
            } else {
                let sender_balance: u256 = self.balance.read(sender_address);
                if sender_balance < amount {
                    false
                } else {
                    self.balance.write(sender_address, sender_balance - amount);
                    self.balance.write(recipient.try_into().unwrap(), sender_balance + amount);
                    true
                }
            }
        }

        fn approve(ref self: ContractState, spender: felt252, amount: u256) -> bool {
            let caller_address: ContractAddress = get_caller_address();
            let spender_address: ContractAddress = spender.try_into().unwrap();
            self.allowances.write((caller_address, spender_address), amount);
            true
        }
    }
}
