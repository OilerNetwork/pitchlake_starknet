// mocking erc20 here...
// seems that the Cairo 0 was camelCase
// what will the Cairo 1 ERC20? are we redeploying in regenesis?
// better implementation: https://github.com/enitrat/cairo1-template
// can experiment next with the cross-contract call testing
// deploy contracts at different addresses like in governance

#[starknet::contract]
pub mod Eth {
    use openzeppelin_token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    // Exposes snake_case & CamelCase entry points
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    // Allows the contract access to internal functions
    impl InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pub erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_supply: u256, recipient: ContractAddress) {
        self.erc20.initializer("Ethereum", "WETH");
        self.erc20.mint(recipient, initial_supply);
    }
}
