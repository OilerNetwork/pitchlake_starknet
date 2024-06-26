use starknet::{ContractAddress};
use pitch_lake_starknet::contracts::{
    option_round::{StartAuctionParams, OptionRoundState},
    market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher},
    vault::Vault::{VaultType, VaultError},
};

// The interface for the vault contract
#[starknet::interface]
trait IVault<TContractState> {
    // Being used for testing event asserters work correctly. Need to look into
    // emitting events from our tests instead of via entry point
    fn rm_me2(ref self: TContractState);

    /// Reads ///

    /// Other

    // Get the vault's  manaager address
    // @dev Better access control ? (oz permits ?)
    fn vault_manager(self: @TContractState) -> ContractAddress;

    // Get the type of vault (ITM | ATM | OTM)
    fn vault_type(self: @TContractState) -> VaultType;

    // Get the market aggregator address
    fn get_market_aggregator(self: @TContractState) -> ContractAddress;

    // Get the ETH address
    fn eth_address(self: @TContractState) -> ContractAddress;

    /// Rounds

    // @return the current option round id
    fn current_option_round_id(self: @TContractState) -> u256;

    // @return the contract address of the option round
    fn get_option_round_address(self: @TContractState, option_round_id: u256) -> ContractAddress;

    /// Liquidity

    // For LPs //

    // Get the liquidity an lp has locked
    fn get_lp_locked_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // Get the liquidity an LP has unlocked
    fn get_lp_unlocked_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // Get the total liquidity an LP has in the protocol
    fn get_lp_total_balance(self: @TContractState, liquidity_provider: ContractAddress) -> u256;

    // For Vault //

    // Get the total liquidity locked
    fn get_total_locked_balance(self: @TContractState) -> u256;

    // Get the total liquidity unlocked
    fn get_total_unlocked_balance(self: @TContractState) -> u256;

    // Get the total liquidity in the protocol
    fn get_total_balance(self: @TContractState,) -> u256;

    /// Premiums

    // Get the total premium LP has earned in the current round
    // @note premiums for previous rounds
    fn get_premiums_earned(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    // Get the total premiums collected by an LP in a round
    fn get_premiums_collected(
        self: @TContractState, liquidity_provider: ContractAddress, round_id: u256
    ) -> u256;

    /// Writes ///

    /// State transition

    // Start the auction on the next round as long as the current round is Settled and the
    // round transition period has passed. Deploys the next next round and updates the current/next pointers.
    // @return the total options available in the auction
    fn start_auction(ref self: TContractState) -> Result<u256, VaultError>;

    // End the auction in the current round as long as the current round is Auctioning and the auction
    // bidding period has ended.
    // @return the clearing price of the auction
    // @return the total options sold in the auction (@note keep or drop ?)
    fn end_auction(ref self: TContractState) -> Result<(u256, u256), VaultError>;

    // Settle the current option round as long as the current round is Running and the option expiry time has passed.
    // @return The total payout of the option round
    fn settle_option_round(ref self: TContractState) -> Result<u256, VaultError>;

    /// LP functions

    // Liquditiy provider deposits to the vault for the upcoming round
    // @return The liquidity provider's updated unlocked position
    fn deposit_liquidity(
        ref self: TContractState, amount: u256, liquidity_provider: ContractAddress
    ) -> Result<u256, VaultError>;

    // Liquidity provider withdraws from the vailt
    // @return The liquidity provider's updated unlocked position
    fn withdraw_liquidity(
        ref self: TContractState, amount: u256
    ) -> Result<u256, Vault::VaultError>;

    /// LP token related

    // LP converts their collateral into LP tokens
    // @note all at once or can LP convert a partial amount ?
    //  - logically i'm pretty sure they could do a partial amount (collecting all rewards in either case)
    fn convert_position_to_lp_tokens(ref self: TContractState, amount: u256);

    // LP converts their (source_round) LP tokens into a position in the current round
    // @dev Premiums/unsold from the source round are not counted
    fn convert_lp_tokens_to_position(ref self: TContractState, source_round: u256, amount: u256);

    // LP token owner converts an amount of source round tokens to target round tokens
    // @dev Rx tokens do not include premiums/unsold from rx (above)
    // This is not a problem for token -> position, but is a problem for
    // token -> token because when rx tokens convert to ry, the ry tokens should
    // be able to collect ry premiums but will not be able to (above)
    // @dev Ry must be running or settled. This way we can know the premiums that the rY tokens earned in the round, and collect them
    // as a deposit into the next round. We need to collect these rY premiums because the LP tokens need to represent the value of a
    // deposit in the round net any premiums from the round.
    // @dev If we do not collect the premiums for rY upon conversion, they would be lost.
    // @return the amount of target round tokens received
    // @dev move entry point to LPToken ?
    fn convert_lp_tokens_to_newer_lp_tokens(
        ref self: TContractState, source_round: u256, target_round: u256, amount: u256
    ) -> Result<u256, VaultError>;
}

#[starknet::contract]
mod Vault {
    use starknet::{
        ContractAddress, ClassHash, deploy_syscall, get_caller_address, contract_address_const,
        get_contract_address
    };
    use openzeppelin::{
        token::erc20::{
            ERC20Component, interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,}
        },
        utils::serde::SerializedAppend
    };
    use pitch_lake_starknet::contracts::{
        vault::{IVault},
        option_round::{
            OptionRound,
            OptionRound::{
                OptionRoundErrorIntoFelt252, OptionRoundConstructorParams, StartAuctionParams,
                OptionRoundState
            },
            IOptionRoundDispatcher, IOptionRoundDispatcherTrait,
        },
        market_aggregator::{IMarketAggregatorDispatcher}
    };

    // The type of vault
    #[derive(starknet::Store, Copy, Drop, Serde, PartialEq)]
    enum VaultType {
        InTheMoney,
        AtTheMoney,
        OutOfMoney,
    }

    // Events
    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        OptionRoundDeployed: OptionRoundDeployed,
    }

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

    #[storage]
    struct Storage {
        // The address for the ETH contract
        eth_address: ContractAddress,
        // The amount liquidity providers deposit into each round: (liquidity_provider, round_id) -> deposit_amount
        positions: LegacyMap<(ContractAddress, u256), u256>,
        // Withdraw checkpoints: (liquidity_provider) -> round_id
        withdraw_checkpoints: LegacyMap<ContractAddress, u256>,
        // Total unlocked liquidity
        total_unlocked_balance: u256,
        // Total locked liquidity
        total_locked_balance: u256,
        // The amount of premiums a liquidity provider collects from each round: (liquidity_provider, round_id) -> collected_amount
        premiums_collected: LegacyMap<(ContractAddress, u256), u256>,
        // The amount of liquidity not sold during each round's auction (if any): (round_id) -> unsold_liquidity
        unsold_liquidity: LegacyMap<u256, u256>,
        // The id of the current option round
        current_option_round_id: u256,
        ///////
        ///////
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        round_addresses: LegacyMap<u256, ContractAddress>,
        round_transition_period: u64,
        auction_run_time: u64,
        option_run_time: u64,
    // liquidity_positions: LegacyMap<((ContractAddress, u256), u256)>,
    }

    // @note Need to add eth address as a param here
    //  - Will need to update setup functions to accomodate
    #[constructor]
    fn constructor(
        ref self: ContractState,
        eth_address: ContractAddress,
        vault_manager: ContractAddress,
        vault_type: VaultType,
        market_aggregator: ContractAddress,
        option_round_class_hash: ClassHash,
    ) {
        self.eth_address.write(eth_address);
        self.vault_manager.write(vault_manager);
        self.vault_type.write(vault_type);
        self.market_aggregator.write(market_aggregator);

        // @dev Deploy the 1st option round
        let mut calldata: Array<felt252> = array![];
        calldata.append_serde(starknet::get_contract_address()); // vault address
        calldata.append_serde(1_u256); // option round id
        let now = starknet::get_block_timestamp();
        let auction_start_date = now + self.round_transition_period.read();
        let auction_end_date = auction_start_date + self.auction_run_time.read();
        let option_settlement_date = auction_end_date + self.option_run_time.read();
        calldata.append_serde(auction_start_date); // auction start date
        calldata.append_serde(auction_end_date);
        calldata.append_serde(option_settlement_date);

        calldata.append_serde(1000000000_u256); // reserve price
        calldata.append_serde(5000_u256); // cap level
        calldata.append_serde(1000000000_u256); // strike price

        let (round_1_address, _) = deploy_syscall(
            option_round_class_hash, 'some salt', calldata.span(), false
        )
            .unwrap();

        // Set round addressess
        self.round_addresses.write(1, round_1_address);
        self.current_option_round_id.write(1);
    }

    #[derive(Copy, Drop, Serde)]
    enum VaultError {
        // Error from OptionRound contract
        OptionRoundError: OptionRound::OptionRoundError,
        // Withdrawal exceeds unlocked position
        InsufficientBalance,
    }

    impl VaultErrorIntoFelt252Trait of Into<VaultError, felt252> {
        fn into(self: VaultError) -> felt252 {
            match self {
                VaultError::OptionRoundError(e) => { e.into() },
                VaultError::InsufficientBalance => { 'Vault: Insufficient balance' }
            }
        }
    }

    #[abi(embed_v0)]
    impl VaultImpl of super::IVault<ContractState> {
        fn rm_me2(ref self: ContractState) {
            self
                .emit(
                    Event::OptionRoundDeployed(
                        OptionRoundDeployed {
                            round_id: 1, address: starknet::get_contract_address(),
                        }
                    )
                );
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            account: starknet::get_contract_address(),
                            position_balance_before: 100,
                            position_balance_after: 100
                        }
                    )
                );
            self
                .emit(
                    Event::Withdrawal(
                        Withdrawal {
                            account: starknet::get_contract_address(),
                            position_balance_before: 100,
                            position_balance_after: 100
                        }
                    )
                );
        }

        /// Reads ///

        /// Other

        fn vault_manager(self: @ContractState) -> ContractAddress {
            self.vault_manager.read()
        }

        fn vault_type(self: @ContractState) -> VaultType {
            self.vault_type.read()
        }

        fn get_market_aggregator(self: @ContractState) -> ContractAddress {
            self.market_aggregator.read()
        }

        fn eth_address(self: @ContractState) -> ContractAddress {
            self.eth_address.read()
        }

        /// Rounds

        fn current_option_round_id(self: @ContractState) -> u256 {
            self.current_option_round_id.read()
        }

        fn get_option_round_address(
            self: @ContractState, option_round_id: u256
        ) -> ContractAddress {
            self.round_addresses.read(option_round_id)
        }

        /// Liquidity

        // For liquidity providers

        fn get_lp_locked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_lp_unlocked_balance(
            self: @ContractState, liquidity_provider: ContractAddress
        ) -> u256 {
            100
        }

        fn get_lp_total_balance(self: @ContractState, liquidity_provider: ContractAddress) -> u256 {
            100
        }

        // For Vault //

        fn get_total_locked_balance(self: @ContractState) -> u256 {
            self.total_locked_balance.read()
        }

        fn get_total_unlocked_balance(self: @ContractState) -> u256 {
            self.total_unlocked_balance.read()
        }

        fn get_total_balance(self: @ContractState,) -> u256 {
            self.get_total_locked_balance() + self.get_total_unlocked_balance()
        }

        /// Premiums

        fn get_premiums_earned(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> u256 {
            100
        }

        fn get_premiums_collected(
            self: @ContractState, liquidity_provider: ContractAddress, round_id: u256
        ) -> u256 {
            self.premiums_collected.read((liquidity_provider, round_id))
        }

        /// Writes ///

        /// State transition

        fn start_auction(ref self: ContractState) -> Result<u256, VaultError> {
            // Get a dispatcher for the current option round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // The liquidity being locked at the start of the round
            let starting_liquidity = self.get_total_unlocked_balance();

            // Calculate the total options available to sell in the auction
            let total_options_available = self
                .calculate_total_options_available(starting_liquidity);

            // Try to start the auction on the current round
            let res = current_round.start_auction(total_options_available, starting_liquidity);
            match res {
                Result::Ok(value) => {
                    // Update total_locked_liquidity
                    self.total_locked_balance.write(starting_liquidity);

                    // Update total_unlocked_liquidity
                    self.total_unlocked_balance.write(0);

                    // Return the total options available
                    Result::Ok(value)
                },
                Result::Err(err) => { Result::Err(VaultError::OptionRoundError(err)) }
            }
        }

        fn end_auction(ref self: ContractState) -> Result<(u256, u256), VaultError> {
            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // Try to end the auction on the option round
            let res = current_round.end_auction();
            match res {
                Result::Ok((
                    clearing_price, total_options_sold
                )) => {
                    // Amount of liquidity currently locked and unlocked
                    let mut locked_liquidity = self.total_locked_balance.read();
                    let mut unlocked_liquidity = self.total_unlocked_balance.read();

                    // Premiums earned from the auction are unlocked for liquidity providers to withdraw
                    unlocked_liquidity += current_round.total_premiums();

                    // Handle any unsold liquidity
                    let total_options_available = current_round.get_total_options_available();
                    if (total_options_sold < total_options_available) {
                        // Number of options that did not sell
                        let unsold_options = total_options_available - total_options_sold;

                        // Portion of the locked liquidity these unsold options represent
                        // @note Consider adding precision factor
                        let unsold_liquidity = (locked_liquidity * unsold_options)
                            / total_options_available;

                        // Decrement locked liquidity by the unsold liquidity and
                        // update the storage variable
                        locked_liquidity -= unsold_liquidity;
                        self.total_locked_balance.write(locked_liquidity);

                        // Increment unlocked liquidity by the unsold liquidity
                        unlocked_liquidity += unsold_liquidity;

                        // Store how the unsold liquidity for this round for future balance calculations
                        self.unsold_liquidity.write(current_round_id, unsold_liquidity);
                    }

                    // Update the total_unlocked_balance storage variable
                    self.total_unlocked_balance.write(unlocked_liquidity);

                    // Return the clearing_price & total_options_sold
                    return Result::Ok((clearing_price, total_options_sold));
                },
                Result::Err(e) => { return Result::Err(VaultError::OptionRoundError(e)); }
            }
        }

        fn settle_option_round(ref self: ContractState) -> Result<u256, VaultError> {
            // Fetch the settlement_price from fossil
            //  - An empty helper function is fine for now, we will discuss the
            //  implementation of this function later

            // Call OptionRound::settle_option_round() with the settlement_price (returns total_payout)

            // Send eth (total_payout) from this contract to the just settled option round (if > 0)

            // Decrement total_locked_balance by total_payout

            // Add total_locked_balance to total_unlocked_balance

            // Set total_locked_balance to 0

            // Increment the current_round_id

            // Fetch reserve_price, cap_level, and strike_price from fossil
            // - An empty helper function is fine for now, we will discuss the
            // implementation of this function later

            // Calculate auction_start_date, auction_end_date, and option_settlement_date
            // - auction_state_date = now + round_transition_period
            // - auction_end_date = auction_start_date + auction_run_time
            // - option_settlement_date = auction_end_date + option_run_time

            // Deploy the new current option round with the above params

            // Emit new round deployed event

            //2.0) Vault::{settle_option_round}
            //- Add function to fetch the settlement price from fossil
            //	- let settlement_price = fetch_settlement_price()
            //		- just the ghost function is fine for now
            //- call OptionRound::settle_option_round using the above settlement_price
            //- increment the current round id
            //- Add function to retrieve reserve price, cap level & strike price from fossil
            //	 - let (reserve price, cap_level, strike_price) = fetch_round_start_params()
            //		  - Just the ghost function is fine for now
            //- deploy the new current option round with the above params
            //
            //
            //make sure to update unlocked/locked balance during the state transition functions too

            Result::Ok(1)
        }

        /// OB functions
        fn deposit_liquidity(
            ref self: ContractState, amount: u256, liquidity_provider: ContractAddress
        ) -> Result<u256, VaultError> {
            // Get a dispatcher for the current round
            let current_round_id = self.current_option_round_id.read();
            let current_round = self.get_round_dispatcher(current_round_id);

            // Transfer the deposit to this contract (from caller to vault)
            let eth = self.get_eth_dispatcher();
            eth.transfer_from(get_caller_address(), get_contract_address(), amount);

            // The index to store the liquidity provider's deposit in `positions`
            let upcoming_round_id = match current_round.get_state() {
                // @dev If the current round is Open, we are in the round transition period and the
                // deposit is for the current round (about to start)
                OptionRoundState::Open => current_round_id,
                // @dev Else, the current round is either Auctioning or Running, and the
                // deposit is for the next round
                _ => current_round_id + 1
            };

            // The total unlocked balance of the Vault before the deposit
            let total_unlocked_balance_before = self.get_total_unlocked_balance();

            // The liquidity provider's total unlocked balance before the deposit (postion's value + premiums)
            let lp_unlocked_balance_before = self.get_lp_unlocked_balance(liquidity_provider);

            // The liquidity provider's deposit value in the mapping at the upcoming round
            let lp_position_value_before = self
                .positions
                .read((liquidity_provider, upcoming_round_id));

            // Update the total unlocked balance and the liquidity provider's value in the
            // positions mapping at the upcoming round
            let total_unlocked_balance_after = total_unlocked_balance_before + amount;
            let lp_unlocked_balance_after = lp_unlocked_balance_before + amount;
            let lp_position_value_after = lp_position_value_before + amount;
            self.total_unlocked_balance.write(total_unlocked_balance_after);
            self.positions.write((liquidity_provider, upcoming_round_id), lp_position_value_after);

            // Emit deposit event
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            account: liquidity_provider,
                            position_balance_before: lp_unlocked_balance_before,
                            position_balance_after: lp_unlocked_balance_after
                        }
                    )
                );

            // Return the liquidity provider's updated unlocked balance
            Result::Ok(lp_unlocked_balance_after)
        }

        fn withdraw_liquidity(ref self: ContractState, amount: u256) -> Result<u256, VaultError> {
            // Calculate the value of the caller's unlocked position from their checkpoint -> the current round
            // - If the current round is Open, this value should be the caller's portion of the previous round's
            //  remaining liquidity, plus the value of the caller's deposit into the next round
            // - If the current round is Auctioning, this value should just include any deposits for the next round
            // - If the current round is Running, this value should only be the caller's portion of the premiums earned
            //  in the current round, plus the value of the caller's deposit into the next round
            // @dev Remember each we need to calculate the value of the caller's position across each round. Each round
            // the caller's liquidity is == their portion of the remaining liquidity (deposits + premiums - payouts) -
            // any premiums from the round that they may have already collected
            // - See crash course for more details

            // Assert amount <= this value

            // Update the caller's withdraw_checkpoint
            // - If the current round is Open, the checkpoint should be set to the current round
            // - Else (Auctioning|Running), the checkpoint should not be updated

            // Update the caller's position in storage
            // - If the current round is Open, set the value in the mapping to `value - amount`, at slot current_round_id
            // - If the current round is Auctioning, set the value in the mapping to `value - amount`, at slot next_round_id
            // - If the current round is Running, that means the user is withdrawing (possibly) from their premiums earned
            // in the current round, and from their deposits into the next round. This means we may or may not need to update the
            // position mapping. If value <= premiums earned in the current round, then we do not need to update the position mapping.
            // However, if value > premiums earned in this round, then we need to update the positions value in the mapping with this
            // difference at slot next_round_id
            //  - i.e Say the caller could collect 10 in premiums in the current round, and has a deposit of 10 into the next round.
            // They withdraw 15. This means we set the value of their position at slot next_round_id to 10 - 5 = 5 (and update premiums collected to 10 for
            // the current round, see below)

            // Update premiums collected in the current round
            // - If the current round is Open | Running, we need to increment the amount of premiums collected in the current round
            // - If the current round is Auctioning, then we do not update this value (since the premiums have not been earned yet the user will not be withdrawing from them)

            // Decrement total_unlocked_balance by amount

            // Transfer eth from Vault to caller

            // Emit withdrawal event

            // Return the value of the caller's unlocked position after the withdrawal

            Result::Ok(1)
        }

        /// LP token related

        fn convert_position_to_lp_tokens(ref self: ContractState, amount: u256) {}

        fn convert_lp_tokens_to_position(
            ref self: ContractState, source_round: u256, amount: u256
        ) {}

        fn convert_lp_tokens_to_newer_lp_tokens(
            ref self: ContractState, source_round: u256, target_round: u256, amount: u256
        ) -> Result<u256, VaultError> {
            Result::Ok(1)
        }
    }


    // Internal Functions
    #[generate_trait]
    impl InternalImpl of VaultInternalTrait {
        // Get a dispatcher for the ETH contract
        fn get_eth_dispatcher(self: @ContractState) -> IERC20Dispatcher {
            let eth_address: ContractAddress = self.eth_address();
            IERC20Dispatcher { contract_address: eth_address }
        }

        // Get a dispatcher for the Vault
        fn get_round_dispatcher(self: @ContractState, round_id: u256) -> IOptionRoundDispatcher {
            let round_address = self.get_option_round_address(round_id);
            IOptionRoundDispatcher { contract_address: round_address }
        }

        fn calculate_total_options_available(
            ref self: ContractState, starting_liquidity: u256
        ) -> u256 {
            //Calculate total options accordingly
            1
        }
    }
}
