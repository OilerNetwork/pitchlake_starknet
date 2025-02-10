export const ABI = [
  {
    "type": "impl",
    "name": "VaultImpl",
    "interface_name": "pitch_lake::vault::interface::IVault"
  },
  {
    "type": "enum",
    "name": "pitch_lake::vault::interface::VaultType",
    "variants": [
      {
        "name": "InTheMoney",
        "type": "()"
      },
      {
        "name": "AtTheMoney",
        "type": "()"
      },
      {
        "name": "OutOfMoney",
        "type": "()"
      }
    ]
  },
  {
    "type": "struct",
    "name": "core::integer::u256",
    "members": [
      {
        "name": "low",
        "type": "core::integer::u128"
      },
      {
        "name": "high",
        "type": "core::integer::u128"
      }
    ]
  },
  {
    "type": "struct",
    "name": "core::array::Span::<core::felt252>",
    "members": [
      {
        "name": "snapshot",
        "type": "@core::array::Array::<core::felt252>"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::fossil_client::interface::L1Data",
    "members": [
      {
        "name": "twap",
        "type": "core::integer::u256"
      },
      {
        "name": "volatility",
        "type": "core::integer::u128"
      },
      {
        "name": "reserve_price",
        "type": "core::integer::u256"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::fossil_client::interface::RoundSettledReturn",
    "members": [
      {
        "name": "total_payout",
        "type": "core::integer::u256"
      }
    ]
  },
  {
    "type": "enum",
    "name": "pitch_lake::fossil_client::interface::FossilCallbackReturn",
    "variants": [
      {
        "name": "RoundSettled",
        "type": "pitch_lake::fossil_client::interface::RoundSettledReturn"
      },
      {
        "name": "FirstRoundInitialized",
        "type": "()"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::types::Bid",
    "members": [
      {
        "name": "bid_id",
        "type": "core::felt252"
      },
      {
        "name": "owner",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "amount",
        "type": "core::integer::u256"
      },
      {
        "name": "price",
        "type": "core::integer::u256"
      },
      {
        "name": "tree_nonce",
        "type": "core::integer::u64"
      }
    ]
  },
  {
    "type": "interface",
    "name": "pitch_lake::vault::interface::IVault",
    "items": [
      {
        "type": "function",
        "name": "get_vault_type",
        "inputs": [],
        "outputs": [
          {
            "type": "pitch_lake::vault::interface::VaultType"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_alpha",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u128"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_strike_level",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::i128"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_eth_address",
        "inputs": [],
        "outputs": [
          {
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_fossil_client_address",
        "inputs": [],
        "outputs": [
          {
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_round_transition_duration",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_auction_duration",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_round_duration",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_current_round_id",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_round_address",
        "inputs": [
          {
            "name": "option_round_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_vault_total_balance",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_vault_locked_balance",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_vault_unlocked_balance",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_vault_stashed_balance",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_vault_queued_bps",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u128"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_account_total_balance",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_account_locked_balance",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_account_unlocked_balance",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_account_stashed_balance",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_account_queued_bps",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u128"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_request_to_settle_round",
        "inputs": [],
        "outputs": [
          {
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_request_to_start_first_round",
        "inputs": [],
        "outputs": [
          {
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "deposit",
        "inputs": [
          {
            "name": "amount",
            "type": "core::integer::u256"
          },
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "withdraw",
        "inputs": [
          {
            "name": "amount",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "queue_withdrawal",
        "inputs": [
          {
            "name": "bps",
            "type": "core::integer::u128"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "withdraw_stash",
        "inputs": [
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "fossil_client_callback",
        "inputs": [
          {
            "name": "l1_data",
            "type": "pitch_lake::fossil_client::interface::L1Data"
          },
          {
            "name": "timestamp",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "pitch_lake::fossil_client::interface::FossilCallbackReturn"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "start_auction",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "end_auction",
        "inputs": [],
        "outputs": [
          {
            "type": "(core::integer::u256, core::integer::u256)"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "place_bid",
        "inputs": [
          {
            "name": "amount",
            "type": "core::integer::u256"
          },
          {
            "name": "price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "pitch_lake::types::Bid"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "update_bid",
        "inputs": [
          {
            "name": "bid_id",
            "type": "core::felt252"
          },
          {
            "name": "price_increase",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "pitch_lake::types::Bid"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "refund_unused_bids",
        "inputs": [
          {
            "name": "round_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "account",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "mint_options",
        "inputs": [
          {
            "name": "round_address",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "exercise_options",
        "inputs": [
          {
            "name": "round_address",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u256"
          }
        ],
        "state_mutability": "external"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::vault::interface::ConstructorArgs",
    "members": [
      {
        "name": "fossil_client_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "eth_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "option_round_class_hash",
        "type": "core::starknet::class_hash::ClassHash"
      },
      {
        "name": "alpha",
        "type": "core::integer::u128"
      },
      {
        "name": "strike_level",
        "type": "core::integer::i128"
      },
      {
        "name": "round_transition_duration",
        "type": "core::integer::u64"
      },
      {
        "name": "auction_duration",
        "type": "core::integer::u64"
      },
      {
        "name": "round_duration",
        "type": "core::integer::u64"
      }
    ]
  },
  {
    "type": "constructor",
    "name": "constructor",
    "inputs": [
      {
        "name": "args",
        "type": "pitch_lake::vault::interface::ConstructorArgs"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::Deposit",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "account_unlocked_balance_now",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "vault_unlocked_balance_now",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::Withdrawal",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "account_unlocked_balance_now",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "vault_unlocked_balance_now",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::WithdrawalQueued",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "bps",
        "type": "core::integer::u128",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "account_queued_liquidity_before",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "account_queued_liquidity_now",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "vault_queued_liquidity_now",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::StashWithdrawn",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "vault_stashed_balance_now",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::option_round::interface::PricingData",
    "members": [
      {
        "name": "strike_price",
        "type": "core::integer::u256"
      },
      {
        "name": "cap_level",
        "type": "core::integer::u128"
      },
      {
        "name": "reserve_price",
        "type": "core::integer::u256"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::OptionRoundDeployed",
    "kind": "struct",
    "members": [
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      },
      {
        "name": "auction_start_date",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "auction_end_date",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "option_settlement_date",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "pricing_data",
        "type": "pitch_lake::option_round::interface::PricingData",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::L1RequestFulfilled",
    "kind": "struct",
    "members": [
      {
        "name": "id",
        "type": "core::felt252",
        "kind": "key"
      },
      {
        "name": "caller",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::PricingDataSet",
    "kind": "struct",
    "members": [
      {
        "name": "pricing_data",
        "type": "pitch_lake::option_round::interface::PricingData",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::AuctionStarted",
    "kind": "struct",
    "members": [
      {
        "name": "starting_liquidity",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "options_available",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::AuctionEnded",
    "kind": "struct",
    "members": [
      {
        "name": "options_sold",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "clearing_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "unsold_liquidity",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "clearing_bid_tree_nonce",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::OptionRoundSettled",
    "kind": "struct",
    "members": [
      {
        "name": "settlement_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "payout_per_option",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::BidPlaced",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "bid_id",
        "type": "core::felt252",
        "kind": "data"
      },
      {
        "name": "amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "bid_tree_nonce_now",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::BidUpdated",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "bid_id",
        "type": "core::felt252",
        "kind": "data"
      },
      {
        "name": "price_increase",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "bid_tree_nonce_before",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "bid_tree_nonce_now",
        "type": "core::integer::u64",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::UnusedBidsRefunded",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "refunded_amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::OptionsMinted",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "minted_amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::OptionsExercised",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "total_options_exercised",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "mintable_options_exercised",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "exercised_amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "round_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "round_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "Deposit",
        "type": "pitch_lake::vault::contract::Vault::Deposit",
        "kind": "nested"
      },
      {
        "name": "Withdrawal",
        "type": "pitch_lake::vault::contract::Vault::Withdrawal",
        "kind": "nested"
      },
      {
        "name": "WithdrawalQueued",
        "type": "pitch_lake::vault::contract::Vault::WithdrawalQueued",
        "kind": "nested"
      },
      {
        "name": "StashWithdrawn",
        "type": "pitch_lake::vault::contract::Vault::StashWithdrawn",
        "kind": "nested"
      },
      {
        "name": "OptionRoundDeployed",
        "type": "pitch_lake::vault::contract::Vault::OptionRoundDeployed",
        "kind": "nested"
      },
      {
        "name": "L1RequestFulfilled",
        "type": "pitch_lake::vault::contract::Vault::L1RequestFulfilled",
        "kind": "nested"
      },
      {
        "name": "PricingDataSet",
        "type": "pitch_lake::vault::contract::Vault::PricingDataSet",
        "kind": "nested"
      },
      {
        "name": "AuctionStarted",
        "type": "pitch_lake::vault::contract::Vault::AuctionStarted",
        "kind": "nested"
      },
      {
        "name": "AuctionEnded",
        "type": "pitch_lake::vault::contract::Vault::AuctionEnded",
        "kind": "nested"
      },
      {
        "name": "OptionRoundSettled",
        "type": "pitch_lake::vault::contract::Vault::OptionRoundSettled",
        "kind": "nested"
      },
      {
        "name": "BidPlaced",
        "type": "pitch_lake::vault::contract::Vault::BidPlaced",
        "kind": "nested"
      },
      {
        "name": "BidUpdated",
        "type": "pitch_lake::vault::contract::Vault::BidUpdated",
        "kind": "nested"
      },
      {
        "name": "UnusedBidsRefunded",
        "type": "pitch_lake::vault::contract::Vault::UnusedBidsRefunded",
        "kind": "nested"
      },
      {
        "name": "OptionsMinted",
        "type": "pitch_lake::vault::contract::Vault::OptionsMinted",
        "kind": "nested"
      },
      {
        "name": "OptionsExercised",
        "type": "pitch_lake::vault::contract::Vault::OptionsExercised",
        "kind": "nested"
      }
    ]
  }
] as const;
