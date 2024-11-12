# Pitchlake Crash Course

**Pitchlake** creates an options market for Ethereum basefee on Starknet, the official paper is [here](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018). This documentation is written as a crash course and architecture overview of the protocol. It is intended to onboard new devs/catch them up to speed, and potentially serve as a pre-prompt for models assisting in the development. Feel free to update or add things as you see fit.

## What Are Options ?

Options are financial contracts that give a buyer the right, but not the obligation, to buy or sell an asset at a predetermined price. Options can be used as a form of insurance, allowing the buyer to hedge against unfavorable price movements. They can also be used to speculate on price movements, with the potential to earn profits if the price moves in the option buyer’s favor.

In the context of Pitchlake, we will use liquidity deposits to auction call options to buyers. These call options will give their owner the right to exercise their options, "buying" basefee at the price set in the contract.

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

When an option round settles, if the average basefee for the round is > the strike price of the options, they become exercisable. In a traditional market, this exercising would entail option buyers (OBs) being able to purchase basefee at the strike price; however, basefee is not a direct commodity that can be transferred like this. Instead, when OBs exercise their options, they are given a payout for the difference between the strike price and average basefee (TWAP) over the course of the option round.

# Contract High-level Overview

## The Vault

A vault acts as the central hub for liquidity providers (LPs) to deposit and withdraw their funds. When an LP deposits liquidity, the vault marks the LP's position in storage (more on this later). The vault always has a pointer to its **current** option round.

When a vault is deployed, its alpha and strike level are set. The alpha level (0 <= α <= 100%) is the risk level of the vault. An alpha level of 50% means that a vault is willing to payout 50% of the liquidity for a round's payout assuming the TWAP remains within the current volatility. The strike level (-100% <= k <= +∞%) is used to calculate a round's strike price. If k is 0% and round 1 settles with a TWAP of 10 GWEI, then round 2's strike price is 10 GWEI. If k is -30% and round 1 settles with a TWAP of 10 GWEI, then round 2's strike price is 7 GWEI.

## Option Rounds

An option round is a distinct period of trading, contained within its own contract. These rounds allow for the auction, settlement, and exercising of Ethereum basefee options, with each contract managing its specific set of options. These contracts implement the ERC20 standard, allowing them to be minted and traded if desired.

### Option Round States

An option round transitions through 4 states during its life cycle: _Open_ -> _Auctioning_ -> _Running_ -> _Settled_. A round is initially deployed with state _Open_. The state becomes _Auctioning_ once its auction begins, _Running_ once its auction ends, and once the option round concludes, its state permanently becomes _Settled_. In the context of the vault, the **current** option round will always be either: _Open_ | _Auctioning_ | _Running_. When the **current** round settles, we deploy the next option round contract and update the current round pointer.

# Contract Entry Points

## Vault:

- **Deposit**: LP adds liquidity to the protocol (into their unlocked balance)
- **Withdraw**: LP withdraws from their liquidity (from their unlocked balance)
- **Queue Withdrawal**: LP queues a percentage of their currently locked position to be stashed upon settlement
- **Withdraw Stash**: LP collects all of their stashed liquidity

- **Start Auction**: Starts the auction for the current round, cannot be called until the round's `auction_start_date` has passed. Locks all unlocked liquidity.
- **End Auction**: End the auction for the current round, cannot be called before the round's `auction_end_date` has been passed. All premiums collected add to the unlocked liquidity, and any unsold liquidity moves from locked to unlocked.
- **Settle Round**: Settles the current option round, cannot be called before the round's settlement date has passed. Removes the total payout from the locked liquidity, stashes aside any queued withdrawals, and moves the remaining liquidity to unlocked. Deploys the next option round and updates the **current** round pointer.

> The state transition functions (on a vault) can be called by anyone, they call the current round's same entry point.

## Option Round:

- **Place Bid**: OB submits a bid for options. Bidding for a max `amount` of options at a max `price` per option. `amount x price` ETH is temporarily locked in the vault during the auction.
- **Edit Bid**: OB edits one of their bids, increasing the bid's `price`, transfers the difference (`amount x (new_price - old_price)` ETH) to the round.
- **Refund Unused Bids**: OB collects any of their bids that were not fully utilized (converted to premium) once the auction ends.
  > _i.e._ If OB bids for 10 options @ 2 ETH each (20 ETH total) and the clearing price is 1 ETH, then 10 x 1 ETH becomes premium, and the remaining 10 ETH becomes refundable.
- **Mint Options**: OB converts the options they win in the auction to ERC20 tokens after the auction ends. In the above example the OB could mint 10 option tokens and trade them (more auction examples later).
- **Exercise Options**: OB exercises their options to claim their portion of the payout after the round settles, corresponding to the number of options they own. When an OB exercises their options, they burn their minted option tokens and flag any non-minted tokens as non-mintable.

- **Start Auction**: Begins the auction phase of the round, allowing option buyers (OBs) to place bids for the available options.
- **End Auction**: Concludes the auction, determining the final distribution of options and premiums. If any of the available options do not sell, a portion of the locked liquidity becomes unlocked. The premiums earned (and any unsold liquidity) is sent from the option round to the vault (unlocked bucket). LPs can withdraw these premiums and unsold liquidity once the auction ends. If they ignore them, they will be included in LP's rolled over liquidity to the next round).
- **Settle Round**: Settles the option round and calculates the total payout of the option round. If there is a payout (index > strike), then the total payout is sent from the vault (locked bucked) to the option round. At this time, the next option round is deployed (with state _Open_) and the **current round** pointer is updated.

> Only the vault can call these state transition functions, but anyone can call the wrapping entry points on the vault.

# A Closer Look at the Contracts

### The Vault <-> Option Round State Connection

A vault has a pointer to its current round. The current round will always be either: _Open_ | _Auctioning_ | _Running_, and all previous rounds will be _Settled_. Once we pass the current round’s settlement date, anyone can settle it. When a round is settled, we deploy the next round and update the current round pointer. When a round is deployed, its auction start date, auction end date, and option settlement date are set. The auction start date will be something like 3-8 hours after deployment (call this the round transition period), the auction end date will be something like 8 hours after the auction start date (call this the auction run time), and the option settlement date will be 30 days after the auction end date (call this the option run time).

The **round transition period** gives Pitchlake LPs time to withdraw from their rolled over positions (if not queued), but also allows LPs from other protocols to enter. This is because if other protocols adopt the same option round schedule as Pitchlake, then without a transition period, there would be no time for LP’s to exit another protocol and join before the next auctions starts, nor would Pitchlake LPs have time to withdraw their positions before they get locked into the next round (if not queued).

Once this round transition period passes (now >= auction*start_date), we can call the `vault::start_auction()` entry point. This will start the option round’s auction (\_Open → Auctioning*). Similarly, `vault::end_auction()` can be called once now >= auction_end_date, and `vault::settle_round()` can be called once now >= option_settlement_date.

**Example**:

When the vault deploys, its **current** round pointer is 1 (_Open_). Once `vault::start_auction()` is called, round 1 becomes _Auctioning_.

The **current** option round (1) continues, transitioning from _Auctioning_ to _Running_ to _Settled_. When round 1 settles, round 2 is deployed and becomes the current round. Once the round transition period passes, the cycle repeats. `vault::start_auction()` is called and round 2 becomes _Auctioning_.

**In Summary:**

- There will always be a current option round
  - The current round will always be: _Open_ | _Auctioning_ | _Running_
  - All previous rounds will be: _Settled_
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

> i.e. A bid of (10 options, 2 ETH) means the bidder wants at most 10 options and is willing to spend up to 2 ETH per option. If the clearing price is > 2 ETH, the entire bid becomes refundable, and if the clearing price is < 2 ETH, then the OB can receive up to 10 options, and the rest of their funds become refundable (if they receive 10 options at 1 ETH, then 10 ETH is refundable and 10ETH is collected as premiums).

**The Auction Ends**

Once the option bidding period has passed, the auction can end, updating the round’s state to _Running_ (while remaining the **current** round in the vault). Pitchlake will use a fair batch auction to settle these auctions. A technical overview of these fair batch auctions can can be found [here](https://docs.cow.fi/cow-protocol/concepts/introduction/batch-auctions), and some examples are discussed later in this crash course.

When the auction ends, the **clearing price** is calculated. This is the price per individual option. With this clearing price, we can calculate how many options each OB will receive, along with how much of the OBs’ bids were used & unused.

The used bids are known as the **premiums**. They are what the OBs end up spending to obtain the options, and are paid to the LPs. Any bids not converted to premiums are claimable via: `OptionRound::refund_unused_bids(OB: ContractAddress).`

After the auction, the OB may mint their options as ERC20 tokens. Minting is not required to exercise, but allows the OB to then send/trade them if desired.

**The Option Round Settles**

Once the option settlement date has been reached, the next step is to settle the round. This permanently sets the round’s state to _Settled_ (deploying the new current round). Fossil lets us know what the average basefee (TWAP) over the option round's duration was, and depending on this value, the options may become exercisable (more on Fossil later in the crash course). If the options become exercisable, the total payout of the options is calculated (and sent from the vault's locked liquidity to the option round). This allows an OB to burn their options in exchange for their portion of the payout.

When the round settles, all of the remaining liquidity (locked - payout) becomes unlocked, and the new current round is deployed. The same values from Fossil are used to initialize the new round's details (more on this later).

> **NOTE:** If a user queues a percentage (> 0) for withdrawal, this percentage of the remaining locked liquidity is stashed aside for them to withdraw at any time, and the rest becomes unlocked.

> **NOTE:** If an LP does not collect their remaining unlocked liquidity before the next auction start, it is not lost. It is rolled over into the locked liquidity in the **next** round.

After the transition period passes, the next round’s auction can start, repeating the same life cycle.

# A Technical Deep Dive

## `Vault::Positions`

Liquidity is classified as either: locked, unlocked, or stashed. When a user deposits/withdraws, they are incrementing/decrementing their unlocked balance. When an auction starts, the LP's unlocked balance becomes locked. When an auction ends, the LP's share of the premiums collected (`options sold x clearing price`) is added to their unlocked balance and any unsold liquidity (`starting_liquidity - (options_sold x max_payout_per_option)`) moves from their locked to unlocked balance. When a round settles, the LP's share of the payout is taken from their locked balance, if the LP queued a percentage of their position for withdrawal, it is moved from locked to stashed, and the remaining is added to their unlocked balance. When an LP withdraws their stashed liquidity, they collect it all at once.

### Storage Representation

To avoid iteration/looping through account positions, we use a mapping and a couple checkpoints to keep track of an LP's position. By knowing the last round the position was updated in, the value of the position at this round, and the current round's state, we can calculate the LP's locked, unlocked, or stashed balance.

#### Representing Positions in Storage

```rust
#[storage]
struct Storage {
	// Amount of liquidity LP deposited into a round
	positions: map(LP: ContractAddress, round_id: uint) -> amount: uint,

	// The last round the LP's position was updated in
	withdraw_checkpoints: map(LP: ContractAddress) -> round_id: uint,

  // ... other flags
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
  // Get the current round ID if it is Open, or the next round ID if the current is Auctioning | Running
  let upcoming_round_id = vault.get_upcoming_round_id();

  // Update LP's position in the next round
  positions[LP, upcoming_round_id] += amount;

  // Transfer the funds from the caller to the vault
  EthDispatcher.transfer_from(get_caller_address(), get_contract_address(0), amount);
}
```

### Calculating a Position's Value

For each round an LP’s position sits, its value is subject change. This change is based on the round's earned liquidity and the round's remaining liquidity. These can be calculated as:

```rust
let earned_liquidity = round.total_premiums() + round.unsold_liquidity();
let remaining_liquidity = round.starting_liquidity() - round.unsold_liquidity() - round.total_payouts();
```

If an LP supplied 33% of the round's starting liquidity, then they earn 33% of round's earned liquidity, and keep 33% of the round's remaining liquidity (if none is queued for stashing). The position value at the end of a round is the value that is rolled to the start of the next. Using this starting value and the next round's starting liquidity, we can do the same and calculate the position's value at the end of the next round.

This process repeats for all the rounds the LP’s position sits in, some pseudo code for calculating an LPs position value at the start of the current round is below.

```
fn get_realized_deposit_for_current_round(
      self: @ContractState, account: ContractAddress
  ) -> u256 {
      // @dev Calculate the value of the account's deposit from the round after their
      // checkpoint to the start of the current round
      let current_round_id = self.current_round_id.read();
      let mut i = self.position_checkpoints.read(account) + 1;
      let mut realized_deposit = 0;
      while i < current_round_id {
          // @dev Increment the realized deposit by the account's deposit in this round
          realized_deposit += self.positions.entry(account).entry(i).read();

          // @dev Get the liquidity that became unlocked for the account in this round (earned)
          let account_unlocked_liq = self
              .get_liquidity_unlocked_for_account_in_round(account, realized_deposit, i);

          // @dev Get the liquidity that remained for the account in this round
          let account_remaining_liq = self
              .get_account_liquidity_that_remained_in_round_unstashed(
                  account, realized_deposit, i
              );

          realized_deposit = account_unlocked_liq + account_remaining_liq;

          i += 1;
      };

      // @dev Add in the liquidity provider's current round deposit
      realized_deposit + self.positions.entry(account).entry(current_round_id).read()
  }
```

We start by looking at the LP's checkpoint to know when their position was updated last. We start our loop here, iterating from the checkpoint to the current round. For each round, we calculate the LP's share of the total earned and remaining liquidity. The remaining amount is used as their starting amount in the next, and so on. Once we calculate the position's value at the end of the previous round (current - 1), we add the value of the deposit in the current round to know the position's value at the start of the current round.

Now that we know the value of the position at the start of the current round, we can calculate how much is locked or unlocked, depending on the current round's state.

> If the current round is Open, the entire realized position is unlocked, 0 is locked

> If the current round is Auctioning, the entire realized position is locked and any next round deposits are unlocked

> If the current round is Running, the LP's share of the unsold portion of the locked liquidity is unlocked, the LP's share of the premium is added to the unlocked liquidity, and any next round deposits are unlocked

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

Fossil is used to **settle the current option round** and **initialize the next option round** (at the same time). Fossil is triggered once the round can settle. At this time Fossil gives the vault the TWAP, volatility, and reserve price.

## Settling the current round

When a round settles, the TWAP of basefee over the round's period determines the payout of the options. If the TWAP of basefee during the round is > the strike price of the options, they become exercisable. If the options become exercisable, we use this value, the strike price, and the cap level to calculate the total payout of the round. This payout is what OBs can claim by burning their options.

## The next option round is initialized

At the same time the current round settles, the next round is deployed. When a round is deployed, the same TWAP is used (along with the vault's strike level, k) to calculate its strike price, the volatility (along with the vault's alpha and strike levels) are used to calculate its cap level, and the reserve price sets the minimum bid price per option in its auction.

- Strike Price (K)

The strike price (K) determines the price for which the options become exercisable. It is calculated from the TWAP and k (strike level). It is defined as:

```rust
  K = BF_0_T0 * (1 + k)
```

Where `BF_0_T0` is the TWAP of basefee over the last few months, and the strike level, k, is set in the vault's deployment ( and is suggested to be -σ (ITM), +σ ̄(OTM), or 0 (ATM) by the [official Pitchlake paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018)).

- Cap

The collateral level (CL) of the contract is calculated based on a cap level (cl > 0) of the round. It determines the max payout of the options. A cl of 50% means that the options will payout up to 50% above the strike, meaning if the strike price is 10 GWEI, and the settlement price is 20 GWEI, the payout is capped at 5 GWEI (not the full 10 GWEI difference).

```rust
  CL = cl * (1 + k) * BF_0_T0
     = cl * K
```

CL is straight forward to calculate, but is dependent on the round's cl; which is calculated using the volatility (λ) and strike level (k):

```
cl = λ − k / (α × (k + 1))
```

- Reserve Price

The reserve price refers to the minimum price at which an option can be sold during the auction (and thus, is the minimum bid price). The reserve price is typically set as a fixed percentage of the theoretical value of the option, based on the Black-Scholes option pricing model. This model takes into account factors such as the riskless interest rate and the volatility of the index. The [official Pitchlake paper](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018) outlines the reserve price calculation in detail.

## Calculating the payout

As stated, once the option round settles, the payout is calculated based on the round's TWAP of basefee, the strike price, and cap levels. The payout is calculated as:

```rust
  Payout = max(0, min((1+cl)K, BF_T1_T2) - K)
         = max(0, min(CL, BF_T1_T2) - K)
```

Where `cl` is the cap level, `BF_T1_T2` is the TWAP of basefee over the round, and `K` is the strike price. The payout is the total amount of funds that OBs can claim per option they own. The equation simply says, if the TWAP is <= K, the payout is 0, and if the TWAP is > K, then the payout is BF - K, capped to be <= (1+cl)K.
