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
    pass

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

class LiquidityPosition:
    def __init__(self, position_id, depositor, amount):
        self.position_id = position_id
        self.depositor = depositor
        self.amount = amount


class Round:
    def __init__(self, blockchain: Blockchain, market_aggregator: MarketAggregator,  round_id: int, config: VaultConfig):
        self.round_id = round_id
        self.state = RoundState.INITIALIZED
        self.min_bid_amount = config.MIN_BID_AMOUNT
        self.min_deposit_amount = config.MIN_DEPOSIT_AMOUNT
        self.min_collateral = config.MIN_COLLATERAL
        self.blockchain = blockchain
        self.market_aggregator = market_aggregator
        self.liquidity_position_ids: List[str] = []  # Stores the IDs of associated liquidity positions

        
        # Timing parameters
        self.round_start_time: Optional[datetime] = None
        self.auction_start_time: Optional[datetime] = None
        self.auction_end_time: Optional[datetime] = None
        self.option_settlement_time: Optional[datetime] = None


    def add_liquidity_position(self, position_id: str, position: LiquidityPosition):
        # Add the position ID to this round's list of positions
        self.liquidity_position_ids.append(position_id)

        # Additional parameters like bids, option issuance, etc., can be added here.


        

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

        self.liquidity_positions: Dict[int, Dict] = {}  # A record of all liquidity positions.
        self.owner_position_mapping: Dict[Address, int] = {}  # Mapping owners to their positions.

    def open_liquidity_position(self, amount: int) -> str:
        # Ensure the amount meets the minimum deposit requirement
        if amount < MIN_DEPOSIT_AMOUNT:
            raise Exception("Deposit amount is below the minimum requirement.")

        sender = self.blockchain.get_current_sender()

        # Create a new liquidity position with a unique ID
        position_id = str(uuid.uuid4())
        new_position = LiquidityPosition(depositor=sender, amount=amount)
        self.liquidity_positions[position_id] = new_position

        # Assign this liquidity position to the next round (if it exists)
        if self.next_round_id in self.rounds:
            self.rounds[self.next_round_id].add_liquidity_position(position_id, new_position)

        # Alternatively, if the round doesn't exist yet, create it and assign the position.
        else:
            new_round = Round(blockchain=self.blockchain, round_id=self.next_round_id)
            new_round.add_liquidity_position(position_id, new_position)
            self.rounds[self.next_round_id] = new_round

        return position_id  # Return the unique ID of the new liquidity position
        
    def start_new_option_round(self):
        """
        Starts a new option round if minimum collateral is met, changing the state of the round, and prepares the next round.
        """
        if self.current_round_id is None:
            raise Exception("No round initialized yet.")

        current_round = self.rounds[self.current_round_id]

        # Check if the round has the minimum required collateral.
        total_collateral = sum(
            pos['amount'] for pos in self.liquidity_positions.values() if pos['round_id'] == self.current_round_id
        )

        if total_collateral < self.config.MIN_COLLATERAL:
            raise Exception("Minimum collateral required to start a new option round not met.")

        current_round.auction_start_time = datetime.utcnow()  # Or appropriate blockchain equivalent
        current_round.state = RoundState.AUCTION_STARTED

        # Set auction_end_time based on auction duration from config
        current_round.auction_end_time = current_round.auction_start_time + self.config.AUCTION_DURATION
        current_round.option_settlement_time = current_round.auction_start_time + self.config.ROUND_DURATION

        # Prepare the next round
        self._create_new_round()
    

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