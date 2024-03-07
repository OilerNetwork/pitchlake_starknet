# Understanding Pitchlake

**Pitchlake** is a cutting-edge protocol built on Starknet, designed to pioneer the trading of Ethereum basefee options. By leveraging the power of Starknet, Pitchlake establishes an efficient, transparent, and accessible market for traders and liquidity providers (LPs) alike. The protocol's details and mechanics are documented in our technical paper, available [here](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018).

## Contracts Overview

### Vault

A vault acts as the central hub for liquidity providers (LPs) to deposit and withdraw their funds. When an LP deposits liquidity, the vault transfers it to the correct option round contract. At any point, an LP can submit a claim and have their liquidity automatically withdrawn at the end of the current option round. At the end of an option round, any claims submitted are processed, and the remaining liquidity is automatically sent to the next option round contract.

### Option Rounds

Each option round is a distinct phase of trading, encapsulated within its own contract. These rounds allow for the auction and settlement of Ethereum basefee options, with each contract managing its specific set of options.

**Lifecycle states**: An option round transitions through several states—Open, Auctioning, Running, and Settled—reflecting different phases from initiation to completion. When an option round is first deployed, its state is set to Open. Once its auction starts, the option round updates to the Auctioning state. Once the auction ends, the option round state updates to Running. And finally, once the option settlement date has been reached, it can be set to Settled.

## Entrypoints

### Vault

- **Deposit**: LPs add liquidity which is immediately sent to the currently active option round, and their vault positions are updated.

- **Submit Claim**: Prepares LPs' funds for withdrawal after the settlement of the current option round.

- **Withdraw**: LPs withdraw from their positions in the current Open option round.

- **Start New Option Round**: Deploys the new next option round contract, updates the vaults current & next pointers accordingly, and starts the auction on the new current round.

- **Getters**: There should be read functions on the vault to return: the vault type, the current option round, the next option round, addresses of option rounds, and an LP's liquidity/position in a round.

> Question: Should there be a getter to see positions in rounds, and remaining liquidity for a round ?

### Option Rounds

- **Start Auction**: Begins the auction phase, allowing traders to place bids on options.

- **Place Auction Bid**: Option buyers submit their bids for options within the round.

- **Settle Auction**: Concludes the auction, determining the final distribution of options and premiums.

- **Refund Unused Bids**: Returns any excess funds to bidders if their bids were not fully utilized.

- **Settle Option Round**: Settles the option round and calculates the total payout of the options.

- **Claim Option Payout**: Option buyers exercise their options and claim their individual payouts, corresponding to the number of options they own.

> Options are represented as ERC20 tokens, we should probably burn them during claim_option_payout, to avoid an OB double exercising, or at least mark them as exercised.

- **Getters**: There should be read functions on an option round to return: the option round's state, the option round's params, the total liquidity in a round, the bid deposit balance of an OB, the auction's clearing price, the balance of unused bids of an OB, the payout balance of an OB, and the premium balance of an LP.

> Are we implementing a premium_balance_of getter ? This would mean fetching the current position from the vault (from last checkpoint), and then calculating the premiums for the round. Not overly complex, just curious if we want this entrypoint on the option round or the vault.

> Are bids removable before an auction settles ? Or are they considered final/locked upon deposit ?

## Technical Implementation

When an LP first deposits liquidity, they receive an ERC721 token representing their position in the vault. This token is updated with each additional liquidity provision, creating a dynamic record of their participation in the market.

> If position is an ERC721, what happens if LP1 sends their token to LP2 ? When LP2 tries to deposit, they will be minted a new position token, and LP1 will not be able to mint another ?
>
> A fix is to not tokenize the positions, instead have them be typical structs indexed by LP address.
>
> Another fix is to inject a \_before_transfer() function on the tokens, to properly update our map of LP_address => token_id whenever a position is transferred.

A position is a struct that looks like so:

```
Postion {
    roundPositions: map(round_id: u256) -> roundPosition,
    lastClaimCheckpoint: (round: round, state: OptionRoundState),
    // not sure state is needed
}
```

and the sub-structs look like so:

```
roundPosition {
    round: round, // not sure if this is needed or if it should be round_id
    amount: u256, // the amount LP deposited into the round
}

round {
    totalAmount: u256, // the remaining liquidity after round settlement ?
    totalPremium: u256, // the total premium collected from the auction
    state: OptionRoundState, // Open | Auctioning | Running | Settled
}
```

> Is round.totalAmount the initial liquidity in a round ? Or the amount post-settlement ? (i.e. total_deposits || total_deposits - total_payout ?)

## Example: LP Participation

An LP begins by depositing liquidity in round 1 (depositing 1 eth) and then again in round 3 (depositing another 1 eth). Their position reflects these contributions, with the lastClaimCheckpoint indicating the last round from which they have withdrawn or claimed funds (in this case: 0).

Their vault::position looks like this:

```
Position {
    lastClaimCheckpoint: 0,

    roundPositions: {
        1: {
            round: {...},
            amount: 1 eth,
        },
        2: {
            round: {empty},
            amount: 0,
        },
        3: {
            round: {...},
            amount: 1 eth,
        },

        ...
    },
}

```

Round 3 ends, and while round 4 is on-going, LP submits a claim to withdraw their position. Once round 4 settles, LP's claim is processed.

To acurately determine LP's available balance for withdraw, we must calculate their dynamic position across the rounds. We use LP's Position.lastClaimCheckpoint to determine where our calculations start.

First, we initialize a variable for claimable amount:

```
claimable_amount = 0;
```

Next, we calculate LP's % of ownership for the option round's pool:

```
ownership_percentage = (claimable_amount + Position.roundPositions[1].amount) / rounds[1].total_amount;
```

Next, we take note of the total liquidity left in round 1:

```
total_liquidity_left_in_round = rounds[1].total_amount - rounds[1].total_payout;
```

With values, we can calculate how much of the option round's total premiums belong to LP, along with how much of the total remaining liquidity is theirs:

```
premiums_earned_in_round = ownership_percentage * rounds[1].total_premiums;

remaining_liquidity_in_round = ownership_percentage * liquidity_left_in_round;
```

The sum of these 2 values is the amount LP could have withdrawn at the end of round 1, but since there was no claim, it was automatically rolled over to round 2:

```
claimable_amount += premiums_earned_in_round + remaining_liquidity_in_round;
```

We repeat the above steps, replacing `1` with `2` and so on, until we finish our calculations with `4`. At this point, `claimable_amount` should accurately depict LP's dynamic position at the end of round 4. The full pseudo code is below:

```
get_claimable_amount_for_LP_upon_round_settlement(LP: ContractAddress, round_just_settled: u256):

    position = Positions[LP];
    round_positions = position.roundPositions;
    claimable_amount = 0;

    // In range [1, 4] inclusive
    for i in range[position.lastClaimcheckpoint + 1, round_just_settled]:
        round = rounds[i];

        ownership_percentage = (claimable_amount + round_positions[i].amount) / round.total_amount;
        total_liquidity_left_in_round = round.total_amount - round.total_payout;

        premiums_earned_in_round = ownership_percentage * round.total_premiums;
        remaining_liquidity_in_round = ownership_percentage * liquidity_left_in_round;

        claimable_amount += (premiums_earned_in_round + remaining_liquidity_in_round);

    return claimable_amount;
```
