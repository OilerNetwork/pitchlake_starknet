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
    "name": "pitch_lake::fact_registry::interface::JobRequestParams",
    "members": [
      {
        "name": "twap",
        "type": "(core::integer::u64, core::integer::u64)"
      },
      {
        "name": "volatility",
        "type": "(core::integer::u64, core::integer::u64)"
      },
      {
        "name": "reserve_price",
        "type": "(core::integer::u64, core::integer::u64)"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake::fact_registry::interface::JobRequest",
    "members": [
      {
        "name": "identifiers",
        "type": "core::array::Span::<core::felt252>"
      },
      {
        "name": "params",
        "type": "pitch_lake::fact_registry::interface::JobRequestParams"
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
        "name": "get_fact_registry_address",
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
        "name": "get_auction_run_time",
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
        "name": "get_option_run_time",
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
        "name": "get_round_transition_period",
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
            "type": "core::integer::u256"
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
            "type": "core::integer::u256"
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
            "type": "core::integer::u16"
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
            "type": "core::integer::u16"
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
            "type": "core::integer::u16"
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
        "name": "refresh_round_pricing_data",
        "inputs": [
          {
            "name": "job_request",
            "type": "pitch_lake::fact_registry::interface::JobRequest"
          }
        ],
        "outputs": [],
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
        "name": "settle_round",
        "inputs": [
          {
            "name": "job_request",
            "type": "pitch_lake::fact_registry::interface::JobRequest"
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
        "name": "round_transition_period",
        "type": "core::integer::u64"
      },
      {
        "name": "auction_run_time",
        "type": "core::integer::u64"
      },
      {
        "name": "option_run_time",
        "type": "core::integer::u64"
      },
      {
        "name": "eth_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "vault_type",
        "type": "pitch_lake::vault::interface::VaultType"
      },
      {
        "name": "fact_registry_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "option_round_class_hash",
        "type": "core::starknet::class_hash::ClassHash"
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
        "type": "core::integer::u16",
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
    "type": "event",
    "name": "pitch_lake::vault::contract::Vault::OptionRoundDeployed",
    "kind": "struct",
    "members": [
      {
        "name": "round_id",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      },
      {
        "name": "reserve_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "strike_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "cap_level",
        "type": "core::integer::u128",
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
      }
    ]
  }
] as const;
