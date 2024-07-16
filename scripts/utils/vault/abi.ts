export const ABI = [
  {
    type: "impl",
    name: "VaultImpl",
    interface_name: "pitch_lake_starknet::contracts::vault::IVault",
  },
  {
    type: "enum",
    name: "pitch_lake_starknet::contracts::vault::Vault::VaultType",
    variants: [
      { name: "InTheMoney", type: "()" },
      { name: "AtTheMoney", type: "()" },
      { name: "OutOfMoney", type: "()" },
    ],
  },
  {
    type: "struct",
    name: "core::integer::u256",
    members: [
      { name: "low", type: "core::integer::u128" },
      { name: "high", type: "core::integer::u128" },
    ],
  },
  {
    type: "enum",
    name: "pitch_lake_starknet::contracts::option_round::OptionRound::OptionRoundError",
    variants: [
      { name: "AuctionAlreadyStarted", type: "()" },
      { name: "AuctionStartDateNotReached", type: "()" },
      { name: "AuctionAlreadyEnded", type: "()" },
      { name: "AuctionEndDateNotReached", type: "()" },
      { name: "OptionRoundAlreadySettled", type: "()" },
      { name: "OptionSettlementDateNotReached", type: "()" },
      { name: "BidBelowReservePrice", type: "()" },
      { name: "BidCannotBeDecreased", type: "core::felt252" },
    ],
  },
  {
    type: "enum",
    name: "pitch_lake_starknet::contracts::vault::Vault::VaultError",
    variants: [
      {
        name: "OptionRoundError",
        type: "pitch_lake_starknet::contracts::option_round::OptionRound::OptionRoundError",
      },
      { name: "InsufficientBalance", type: "()" },
    ],
  },
  {
    type: "enum",
    name: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
    variants: [
      { name: "Ok", type: "core::integer::u256" },
      {
        name: "Err",
        type: "pitch_lake_starknet::contracts::vault::Vault::VaultError",
      },
    ],
  },
  {
    type: "enum",
    name: "core::result::Result::<(core::integer::u256, core::integer::u256), pitch_lake_starknet::contracts::vault::Vault::VaultError>",
    variants: [
      { name: "Ok", type: "(core::integer::u256, core::integer::u256)" },
      {
        name: "Err",
        type: "pitch_lake_starknet::contracts::vault::Vault::VaultError",
      },
    ],
  },
  {
    type: "interface",
    name: "pitch_lake_starknet::contracts::vault::IVault",
    items: [
      {
        type: "function",
        name: "rm_me2",
        inputs: [],
        outputs: [],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "vault_manager",
        inputs: [],
        outputs: [
          { type: "core::starknet::contract_address::ContractAddress" },
        ],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "vault_type",
        inputs: [],
        outputs: [
          { type: "pitch_lake_starknet::contracts::vault::Vault::VaultType" },
        ],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_market_aggregator",
        inputs: [],
        outputs: [
          { type: "core::starknet::contract_address::ContractAddress" },
        ],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "current_option_round_id",
        inputs: [],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_option_round_address",
        inputs: [{ name: "option_round_id", type: "core::integer::u256" }],
        outputs: [
          { type: "core::starknet::contract_address::ContractAddress" },
        ],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_lp_locked_balance",
        inputs: [
          {
            name: "liquidity_provider",
            type: "core::starknet::contract_address::ContractAddress",
          },
        ],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_lp_unlocked_balance",
        inputs: [
          {
            name: "liquidity_provider",
            type: "core::starknet::contract_address::ContractAddress",
          },
        ],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_lp_total_balance",
        inputs: [
          {
            name: "liquidity_provider",
            type: "core::starknet::contract_address::ContractAddress",
          },
        ],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_total_locked",
        inputs: [],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_total_unlocked",
        inputs: [],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_total_balance",
        inputs: [],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_premiums_earned",
        inputs: [
          {
            name: "liquidity_provider",
            type: "core::starknet::contract_address::ContractAddress",
          },
          { name: "round_id", type: "core::integer::u256" },
        ],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "get_premiums_collected",
        inputs: [
          {
            name: "liquidity_provider",
            type: "core::starknet::contract_address::ContractAddress",
          },
          { name: "round_id", type: "core::integer::u256" },
        ],
        outputs: [{ type: "core::integer::u256" }],
        state_mutability: "view",
      },
      {
        type: "function",
        name: "start_auction",
        inputs: [],
        outputs: [
          {
            type: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "end_auction",
        inputs: [],
        outputs: [
          {
            type: "core::result::Result::<(core::integer::u256, core::integer::u256), pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "settle_option_round",
        inputs: [],
        outputs: [
          {
            type: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "deposit_liquidity",
        inputs: [{ name: "amount", type: "core::integer::u256" }],
        outputs: [
          {
            type: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "withdraw_liquidity",
        inputs: [{ name: "amount", type: "core::integer::u256" }],
        outputs: [
          {
            type: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "convert_position_to_lp_tokens",
        inputs: [{ name: "amount", type: "core::integer::u256" }],
        outputs: [],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "convert_lp_tokens_to_position",
        inputs: [
          { name: "source_round", type: "core::integer::u256" },
          { name: "amount", type: "core::integer::u256" },
        ],
        outputs: [],
        state_mutability: "external",
      },
      {
        type: "function",
        name: "convert_lp_tokens_to_newer_lp_tokens",
        inputs: [
          { name: "source_round", type: "core::integer::u256" },
          { name: "target_round", type: "core::integer::u256" },
          { name: "amount", type: "core::integer::u256" },
        ],
        outputs: [
          {
            type: "core::result::Result::<core::integer::u256, pitch_lake_starknet::contracts::vault::Vault::VaultError>",
          },
        ],
        state_mutability: "external",
      },
    ],
  },
  {
    type: "constructor",
    name: "constructor",
    inputs: [
      {
        name: "vault_manager",
        type: "core::starknet::contract_address::ContractAddress",
      },
      {
        name: "vault_type",
        type: "pitch_lake_starknet::contracts::vault::Vault::VaultType",
      },
      {
        name: "market_aggregator",
        type: "core::starknet::contract_address::ContractAddress",
      },
      {
        name: "option_round_class_hash",
        type: "core::starknet::class_hash::ClassHash",
      },
    ],
  },
  {
    type: "event",
    name: "pitch_lake_starknet::contracts::vault::Vault::Deposit",
    kind: "struct",
    members: [
      {
        name: "account",
        type: "core::starknet::contract_address::ContractAddress",
        kind: "key",
      },
      {
        name: "position_balance_before",
        type: "core::integer::u256",
        kind: "data",
      },
      {
        name: "position_balance_after",
        type: "core::integer::u256",
        kind: "data",
      },
    ],
  },
  {
    type: "event",
    name: "pitch_lake_starknet::contracts::vault::Vault::Withdrawal",
    kind: "struct",
    members: [
      {
        name: "account",
        type: "core::starknet::contract_address::ContractAddress",
        kind: "key",
      },
      {
        name: "position_balance_before",
        type: "core::integer::u256",
        kind: "data",
      },
      {
        name: "position_balance_after",
        type: "core::integer::u256",
        kind: "data",
      },
    ],
  },
  {
    type: "event",
    name: "pitch_lake_starknet::contracts::vault::Vault::OptionRoundDeployed",
    kind: "struct",
    members: [
      { name: "round_id", type: "core::integer::u256", kind: "data" },
      {
        name: "address",
        type: "core::starknet::contract_address::ContractAddress",
        kind: "data",
      },
    ],
  },
  {
    type: "event",
    name: "pitch_lake_starknet::contracts::vault::Vault::Event",
    kind: "enum",
    variants: [
      {
        name: "Deposit",
        type: "pitch_lake_starknet::contracts::vault::Vault::Deposit",
        kind: "nested",
      },
      {
        name: "Withdrawal",
        type: "pitch_lake_starknet::contracts::vault::Vault::Withdrawal",
        kind: "nested",
      },
      {
        name: "OptionRoundDeployed",
        type: "pitch_lake_starknet::contracts::vault::Vault::OptionRoundDeployed",
        kind: "nested",
      },
    ],
  },
] as const;
