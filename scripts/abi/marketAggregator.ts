export const ABI = [
  {
    "type": "impl",
    "name": "MarketAggregatorImpl",
    "interface_name": "pitch_lake_starknet::market_aggregator::interface::IMarketAggregator"
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
    "type": "enum",
    "name": "core::option::Option::<core::integer::u256>",
    "variants": [
      {
        "name": "Some",
        "type": "core::integer::u256"
      },
      {
        "name": "None",
        "type": "()"
      }
    ]
  },
  {
    "type": "enum",
    "name": "core::option::Option::<core::integer::u128>",
    "variants": [
      {
        "name": "Some",
        "type": "core::integer::u128"
      },
      {
        "name": "None",
        "type": "()"
      }
    ]
  },
  {
    "type": "interface",
    "name": "pitch_lake_starknet::market_aggregator::interface::IMarketAggregator",
    "items": [
      {
        "type": "function",
        "name": "get_reserve_price_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_reserve_price_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_cap_level_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u128>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_cap_level_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u128>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_strike_price_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_strike_price_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_TWAP_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_TWAP_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u256>"
          }
        ],
        "state_mutability": "view"
      }
    ]
  },
  {
    "type": "impl",
    "name": "MarketAggregatorMock",
    "interface_name": "pitch_lake_starknet::market_aggregator::interface::IMarketAggregatorMock"
  },
  {
    "type": "interface",
    "name": "pitch_lake_starknet::market_aggregator::interface::IMarketAggregatorMock",
    "items": [
      {
        "type": "function",
        "name": "set_reserve_price_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "reserve_price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_reserve_price_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "reserve_price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_cap_level_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "cap_level",
            "type": "core::integer::u128"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_cap_level_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "cap_level",
            "type": "core::integer::u128"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_strike_price_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "strike_price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_strike_price_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "strike_price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_TWAP_for_block_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "TWAP",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "set_TWAP_for_time_period",
        "inputs": [
          {
            "name": "from",
            "type": "core::integer::u64"
          },
          {
            "name": "to",
            "type": "core::integer::u64"
          },
          {
            "name": "TWAP",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      }
    ]
  },
  {
    "type": "constructor",
    "name": "constructor",
    "inputs": []
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::market_aggregator::contract::MarketAggregator::Event",
    "kind": "enum",
    "variants": []
  }
] as const;
