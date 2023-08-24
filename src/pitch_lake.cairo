// https://www.sciencedirect.com/book/9780123745071/auction-theory
// https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018

// TODO:
// underlying
// setting expiry
// setting strike price
// collateralization
// settlement
// premium
// batch auction
// historical volatility
// liquidity provision
// option minting
// liquidity roll-over
// reserve price (this will be difficult?)
// liquidity cap
// fossil
use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};


#[starknet::interface]
trait IPitchLake<TContractState> {

    //new members
    /////////////////
    #[view]
    fn in_the_money_vault(ref self: TContractState) -> ContractAddress;
    #[view]
    fn out_the_money_vault(ref self: TContractState) -> ContractAddress;
    #[view]
    fn at_the_money_vault(ref self: TContractState) -> ContractAddress;
}

#[starknet::contract]
mod PitchLake {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;

    #[storage]
    struct Storage {
    }

    #[external(v0)]
    impl PitchLakeImpl of super::IPitchLake<ContractState> {

        #[view]
        fn in_the_money_vault(ref self: ContractState) -> ContractAddress{
            ContractAddressZeroable::zero()
        }
        #[view]
        fn out_the_money_vault(ref self: ContractState) -> ContractAddress{
            ContractAddressZeroable::zero()
        }
        #[view]
        fn at_the_money_vault(ref self: ContractState) -> ContractAddress{
            ContractAddressZeroable::zero()
        }

    }
}
