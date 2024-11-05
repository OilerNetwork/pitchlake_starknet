const MINUTE: u64 = 60;
const HOUR: u64 = 60 * MINUTE;
const DAY: u64 = 24 * HOUR;

const BPS_u128: u128 = 10_000;
const BPS_i128: i128 = 10_000;
const BPS_u256: u256 = 10_000;
const BPS_felt252: felt252 = 10_000;


/// VAULT ///

/// OPTION ROUND ///

// Testing
const ROUND_TRANSITION_PERIOD: u64 = 1 * MINUTE;
const AUCTION_RUN_TIME: u64 = 10 * MINUTE;
const OPTION_RUN_TIME: u64 = 5 * MINUTE;

// Realistic
// const ROUND_TRANSITION_PERIOD: u64 = 1 * HOUR;
// const AUCTION_RUN_TIME: u64 = 6 * HOUR;
// const OPTION_RUN_TIME: u64 = 30 * DAY;

/// FOSSIL CLIENT ///

// The identifier of the program Fossil will run
const PROGRAM_ID: felt252 = 'PITCH_LAKE_V1';

// Vaults accept data from Fossil if the timestamp is within this tolerance
const REQUEST_TOLERANCE: u64 = 1 * HOUR;

