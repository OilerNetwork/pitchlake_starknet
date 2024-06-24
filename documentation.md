# Pitchlake Crash Course

**Pitchlake** creates an options market for Ethereum basefee on Starknet, the official paper is [here](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018). This documentation is written as a crash course and architecture overview of the protocol. It is intended to onboard new devs/catch them up to speed, and hopefully serve as a pre-prompt for models assisting in the development. Feel free to update or add things as you see fit.

## What Are Options ?

Options are financial contracts that give a buyer the right, but not the obligation, to buy or sell an asset at a predetermined price. Options can be used as a form of insurance, allowing the buyer to hedge against unfavorable price movements. They can also be used to speculate on price movements, with the potential to earn profits if the price moves in the option buyer’s favor.

In the context of Pitchlake, we will use liquidity deposits to auction call options to buyers. These call options will give their owner the right to exercise their options, buying basefee at the price set in the contract.

## How EIP-1559 Decides Basefee

Under [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559), each block has a base fee, which is the minimum price per unit of gas for inclusion in this block. The base fee is calculated independently of the current block and is instead determined by the blocks before it - making transaction fees more predictable for users.

Here's how the base fee is calculated:

1. The protocol sets a base fee for each block.
2. If the previous block used more than the target gas (set at 50% of the maximum gas limit per block), the base fee increases. Conversely, if it used less, the base fee decreases. The amount of change is proportional to how far gas usage deviated from the target gas.
3. To prevent large swings in the base fee, the amount it can change from one block to the next is limited (currently to 12.5% per block).
4. Any transaction fees above the base fee are given to the miner as a tip.

This mechanism aims to make base fees more predictable and responsive to network congestion compared to the previous model. However, base fees can still fluctuate significantly block by block, particularly during periods of high network activity. This variability can make it challenging for rollups to accurately estimate the cost of their transactions over longer time horizons.

## Why Buy Basefee Options ?

A rollup uses a lot of gas each month settling L2 blocks on L1, hence L2 gas fees. The goal of the rollup is the have L2 → L1 settlements as cheap as possible, charging the L2 users just enough to cover it.

A problem arises from the fluctuating gas prices on Ethereum, coupled with the latency between L2 → L1 settlement. A transaction on L2 could happen hours before it is settled on L1, leaving the rollup to guess or use some heuristic when pricing the L2 transaction. With Pitchlake, these rollups can now hedge their exposure to these fluctuating gas prices on Ethereum, providing a more consistent fee experience for the L2 users.

When an option round settles, if the average basefee for the round is > the strike price of the options, they become exercisable (more on this later in the crash course). In a traditional market, this exercising would entail option buyers (OBs) being able to purchase basefee at the strike price; however, basefee is not a direct commodity that can be transferred like this. Instead, when OBs exercise their options, they are given a payout for the difference between the strike price and average basefee over the course of the option round.

# A High-level Overview of the Contracts

## The Vault

The vault acts as the central hub for liquidity providers (LPs) to deposit and withdraw their funds. When an LP deposits liquidity, the vault updates the LP's position in storage. Liquidity is classified in 2 buckets, locked and unlocked. When an auction starts, all unlocked liquidity becomes locked (collateral for the potential option payout). All deposits and withdraws pertain to an LP's unlocked balance. The vault will have a pointer to the **current** option round.

## Option Rounds

An option round is a distinct period of trading, contained within its own contract. These rounds allow for the auction, settlement, and exercising of Ethereum basefee options, with each contract managing its specific set of options. These contracts implement the ERC20 standard, minting tokens to the option buyers (OBs) to represent the options themselves.

### Option Round States

An option round transitions through 4 states during its life cycle: _Open_ | _Auctioning_ | _Running_ | _Settled_. A round is initially deployed with state _Open_. The state becomes _Auctioning_ once its auction begins, _Running_ once its auction ends, and once the option round concludes, its state permanently becomes _Settled_. In the context of the vault, the **current** option round will always be either: _Open_ | _Auctioning_ | _Running_. When the **current** round settles, we deploy the next option round contract, update the current round, and start a **round transition period**. The round transition period must pass before we start the **next** auction. This **round transition period** and option round states are detailed further into the crash course.

## LP Tokens

When an LP deposits liquidity, their positions are stored in the vault contract's storage. The details of their positions remain within in storage from round to round, and when a user wishes to withdraw their funds, these details are used to calculate the value of their position at the current time.

However, if an LP wishes to sell their current position (maybe LP speculates there will be a payout and their position will decrease in value), they can convert their position into LP tokens (ERC20s), and sell them on the secondary market. At any point, these LP tokens can be converted back into a deposit into the protocol.

**_Simply:_** An LP’s position is handled through storage in the vault contract, and only becomes tokenized if the LP chooses to convert their active position to LP tokens. These positions and LP tokens are discussed in more detail later in the crash course.

# Contract Entry Points

## The Vault:

- **Deposit**: LP adds liquidity to the protocol (into their unlocked balance)
- **Withdraw**: LP withdraws from their liquidity (from their unlocked balance)
- (\*)Start Auction: Starts the auction for the current round, cannot be called before the round transition period has passed. Locks all unlocked liqudity.
- (\*)End Auction: End the auction for the current round, cannot be called before the auction end date has been passed.
- (\*)Settle Option Round: Settles the current option round, cannot be called before the settlement date has passed. Unlocks all remaining liquidity.

> \* Anyone can call these state transition functions, the incentivisation scheme still needs to be designed.

## An Option Round:

- (\*) **Start Auction**: Begins the auction phase of the round, allowing option buyers (OBs) to place bids for the available options.
- **Place Auction Bid**: OB submits a bid for options.
- (\*) **End Auction**: Concludes the auction, determining the final distribution of options and premiums. If any of the available options do not sell, a portion of the locked liquidity becomes unlocked. The premiums earned (and any unsold liquidity) is sent from the option round to the vault (unlocked bucket). LPs can withdraw these premiums and unsold liquidity once the auction ends. If they ignore them, they will be included in LP's rolled over liquidity to the next round).
- **Refund Unused Bids**: OB collects any of their bids that were not fully utilized (converted to premium).
  > _i.e._ If OB bids for 10 options @ 2ETH each (20ETH total), and the clearing price comes out to be 1ETH, then 10ETH becomes refundable and can be collected at any time after the auction settles.
- **Tokenize Options**: OB converts the options they earn in the auction to ERC20 tokens. More on this later.
- (\*) **Settle Option Round**: Settles the option round and calculates the total payout of the option round. If there is a payout (index > strike), then the total payout is sent from the vault (locked bucked) to the option round. At this time, the next option round is deployed (with state _Open_) and the **current round** pointer is updated.
- **Exercise Options**: OB exercises their options to claim their individual payout, corresponding to the number of options they own. OBs can exercise their options at any time after the round settles.

> \* Only the vault can call these state transition functions, but anyone can call the wrapping entry points in the vault.

# A Closer Look at the Contracts

### The Vault <-> Option Round State Connection

The vault has a pointer to the current round. The current round will always be either: _Open_ | _Auctioning_ | _Running_, and all previous rounds will be _Settled_.

Once we pass the current round’s settlement date, we can settle it. Once a round settles, we deploy the next round, update the current round pointer, and the **round transition window** must pass before the next round’s auction can start. This window gives Pitchlake LPs time to withdraw from their rolled over positions, but also allows any LPs from other protocols to enter.

> _This is because if other protocols adopt the same option round schedule as Pitchlake, then without a transition window, there would be no time for LP’s to exit another protocol and join before the next auctions starts, nor would Pitchlake LPs have time to withdraw their positions before they get locked into the next round._

Once this round transition window passes, we can call the `vault::start_auction()` entry point. This will start the option round’s auction (_Open → Auctioning_).

**Example**:

When the vault deploys, its **current** round pointer is 1 (_Open_). Once `vault::start_auction()` is called, round 1 becomes _Auctioning_.

The **current** option round (1) continues, transitioning from _Auctioning_ to _Running_ to _Settled_. During this time, any deposits to the vault will be sent to the unlocked bucket. After round 1 settles, round 2 is deployed and becomes the current round. Once the transition window passes, the cycle repeats. `vault::start_auction()` is called, round 2 becomes _Auctioning_, and all unlocked liquidity becomes locked.

**In Summary:**

- There will always be a current option round
  - The current round will always be: _Open_ | _Auctioning_ | _Running_
  - The previous rounds will always be: _Settled_
- Once the current round settles, the next round is deployed and it becomes the current round.
- There is a window of time that must pass before the next round's auction can start (round transition period).
- When an auction starts, all unlocked liquidity becomes locked.
- When an option round settles, all remaining locked liquidity becomes unlocked
- Deposits always go into the unlocked bucket
- Withdraws always come from the unlocked bucket
- If an LP does not withdraw their premiums before the next auction starts, it adds to their position in the next round

### The Life Cycle of an Option Round

**A Round Opens**

A round deploys with state _Open_ as the **current** round in the vault. A round will remain _Open_ until its auction starts.

**The Auction Starts**

Once a round’s auction starts, its state becomes _Auctioning_. While a round is _Auctioning_, OBs can submit bids using the `OptionRound::place_bid(amount, price)` entry point:

> `amount:` The max amount of options OB is bidding for.

> `price:` The max price per individual option that OB is bidding.

> i.e. A bid of (10, 2) means the bidder wants at most 10 options and is willing to spend up to 2ETH per option. If the clearing price is > 2ETH, the entire bid becomes refundable, and if the clearing price is < 2ETH, then the OB can receive up to 10 options, and the rest of their funds becomes refundable (if they receive 10 options at 1ETH, then 10ETH is refundable and 10ETH is collected as premiums).

**The Auction Ends**

Once the option bidding period has passed, the auction can end, updating the round’s state to _Running_ (while remaining the **current** round in the vault). Pitchlake will use a fair batch auction to settle these auctions. A technical overview of these fair batch auctions can can be found [here](https://docs.cow.fi/cow-protocol/concepts/introduction/batch-auctions), and some examples are discussed later in this crash course.

When the auction settles, the **clearing price** is calculated. This is the price per individual option. With this clearing price, we can calculate how many options each OB will receive, along with how much of the OBs’ bids were used & unused.

The used bids are known as the **premiums**. They are what the OBs end up spending to obtain the options, and are paid to the LPs. Any bids not converted to premiums are claimable via: `OptionRound::refund_unused_bids(OB: ContractAddress).`

The options will be in the form of ERC20 tokens, distributed to OBs at the end of the auction. Tokenizing the options allow them to be traded/sold/burned/aggregated/packaged into new derivates/etc. To save on gas, options will not be minted upon auction end, instead the user will need to tokenize their options (if they wish to transfer/sell them). See [this notion page](https://www.notion.so/nethermind/Bid-Notes-b2c4f7c8995a4727993e771e96a134e5?pvs=4) for more details.

**The Option Round Settles**

Once the option settlement date has been reached, the next step is to settle the round. This permanently sets the round’s state to _Settled_ (deploying the new current round). Fossil lets us know what the average basefee over the option round's duration was, and depending on this value, the options may become exercisable (more on Fossil later in the crash course). If the options become exercisable, the total payout of the options is calculated (and sent from the vault's locked bucket to the option round). This allows an OB to burn their options in exchange for their portion of the payout.

When the round settles, all of the remaining liquidity (locked - payout) becomes unlocked, and we start the round transition period. At this time the new current round is deployed and values from Fossil are used to initialize the round's details (more on this later).

> **NOTE:** If an LP does not collect their premiums (unlocked liquidity) during a round, it is not lost. It is included as part of their rolled over liquidity into the **next** round.

After the transition period passes, the next round’s auction can start, repeating the same life cycle.

# A Technical Deep Dive

## `Vault::Positions`

### Storage Representation

When an LP deposits liquidity, they update their position inside the vault. A position is represented by a fairly simple mapping, along with the id of the round an LP made their last withdrawal from. This checkpoint allows us to calculate a position's value in later rounds.

```rust
#[storage]
struct Storage {
	// Amount of liquidity LP deposited into a round
	positions: map(LP: ContractAddress, round_id: uint) -> amount: uint,

	// The last round LP made a withdrawal from
	withdraw_checkpoints: map(LP: ContractAddress) -> round_id: uint,
}
```

**Example**: LP deposits 1 ETH into round 1, and 1 ETH into round 3, their position will look like this:

```rust
          | 1 | -> | 1 eth |
| LP | -> | 2 | -> |   0   |
          | 3 | -> | 1 eth |
```

Some pseudo code for a deposit is below:

```rust
// LP deposits liquidity into the next round
fn deposit_liquidity(LP: ContractAddress, amount: u256) {
  let current_round_id = vault::current_round_id;
	let next_round_id = current_round_id + 1;

  // Update LP's position in the next round
  positions[LP, next_round_id] += amount;

  // Transfer the funds to the vault
  ETH_DISPATCHER.transfer_from(LP, this_contract::contract_address, amount);
}
```

### Calculating a Position's Value

When an LP withdraws from their position, we need to calculate its value at the current time. For each round an LP’s position sits, its value is subject change. This change is based on how much premium the round collects (from OBs), and how much the round has to payout (to OBs). We can define this remaining liquidity like so:

```rust
let remaining_liquidity = round.total_deposits() + round.total_premiums() - round.total_payouts();
```

Since withdrawals come from an LP's unlocked balance, if they wish to withdraw their entire position, it must be during the round transition period. Otherwise they are only able to withdraw their premiums. This is because premiums are sent to the unlocked bucket as soon as the auction ends, but the locked liquidity remains locked until the round settles.

If an LP supplied 50% of a round’s liquidity, they own 50% of the round’s remaining liquidity once it settles. If an LP does not collect any of their premiums or unlocked liquidity, their portion (50%) of the remaining liquidity is rolled over to the next round. This rolled over amount is their position in the next round.

This next round’s position and the next round’s total deposits determine the percentage of the next round's pool that LP supplied. With this percentage, we know how much of the round’s remaining liquidity belonged to LP.

This process repeats for all the rounds the LP’s position sits in, some pseudo code for an LP withdrawing from their position is below.

We start by calculating LP’s position value at the end of the current round (ending_amount), and check to make sure LP is not withdrawing more than this value. The next step, is to update LP’s position & withdraw checkpoint. This allows us to calculate the position’s value during the next withdraw. Finally, we transfer the withdraw amount from the unlocked bucket to LP.

```rust
// LPs can only withdraw at any time, but their entire position is only unlocked during the round transition period.
// This pseudo code demonstrates withdrawing from an entire position, hence us checking the state of the current round.
// In practice, the LP can withdraw at any time, but to keep the example simple, we are constraining it to only during the
// round transition period.
// @param LP: The address withdrawing liquidity
// @param withdraw_amount: The amount LP is trying to withdraw
fn withdraw_from_position(LP: ContractAddress, withdraw_amount: uint) {
  // Get the current and next round ids from the vault
	let current_round_id = vault::current_round_id;
  let previous_round_id = current_round_id - 1;

  // Assert the current round is open (meaning we are in the round transition period)
  assert_round_is_open(current_round_id);

	// The amount LP's position is worth at the end of the current round
	let mut ending_amount = 0;

  // Iterate through each round position from the last withdraw checkpoint to the previous round (both inclusive)
	for i in range(withdraw_checkpoints[LP], previous_round_id) {
		// How much liquidity did LP supply in this round
		let starting_amount = ending_amount + vault::positions[LP, i];

		// Get a round i dispatcher
		let this_round = RoundDispatcher {address_for_round(i)};

    // How much liquidity remained in this round
		let remaining_liquidity = this_round.total_deposits() + this_round.total_premiums() - this_round.total_payouts();

		// How much of this round's pool did LP supply
		let pool_percentage = starting_amount / this_round.total_deposits();

		// LP ends the round with their share of the remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;

		// @dev For simplicity, we are not including the calculation for how much
		// of the premiums/unlocked liquidity LP may have collected during this round,
		// but it will need to be implemented, and look something like:
		// `ending_amount -= lp_collections_in_round(LP, i)`,
		// where `lp_collections_in_round()` retrieves how much premium/unlocked
		// liquidity LP collected during this round if any (collected funds were not rolled over to the next round)

  // @dev At this point, ending_amount is the value of LP's position at the end of the previous round.
  // @dev This is the amount rolled over into the current round.

	if (withdraw_amount > ending_amount)
		revert_with_reason("Withdrawing more than position's value");

	// Update LP's position value after the withdraw
	positions[LP, current_round_id] = ending_amount - withdraw_amount;

	// Update LPs withdraw checkpoint for future calculations
	withdraw_checkpoints[LP] = current_round_id;

	// Send ETH from the vault to LP
	ETH_DISPATCHER.transfer_from(this_contract.contract_address(), LP, withdraw_amount);
}
```

### Token Representation

#### Positions → LP Tokens

The above architecture works fine for LPs to withdraw from their positions upon round settlements, but not if they wish to sell their active positions on a secondary market. To do this, they will need to tokenize their position by converting it from the vault's storage to LP tokens (ERC20), and selling them as such.

LP tokens represent a position's value at the start of a round net of any premiums collected from the round. By knowing the value of a position at the start of a round, we can calculate its value at the end of the round (once it settles), and there by also knowing the value going into the next round (by rolling over). There will be an LP token contract (ERC20) associated with each round. Meaning if an LP tokenizes their position during round 3 (r3), they are minted r3 LP tokens.

When an LP tokenizes their position, they are converting the value of their position at the start of the **current** round to LP tokens. They can only do so once the round's auction has ended, and before the option round settles. Simply, LPs can only tokenize their position in the **current** round if the **current** round's state is _Running_. The **current** round cannot be _Auctioning_, because the premiums would not be known yet, and it could not be _Open_ because then they could just withdraw their position normally (if current round is Open, it means we are in the round transition period).

Some pseudo code for an LP tokenizing their entire current position is below:

```rust
// LP tokenizes their entire current position.
// @dev The current round's auction must be over and the round cannot be settled yet
// @param LP: The account converting their position into LP tokens
fn tokenize_position(LP: ContractAddress){
  // Get the current and next round ids from the vault
	let current_round_id = vault::current_round_id;
	let next_round_id = current_round_id + 1;

  // Assert the current round is running
  assert_round_is_running(current_round_id);

  // Collect LP's premiums if they have not already
  collect_premiums_if_not_yet(LP);

	// The amount LP's position is worth at the end of the round
	let mut ending_amount = 0;

	// Iterate through each position from the last checkpoint to the previous round (both inclusive)
	for i in range(withdraw_checkpoints[LP], previous_round_id) {
		// How much liquidity did LP supply in this round
		let starting_amount = ending_amount + vault::positions[LP, i];

		// Get a round i dispatcher
		let this_round = RoundDispatcher {address_for_round(i)};

		// How much liquidity remained in this round
		let remaining_liquidity = this_round.total_deposits() + this_round.total_premiums() - this_round.total_payouts();

		// How much of this round's pool did LP own
		let pool_percentage = starting_amount / this_round.total_deposits();

		// LP ends the round with their share of the remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;

		// @dev For simplicity, we are not including the calculation for how much
		// of the premiums/unlocked liquidity LP may have collected during this round,
		// but it will need to be implemented, and look something like:
		// `ending_amount = ending_amount - lp_collections_in_round(LP, i)`,
		// where `lp_collections_in_round()` retrieves how much premiums and unlocked
		// liquidity LP collected during this round (as in, not rolled over to the next round)
	}

  // @dev At this point, ending_amount is the amount of liquidity LP ended the previous round with.
  // @dev This is the amount they started the current round with.

  // Update LP's position value after the exit
  positions[LP, current_round_id] = 0;

  // Update LP's withdraw checkpoint for future calculations
  withdraw_checkpoints[LP] = current_round_id;

  // Mint LP tokens to LP
  let LP_token_dispatcher = ERC20Dispatcher{contract_address: address_for_lp_token_contract(current_round_id)};
  LP_token_dispatcher.mint(LP, ending_amount);
}

```

#### Tokens -> Positions

Notice that when an LP tokenizes their position, they also collect their premiums from the round. This means that when these tokens get converted back into a position, the premiums from the round are not included in the calculation for their value. It is important to note that these tokens **do** accrue premiums, just not for the round they were created in.

For example: Say the current round is 3 and LP1 speculates that gas prices will go up, resulting in a payout for the option round. Instead of accepting this loss, LP1 decides to tokenize their position, and sell it, hoping to get more than this expected potential loss.

If LP1 tokenizes their position, this collects their r3 premiums (if they have not already), updates their position & withdraw checkpoint to 0 in r3, and then mints them r3 LP tokens. LP2 buys these tokens and sits on them for round 4 and chooses to convert them back into a position in round 5.

To do so, we use the r3 LP tokens to know the value of the position at the start of r3. With round 3's total deposits, we can calculate the percentage of the r3 pool these tokens supplied. Since r3 is settled, we know how much liquidity remained in the round. Using the r3 pool percentage we know the value of the tokens at the end of round 3. We subtract out the premiums earned from round 3 (since LP1 already collected them when they tokenized the position), and use this as the value of the tokens at the start of round 4. Since round 4 is settled we can do the same thing as before and calculate the value of the tokens at the end of round 4. This value (including the premiums earned this time) is the value of the tokens at the start of round 5. Once we know this value, we can burn the r3 LP tokens, and update LP2's round 5 position in the vault's storage to the calculated value.

Some pseudo code for converting LP tokens into positions is below:

```rust
// LP tokenizes their LP tokens into a position in the current round.
// @dev The LP tokens cannot be converted into a position in the same round they were created in. This
// is because then the LP would be able to drain the premiums.
// @param LP: The account converting their LP tokens into a position
// @param LP_token_id: The id of the round the LP tokens come from (3 would the the id in the previous example)
fn convert_LP_tokens_to_position(LP: ContractAddress, LP_token_id: uint, LP_token_amount: uint){
  // Get the current round id from the vault
	let current_round_id = vault::current_round_id;
  let previous_round_id = current_round_id - 1;

  // LP tokens cannot be converted into a position in the same round they were created in
  if (current_round_id == LP_token_id)
    revert_with_reason("Cannot convert LP tokens into a position in the same round they were created in");

  // @dev Calculate the value of the LP tokens at the end of the round they come from.

  // Get a round LP_token_id dispatcher
  let this_round = RoundDispatcher {address_for_round(LP_token_id + 1)};

  // How much liquidity remained in the round ignoring premiums
  let remaining_liquidity = this_round.total_deposits() - this_round.total_payouts();

  // How much of the round's pool did these tokens supply
  let pool_percentage = ending_amount / this_round.total_deposits();

  // The tokens are worth their share of the remaining liquidity
  let mut ending_amount = pool_percentage * remaining_liquidity;

	// Iterate through each round after the LP token id to the end of the previous round (both inclusive)
	for i in range(LP_token_id + 1, previous_round_id) {
		// Get a round i dispatcher
		let this_round = RoundDispatcher {address_for_round(i)};

		// How much liquidity remained in this round, including premiums
		let remaining_liquidity = this_round.total_deposits() + this_round.total_premiums() - this_round.total_payouts();

		// How much of this round's pool did LP own
		let pool_percentage = ending_amount / this_round.total_deposits();

		// LP ends the round with their share of the remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;
	}

  // @dev At this point, ending_amount is the value of the LP tokens at the end of the previous round
  // @dev This is the value at the start of the current round

  // Update LP's position value in the current round
	positions[LP, current_round_id] = ending_amount;

	// @dev Note, we are not concerned with LP's withdraw checkpoint since this acts like a typical deposit into the current round

  // Burn the LP tokens
  let LP_token_dispatcher = ERC20Dispatcher{address_for_lp_token_contract(LP_token_id)};
  LP_token_dispatcher.burn(LP, LP_token_amount);
}
```

# Batch Auctions

When we start an auction, we know the total liquidity for the round. Using this amount and data from Fossil, we will know the max number of options this round can sell. The goal of the auction is to sell as many of these options as it can. The auction will prioritize the quantity of options sold over the total premium. What this means is that if the auction will make less in premiums selling more of the options than selling less at a higher price, it will clear at the lower price. For example say an auction has 100 options to sell, if it can sell all 100 @ 1 ETH (100 ETH in premium) or 75 @ 2 ETH (150 ETH in premium), it will chose to sell 100 @ 1 ETH. However, the auction will prioritize the premium total if it is selling the most options it can. For example, say the auction has 100 options to sell, if it can sell 100 @ 1 ETH (100 ETH in premium), or 100 @ 1.5 ETH (150 ETH), it will chose to sell 100 @ 1.5 ETH.

OBs submit their bids using the `OptionRound::place_bid(amount, price)` entry point. The `amount` is the max amount of options that OB is bidding for, and the `price` is the max price per option the OB is willing to spend. This is the `amount * price` is the total amount of funds that will leave OB's wallet while the auction continues.

## Examples

**_Example 1: Basic Refunded/Unused Bids_**

- **Scenario:** OB1 bids for 10 options at 0.5 ETH each, other OBs also place various bids.
- **Outcome:** The auction settles with a clearing price of 0.6 ETH per option. Since OB1's maximum price was 0.5 ETH, none of their bid is used, making the entire 5 ETH refundable.

**_Example 2: Partially Successful Bid with Refund_**

- **Scenario:** The round has 30 options to sell. OB1 bids 20 options at 0.5 ETH per option (10 ETH total), and OB2 bids 20 options at 1 ETH per option (20 ETH total).
- **Outcome:** The clearing price is determined to be 0.5 ETH, to sell all 30 options. OB2, with the higher bid price, gets priority and receives 20 options. OB1 receives the remaining 10 options. Because of the lower clearing price, 10 ETH of OB2's 20 ETH is converted into premium, while only 5 ETH of OB1's bid is converted premium. OB1's remaining 5 ETH and OB2's remaining 10 ETH are refundable.

- **Note**: A clearing price > 0.5 ETH would not sell all 30 options, the goal of the auction is to sell as many options as it can, even if it can make more premiums by selling fewer options at a higher price.

**_Example 3: Maximizing Revenue by Setting a Higher Clearing Price_**

- **Scenario:** The round has 20 options available. OB1 bids for 10 options at 0.5 ETH per option, OB2 bids for 10 options at 1 ETH per option, and OB3 bids for 10 options at 2 ETH per option.
- **Outcome:** The clearing price is determined to be 1 ETH, selling all 20 options while maximizing revenue. OB1's entire bid becomes refundable, OB2's entire bid is converted into premiums, and OB3's bid is split (10 ETH becomes premiums, and 10ETH becomes refundable).

# Fossil Integration

Fossil is what we call a zk co-processor (storage proofs + provable computation), and is the back bone to the Pitchlake protocol. With Fossil, we can read values from Ethereum block headers and storage slots, do some computing on them, and using some proofs, we can trustlessly accept these values on Starknet.

Fossil is used to **settle the current option round** and **initialize the next option round** (at the same time).

## Settling the current round

When a round settles, we fetch the TWAP of basefee over the round's period from Fossil to determine the payout of the options. If the TWAP of basefee during the round is > the strike price of the options, they become exercisable. If the options become exercisable, we use this value, the strike price, and the cap values to calculate the total payout of the round. This payout is what OBs can claim by burning their options.

## The next option round is initialized

When the current option round settles, the next option round gets deployed and initialized, this is the start of the _round transition period_. While in this transition period, the parameters of the next option round are known (initialized), and LPs can decide to withdraw their rolled over liquidity.

The values used in the initializer that stem from Fossil are the strike price, cap level, and reserve price.

- Strike Price (K)

The strike price determines a price for which the options become exercisable. It is calculated from the TWAP and volatility of basefee over the last few months (from 0 -> T0). Depending on the type of vault (ITM, ATM, OTM), the strike price will be either greater than, less than, or equal to the TWAP of basefee over the last few months. It is defined as:

```rust
  K = BF_0_T0 * (1 + k)
```

Where `BF_0_T0` is the TWAP of basefee over the last few months, and the percentage level, k, is suggested to be -σ (ITM), +σ ̄(OTM), or 0 (ATM) by the [official Pitchlake paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018).

- Cap Values

The collateral level (CL) of the contract is calculated based on a cap level (cl > 0). The cl is defined as a percentage level of the strike price, and sets the max payout for the options.

```rust
  CL = cl * (1 + k) * BF_0_T0

  CL = cl * K
```

There is discussion of an alternate design where the cap level is not fixed at initialization, but is instead calculated once the auction settles. This caps the option's payout based on the implied volatility realized in the market, and can be found using:

```rust
  P = C(K, t) - C(K(1+cl), t)
```

Where `P` is the clearing price of the auction, and C(K, t) represents the price of an uncapped call option with strike K at time t (Black-Scholes). This cl can then be used in the above CL formula.

- Reserve Price

The reserve price refers to the minimum price at which an option can be sold during the auction (and thus, is the minimum bid price). The reserve price is typically set as a fixed percentage of the theoretical value of the option, based on the Black-Scholes option pricing model. This model takes into account factors such as the riskless interest rate and the volatility of the index. The [official Pitchlake paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018) outlines the reserve price calculation in detail.

## Calculating the payout

As stated, once the option round settles, the payout is calculated based on the round's TWAP of basefee, the strike price, and cap levels. The payout is calculated as:

```rust
  Payout = max(0, min((1+cl)K, BF_T1_T2) - K)
```

Where `cl` is the cap level, `BF_T1_T2` is the TWAP of basefee over the round, and `K` is the strike price. The payout is the total amount of funds that OBs can claim per option they own. The equation simply says, if the TWAP is <= K, the payout is 0, and if the TWAP is > K, then the payout is BF - K, capped to be <= (1+cl)K.

## In Summary

Fossil is used twice over the course of an option round's life cycle, at initialization and settlement. When we settle the current round, we initialize the next. This starts the round transition period, and once it is over, the next auction (for the initialized round) can start.
