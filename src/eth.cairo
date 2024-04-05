// mocking erc20 here...
// seems that the Cairo 0 was camelCase
// what will the Cairo 1 ERC20? are we redeploying in regenesis?
// better implementation: https://github.com/enitrat/cairo1-template
// can experiment next with the cross-contract call testing
// deploy contracts at different addresses like in governance

#[starknet::contract]
mod Eth {
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::ContractAddress;
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }
    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    // Allows the contract access to internal functions
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }
    #[constructor]
    fn constructor(
        ref self: ContractState,
        symbol: ByteArray,
        name: ByteArray,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
        // let name = 'Ethereum';
        // let symbol = 'WETH';
        self.erc20.initializer(name, symbol);
        self.erc20._mint(recipient, initial_supply);
    }
}
