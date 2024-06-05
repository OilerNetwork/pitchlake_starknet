// Pending bids become either premiums or refundable
// @note move tests in from pending_and_refunded_bids_tests.cairo
// @note move tests in from clearing_price_tests.cairo
// @note move tests in from options_minted_tests.cairo
// @note move tests in from premiums_earned_tests.cairo

// @note Consider breaking auction_end_tests.cairo into a directory/mod
// so that tree is more organized
//  option_round/
//    state_transition/
//      auction_start/
//        -
//      auction_end/
//        - pending_and_refunded_bids_tests.cairo
//        - clearing_price_tests.cairo
//        - options_minted.cairo
//        - premiums_earned_tests.cairo
//      option_settle/
//        - calculated_payout_tests.cairo


