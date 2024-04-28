// @note Add test that LP can tokenize the current position only while current round is Running
//  - acts as a withdraw in the current round, updating lp unallcated/collateral & vault::position (+ checkpoint)
// @note Add test that LP can positionize into any current round other than the round the tokens come from
//  - acts as a deposit of xyz into the current round, updating lp unallcated/collateral & vault::position

// Entry points are on the vault but we are seperating the tests here for simplicity
