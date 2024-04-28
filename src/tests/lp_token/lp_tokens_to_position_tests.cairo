// When an LP converts their tokens -> position, they are giving themselves a standard 
// position in the current round. Since the LP tokens represent currently locked liquidity,
// it really does not matter the state of the curret round. We simply caluclate the value of 
// the LP tokens (net the premiums from the round they come from) to the start of the current round
// (end of the previous round that rolls over). This is the value we add to the standard storage position
// for LP in the current round (just like a deposit, execpt a normal deposit adds to the position in the NEXT round).
 
// @note Add test that token->position always goes into the current round
//  - @note Add test that value increments position in current round, no affect on checkpoint
// @note Add test that LP tokens burn after positionizing
// @note Add test that tokens from round x cannot be positionized in round x
// @note Add test that the value of the LP tokens over multiple rounds is correct
// @note Test premiums from the round of origin do not affect the value of the LP tokens
// @note Test that all other rounds after origin round do accrue premiums (not the current round tho, we only care about the value of the tokens -> start_of_current_round)
// @note Test things work properly for an LP who positionizes their tokens but also has an active storage position 
// @note Test that lp cannot positionize > their lp token balance
