export const ABI = [
  {
    "type": "impl",
    "name": "FossilClientImpl",
    "interface_name": "pitch_lake::fossil_client::interface::IFossilClient"
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
    "type": "interface",
    "name": "pitch_lake::fossil_client::interface::IFossilClient",
    "items": [
      {
        "type": "function",
        "name": "fossil_callback",
        "inputs": [
          {
            "name": "request",
            "type": "core::array::Span::<core::felt252>"
          },
          {
            "name": "result",
            "type": "core::array::Span::<core::felt252>"
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
    "inputs": [
      {
        "name": "fossil_processor",
        "type": "core::starknet::contract_address::ContractAddress"
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
    "type": "event",
    "name": "pitch_lake::fossil_client::contract::FossilClient::FossilCallbackSuccess",
    "kind": "struct",
    "members": [
      {
        "name": "vault_address",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "data"
      },
      {
        "name": "l1_data",
        "type": "pitch_lake::fossil_client::interface::L1Data",
        "kind": "data"
      },
      {
        "name": "timestamp",
        "type": "core::integer::u64",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake::fossil_client::contract::FossilClient::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "FossilCallbackSuccess",
        "type": "pitch_lake::fossil_client::contract::FossilClient::FossilCallbackSuccess",
        "kind": "nested"
      }
    ]
  }
] as const;
