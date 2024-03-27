# Pitchlake Crash Course

# Understanding Pitchlake

**Pitchlake** creates an options market for Ethereum basefee on Starknet, the official paper is [here](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018). This documentation is written as a crash course and architecture overview of the protocol. It is intended to onboard new devs/catch them up to speed, and hopefully serve as a pre-prompt for models assisting in the development. Feel free to update or add things as you see fit.

## What Are Options ?

Options are financial contracts that give a buyer the right, but not the obligation, to buy or sell an asset at a predetermined price. Options can be used as a form of insurance, allowing the buyer to hedge against unfavorable price movements. They can also be used to speculate on price movements, with the potential to earn profits if the price moves in the option buyer’s favor.

In the context of Pitchlake, we will use liquidity deposits to auction call options to buyers. These call options will give their owner the right to exercise their options, buying basefee at the price set in the contract.

## Why Buy Basefee Options ?

A rollup uses a lot of gas each month settling L2 blocks on L1, hence L2 gas fees. The goal of the rollup is the have L2 → L1 settlements as cheap as possible, charging the L2 users just enough to cover it.

A problem arises from the fluctuating gas prices on Ethereum, coupled with the latency between L2 → L1 settlement. A transaction on L2 could happen hours before it is settled on L1, leaving the rollup to guess or use some heuristic when pricing the L2 transaction. With Pitchlake, these rollups can now hedge their exposure to these fluctuating gas prices on Ethereum, providing a more consistent fee experience for the L2 users.

When an option round settles, if the average basefee for the round is > the strike price, the options become exercisable (more on this later in the crash course). In a traditional market, this exercising would entail option buyers (OBs) being able to purchase basefee at the strike price; however, basefee is not a direct commodity that can be transferred like this. Instead, when OBs exercise their options, they are given a payout for the difference between the strike price and average basefee over the course of the option round.

# Overview of the Contracts

## Vault

The vault acts as the central hub for liquidity providers (LPs) to deposit and withdraw their funds. When an LP deposits liquidity, the vault transfers these funds to the correct option round contract, updating the LP’s position in the vault (deposits will always go into the **next** round).

Once the current round settles, all of the remaining liquidity is rolled over to the next round. After this settlement, there will be a period of time that must pass before the next round's auction can start; we can refer to this as the _round transition window_. During this round transition window, LPs can withdraw from their rolled over positions, and the next round is still accepting deposits (more on this round transition window further into the crash course).

~~At any point, an LP may submit a claim to flag their current position for withdrawal. Once the option round settles, the submitted claims are kept inside the option round contract, and the remaining liquidity is sent to the next option round contract. LPs can go back and withdraw these claims at any point.~~

## Option Rounds

Each option round is a distinct period of trading, contained within its own contract.
These rounds allow for the auction, settlement, and exercising of Ethereum basefee options, with each contract managing its specific set of options. These contracts are modified ERC20 contracts, with the tokens representing the options themselves.

**Option Round States**: An option round transitions through 4 states during its lifecycle: _Open_ | _Auctioning_ | _Running_ | _Settled_. A round is initially deployed with state _Open_. The state becomes _Auctioning_ once its auction begins, and _Running_ once the auction is settled. Once the option round has concluded, its state permanently becomes _Settled_. These option round states are detailed in the next section.

## LP Tokens

When an LP deposits liquidity, their positions are stored in the vault contract. The details of their positions remain within the vault’s storage from round to round, and when a user wishes to withdraw their funds, these details are used to calculate the value of their position in the current round.

However, if an LP wishes to sell their position (maybe LP speculates there will be a payout and their position will decrease in value), they can convert their active position into LP tokens (ERC20), and sell them on the secondary market. At any point, these LP tokens can be converted back into an active position (@dev is this the case ?).

**_Simply:_** An LP’s position is handled through storage in the vault contract, and only becomes tokenized if the LP chooses to convert their active position to LP tokens. These positions are discussed in more detail later in the crash course.

# Closer Look into the Contracts

## Vault Entry Points:

- **Deposit**: LPs add liquidity to the next option round contract, updating their positions.
- **Collect:** LPs can collect from their current premiums & unlocked liquidity in the current round (if they do not, the funds will be rolled over to the next round when the current round settles).
- **Withdraw**: LPs withdraw from their liquidity in the _Open_ (next) round.
- **\*Start Next Option Round**: Starts the next round’s auction, deploys the new next round, and updates the vault’s current & next pointers accordingly. This also locks all liquidity provided by LPs.
- **Getters**: There should be read functions on the vault for the current & next option rounds, addresses for option rounds, an LP's position value in the current round, and the premiums/unlocked liquidity an LP can collect from the current round.

**Note:** Anyone can start a new option round, as long as the current round is Settled and the round transition window has passed. The incentivisation scheme still needs to be designed.

## Vault <-> Option Round State Connection

The vault has pointers for its current and next round ids. The current round will always be either: _Auctioning | Running | Settled,_ and the next round will always be _Open._

Once we pass the current round’s settlement date, we can settle it. Once a round settles, the _round transition window_ must pass before the next round’s auction can start. This window gives Pitchlake LPs time to withdraw from their rolled over positions, but also allows any LPs from other protocols to enter.

> _This is because if other protocols adopt the same option round schedule as Pitchlake without a transition window, there would be no time for LP’s to leave the protocol and join another before the next auctions starts._

Once this transition window passes, we can call the `vault::start_next_option_round()` entry point. This will start the next option round’s auction (_Open → Auctioning_), deploy the new next option round contract (→ _Open_), and increment the current & next round pointers by 1.

**_Example_**:

When the vault deploys, its current round pointer is 0 (_Settled),_ and its next round pointer is 1 (_Open)_. Once `vault::start_next_option_round()` is called, round 1 starts _Auctioning,_ round 2 gets deployed (as _Open_), the current round pointer becomes 1, and the next round pointer becomes 2.

The current option round (1) continues, transitioning from _Auctioning_ to _Running_ to _Settled_—during this period, any deposits to the vault will be sent to the next round (2). After round 1 settles and the transition window passes, the cycle repeats. `vault::start_next_option_round()` is called, round 2 becomes _Auctioning_, round 3 gets deployed as _Open_, the current pointer becomes 2, and the next pointer becomes 3.

**_Summary:_**

- There will always be a current and next option round contract deployed.
  - The current round will always be: _Auctioning | Running | Settled._
  - The next round will always be _Open._
- Once the current round settles, there is a window of time that must pass before the next round's auction can start.
  - Once the auction for a round starts, it becomes the current round, and the next round gets deployed.
- Deposits always go into the next option round.
- Withdraws always come from the next round.
  - LP’s r1 position liquidity will roll over to r2 once r1 settles. During the transition window, r2 is **_still the next round_**, which is where LP’s withdraw will come from.
- ~~Claims are in the context of the current round.~~
  - ~~If LP submits a claim, their current position is flagged to not be sent to the next round, and once the current round settles, these claims can be withdrawn.~~
  - ~~If LP does not submit a claim, their current position is sent to the next round when the current round settles.~~
- ~~An LP can withdraw any of their claims once they are processed (as in, once the round the claim was submitted in settles).~~

## Option Round Entry Points

- (1\*) **Start Auction**: Begins the auction phase of the round, allowing option buyers (OBs) to place bids for the available options. At this time the round becomes the current round within the vault.
- **Place Auction Bid**: OBs submit their bids for options.
- (2\*) **Settle Auction**: Concludes the auction, determining the final distribution of options and premiums. If any of the available options do not sell, a portion of the LPs' locked liquidity becomes unlocked. (LPs can withdraw these premiums and unlocked liquidity once the auction settles. If they ignore them, they will be included in LP's rolled over liquidity to the next round).
- **Refund Unused Bids**: Bidders can collect any of their bids that were not fully utilized.
  > _i.e._ If OB bids 10 ETH for 10 options and only receives 5 options (@1 ETH / option), they can collect their unused 5 ETH at any time after the auction settles).
- (3\*) **Settle Option Round**: Settles the option round and calculates the total payout of the option round.
- **Exercise Options**: Option buyers can exercise their options and claim their individual payouts, corresponding to the number of options they own.
- **Getters**: There should be read functions on an option round to return: the option round's state (Open | Auctioning | Running | Settled), the option round's constructor args, the initial liquidity in the round, the bid deposit balance of an option bidder, the auction's clearing price, the balance of unused bids of an option bidder, the total premiums collected, the total payout upon round settlement, and the payout balance for an option buyer.

> \*An auction can only start once the previous round settles and the transition window has passed.

> \*An auction can only settle if the option bidding period has ended.

> \*An option round can only settle if option settlement date has been reached.

**Note:** These functions can be called by anyone (and may have a wrapping entry point through the vault). The incentivisation scheme still needs to be designed.

## The Lifecycle of an Option Round

**A Round Opens**

A round deploys with state _Open_ as the **next** round in the vault. While _Open,_ LPs can deposit liquidity. A round will remain _Open_ until its auction starts.

**The Auction Starts**

Once a round’s auction starts, its state becomes _Auctioning_, it becomes the **current** round in the vault, and the next option round is deployed.. While a round is _Auctioning_, OBs can submit bids using the `OptionRound::place_bid(amount, price)` entry point:

`amount:` The max amount of funds being bid.

`price:` The max price per option OB is bidding per option.

**The Auction Ends**

Once the option bidding period has passed, the auction can end, updating the round’s state to _Running_ (remaining the **current** round in the vault). Pitchlake will use a fair batch auction to settle these auctions. A technical overview of these fair batch auctions can can be found [here](https://docs.cow.fi/cow-protocol/concepts/introduction/batch-auctions), and some examples are discussed later in this crash course.

When the auction settles, the **clearing price** is calculated. This is the price per individual option. With this clearing price, we can calculate how many options each OB receives from their bids, along with how much of each OBs’ bids go used & unused.

The used bids are known as the **premiums**. They are what the OBs end up spending to obtain the options, and are paid to the LPs. Any bids not converted to premiums are claimable via: `OptionRound::refund_unused_bids(OB: ContractAddress).`

The options will be in the form of ERC20 tokens, minted to OBs upon the auction’s end. Tokenizing the options allow them to be traded/sold/burned/aggregated/packaged into new derivates/etc.

**The Option Round Settles**

Once the option settlement date has been reached, the next step is to settle the round. This permanently sets the round’s state to _Settled_ (still the **current** round in the vault). Fossil lets us know what the average basefee over the option round's duration was, and depending on this value, the options may become exercisable (more on Fossil later in the crash course). If the options become exercisable, the total payout of the options is calculated. This allows an OB to burn their options in exchange for their portion of the payout.

At this time, the remaining LP liquidity is sent to the next round, along with any premiums/unlocked liquidity that was not collected.

> **NOTE:** If an LP does not collect their premium or unlocked liquidity during a round, it is not lost. It is included as part of their rolled over liquidity into the next round.

After the round is settled and the transition period has passed, the next round’s auction can start, repeating the same lifecycle. At this point the round is no longer the **current** round in the vault, that pointer points to the round thats auction just start.

## A Deep Dive into `Vault::Positions`

### Storage Representation

When an LP deposits liquidity, they update their position inside the vault. These positions are represented by a fairly simple mapping and the id of the round LP makes their last withdrawal from. These checkpoints allow us to calculate a position's value later on.

```rust
#[storage]
struct Storage {
	// Amount of liquidity LP deposited into a round
	positions: map(LP: ContractAddress, round_id: uint) -> amount: uint,
	// The last round LP made a withdrawal from
	withdraw_checkpoints: map(LP: ContractAddress, round_id: uint),
}
```

**Example**: LP deposits 1 ETH into round 1, and 1 ETH into round 3, there position will look like this:

```rust
				| 1 -> 1 eth
LP_address ->	| 2 -> 0
				| 3 -> 1 eth
```

### Calculating Position Value

When LPs withdraw from their positions, we need to calculate the value of the position at the current time. For each round an LP’s position sits, its value is subject change. This change is based on how much in premiums the round collects (from OBs), and how much the round has to payout (to OBs). We can define this remaining liquidity like so:

```rust
remaining_liquidity = round.total_deposits() + round.total_premiums() - round.total_payouts()
```

If an LP supplied 50% of the current round’s liquidity, they own 50% of the current round’s remaining liquidity once it settles. If an LP does not collect any of their premiums or unlocked liquidity, their portion of this remaining liquidity + their premiums + their unlocked liquidity, is rolled over to the next round, and is considered their position in this next round.

This next round’s position and the next round’s total deposits determine the percentage of the next round's pool that LP supplied. With this percentage, we know how much of the round’s remaining liquidity belonged to them.

This process repeats for all the rounds the LP’s position sits in, some pseudo code is below.

We start by calculating LP’s position value at the end of the current round (ending_amount), and check to make sure LP is not withdrawing more than this value. The next step, is to update LP’s position & withdraw checkpoint. This allows us to calculate the position’s value during the next withdraw. Finally, we transfer the withdraw amount from the next round to LP (we do this last to avoid reentrancy attacks).

```rust
// LPs withdraw during the round transition period
// @dev The current round is Settled, and the next round is Open.
// @dev LP liquidity is currently sitting in the next round.
// @param LP: The address withdrawing liquidity
// @param withdraw_amount: The amount LP is withdrawing
withdraw_from_position(LP: ContractAddress, withdraw_amount: uint) {
	let current_round_id = vault::current_round_id;
	let next_round_id = vault::next_round_id;

	// The amount LP's position is worth at the end of the current round
	let mut ending_amount = 0;
	// Iterate through each position since the last withdraw to the current round (both inclusive)
	for i in range(withdraw_checkpoints[LP] + 1, current_round_id) {
		// How much liquidity did LP supply in this round
		let starting_amount = ending_amount + positions[LP, i];
		// Get a round i dispatcher
		let this_round = RoundDispatcher {address_for_round(i)};
		// How much of this round's pool did LP own
		let pool_percentage = starting_amount / this_round.total_deposits;
		// How much liquidity remains in this round
		let remaining_liquidity = this_round.total_deposits() + this_round.total_premiums() - this_round.total_payouts();
		// LP ends the round with their share of the remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;
		// @dev For simplicity, we are not including the calculation for how much
		// of the premiums/unlocked liquidity LP may have collected during this round,
		// but it will need to be implemented, and look something like:
		// ending_amount = ending_amount - lp_collections_in_round(LP, i)
		// where lp_collections_in_round retrienves how much premiums and unlocked
		// liquidity lp collected during this round (i.e not rolled over to the next round)
	}

	if (withdraw_amount > ending_amount)
		revert_with_reason("Withdrawing more than position's value");

	// Update LP's position value after the withdraw
	positions[LP, next_round_id] = ending_amount - withdraw_amount;
	// Update LPs withdraw checkpoint for future calculations
	withdraw_checkpoints[LP] = current_round_id;

	// Send ETH from the next round to LP
	ETH_DISPATCHER.transfer_from(next_round_id, LP, withdraw_amount);
}
```

### Positions → LP Tokens

The above architecture works fine for LPs to withdraw from their positions after round settlements, but not if they wish to sell their active positions on a secondary market. To do this, they will need to tokenize their position by converting it into LP tokens, and selling them as such.

LP tokens represent a position’s value as a round 1 (the first ever round) deposit. By knowing the value of a round 1 deposit, we can calculate its value at the start of each round, and visa versa, if we know the value of a position at the start of a round, we can calculate its value as a round 1 deposit by calculating backwards.

@dev this is where confusion is right now, when can LP tokens -> position ? and when can positions -> LP tokens ?

@dev position->lp tokens if round.state => Auctioning | Running ?

@dev lp tokens -> position if round.state =>

Some pseudo code for this:

```rust
// LP tokenizes a portion of their active position.
// @dev This assumes the current round is ongoing (Auctioning/Running)
// @dev If the current round is Settled, then the position is calculated
// up to the end of the current round instead of up to the end of the previous
// round.
tokenize_position(LP: ContractAddress, amount_to_tokenize: uint){
	let current_round_id = vault::current_round_id;
	let next_round_id = vault::next_round_id;
	let previous_round_id = current_round_id - 1;

	// Calculate LP's position value at the end of the PREVIOUS round (start of the current round)
	let mut ending_amount = 0;
	for i in range(withdraw_checkpoints[LP] + 1, previous_round_id) {
		// How much liquidity did LP supply in this round
		let starting_amount = ending_amount + positions[LP, i];
		// Get round i's contract address
		let this_round = RoundDispatcher {address_for_round(i)};
		// How much of this round's pool did LP own
		let pool_percentage = starting_amount / this_round.total_deposits;
		// How much liquidity remains in this round
		let remaining_liquidity = this_round.total_deposits() + this_round.total_premiums() - this_round.total_payouts();
		// Update LP's position value to their portion of this round's remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;
	}

	// @dev Now that we know how much liquidity LP ended the previous round with
	// (started the current round with), we can work backwards to calculate how much
	// this would have been worth as a round 1 deposit

	if (amount_to_tokenize > ending_amount)
		revert_with_reason("Tokenizing more than position's value");

	// Calculate LP's position value from end of the previous round to
	// the start of the FIRST round
	for i in range(previous_round_id, 1){
		let this_round = RoundDispatcher{address_for_round(i)};

		// The remaining liquidity at the end of this round
		let remaining_liquidity = this_round.total_deposits()
																+ this_round.total_premiums()
																	- this_round.total_payouts();

		// What percentage of this remaining liquidity was LP's
		let pool_percentage = ending_amount / remaining_liquidity();

		// Set LP's ending amount in the precurssing round
		// @dev The ending amount in the precurssing round is equal to
		// the starting amount in this round.
		ending_amount = pool_percentage * this_round.total_deposits();
	}

	// @dev At this point, the ending_amount represents how much LP's position
	// is worth in terms of a round 1 deposit.

	// Update LP's position value after the tokenizing
	positions[LP, current_round_id] = ending_amount - amount_to_tokenize;
	// Update LPs withdraw checkpoint for future calculations
	withdraw_checkpoints[LP] = previous_round_id;

	// Mint LP their tokenized position as LP tokens
	LP_TOKEN_DISPATCHER.mint(LP, ending_amount);
}
```

**Example**: LP deposits X ETH into round 1. This X ETH turns into Y ETH upon round 1 settlement, and is LP’s position value at the start of round 2. While round 2 is _Running_, LP thinks gas prices will go up, thus resulting in a potential_payout for the options, and lowering the value of their position (Y - potential_payout).

Instead of accepting this loss, LP decides to play the market by selling their active position on the secondary market, hoping to get more than (Y - potential_payout) for their position. To do this, we first calculate the value of LP’s position in round 2 to be Y, then we work backwards to convert Y into X, and mint X LP tokens.

### LP Tokens → Positions

A buyer of these LP tokens can sit on them for multiple rounds, or convert them into an active position. LP tokens can only be converted into active positions during a specific window, and the holder should want to convert them as soon as the first window arises.

@dev below here is still being updated to new architecture

@dev what is this window ?

@dev only on a round that is open | auctioning ?

_Why ?_

With a typical vault::position, an LP can collect their premiums as soon as the current auction ends, if they do not, it is rolled to the next round once the current one settles. This is fine because the contracts will track how much is collected, if any, and take it into account when calculating position values (detailed later); however, a problem arises if we were to allow an LP token holder to collect premiums instantly too.

If a malicious user owns some LP tokens in wallet_A, after the current round’s auction ends they collect their premiums. They could then transfer the LP tokens to wallet_B, allowing wallet_B to also collect the same amount of premiums. This process could be used to drain the option round contract. We might think to simply burn some of the LP tokens when the user collects their premiums; however, this would be a fairly complex calculation, and would still not protect the protocol from attacks. Say the malicious user does not have any LP tokens yet, but has an active position. They could use this active position to collect their premiums, immediately tokenize their position, then transfer the tokens to wallet_B and double collect.

To avoid these attacks, we will not allow LP token holders to collect their premiums from the current round, they will be rolled over to the next round as long as they are still LP tokens, and only once converted to an active position can they collect premiums when auctions settle.

_What Window ?_

To overcome more potential attacks and book keeping complications, we will only allow LP tokens to be converted to active positions during a specific window. This window starts once the current round settles, and ends when the next round’s auction ends. Or in other terms, LP tokens can only be converted during the round transition period (while current: _Settled_, next: _Open_), and the during the auction of the next round (while current: _Auctioning,_ next: _Open_). Or in simplest terms, the tokens can only be converted into positions if the current round is _Settled_ or _Auctioning_.

If the current round is _Settled_, the LP tokens are converted into a position in the next round. If the current round is _Auctioning_, then the LP tokens are converted into a position in the current round.

**Summary**: Positions can be converted to LP tokens at anypoint

if the current round is _Settled_ or _Auctioning_. If the current round is _Running_, we introduce these double collecting and draining attack vectors, as well as add complexity to calculating position values since the _Running_ round will not have its total_payout calculated yet. This window of time starts right after the current round settles, and right before the next auction ends

**Summary:** Convert asap to have the most liquid version of your assets

LP tokens can only be converted to active positions if the current round is _Settled_ or _Auctioning_. If th

This is because the current round is never _Open_.

The current round will never be _Open_, and if the current round is _Running_ we do not want to introduce the possibility for double premium collection/contract draining. cannot calculate the position’s value since the payout has not been calculated yet, plus, if LP tokens were converted during

directly in a round 1 position, but this could break future logic. If the user converting LP tokens to a position already has active positions & previous withdraw checkpoints, setting a round 1 position would not be reachable in the calculation for the positions value during withdraw.

To overcome this, we convert LP tokens to a position in the next round. Some pseudo code for this:

```rust
deposit_lp_tokens(amount: uint){
	let next_round_id = vault::next_round_id;
	let next_round = RoundDispatcher{address_for_round(next_round_id)};

	// Calculate value of tokens at the end of the current_
	let mut ending_amount = 0;
	for i in range(withdraw_checkpoints[LP] + 1, current_round_id {
		// How much liquidity did LP supply in this round
		let starting_amount = ending_amount + positions[LP, i];
		// Get round i's contract address
		let this_round = RoundDispatcher {address_for_round(i)};
		// How much of this round's pool did LP own
		let pool_percentage = starting_amount / this_round.total_deposits;
		// How much liquidity remains in this round
		let remaining_liquidity = this_round.total_deposits()
																+ this_round.total_premiums()
																	- this_round.total_payouts();
		// Update LP's position value to their portion of this round's remaining liquidity
		ending_amount = pool_percentage * remaining_liquidity;
	}


}
```

(below is not updated to current architecture)

### Pseudo Code: Vault

```rust
VaultContract {
	storage{
		// Pointers
		current_round_id: uint,
		next_round_id: uint,
		// Lookup tables for contract addresses
		round_contracts: map(round_id: uint) -> ContractAddress,
		position_contracts: map(round_id: uint) -> ContractAddress,
		// Claims submitted by LPs
		submited_claims: map(round_id: uint, LP: ContractAddress) -> FloatingPoint // fp in cairo ?
	}

	/// entry points ///
	fn deposit(amount: uint){...}

	fn submit_claim(position_round_id: uint){...}

	fn withdraw_claim(claim_round_id: uint){...}

	fn start_next_option_round(){...}


	/// helpers (for pseudo code) ///

	// get a round contract
	fn _get_round_contract(round_id: uint){
		let round_address = round_contracts.read(round_id);
		return IOptionRoundDispatcher{contract_address: round_address}
	}

	// get a position contract
	fn _get_position_contract(round_id: uint){
		let position_address = position_contracts.read(round_id);
		return IERC20Dispatcher{contract_address: position_address};
	}

	// get the current round & position contracts
	fn _get_current_round_and_position_contracts() -> (IOptionRoundDispatcher, IERC20Dispatcher)  {
		let id = current_round_id.read();
		return (
			_get_round_contract(id),
			_get_position_contract(id),
		)
	}

	// get the next round & position contracts
	fn _get_next_round_and_position_contracts() -> (IOptionRoundDispatcher, IERC20Dispatcher)  {
		let id = next_round_id.read();
		return (
			_get_round_contract(id),
			_get_position_contract(id),
		)
	}
}
```

### `Vault::deposit()`

When an LP deposits into the vault, the funds are sent to the next round contract, and LP is minted tokens from the next position contract. Looking something like this:

```rust
fn deposit(amount: uint) -> bool{
	// Next option round contract, and next position token contract
	let (next_round, next_position) = _get_next_round_and_position_contracts();

	// Transfer LP's deposit to the round
	let LP = get_caller_address();
	let success = ERC20Dispatcher{contract_address: ETH_ADDRESS}.transfer_from(
		LP,
		next_round.contract_address,
		amount
	);
	if (!success) {return false;}

	// Mint LP position tokens
	success = next_position.mint(LP, amount);
	if (!success) {return false;}

	return true;
}
```

### `Vault::submit_claim()`

When an LP submits a claim, their percentage of the current round’s pool is flagged for claim. pseudocode:

```rust
// @param position_round_id: The round id of the position LP is claiming for.
// i.e. If LP is claiming their round 2 position, position_round_id := 2.
fn submit_claim(position_round_id: uint) -> bool {
	// Current option round contract, and current position token contract (this round is Auctioning | Running)
	let (current_round, current_position) = _get_current_round_and_position_contracts();
	// get round contract with postition round id
	// LP's initial deposit into the position_round_id.
	// Also represents the position's value at the start of each round
	let LP = get_caller_address();
	let mut position_value = position_round_id.balance_of(LP);

	// If LP does not have a position to claim, no claim is submitted.
	if (position_value == 0) {return false;}

	// Calculate LP's dynamic position from their initial deposit
	// to the start of the current round
	for i in range(postion_round_id, current_round_id.read() - 1){
		// The option round being interated over
		let this_round = _get_round_contract(i);

		// Percentage of this round's pool LP owned
		let pool_percentage = position_value / this_round.total_deposits()

		// The liquidity that remains at the end of this round
		let remaining_liq = this_round.total_deposits()
												+ this_round.total_premiums()
													- this_round.total_payout();

		// The remaining liquidity that belongs to LP
		position_value = pool_percentage * remaining_liq;
	}
	// Now, position_value is the liquidity that LP started the current round with (ended the previous round with)

	// Percentage of the current pool LP owns
	let current_pool_percentage = position_value / current_round.total_deposits();

	// Increment claimed percentage of the current round
	current_round.claimed_percentage += current_pool_percentage;

	// Increment LP's claimed percentage of the current round
	submitted_claims[LP] += current_pool_percentage;

	return true;
	// @note Once the current round settles (below), the current_round.claimed_percentage will NOT get transferred to the next round.
}
```

### `Vault::start_next_option_round()`

When we start the next option round, we will settle the current round, keeping any claimed liquidity within it, and move the remaining liquidity to the next round (along with the other logic mentioned previously). This will look something like this:

```rust
fn start_next_option_round(){
	// Current and next option round contracts
	let (current_round, _) = _get_current_round_and_position_contracts();
	let (next_round, _) = _get_next_round_and_position_contracts();

	// Settle current round
	let success = current_round.settle_option_round() // breakdown in next section
	// If the current option round does not settle, revert
	if (!success) {revert_with_reason("current round failed to settle");}

	// Remaining liquidity in the settled round
	let remaining_liq = current_round.total_deposits
											+ current_round.total_premiums
												- current_round.total_payouts;

	// Amount of this remaining liquidity that was claimed
	let amount_claimed = current_round.claimed_percentage * remaining_liq;

	// Amount of this remaining liquidity to transfer to the next round
	let amount_to_transfer = remaining_liq - amount_claimed;

	// Transfer the unclaimed remaining liquidity to the next round
	ERC20Dispatcher{contract_address: ETH_ADDRESS}
		.transfer_from(
			current_round.contract_address,
			next_round.contract_address,
			amount_to_transfer
		);

	// ... Start next round's auction

	// ... Deploy new next round

	// ... Update current & next pointers by 1
}
```

`OptionRound::settle_option_round()` looks something like this:

```rust
OptionRoundContract{
	storage{
		round_params: OptionRoundParams,
		state: OptionRoundState,

		total_deposits: uint, // finalized when auction starts
		total_premiums: uint, // set when auction ends
		total_payouts: uint,  // set when auction settles
		claimed_percentage: FloatingPoint, // % of remaining liq. being claimed at settlement. floating points in cairo (alexandria?)
	}

	// Settle the option round, set the total_payout
	fn settle_option_round() -> bool{
		let caller = get_caller_address();
		// If caller is not the vault
		if (caller != VAULT_ADDRESS) {return false};
		// If not ready to be settled
		if (get_block_timestamp() < round_params.read().option_end_date) {return false}

		// Calculate payout using Fossil
		total_payouts.write(_calculate_payout());

		// Update this round's state
		state.write(OptionRoundState::Settled);

		return true;
	}
}
```

### `Vault::withdraw_claim()`

If an LP submitted a claim, it can be withdrawn once the round settles. Looking something like this:

```rust
// @param claim_round_id: The id of the round LP submitted their claim during (the
// round that LP claimed from).
fn withdraw_claim(claim_round_id: uint) -> bool{
	let claimed_round = _get_round_contract(round_id);

	if (claimed_round.state != OptionRoundState::Settled) {return false};

	// How much of the pool did LP own
	let LP = get_caller_address();
	let claimable_percentage = submitted_claims.read(LP, round_id).read();

	// If LP has no claims/already made their withdrawal
	if (claimable_percentage == 0) {return false}

	// How much liquidity remained in the round
	let remaining_liq = this_round.total_deposits
											+ this_round.total_premiums
												- this_round.total_payouts;

	// How much of this liquidity belonged to LP ?
	let withdraw_amount = claimable_percentage * remaining_liq;

	// Reset LP's claimable percentage
	submitted_claims(get_caller_address(), round_id).write(0);

	// Transfer the claims to LP
	ERC20Dispatcher{contract_address: ETH_ADDRESS}
		.transfer_from(
			claimed_round.contract_address,
			LP,
			withdraw_amount,
		);
}
```

## Batch Auction Examples

**_Example 1: Basic Refunded/Unused Bids_**

- **Scenario:** OB1 bids 10 ETH for options, setting a maximum price of 0.5 ETH per option. Other OBs also place various bids.
- **Outcome:** The auction settles at a clearing price of 0.6 ETH per option. Since OB1's maximum price was 0.5 ETH, none of their bid is used, making the entire 10 ETH refundable.

**_Example 2: Partially Successful Bid with Refund_**

- **Scenario:** The round has 30 options to sell. OB1 bids 10 ETH at 0.5 ETH per option, and OB2 bids 10 ETH at 1 ETH per option.
- **Outcome:** The clearing price is set at 0.5 ETH to sell all 30 options. OB2, with the higher bid price, gets priority and receives 20 options. OB1 receives the remaining 10 options. OB2's 10 ETH is fully converted into premium, while 5 ETH of OB1's bid is used for premiums (buying 10 options), and the remaining 5 ETH is refundable.
- **Note**: A clearing price > 0.5 ETH would not sell all 30 options, the goal of the auction is to sell all options for the highest price it can.
  - Question: what if we can make more money by not selling all the options ? i.e OB1 (10ETH, 0.5ETH) and OB2 (20ETH, 1). In this case we can sell all 30 @0.5 for 15 ETH, but could have sold 20 @1 for 20ETH ?

**_Example 3: Maximizing Revenue by Setting a Higher Clearing Price_**

- **Scenario:** The round has 20 options available. OB1 bids 10 ETH at 0.5 ETH per option, OB2 bids 10 ETH at 1 ETH per option, and OB3 bids 10 ETH at 2 ETH per option.
- **Outcome:** The clearing price is determined to be 1 ETH, selling all 20 options while maximizing revenue. OB3 and OB2 each receive 10 options, using their entire bids as premium. OB1's bid is fully refundable since the clearing price exceeded their maximum bid.

# Fossil Integration

Fossil is what we call a zk co-processor (storage proofs + provable computation), and is the back bone to the Pitchlake protocol. With Fossil, we can read values from Ethereum blocks, do some computing on them, and using some proofs, we can trustlessly accept these values on Starknet.

Fossil is utilized at 2 points during an option round’s lifecycle. The first time we use Fossil is when an option round’s auction starts (_Open → Auctioning_). Here, we rely on Fossil to give us some values for the option round’s params. These values are found through calculations on historical gas prices, giving us the: current average basefee, standard deviation, strike price, cap level, and reserve price.

The second time we use Fossil is when we settle the option round (_Running → Settled)_. Here, we rely on Fossil to let us know what the average basefee over the course of the option round was. Depending on this value, the strike price, and the vault’s type, the options may become exercisable; if they do, the value helps us determine their payout (since we cannot directly send/sell basefee).
