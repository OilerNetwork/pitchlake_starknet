// When an LP converts their position -> tokens, they are choosing the convert some of the value of their active 
// position in the current round, net any premiums (their collateral) to tokens. Meaning we will need to calulcate the value of their 
// position at the start of the current round from their last checkpoint (collateral), collect their premiums 
// (if they have not yet), update their position & checkpoint, then mint them LP tokens.
//
// @note Test that collateral is correct over multiple rounds (with and without payouts and with or without unsold liquidity)
// @note Test that the only time this is allowed is when the current round is Running.
//  - Auctioning means no premiums yet, needed for LP token logic to work
//  - Settled means the $ is in the next round and is no longer collateral (is unallocated and could just be withdrawn normally)
// @note Test that position -> tokens updates the checkpoint to the current round and the value of the deposit into the current round (value - tokenizing_amount)
// @note Test that tokenizing > collateral fails
// @note Test that tokenizing SOME of the collateral collects ALL premiums
// @note Test no sub over flows because of this:
//  - Calculating position value subracts collected_rewards from the total_rewards (total - collected)
//    - There is a chance that collected is > remaining total if LP tokenizes some, so test that in this case there is no error, but is treated as if they collected all.
//    - @note Add test that this executes correctly
//    - @note Also test that this is not an issue when caluclating rolled_over_amount
