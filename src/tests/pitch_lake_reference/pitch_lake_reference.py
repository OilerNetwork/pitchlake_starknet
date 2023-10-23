import uuid
import threading
from eth_typing import Address
from datetime import timedelta, datetime
from typing import Dict, List, Optional, Any, Protocol, Tuple


class Blockchain:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(Blockchain, cls).__new__(cls)
                # Initialize the blockchain state
                cls._instance.current_time = datetime.utcnow()
                cls._instance.current_sender = None
        return cls._instance

    def set_current_time(self, new_time: datetime):
        self.current_time = new_time

    def set_current_sender(self, sender):
        self.current_sender = sender

    def get_current_time(self):
        return self.current_time

    def get_current_sender(self):
        return self.current_sender
    
class MarketAggregator:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(MarketAggregator, cls).__new__(cls)
                # Initialize with default market conditions
                cls._instance.prev_month_std_dev = 0
                cls._instance.prev_month_avg_basefee = 0
                cls._instance.current_month_avg_basefee = 0
        return cls._instance

    def set_prev_month_std_dev(self, value: int):
        self.prev_month_std_dev = value

    def set_prev_month_avg_basefee(self, value: int):
        self.prev_month_avg_basefee = value

    def set_current_month_avg_basefee(self, value: int):
        self.current_month_avg_basefee = value

    def get_prev_month_std_dev(self) -> int:
        return self.prev_month_std_dev

    def get_prev_month_avg_basefee(self) -> int:
        return self.prev_month_avg_basefee

    def get_current_month_avg_basefee(self) -> int:
        return self.current_month_avg_basefee
        

class StrikePriceStrategy:
    def __init__(self, market_aggregator):
        self.market_aggregator = market_aggregator

    def calculate(self):
        raise NotImplementedError("You should implement this method")


class InTheMoneyStrategy(StrikePriceStrategy):
    def calculate(self):
        base_fee = self.market_aggregator.get_prev_month_avg_basefee()
        std_dev = self.market_aggregator.get_prev_month_std_dev()
        return base_fee + std_dev


class AtTheMoneyStrategy(StrikePriceStrategy):
    def calculate(self):
        return self.market_aggregator.get_prev_month_avg_basefee()


class OutOfTheMoneyStrategy(StrikePriceStrategy):
    def calculate(self):
        base_fee = self.market_aggregator.get_prev_month_avg_basefee()
        std_dev = self.market_aggregator.get_prev_month_std_dev()
        return base_fee - std_dev

class RoundState:
    INITIALIZED = 0
    AUCTION_STARTED = 1
    AUCTION_SETTLED = 2
    OPTION_SETTLED = 3

# Assume these classes are properly defined elsewhere.
class OptionRoundParams:
    def __init__(self, 
                 current_average_basefee: int, 
                 standard_deviation: int,
                 strike_price: int, 
                 cap_level: int, 
                 collateral_level: int, 
                 reserve_price: int, 
                 total_options_available: int,
                 option_expiry_time: int, 
                 auction_end_time: int, 
                 minimum_bid_amount: int, 
                 minimum_collateral_required: int):
        self.current_average_basefee = current_average_basefee  # in wei
        self.standard_deviation = standard_deviation
        self.strike_price = strike_price  # in wei
        self.cap_level = cap_level  # in wei
        self.collateral_level = collateral_level
        self.reserve_price = reserve_price  # in wei
        self.total_options_available = total_options_available
        # self.start_time = start_time  # this line is commented out because it's not present in the struct provided
        self.option_expiry_time = option_expiry_time  # can't settle before this time
        self.auction_end_time = auction_end_time  # auction can't settle before this time
        self.minimum_bid_amount = minimum_bid_amount  # to prevent a DoS vector
        self.minimum_collateral_required = minimum_collateral_required  # round won't start until this much collateral

class OptionRoundState:
    pass

class VaultType:
    pass

class ContractAddress:
    pass

class IMarketAggregatorDispatcher:
    pass


# The main protocol class
class IVault(Protocol):
    def open_liquidity_position(self, amount: int) -> int:
        ...

    def deposit_liquidity_to(self, lp_id: int, amount: int) -> bool:
        ...

    def withdraw_liquidity(self, lp_id: int, amount: int) -> bool:
        ...

    def start_new_option_round(self) -> Tuple[int, OptionRoundParams]:
        ...

    def auction_place_bid(self, amount: int, price: int) -> bool:
        ...

    def settle_auction(self) -> int:
        ...

    def settle_option_round(self) -> bool:
        ...

    def get_option_round_state(self) -> OptionRoundState:
        ...

    def get_option_round_params(self, option_round_id: int) -> OptionRoundParams:
        ...

    def get_auction_clearing_price(self, option_round_id: int) -> int:
        ...

    def refund_unused_bid_deposit(self, option_round_id: int, recipient: ContractAddress) -> int:
        ...

    def claim_option_payout(self, option_round_id: int, for_option_buyer: ContractAddress) -> int:
        ...

    def vault_type(self) -> VaultType:
        ...

    def current_option_round(self) -> Tuple[int, OptionRoundParams]:
        ...

    def next_option_round(self) -> Tuple[int, OptionRoundParams]:
        ...

    def get_market_aggregator(self) -> IMarketAggregatorDispatcher:
        ...

    def unused_bid_deposit_balance_of(self, option_buyer: ContractAddress) -> int:
        ...

    def payout_balance_of(self, option_buyer: ContractAddress) -> int:
        ...

    def option_balance_of(self, option_buyer: ContractAddress) -> int:
        ...

    def premium_balance_of(self, lp_id: int) -> int:
        ...

    def collateral_balance_of(self, lp_id: int) -> int:
        ...

    def unallocated_liquidity_balance_of(self, lp_id: int) -> int:
        ...

    def total_collateral(self) -> int:
        ...

    def total_unallocated_liquidity(self) -> int:
        ...

    def total_options_sold(self) -> int:
        ...

    def decimals(self) -> int:  # Python equivalent of u8 is int
        ...

class VaultConfig:
    # Configuration parameters with their default values.
    ROUND_DURATION: timedelta = timedelta(days=25)
    AUCTION_DURATION: timedelta = timedelta(days=15)
    SETTLEMENT_INTERVAL: timedelta = timedelta(days=5) # time between option settlement and next round start
    MIN_BID_AMOUNT: int = int(0.5 * 10 ** 18)  # 0.5 ETH in Wei
    MIN_DEPOSIT_AMOUNT: int = int(0.1 * 10 ** 18)  # 0.1 ETH in Wei
    MIN_COLLATERAL: int = 10 ** 18  # 1 ETH in Wei

class RoundPositionEntry:
    def __init__(self, amount, next_round_id):
        self.amount = amount
        self.next_round_id = next_round_id  # Initially, this will be the same as the round it was created for.

class RoundPositions:
    def __init__(self):
        self.positions = {}  # Key: (round_id, position_id), Value: RoundPositionEntry

    def add_position(self, round_id, position_id, amount):
        # The initial next_round_id is the same as the round_id during creation.
        entry = RoundPositionEntry(amount=amount, next_round_id=round_id)
        self.positions[(round_id, position_id)] = entry

    def deposit_liquidity_to(self, round_id, position_id, additional_amount):
        entry_key = (round_id, position_id)

        if entry_key in self.positions:
            current_entry = self.positions[entry_key]
            
            if round_id == current_entry.next_round_id:
                # Update the amount for the current round
                current_entry.amount += additional_amount
            else:
                # Linking to a new round, creating a new entry in the process
                new_entry = RoundPositionEntry(amount=additional_amount, next_round_id=round_id)
                self.positions[(current_entry.next_round_id, position_id)] = new_entry
                
                # Update the link for the previous entry
                current_entry.next_round_id = round_id
        else:
            # Handle the case where the position entry does not exist (e.g., error handling or creation)
            pass    

class LiquidityPosition:
    def __init__(self, position_id, depositor, round_id):
        self.position_id = position_id
        self.depositor = depositor
        self.round_id = round_id


class Round:
    def __init__(self,strike_price_strategy: StrikePriceStrategy, blockchain: Blockchain, market_aggregator: MarketAggregator,  round_id: int, config: VaultConfig):
        self.round_id = round_id
        self.state = RoundState.INITIALIZED
        self.min_bid_amount = config.MIN_BID_AMOUNT
        self.min_deposit_amount = config.MIN_DEPOSIT_AMOUNT
        self.min_collateral = config.MIN_COLLATERAL
        self.blockchain = blockchain
        self.market_aggregator = market_aggregator
        self.strike_price_strategy = strike_price_strategy  # "in_the_money", "at_the_money", or "out_the_money"
        self.total_collateral = 0  # Initialize total collateral for the round.
        
        # Timing parameters
        self.round_start_time: Optional[datetime] = None
        self.auction_start_time: Optional[datetime] = None
        self.auction_end_time: Optional[datetime] = None
        self.option_settlement_time: Optional[datetime] = None

        # Initialize parameters specific to the round
        self.cap_level = None
        self.strike_price = None
        self.collateral_level = None
        self.total_options = None
        self.reserve_price = None



# The Vault implementation maintains a record of all open liquidity positions/tokens.
class Vault(IVault):
    def __init__(self, strike_price_strategy: StrikePriceStrategy, blockchain: Blockchain, market_aggregator: MarketAggregator, config: Optional[VaultConfig] = None):
        self.config = config if config else VaultConfig()
        self.blockchain = blockchain
        self.market_aggregator = market_aggregator
        self.round_start_time: Optional[datetime] = None
        self.auction_start_time: Optional[datetime] = None
        self.auction_end_time: Optional[datetime] = None
        self.option_settlement_time: Optional[datetime] = None
        self.strike_price_strategy = strike_price_strategy
        self.position_id = 0  # New attribute to keep track of the latest position ID
        self.round_positions = {}  # Key: (round_id, position_id), Value: RoundPositionEntry


        self.liquidity_positions: Dict[int, LiquidityPosition] = {}  # A record of all liquidity positions.
        self.rounds: Dict[int, Round] = {}  # A record of all rounds.
        self.current_round_id: Optional[int] = None  # The ID of the current round.
        self.next_round_id: Optional[int] = 0  # The ID of the next round.
        self.rounds[self.next_round_id] = self._create_new_round(self.next_round_id)


    def open_liquidity_position(self, amount: int) -> int:
        # Ensure the amount meets the minimum deposit requirement
        if amount < self.config.MIN_DEPOSIT_AMOUNT:
            raise Exception("Deposit amount is below the minimum requirement.")

        sender = self.blockchain.get_current_sender()

        # Create a new liquidity position with a unique ID
        new_position = LiquidityPosition(depositor=sender, position_id=self.position_id, round_id=self.next_round_id)
        self.liquidity_positions[self.position_id] = new_position

        # Record this liquidity position
        self.liquidity_positions[self.position_id] = self.next_round_id  # Save the round ID against the position ID
        

        new_entry = RoundPositionEntry(amount, self.next_round_id)
        # Create an entry in RoundPositions
        self.round_positions[(self.next_round_id, self.position_id)] = new_entry

        # Update the total collateral for the next round.
        self.rounds[self.next_round_id].total_collateral += amount

        # Update the position ID for future positions
        self.position_id += 1
        return self.position_id - 1  # Return the unique ID of the new liquidity position
        
    def start_new_option_round(self) -> Tuple[int, OptionRoundParams]:
        """
        Starts a new option round if minimum collateral is met, changing the state of the round, and prepares the next round.
        """
        if self.next_round_id is None:
            raise Exception("No round initialized yet.")

        next_round = self.rounds[self.next_round_id]

        # Check if the round has the minimum required collateral.
        total_collateral = next_round.total_collateral

        if total_collateral < self.config.MIN_COLLATERAL:
            raise Exception("Minimum collateral required to start a new option round not met.")

        next_round.auction_start_time = datetime.utcnow()  # Or appropriate blockchain equivalent
        next_round.state = RoundState.AUCTION_STARTED

        # Set auction_end_time based on auction duration from config
        next_round.auction_end_time = next_round.auction_start_time + self.config.AUCTION_DURATION
        next_round.option_settlement_time = next_round.auction_start_time + self.config.ROUND_DURATION

        self.current_round_id = self.next_round_id
        self.next_round_id += 1

        # Prepare the next round
        self.rounds[self.next_round_id] = self._create_new_round(self.next_round_id)

        # # Creating the OptionRoundParams instance with the gathered data.
        # option_round_params = OptionRoundParams(
        #     current_average_basefee=current_average_basefee,
        #     standard_deviation=standard_deviation,
        #     strike_price=strike_price,
        #     cap_level=cap_level,
        #     collateral_level=collateral_level,
        #     reserve_price=reserve_price,
        #     total_options_available=total_options_available,
        #     option_expiry_time=option_expiry_time,
        #     auction_end_time=auction_end_time,
        #     minimum_bid_amount=minimum_bid_amount,
        #     minimum_collateral_required=minimum_collateral_required
        # )


        return self.current_round_id, OptionRoundParams(

        
    def deposit_liquidity_to(self, position_id, amount):
        """
        Deposit additional liquidity to an existing position.
        """
        if position_id not in self.liquidity_positions:
            raise Exception("No liquidity position found with the provided ID.")

        position = self.liquidity_positions[position_id]
        round_id = position.round_id  # retrieve the round_id from the position instance

        # We need to find the correct round to deposit to, and potentially create a new entry if rounds have advanced.
        while True:
            round_position_key = (round_id, position_id)
            
            if round_position_key not in self.round_positions:
                raise Exception(f"No entry in round_positions for round_id {round_id} and position_id {position_id}")

            round_position_entry = self.round_positions[round_position_key]
            
            if round_position_entry.next_round_id == round_id and self.next_round_id != round_id:
                # We're at the end of the linked list for this position, but the Vault has moved on to a new round.
                # So, we need to create a new entry and link it.
                
                new_round_position_entry = RoundPositionEntry(amount, self.next_round_id)
                self.round_positions[(self.next_round_id, position_id)] = new_round_position_entry  # Create new entry
                round_position_entry.next_round_id = self.next_round_id  # Update link of the old entry
                break
            elif round_position_entry.next_round_id == round_id:
                # We are in the correct round, so we update
                round_position_entry.amount += amount
                break
            else:
                # The position is in a newer round, so we update the round_id and continue the loop
                round_id = round_position_entry.next_round_id

        # Update any necessary state in the position, if required
        position.amount += amount  # Assuming the position also tracks its total amount

        # Update the total collateral for the next round.
        self.rounds[self.next_round_id].total_collateral += amount

        return f"Liquidity position {position_id} updated with an additional {amount}."
    
    def _create_new_round(self, new_round_id: int):
        """
        Internal method to initialize and register a new round within the vault.
        """

        # Define the start time for the new round. This could be 'now' or a specific start time if rounds are scheduled.
        start_time = datetime.datetime.now()  # Or specific scheduling based on your application logic.

        # Create a new Round instance with the necessary parameters.
        new_round = Round(
            round_id=new_round_id,
            start_time=start_time,
            strike_price_strategy=self.strike_price_strategy,
            blockchain=self.blockchain,
            market_aggregator=self.market_aggregator,
            config=self.config
        )

        # Return the new round. Depending on your application's flow, you might return the round, its ID, or a status indicator.
        return new_round
    

    # Implement the other IVault methods...


# Usage
market_aggregator = MarketAggregator()
market_aggregator.set_prev_month_std_dev(5000)  # Simulating previous month's standard deviation
market_aggregator.set_prev_month_avg_basefee(100)  # Simulating average base fee

# create a blockchain instance
blockchain = Blockchain()

# Create strategies
out_of_the_money_strategy = OutOfTheMoneyStrategy(market_aggregator)

# create a vault instance with the blockchain
vault = Vault(out_of_the_money_strategy, blockchain, market_aggregator)

# Simulate a new transaction by setting the sender and time
blockchain.set_current_sender("0x123abc")
blockchain.set_current_time(datetime.utcnow())

new_position_id = vault.open_liquidity_position( int(1000))
print(f"Opened new liquidity position with ID: {new_position_id}")    