const MINUTE: u64 = 60;
const HOUR: u64 = 60 * MINUTE;
const DAY: u64 = 24 * HOUR;
const BPS_u128: u128 = 10_000;
const BPS_i128: i128 = 10_000;
const BPS_u256: u256 = 10_000;
const BPS_felt252: felt252 = 10_000;

/// FOSSIL CLIENT ///

// The identifier of the program Fossil will run
const PROGRAM_ID: felt252 = 'PITCH_LAKE_V1';

// The time it takes for Fossil to be able to prove the latest block header
const PROVING_DELAY: u64 = 10 * MINUTE;

