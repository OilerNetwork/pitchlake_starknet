export const ABI = [
  {
    "type": "impl",
    "name": "FactRegistryImpl",
    "interface_name": "pitch_lake::fact_registry::interface::IFactRegistry"
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
    "name": "pitch_lake::fact_registry::interface::IFactRegistry",
    "items": [
      {
        "type": "function",
        "name": "get_fact",
        "inputs": [
          {
            "name": "job_id",
            "type": "core::felt252"
          }
        ],
        "outputs": [
          {
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "set_fact",
        "inputs": [
          {
            "name": "job_request",
            "type": "pitch_lake::fact_registry::interface::JobRequest"
          },
          {
            "name": "job_data",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [
          {
            "type": "core::felt252"
          }
        ],
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
    "name": "pitch_lake::fact_registry::contract::FactRegistry::Event",
    "kind": "enum",
    "variants": []
  }
] as const;
