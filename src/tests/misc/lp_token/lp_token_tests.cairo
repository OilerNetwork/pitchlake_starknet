//use starknet::{
//    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
//    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
//    testing::{set_block_timestamp, set_contract_address}
//};
//use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
//use pitch_lake_starknet::{
//    library::eth::Eth,
//    tests::{
//        utils::{
//            helpers::{
//                accelerators::{timeskip_and_settle_round},
//                setup::{setup_facade, decimals, deploy_vault},
//                event_helpers::{pop_log, assert_no_events_left, assert_event_transfer}
//            },
//            lib::test_accounts::{
//                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
//                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
//            },
//            facades::{
//                vault_facade::{VaultFacade, VaultFacadeTrait},
//                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
//            },
//        },
//    }
//};
//
/////
///// Position -> LP Tokens ///
/////
//
//// Test converting position->lp tokens fails if the auction has not ended
//#[ignore]
//#[test]
//#[available_gas(50000000)]
//#[should_panic(expected: ('Cannot tokenize until auction ends', 'ENTRYPOINT_FAILED',))]
//fn test_convert_position_to_lp_tokens_while_auctioning_failure() {
//    let (mut vault_facade, _) = setup_facade();
//    // Deposit liquidity so auction can start
//    let deposit_amount_wei = 50 * decimals();
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//    // Start the auction
//    vault_facade.start_auction();
//    // Try to convert position to tokens, should fail since premiums are not known yet
//    vault_facade.convert_position_to_lp_tokens(1, liquidity_provider_1());
//}
//
//// Test converting position -> lp tokens while the current round is settled
////  @note We should discuss if there is a use case for this. I do not think it breaks any logic
////  (it should act the same as if the round were Running), but the liquidity is all unlocked in the
////  next round during this time and could just be withdrawn instead of tokenized.
////  @note If we allow this, the premiums still need to be collected, since they are already sitting in the
////  next round, we can mark the current round's premiums collected, and leave the amount sitting in the next round
//#[ignore]
//#[test]
//#[available_gas(50000000)]
//#[should_panic(expected: ('Cannot tokenize when round is settled?', 'ENTRYPOINT_FAILED',))]
//fn test_convert_position_to_lp_tokens_while_settled__TODO__() {
//    let (mut vault_facade, _) = setup_facade();
//    // LP deposits (into round 1)
//    let deposit_amount_wei: u256 = 10000 * decimals();
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//    // Start auction
//    vault_facade.start_auction();
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//    // Make bid
//    let bid_amount: u256 = current_round.get_total_options_available();
//    let bid_price: u256 = current_round.get_reserve_price();
//    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
//    // Settle auction
//    set_block_timestamp(current_round.get_auction_end_date() + 1);
//    let (clearing_price, _) = vault_facade.end_auction();
//    assert(clearing_price == bid_price, 'clearing price wrong');
//    // Settle option round
//    set_block_timestamp(current_round.get_option_settlement_date() + 1);
//    vault_facade.settle_option_round();
//    // Convert position -> tokens while current round is Settled
//    vault_facade.convert_position_to_lp_tokens(1, liquidity_provider_1());
//// @note verify expected behavior
//}
//
//// Test that converting position -> LP tokens auto-collects premiums and updates the position
//// @dev Check unallocated assertions after speaking with Dhruv, should unallocated_balance be premiums + next_round_deposit, or just next_round_deposit ?
//// @dev Is this test suffice for knowing withdrawCheckpoint and current_roundPosition is updated correctly? If lp_collateral is correct then withdrawCheckpoint must be right ?
//#[ignore]
//#[test]
//#[available_gas(50000000)]
//fn test_convert_position_to_lp_tokens_success() { //
//    let (mut vault_facade, _) = setup_facade();
//    // LPs deposit 50/50 into the next round (round 1)
//    let deposit_amount_wei: u256 = 10000 * decimals();
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_2());
//    // Start auction
//    let total_options_available = vault_facade.start_auction();
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//    // Make bid
//
//    let reserve_price = current_round.get_reserve_price();
//    let auction_end_time = current_round.get_auction_end_date();
//
//    let bid_amount: u256 = total_options_available;
//    let bid_price: u256 = reserve_price;
//    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
//    // Settle auction
//    set_block_timestamp(auction_end_time + 1);
//    // Get initial states before conversion
//    //let lp1_premiums_init = vault_facade.get_premiums_for(liquidity_provider_1(), 'todo'.into());
//    //let lp2_premiums_init = vault_facade.get_premiums_for(liquidity_provider_2(), 'todo'.into());
//    let (lp1_collateral_init, _lp1_unallocated_init) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    let (lp2_collateral_init, lp2_unallocated_init) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_2());
//    //    let (current_round_collateral_init, _current_round_unallocated_init) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral_init, next_round_unallocated_init) = next_round
//    //        .get_all_round_liquidity();
//    // LP1 converts 1/2 of their position to tokens
//    let tokenizing_amount = deposit_amount_wei / 4;
//    vault_facade.convert_position_to_lp_tokens(tokenizing_amount, liquidity_provider_1());
//    // Get states after conversion
//    //let lp1_premiums_final = vault_facade.get_premiums_for(liquidity_provider_1(), 'todo'.into());
//    //let lp2_premiums_final = vault_facade.get_premiums_for(liquidity_provider_2(), 'todo'.into());
//    let (lp1_collateral_final, lp1_unallocated_final) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    let (lp2_collateral_final, lp2_unallocated_final) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_2());
//    //    let (current_round_collateral_final, current_round_unallocated_final) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral_final, next_round_unallocated_final) = next_round
//    //        .get_all_round_liquidity();
//    // Assert all premiums were collected (deposit into the next round)
//    let expected_premiums_share = current_round.total_premiums() / 2;
//    //assert(
//    //    lp1_premiums_final == lp1_premiums_init
//    //        - expected_premiums_share && lp1_premiums_final == 0,
//    //    'lp1 premiums incorrect'
//    //); // @dev need both checks ?
//    //assert(lp2_premiums_final == lp2_premiums_init, 'lp2 premiums shd not change');
//    // @dev Some of LP1's collateral is now represented as tokens, this means their collateral will decrease,
//    // but the round's will remain the same.
//    assert(
//        lp1_collateral_final == lp1_collateral_init - tokenizing_amount, 'premiums not collected'
//    );
//    assert(lp2_collateral_final == lp2_collateral_init, 'premiums shd not collect');
//    //    assert(
//    //        current_round_collateral_final == current_round_collateral_init,
//    //        'round collateral shd not change'
//    //    );
//    //    assert(next_round_collateral_final == next_round_collateral_init, 'round not locked yet');
//    // @dev Collected premium should be deposited into the next round
//    // @dev Find out if unallocated is premiums + next round depoist or just next round deposit
//    assert(lp1_unallocated_final == 'TODO'.into(), 'lp1 unallocated shd ...');
//    assert(lp2_unallocated_final == lp2_unallocated_init, 'lp2 shd not change');
////    assert(current_round_unallocated_final == 'TODO'.into(), 'round unallocated shd ...');
////    assert(
////        next_round_unallocated_final == next_round_unallocated_init + expected_premiums_share,
////        'premiums not deposited'
////    );
//// Check ETH transferred from current -> next round
//// assert_event_transfer(
////     eth.contract_address,
////     current_round.contract_address(),
////     next_round.contract_address(),
////     expected_premiums_share
//// );
//// @note Add lp token transfer event assert function
//// assert_lp_event_transfer(lp_token_contract, from: 0, to: LP1, amount: tokenizing_amount)
//}
//
//// @note Add test that the auto-collect does nothing if LP has already collected their premiums
//// @note Add test that tokenizing > collateral fails
//
/////
///// LP Tokens -> Position ///
/////
//
//// Test converting tokens-> position deposits into the current round
//// @dev If user can choose target round when converting, then target must be > withdrawCheckpoint,
//// and the round target-1 must be settled.
//#[ignore]
//#[test]
//#[available_gas(50000000)]
//fn test_convert_lp_tokens_to_position_is_always_deposit_into_current_round() { //
//    let (mut vault_facade, _) = setup_facade();
//    // LP deposits (into round 1)
//    let deposit_amount_wei: u256 = 10000 * decimals();
//    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
//    // Start auction
//    vault_facade.start_auction();
//    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
//
//    let reserve_price = current_round.get_reserve_price();
//    let total_options_available = current_round.get_total_options_available();
//    let auction_end_time = current_round.get_auction_end_date();
//
//    // Make bid
//    let bid_amount: u256 = total_options_available;
//    let bid_price: u256 = reserve_price;
//    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
//    // Settle auction
//    set_block_timestamp(auction_end_time + 1);
//    vault_facade.end_auction();
//
//    // Convert position -> tokens (while current is Running)
//    vault_facade.convert_position_to_lp_tokens(deposit_amount_wei, liquidity_provider_1());
//    // Initial state
//    let (lp_collateral_init, lp_unallocated_init) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    //    let (current_round_collateral_init, current_round_unallocated_init) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral_init, next_round_unallocated_init) = next_round_facade
//    //        .get_all_round_liquidity();
//    //
//    // Convert some tokens to a position while current is Running
//    vault_facade.convert_lp_tokens_to_position(1, deposit_amount_wei / 4, liquidity_provider_1());
//    // Get states after conversion1
//    let (lp_collateral1, lp_unallocated1) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    //    let (current_round_collateral1, current_round_unallocated1) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral1, next_round_unallocated1) = next_round_facade
//    //        .get_all_round_liquidity();
//    //
//    // Settle option round
//    // @dev Do we need to mock the mkagg to say there is no payout for these tests ?
//    timeskip_and_settle_round(ref vault_facade);
//
//    // Convert some tokens to a position while current is Settled
//    vault_facade.convert_lp_tokens_to_position(1, deposit_amount_wei / 4, liquidity_provider_1());
//    // Get states after conversion2
//    let (lp_collateral2, lp_unallocated2) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    //    let (current_round_collateral2, current_round_unallocated2) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral2, next_round_unallocated2) = next_round_facade
//    //        .get_all_round_liquidity();
//    //
//    /// Start next round's auction
//    // @dev Need to jump to time += RTP
//    vault_facade.start_auction();
//    let mut next_next_round = vault_facade.get_current_round();
//
//    // Convert some tokens to a position while current is Auctioning
//    vault_facade.convert_lp_tokens_to_position(1, deposit_amount_wei / 4, liquidity_provider_1());
//    // Get states after conversion3
//    let (lp_collateral3, lp_unallocated3) = vault_facade
//        .get_lp_locked_and_unlocked_balance(liquidity_provider_1());
//    //    let (current_round_collateral3, current_round_unallocated3) = current_round
//    //        .get_all_round_liquidity();
//    //    let (next_round_collateral3, next_round_unallocated3) = next_round_facade
//    //        .get_all_round_liquidity();
//    //    let (next_next_round_collateral3, next_next_round_unallocated3) = next_next_round
//    //        .get_all_round_liquidity();
//
//    // Assert initial state after converting position -> tokens
//    assert(lp_collateral_init == 0, 'lp collat.init shd be in tokens');
//    assert(
//        lp_unallocated_init == 0, 'lp unalloc.init shd be 0'
//    ); // premiums already collected when position->tokens
//    //   assert(current_round_collateral_init == deposit_amount_wei, 'current r collat.init wrong');
//    //assert(
//    //        current_round_unallocated_init == 0, 'current r unalloc.init shd be 0'
//    // ); // @dev should this be total premiums ? or stay 0 since all were collected
//    //   assert(next_round_collateral_init == 0, 'next round collat.init shd be 0');
//    //  assert(next_round_unallocated_init == 0, 'next round unalloc.init shd b 0');
//
//    // Assert converting tokens -> position while current is Running deposits into the next round
//    assert(lp_collateral1 == deposit_amount_wei / 4, 'conversion amount shd be collat');
//    assert(lp_unallocated1 == 0, 'lp unalloc1 shd be 0');
//    //    assert(current_round_collateral1 == deposit_amount_wei, 'current r collat1 wrong');
//    //    assert(current_round_unallocated1 == 0, 'current r unalloc1 shd be 0');
//    //    assert(next_round_collateral1 == 0, 'next round collat1 shd be 0');
//    //    assert(next_round_unallocated1 == 0, 'next round unalloc1 shd be 0');
//
//    // Assert converting tokens -> position while current is Settled deposits into the next round
//    assert(lp_collateral2 == 0, 'liq is unalloc in next round');
//    assert(lp_unallocated2 == deposit_amount_wei / 2, 'prev collat shd rollover');
////    assert(current_round_collateral2 == 0, 'current r collat2 shd b 0');
////    assert(current_round_unallocated2 == 0, 'current r unalloc2 shd b 0');
////    assert(next_round_collateral2 == 0, 'next round collat2 shd b 0');
////    assert(next_round_unallocated2 == deposit_amount_wei / 2, 'all liq shd be unalloc in next');
//
//// Assert converting tokens -> position while current is Auctioning deposits into the next next round
////    assert(lp_collateral3 == 3 * deposit_amount_wei / 4, 'lp collat shd rollover + amount');
////    assert(lp_unallocated3 == 0, 'lp unalloc shd be 0');
////    assert(current_round_collateral3 == 0, 'current r collat shd be 0');
////    assert(current_round_unallocated3 == 0, 'current r unalloc shd be 0');
////    assert(next_round_collateral3 == 3 * deposit_amount_wei / 4, 'round collat shd rollover');
////    assert(next_round_unallocated3 == 0, 'round unalloc shd be 0');
////    assert(next_next_round_collateral3 == 0, 'next next round collat shd be 0');
////    assert(next_next_round_unallocated3 == 0, 'next next round unalloc shd b 0');
//}
//
//// Test converting round lp tokens into a position backwards fails (only if user can choose target round)
////fn test_convert_lp_tokens_to_position_backwards_fails() { }
//
//// Test converting lp tokens into a position does not count the premiums earned in the source round
//#[test]
//#[available_gas(50000000)]
//#[ignore]
//fn test_convert_lp_tokens_to_position_does_not_count_source_round_premiums() { //
//// Deploy vault
//
//// LP1 and LP2 deposits into round 1 (50/50)
//
//// Start/end round 1's auction
//
//// LP1 converts entire position to lp tokens, then sends them to LP3
//
//// Accelerate to current round 3
//
//// LP3 converts all their r1 lp tokens -> r3 position
//
//// Assert LP3's r3 position is < LP2's r3 position (LP3's position does not include the premiums from r1 rolling over, but LP2's does)
//// assert(vault::position[LP3, 3] < vault::position[LP2, 3])
//}
//
//
//// Test converting lp tokens into a position in same round (r1 tokens to r1 position) sets premiumsCollected to true
////  - The minter of the rx tokens already collected their premiums, this ensures that if the buyer of the tokens converts the rx tokens
////  into an rx position, they are not allowed to double-collect these premiums
//fn test_rx_tokens_to_rx_position_sets_rx_premiums_collected_to_true() { //
//// Deploy vault
//
//// LP1 deposits 20 ETH into round 1
//
//// Start/end round 1's auction
//
//// Convert 10 ETH to r1 LP tokens
//// vault.convert_position_to_lp_tokens(amount: 10 ETH)
//
//// Split the tokens so that LP1 has 1/2, and LP2 has the other half
//// lp_token_dispatcher.transfer_from(LP1, LP2, 5 ETH r1 lp tokens)
//
//// LP1 and LP2 both have 5 ETH r1 lp tokens
//
//// Both convert their tokens to positions in round 1
//// vault.convert_lp_tokens_to_position(lp_token_id: 1, target_round_for_position: 1, amount: 5 ETH LP tokens, caller: LP1)
//// vault.convert_lp_tokens_to_position(lp_token_id: 1, target_round_for_position: 1, amount: 5 ETH LP tokens, caller: LP2)
//
//// Assert positions are expected
//// assert(position[1, LP1] == 15 ETH)
//// assert(position[1, LP2] == 5 ETH)
//
//// Assert premiums are expected
//// @note Both LP's should not have any premiums to claim, when LP1 converted position -> token, they already collected the premiums for the tokens
//// assert(vault.premiums_balance_of(LP1) == 0)
//// assert(vault.premiums_balance_of(LP2) == 0)
//
//// What are premiumsCollected for both LP1 and LP2 ?
////  -
//
//// Convert all r1 LP tokens to an r1 position
//// vault.convert_lp_tokens_to_position(lp_token_id: 1, target_round_for_position: 1, amount: 5 ETH LP tokens)
//
//// Assert 5 ETH LP tokens were burned
//
//// Assert position[1] == 10ETH
//
//// premiumsCollected needs to be set, so that LP cannot double claim the r1 premium
//
//}
//
//// Test converting lp tokens into a position in the same round (r1 tokens to r1 position) handles exisiting premiums
//// @dev When rX tokens -> rX position, we set premiumsCollected to true. If the user has an active position with
//// collectable premiums, we do not want them to get lost, so we collect them during this step.
//fn test_rx_tokens_to_rx_position_handles_exisiting_premiums() { //
//// lp 1 and 2 deposit, auction starts/ends
//// lp 1 tokenizes and sells to lp2
//// lp 2 converts the rX tokens into an rX position,
//// - test that lp2's already exisiting premiums get collected
//// - test that lp2's premiumsCollected is true
//}
//// @note Add test that converting tokens->position is always a position into the current round
////    @dev If we want to add that a user can choose the position round (rx tokens -> ry position),
////    then y must be > user.withdrawCheckpoint and we should check that other logic does not break.
////    @dev The 2 tests below are not needed if the conversion is always into the current round, only
////    if they user can specify the round when converting tokens->position
//
/////
///// LP Tokens (rA) -> LP tokens (rB)
/////
//
//// - Cannot go backwards (B must be > A)
//// - rB's auction must be over
//// - @dev LP tokens represent a position net premiums, so we do not count the premiums earned from an lp token's source round.
//// This is an issue because if a user converts tokenAs -> tokenBs, in the future we will ingore the premiums earned from roundB. To make sure the user
//// still gets their premiums from this round upon tokenA->tokenB conversion, we need to collect the premiums from roundB for the user
//// (we collect the amount of premiums the tokens earn in rB, if the user already has a storage position in rB with collectable premiums we ignore them).
//// - @dev When we collect rB's premiums, we do not touch premiumsCollected or collectable premiums in rB, they can stay as they are in storage
//// - @dev When we collect rB's premiums, we deposit them into roundB+1 as a position.
////    - We cannot collect the premiums as ETH since rB might be a historical (not the current) round and that ETH may be locked in the current round. If B is the current round, then
////    this position in rB+1 is immediately withdrawable.
//
//// @dev Begs the question, should collect always be a deposit into the next round, to then be withdrawable if choosen to (if user wants to claim premiums as eth, can just do a multi-call, collect, then withdraw)
////  - `collect()` should not always set premiumsCollected to true. If a user converts tokens A-B, we collect the rB premiums for the tokens. If the user has a position in storage with collectable premiums, we are
////  not touching them, so premiumsCollected does not need to be set. So maybe the collect entry point does set premiums collected to true, but collecting during a tokenA-tokenB conversion does not
//
//

