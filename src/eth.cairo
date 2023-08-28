// mocking erc20 here...
// seems that the Cairo 0 was camelCase
// what will the Cairo 1 ERC20? are we redeploying in regenesis?
// better implementation: https://github.com/enitrat/cairo1-template
// can experiment next with the cross-contract call testing
// deploy contracts at different addresses like in governance


#[starknet::contract]
mod Eth {   
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::ERC20::ContractState as ERC20State;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(
        ref self: ERC20State,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
//        let mut unsafe_state = ERC20::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref self, name, symbol);
        ERC20::InternalImpl::_mint(ref self, recipient, initial_supply);
    }

    #[external(v0)]
    fn name(self: @ERC20State) -> felt252 {
        ERC20::ERC20Impl::name(self)
    }

    #[external(v0)]
    fn symbol(self: @ERC20State) -> felt252 {
        ERC20::ERC20Impl::symbol(self)
    }

    #[external(v0)]
    fn decimals(self: @ERC20State) -> u8 {
        ERC20::ERC20Impl::decimals(self)
    }

    #[external(v0)]
    fn total_supply(self: @ERC20State) -> u256 {
        ERC20::ERC20Impl::total_supply(self)
    }

    #[external(v0)]
    fn balance_of(self: @ERC20State, account: ContractAddress) -> u256 {
        ERC20::ERC20Impl::balance_of(self, account)
    }

    #[external(v0)]
    fn allowance(self: @ERC20State, owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::ERC20Impl::allowance(self, owner, spender)
    }

    #[external(v0)]
    fn transfer(ref self: ERC20State, recipient: ContractAddress, amount: u256) -> bool {
        ERC20::ERC20Impl::transfer(ref self, recipient, amount)
    }

    #[external(v0)]
    fn transfer_from(
        ref self: ERC20State, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool {
        ERC20::ERC20Impl::transfer_from(ref self, sender, recipient, amount)
    }

    #[external(v0)]
    fn approve(ref self: ERC20State, spender: ContractAddress, amount: u256) -> bool {
        ERC20::ERC20Impl::approve(ref self, spender, amount)
    }
}
