# Timestamp Ranges for L1 Data Validation

This guide explains how to calculate the correct timestamp ranges to pass the L1 data validation checks in the vault contract.

## Required View Functions

The vault contract provides these view functions to get the necessary components:

- `get_round_duration()` - Returns the round duration (line 266)
- `get_current_round_id()` - Returns the current round ID (line 283)  
- `get_round_dispatcher(round_id)` - Gets a round dispatcher for round-specific functions (line 800)

From the round dispatcher, you can call:
- `get_option_settlement_date()` - For running rounds
- `get_deployment_date()` - For non-running rounds

## Calculating Expected Ranges

```cairo
// Get the components
let round_duration = vault.get_round_duration();
let current_round_id = vault.get_current_round_id();
let current_round = vault.get_round_dispatcher(current_round_id);

// Determine upper bound based on round state
let upper_bound = if round_state == OptionRoundState::Running {
    current_round.get_option_settlement_date()
} else {
    current_round.get_deployment_date()  
};

// Calculate the expected ranges
let twap_lower_bound = upper_bound - round_duration;
let reserve_price_lower_bound = upper_bound - (3 * round_duration);
let max_return_lower_bound = reserve_price_lower_bound;

// All end timestamps should equal upper_bound
let expected_end_timestamp = upper_bound;
```

## Expected Values for L1 Data

Your L1 data should have these timestamp values:

| Field | Expected Value |
|-------|----------------|
| `twap_start_timestamp` | `upper_bound - round_duration` |
| `reserve_price_start_timestamp` | `upper_bound - (3 * round_duration)` |
| `max_return_start_timestamp` | `upper_bound - (3 * round_duration)` |
| `twap_end_timestamp` | `upper_bound` |
| `reserve_price_end_timestamp` | `upper_bound` |
| `max_return_end_timestamp` | `upper_bound` |

## Notes

- For **running rounds**: `upper_bound` = option settlement date
- For **non-running rounds**: `upper_bound` = deployment date  
- Reserve price and max return have the same lower bound (3x round duration before upper bound)
- All end timestamps must equal the upper bound
- TWAP has a shorter window (1x round duration before upper bound)