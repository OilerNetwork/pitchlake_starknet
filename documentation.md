# Understanding Pitchlake

**Pitchlake** creates an options market for Ethereum basefee on Starknet. The official paper is [here](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018).

This documentation is written as a crash course and architecure overview of the pitchlake protocol.

## Contracts Overview

### Vault

A vault acts as the central hub for liquidity providers (LPs) to deposit and withdraw their funds.
When an LP deposits liquidity, the vault transfers the funds to the correct option round contract.
At any point, an LP may submit a claim to have their funds automatically withdrawn at the end of the current option round.
Upon option round settlement, any claims that were submitted are processed, and the remaining liquidity is sent to the next option round contract.

### Option Rounds

Each option round is a distinct period of trading, contained within its own contract.
These rounds allow for the auction, settlement, and exercising of Ethereum basefee options, with each contract managing its specific set of options.

**Option Round States**: An option round transitions through 4 states during its lifecycle: Open | Auctioning | Running | Settled.
A round is initially deployed with state _Open_.
The state becomes _Auctioning_ once its auction begins, and _Running_ once the auction is settled.
Once the option round has concluded, its state permanently becomes _Settled_.

## Entrypoints

### Vault

- **Deposit**: LPs add liquidity which is sent to the current option round contract (if current.state == _Open_, else, the next option round contract), updating LPs positions in the vault.

- **Submit Claim**: LPs flag their positions for withdrawal after the settlement of the current option round.

<!-- - **Withdraw**: LPs withdraw from their positions in the current Open option round. -->

- **Start New Option Round**: Deploys the next option round contract, updates the vaults current & next pointers accordingly, and starts the auction on the new current round.

- **Getters**: There should be read functions on the vault to return: the vault type, the current option round, the next option round, addresses of option rounds, and an LP's liquidity/position in a round.

> Question: Should there be a getter to see positions in rounds, and remaining liquidity for a round ?

### Option Rounds

- **Start Auction**: Begins the auction phase of the round, allowing traders to place bids on options.

- **Place Auction Bid**: Option buyers submit their bids for options within the round.

- **Settle Auction**: Concludes the auction, determining the final distribution of options and premiums.

- **Refund Unused Bids**: Bidders can collect any of their bids that were not fully utilized.

- **Settle Option Round**: Settles the option round and calculates the total payout of the option round.

- **Claim Option Payout**: Option buyers can exercise their options and claim their individual payouts, corresponding to the number of options they own.

> Options are represented as ERC20 tokens, we should probably burn them during claim_option_payout, to avoid an OB double exercising, or at least mark them as exercised.

- **Getters**: There should be read functions on an option round to return: the option round's state, the option round's params, the total liquidity in a round, the bid deposit balance of an OB, the auction's clearing price, the balance of unused bids of an OB, the payout balance of an OB, and the premium balance of an LP.

> Are we implementing a premium_balance_of getter ? This would mean fetching the current position from the vault (from last checkpoint), and then calculating the premiums for the round. Not overly complex, just curious if we want this entrypoint on the option round or the vault.

> Are bids removable before an auction settles ? Or are they considered final/locked upon deposit ?

## Technical Implementation

When an LP first deposits liquidity, the vault issues them an ERC721 token representing their position.
This token is updated with each additional deposit, creating a record of their participation in the market.

> If position is an ERC721, what happens if LP1 sends their token to LP2 ? When LP2 tries to deposit, they will be minted a new position token, and LP1 will not be able to mint another ?
>
> A fix is to not tokenize the positions, instead have them be typical structs indexed by LP address.
>
> Another fix is to inject a \_before_transfer() function on the tokens, to properly update our map of LP_address => token_id whenever a position is transferred.

A position in the vault will look something like this:

```
/// Contract Storage ///

storage {
    rounds: map(round_id: u256) -> Round,
    positions: map(erc721_token_id: u256) -> Position,
}

/// Structs ///

Round {
    totalDeposits: u256, // the total liquidity at the start of the round
    totalPayout: u256, // the total amount allocated for option payouts (can be 0)
    totalPremium: u256, // the total premium collected from the round's auction
    state: OptionRoundState, // Open | Auctioning | Running | Settled
}

struct Position {
    lastClaimCheckpoint: round_id: u256, // the last round LP claimed from
    roundPositions: map(round_id: u256) -> amount: u256, // the amount LP deposited into each round
}
```

<!-- RoundPosition {
    round: round, // not sure if this is needed or if it should be round_id
    amount: u256, // the amount LP deposited into the round
} -->

> Is round.totalAmount the initial liquidity in a round ? Or the amount post-settlement ? (i.e. total_deposits || total_deposits - total_payout ?)

## Example: LP Participation

An LP begins by depositing liquidity in round 1 (1 eth) and then again in round 3 (another 1 eth).
Their vault::position reflects these contributions, like this:

```
Position {
    lastClaimCheckpoint: 0,
    roundPositions: {
        1| 1 eth,
        2| 0,
        3| 1 eth,
        ...
    },
}

```

Round 3 settles, and during round 4, LP submits a claim to withdraw their position. Once round 4 settles, LP's claim is processed.

To acurately determine LP's available balance for withdraw, we must calculate their dynamic position across the rounds.
We use LP's Position.lastClaimCheckpoint to determine where the calculation starts.

First, we initialize a variable for claimable amount:

```
claimable_amount = 0
```

Next, we calculate LP's % of ownership for the option round's pool:

```
ownership_percentage = (claimable_amount + positions[LP].roundPositions[1].amount) / rounds[1].totalDeposits
```

Next, we take note of the total liquidity left after round 1 settled:

```
total_liquidity_left_in_round = rounds[1].totalDeposits - rounds[1].totalPayout
```

With these values, we can calculate how much of the option round's total premiums belong to LP, along with how much of the total remaining liquidity is theirs:

```
premium_earned_in_round = ownership_percentage * rounds[1].totalPremium

remaining_liquidity_in_round = ownership_percentage * total_liquidity_left_in_round
```

The sum of these 2 values is the amount LP could have withdrawn at the end of round 1, but since there was no claim, it was automatically rolled over to round 2:

```
claimable_amount += premiums_earned_in_round + remaining_liquidity_in_round;
```

We repeat the above steps, replacing `1` with `2` and so on, until we finish our calculations with `4`. At this point, `claimable_amount` should accurately depict LP's dynamic position at the end of round 4. The full pseudo code is below:

```
get_claimable_amount_for_LP_upon_round_settlement(LP: ContractAddress, round_just_settled: u256):

    position: Position = positions[LP];
    round_positions = position.roundPositions;

    claimable_amount = 0;

    // In range [1, 4] inclusive
    for i in range[position.lastClaimcheckpoint + 1, round_just_settled]:
        round = rounds[i];

        ownership_percentage = (claimable_amount + round_positions[i].amount) / round.totalDeposits;
        total_liquidity_left_in_round = round.totalDeposits - round.totalPayout;

        premiums_earned_in_round = ownership_percentage * round.totalPremium;
        remaining_liquidity_in_round = ownership_percentage * total_liquidity_left_in_round;

        claimable_amount += (premiums_earned_in_round + remaining_liquidity_in_round);

    return claimable_amount;
```
