import uuid
import threading
from eth_typing import Address
from datetime import timedelta, datetime
from typing import Dict, List, Optional, Any, Protocol, Tuple
import math
from scipy.stats import norm


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
                 max_payout_per_option: int,
                 reserve_price: int, 
                 total_options_forsale: int,
                 option_expiry_time: int, 
                 auction_end_time: int, 
                 minimum_bid_amount: int, 
                 minimum_collateral_required: int):
        self.current_average_basefee = current_average_basefee  # in wei
        self.standard_deviation = standard_deviation
        self.strike_price = strike_price  # in wei
        self.cap_level = cap_level  # in wei
        self.collateral_level = collateral_level
        self.max_payout_per_option = max_payout_per_option
        self.reserve_price = reserve_price  # in wei
        self.total_options_forsale = total_options_forsale
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

    # amount is in wei and its the total amount that the user is willing to pay for the options. price is the max price per option
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
        self.total_options_forsale = None
        self.total_options_sold = None
        self.reserve_price = None
        self.max_payout_per_option = None
        self.bids: List[Dict[str, int]] = []  # List of bids. Each bid is a dictionary.
        self.options_distribution = {}  # Records the number of options each bidder receives
        self.refunds = {}  # Records the refund amounts in wei



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

    def decimals(self) -> int:  
        return 18
        
    def calculate_option_payout(self, round: Round, settlement_price: int) -> int:
        """
        Calculate the payout for an option position based on the settlement price.

        :param round: The round instance containing details like strike price and cap level.
        :param settlement_price: The settlement price of the underlying asset in wei.
        :return: The payout amount in wei.
        """
        # Convert settlement price and strike price from wei to Gwei for the calculations.
        settlement_price_gwei = settlement_price // 1e9  # Convert from wei to Gwei
        strike_price_gwei = round.strike_price // 1e9  # Convert from wei to Gwei
        cap_level_gwei = round.cap_level // 1e9  # Convert from wei to Gwei

        # Determine the difference in price, ensuring it's not negative.
        price_difference_gwei = max(settlement_price_gwei - strike_price_gwei, 0)

        # If the settlement price is greater than the strike price, calculate the payout.
        if price_difference_gwei > 0:
            # Payout is 1 ETH per Gwei of price difference.
            # However, the payout is capped at the cap level.
            payout_gwei = min(price_difference_gwei, cap_level_gwei)

            # The payout is in ETH, equivalent to the price difference in Gwei.
            payout = payout_gwei * round.collateral_level  # 1 ETH = 1e18 wei
        else:
            # If the settlement price is below or equal to the strike price, there's no payout.
            payout = 0

        return payout

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
        next_round.strike_price = self.strike_price_strategy.calculate()
        next_round.cap_level = self.market_aggregator.get_prev_month_avg_basefee() + (3 * self.market_aggregator.get_prev_month_std_dev())
        print(f"next_round.cap_level: {next_round.cap_level}") 
        print(f"next_round.strike_price: {next_round.strike_price}")
        # Convert the cap_level and strike_price from wei to Gwei for the calculations.
        cap_level_gwei = next_round.cap_level // 1e9  # Convert from wei to Gwei
        strike_price_gwei = next_round.strike_price // 1e9  # Convert from wei to Gwei
        # The collateral_level represents the maximum payout per option in wei.
        next_round.collateral_level = 1e18  # 1 ETH in wei, since the payout is 1 ETH per Gwei difference

        # Calculate the price difference limit in Gwei.
        price_difference_limit = cap_level_gwei - strike_price_gwei
        print(f"Price difference limit in Gwei: {price_difference_limit}")       

        # Calculate the maximum payout in wei for one option.
        # This is the payout per Gwei difference times the maximum Gwei difference.
        next_round.max_payout_per_option = next_round.collateral_level * price_difference_limit

        # Calculate the total number of options that the total collateral can support.
        # This is the total collateral divided by the maximum payout for one option.
        next_round.total_options_forsale = next_round.total_collateral // next_round.max_payout_per_option  # Floor division for whole options
        next_round.reserve_price = self.market_aggregator.get_prev_month_std_dev() * 2 # just an assumption

        self.current_round_id = self.next_round_id
        self.next_round_id += 1

        # Prepare the next round
        self.rounds[self.next_round_id] = self._create_new_round(self.next_round_id)

        # Gather the necessary data to return to the caller.
        current_average_basefee = self.market_aggregator.get_current_month_avg_basefee()
        standard_deviation = self.market_aggregator.get_prev_month_std_dev()
        strike_price = next_round.strike_price
        cap_level = next_round.cap_level
        collateral_level = next_round.collateral_level
        max_payout_per_option = next_round.max_payout_per_option
        reserve_price = next_round.reserve_price
        total_options_forsale = next_round.total_options_forsale
        option_expiry_time = next_round.option_settlement_time
        auction_end_time = next_round.auction_end_time
        minimum_bid_amount = self.config.MIN_BID_AMOUNT
        minimum_collateral_required = self.config.MIN_COLLATERAL

        option_round_params = OptionRoundParams(
            current_average_basefee=current_average_basefee,
            standard_deviation=standard_deviation,
            strike_price=strike_price,
            cap_level=cap_level,
            collateral_level=collateral_level,
            max_payout_per_option=max_payout_per_option,
            reserve_price=reserve_price,
            total_options_forsale=total_options_forsale,
            option_expiry_time=option_expiry_time,
            auction_end_time=auction_end_time,
            minimum_bid_amount=minimum_bid_amount,
            minimum_collateral_required=minimum_collateral_required
        )

        return self.current_round_id, option_round_params

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
        start_time = datetime.now()  # Or specific scheduling based on your application logic.

        # Create a new Round instance with the necessary parameters.
        new_round = Round(
            round_id=new_round_id,
            # start_time=start_time,
            strike_price_strategy=self.strike_price_strategy,
            blockchain=self.blockchain,
            market_aggregator=self.market_aggregator,
            config=self.config
        )

        # Return the new round. Depending on your application's flow, you might return the round, its ID, or a status indicator.
        return new_round
    
    def fetch_current_round(self):
        """
        Fetch the current round based on the current round ID.

        :return: The current round object.
        """
        if self.current_round_id in self.rounds:
            return self.rounds[self.current_round_id]
        else:
            raise ValueError("No active auction round found.")

    def auction_place_bid(self, bid_amount, bid_price):
        """
        Place a new bid in the auction if it meets the reserve price.

        :param bidder_id: The ID/address of the bidder.
        :param bid_amount: The total amount in wei the bidder is willing to pay.
        :param bid_price: The price per option in wei the bidder is willing to pay.
        """
        current_round = self.fetch_current_round()

        if current_round.state != RoundState.AUCTION_STARTED:
            raise ValueError("Can only place bids in a round where the auction has started.")

        if bid_price < current_round.reserve_price:
            raise ValueError("Your bid amount is below the reserve price.")

        # Ensure the bid is placed before the auction end time
        current_time = self.blockchain.get_current_time()  # Or however you obtain the current time
        if current_time >= current_round.auction_end_time:
            raise ValueError("The auction has ended. No more bids can be placed.")

        bidder_id = self.blockchain.get_current_sender()

        # Place the bid (This could be adding the bid to a list of bids, or however your system accepts new bids)
        new_bid = {
            'bidder_id': bidder_id,
            'size': bid_amount,  # Total amount in wei the user is willing to pay
            'price': bid_price,  # Price per option in wei the user is willing to pay
        }
        current_round.bids.append(new_bid)
        print(f"Bid placed for bidder {bidder_id} with amount {bid_amount} and price {bid_price}.")

    def settle_auction(self):
        """
        Settle the auction based on the bids and distribute options accordingly.
        """
        current_round = self.fetch_current_round()

        if current_round.state != RoundState.AUCTION_STARTED:
            raise ValueError("Can only settle an auction that has started.")

        # Fetch the current time from the blockchain
        current_blockchain_time = self.blockchain.get_current_time()

        # Check if the auction settle time has been reached
        if current_blockchain_time < current_round.auction_end_time:
            raise ValueError("Auction time has not expired yet.")

        # Validation to ensure auction can be settled
        if not current_round.bids:
            raise ValueError("No bids in this auction round.")

        sorted_bids = sorted(current_round.bids, key=lambda x: (-x['price'], x['size']))  # Assuming you want to sort by price then size

        # Calculate the clearing price
        clearing_price = self._calculate_clearing_price(current_round)
        print(f"Clearing price: {clearing_price} ")

        if clearing_price == 0:
            raise ValueError("Auction could not clear any options. No sale occurred.")

        # Distribute options and handle transactions
        self._distribute_options_based_on_clearing_price(current_round, clearing_price )

        # Auction has ended
        current_round.state = RoundState.AUCTION_SETTLED
        print("Auction has settled.")

    def _calculate_clearing_price(self, current_round: Round) -> int:
        """
        Calculate the clearing price based on the current round's bids and options available.

        :param current_round: The current round object containing all relevant auction data.
        :return: The calculated clearing price in wei.
        """
        # Filter bids that meet or exceed the reserve price and sort them by price in descending order.
        filtered_bids = [bid for bid in current_round.bids if bid['price'] >= current_round.reserve_price]
        filtered_bids.sort(key=lambda x: (-x['price'], x['size']))

        # Initialize the clearing price
        clearing_price = 0

        # Determine the clearing price.
        for current_price in [bid['price'] for bid in filtered_bids]:
            # Calculate the total units that would be bought at this price point.
            total_units = sum([min(bid['size'] // current_price, current_round.total_options_forsale) for bid in filtered_bids if bid['price'] >= current_price])
            
            # If the total units meet or exceed the options available, we've found our clearing price.
            if total_units >= current_round.total_options_forsale:
                clearing_price = current_price
                break

        # If no suitable clearing price was found during the iteration (i.e., demand was too low), 
        # use the price of the lowest valid bid.
        if not clearing_price and filtered_bids:
            clearing_price = filtered_bids[-1]['price']

        return clearing_price
    
    def _distribute_options_based_on_clearing_price(self, current_round: Round, clearing_price: int):
        options_left = current_round.total_options_forsale
        allocations = {}  # Temporary storage for option allocations
        refunds = {}  # Temporary storage for refunds

        print(f"\nDistributing options for round {current_round.round_id} with clearing price: {clearing_price}")
        print("Starting option distribution...\n")

        for bid in current_round.bids:
            bidder_id = bid['bidder_id']
            if bid['price'] < clearing_price:
                refunds[bidder_id] = bid['size']  # Full refund since no options were bought
                print(f"Bidder {bidder_id} bid below the clearing price. A full refund of {bid['size']} will be issued.")
            else:
                # Calculate the number of options the bidder receives
                options_to_allocate = min(options_left, bid['size'] // clearing_price)
                options_left -= options_to_allocate

                if options_to_allocate > 0:
                    allocations[bidder_id] = options_to_allocate
                    print(f"Bidder {bidder_id} receives {options_to_allocate} options.")

                # Calculate if there's any amount to be refunded
                refund_amount = bid['size'] - (options_to_allocate * clearing_price)
                if refund_amount > 0:
                    refunds[bidder_id] = refund_amount
                    print(f"Bidder {bidder_id} will be refunded {refund_amount} due to overpayment.")

        # After processing all bids, update the round's records.
        current_round.option_allocations = allocations
        current_round.refunds = refunds

        if options_left > 0:
            print(f"\n{options_left} options remain undistributed after the auction.")

        print("\nOption distribution completed.\n")
        


            
    # Implement the other IVault methods...


# Usage

market_aggregator = MarketAggregator()
# set the prev month std dev and avg base fee in wei
prev_month_std_dev = 4 * 1e9
prev_month_avg_basefee = 20 * 1e9
market_aggregator.set_prev_month_std_dev(prev_month_std_dev)  # Simulating previous month's standard deviation
market_aggregator.set_prev_month_avg_basefee(prev_month_avg_basefee)  # Simulating average base fee

# create a blockchain instance
blockchain = Blockchain()

# Create strategies
out_of_the_money_strategy = OutOfTheMoneyStrategy(market_aggregator)

# create a vault instance with the blockchain
vault = Vault(out_of_the_money_strategy, blockchain, market_aggregator)

# Simulate a new transaction by setting the sender and time
blockchain.set_current_sender("0x123abc")
blockchain.set_current_time(datetime.utcnow())

new_position_id_1 = vault.open_liquidity_position( int(100) * 10**18)
print(f"Opened new liquidity position with ID: {new_position_id_1}")    

#simulate another transaction with a different sender and time

blockchain.set_current_sender("0x456def")
blockchain.set_current_time(datetime.utcnow())

new_position_id_2 = vault.open_liquidity_position( int(200) * 10**18)
print(f"Opened new liquidity position with ID: {new_position_id_2}")

blockchain.set_current_sender("0x456d11")
blockchain.set_current_time(datetime.utcnow())

new_position_id_2 = vault.open_liquidity_position( int(300) * 10**18)
print(f"Opened new liquidity position with ID: {new_position_id_2}")

# start a new option round
round_id, option_round_params = vault.start_new_option_round()
#print all the option_round_params
print(f"Started new option round with ID: {round_id}")
print(f"Current average basefee: {option_round_params.current_average_basefee}")
print(f"Standard deviation: {option_round_params.standard_deviation}")
print(f"Strike price: {option_round_params.strike_price}")
print(f"Cap level: {option_round_params.cap_level}")
print(f"Collateral level: {option_round_params.collateral_level}")
print(f"Max payout per option: {option_round_params.max_payout_per_option}")
print(f"Reserve price: {option_round_params.reserve_price}")
print(f"Total options for sale: {option_round_params.total_options_forsale}")
print(f"Option expiry time: {option_round_params.option_expiry_time}")
print(f"Auction end time: {option_round_params.auction_end_time}")
print(f"Minimum bid amount: {option_round_params.minimum_bid_amount}")
print(f"Minimum collateral required: {option_round_params.minimum_collateral_required}")

blockchain.set_current_sender("0x456d22")

# place a bid where size is in wei and price si in wei per option
size = 10 * 10 ** vault.decimals()
price = 10 * 10 ** vault.decimals()
vault.auction_place_bid( size , price)

# place another bid
blockchain.set_current_sender("0x456d23")

size = 20 * 10 ** vault.decimals()
price = 20 * 10 ** vault.decimals()
vault.auction_place_bid( size , price)

# place another bid
blockchain.set_current_sender("0x456d25")

size = 30 * 10 ** vault.decimals()
price = 30 * 10 ** vault.decimals()
vault.auction_place_bid( size , price)

blockchain.set_current_time(option_round_params.auction_end_time + timedelta(days=1))
vault.settle_auction()
