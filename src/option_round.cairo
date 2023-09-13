use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;



// unit of account is in wei
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
struct OptionRoundParams {
    standard_deviation:u256,
    strike_price: u256, // wei
    cap_level :u256,  //wei 
    collateral_level: u256,
    reserve_price: u256, //wei
    total_options_available: u256,
    start_time:u64,
    expiry_time:u64
}

#[derive(Copy, Drop, Serde, PartialEq)]
enum OptionRoundState {
    Initialized: (),
    AuctionStarted: (),
    AuctionEnded: (),
    AuctionSettled: (),
}



#[starknet::interface]
trait IOptionRound<TContractState> {

    // starts the auction to determine the option premium clearing price, true if auction has never been started before otherwise false
    #[external]
    fn start_auction(ref self: TContractState, option_params : OptionRoundParams) -> bool;

    // returns true if bid if deposit has been locked up in the auction. false if auction not running or bid below reserve price
    #[external]
    fn bid(ref self: TContractState, amount : u256, price :u256) -> bool;

    // successfully ended an auction, false if there was no auction in process
    #[external]
    fn end_auction(ref self: TContractState) -> bool;

    // if the option is past the expiry date then upon proof verification final_price is accepted and payouts can begin. 
    #[external]
    fn settle(ref self: TContractState, final_price:u256, proof: Array<u256>) -> bool;

    // returns the current state of the option round
    #[external]
    fn get_option_round_state(ref self: TContractState) -> OptionRoundState;

    // gets the most auction price for the option, if the auction has ended
    #[view]
    fn get_auction_clearing_price(ref self: TContractState) -> u256;

    // moves/transfers the unused premium deposit back to the bidder, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call claim_premium_deposit to transfer any used deposits
    #[external]
    fn claim_premium_deposit(ref self: TContractState ) -> u256;

    // transfers any payout due to the option buyer, return value is the amount of the transfer
    // this is per option buyer. every option buyer will have to individually call claim_payout.
    #[external]
    fn claim_payout(ref self: TContractState ) -> u256;

    // if the options are past the expiry date then we can move the collateral (after the payout) back to the vault(unallocated pool), returns the collateral moved
    // this is per liquidity provider, every option buyer will have to individually call transfer_collateral_to_vault
    #[external]
    fn transfer_collateral_to_vault(ref self: TContractState) -> u256;

    // after the auction ends, liquidity_providers can transfer the premiums paid to them back to the vault from where they can be immediately withdrawn.
    // this is per liquidity provider, every liquidity provider will have to individually call transfer_premium_paid_to_vault
    #[external]
    fn transfer_premium_paid_to_vault(ref self: TContractState) -> u256;

    // total amount deposited as part of bidding by an option buyer, if the auction has not ended this represents the total amount locked up for auction and cannot be claimed back,
    // if the auction has ended this the amount which was not converted into an option and can be claimed back.
    #[view]
    fn bid_deposit_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // payout due to an option buyer
    #[view]
    fn payout_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // no of options bought by a user
    #[view]
    fn option_balance_of(self: @TContractState, option_buyer: ContractAddress) -> u256;

    // premium balance of liquidity_provider
    #[view]
    fn premium_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // locked collateral balance of liquidity_provider
    #[view]
    fn collateral_balance_of(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // total collateral available in the round
    #[view]
    fn total_collateral(self: @TContractState) -> u256;

    // total options sold
    #[view]
    fn total_options_sold(self: @TContractState) -> u256;

}

#[starknet::contract]
mod OptionRound  {
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::token::erc20::interface::IERC20;
    use starknet::ContractAddress;
    use pitch_lake_starknet::vault::VaultType;
    use pitch_lake_starknet::pool::IPoolDispatcher;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use super::{OptionRoundParams, OptionRoundState};

    #[storage]
    struct Storage {
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress
    ) {
    }

    #[external(v0)]
    impl OptionRoundImpl of super::IOptionRound<ContractState> {

        fn start_auction(ref self: ContractState, option_params:OptionRoundParams) -> bool{
            true            
        }

        fn bid(ref self: ContractState, amount : u256, price :u256) -> bool{
            true
        }

        // returns the clearing price for the auction
        fn end_auction(ref self: ContractState) -> bool{
            // final clearing price
            true
        }

        fn settle(ref self: ContractState, final_price:u256, proof: Array<u256>) -> bool{
            true
        }

        fn get_option_round_state(ref self: ContractState) -> OptionRoundState{
            // final clearing price
            OptionRoundState::AuctionStarted
        }

        fn get_auction_clearing_price(ref self: ContractState) -> u256{
            // final clearing price
            100
        }

        fn claim_premium_deposit(ref self: ContractState ) -> u256{
            100
        }

        fn claim_payout(ref self: ContractState ) -> u256{
            100
        }

        fn transfer_collateral_to_vault(ref self: ContractState) -> u256{
            100
        }


        fn transfer_premium_paid_to_vault(ref self: ContractState) -> u256{
            100
        }

        fn payout_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256{
            100
        }

        fn option_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256{
            100
        }

        fn premium_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256{
            100
        }

        fn collateral_balance_of(self: @ContractState, liquidity_provider: ContractAddress) -> u256{
            100
        }

        fn total_collateral(self: @ContractState) -> u256{
            100
        }

        fn total_options_sold(self: @ContractState) -> u256{
            100
        }

        fn bid_deposit_balance_of(self: @ContractState, option_buyer: ContractAddress) -> u256{
            100
        }


    }
}
