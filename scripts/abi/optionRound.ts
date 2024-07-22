export const ABI = [
  {
    "type": "impl",
    "name": "ERC20MetadataImpl",
    "interface_name": "openzeppelin::token::erc20::interface::IERC20Metadata"
  },
  {
    "type": "struct",
    "name": "core::byte_array::ByteArray",
    "members": [
      {
        "name": "data",
        "type": "core::array::Array::<core::bytes_31::bytes31>"
      },
      {
        "name": "pending_word",
        "type": "core::felt252"
      },
      {
        "name": "pending_word_len",
        "type": "core::integer::u32"
      }
    ]
  },
  {
    "type": "interface",
    "name": "openzeppelin::token::erc20::interface::IERC20Metadata",
    "items": [
      {
        "type": "function",
        "name": "name",
        "inputs": [],
        "outputs": [
          {
            "type": "core::byte_array::ByteArray"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "symbol",
        "inputs": [],
        "outputs": [
          {
            "type": "core::byte_array::ByteArray"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "decimals",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u8"
          }
        ],
        "state_mutability": "view"
      }
    ]
  },
  {
    "type": "impl",
    "name": "OptionRoundImpl",
    "interface_name": "pitch_lake_starknet::option_round::interface::IOptionRound"
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
    "name": "core::bool",
    "variants": [
      {
        "name": "False",
        "type": "()"
      },
      {
        "name": "True",
        "type": "()"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake_starknet::types::Bid",
    "members": [
      {
        "name": "id",
        "type": "core::felt252"
      },
      {
        "name": "nonce",
        "type": "core::integer::u64"
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
        "name": "is_tokenized",
        "type": "core::bool"
      },
      {
        "name": "is_refunded",
        "type": "core::bool"
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake_starknet::types::OptionRoundConstructorParams",
    "members": [
      {
        "name": "vault_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "round_id",
        "type": "core::integer::u256"
      }
    ]
  },
  {
    "type": "enum",
    "name": "pitch_lake_starknet::types::OptionRoundState",
    "variants": [
      {
        "name": "Open",
        "type": "()"
      },
      {
        "name": "Auctioning",
        "type": "()"
      },
      {
        "name": "Running",
        "type": "()"
      },
      {
        "name": "Settled",
        "type": "()"
      }
    ]
  },
  {
    "type": "interface",
    "name": "pitch_lake_starknet::option_round::interface::IOptionRound",
    "items": [
      {
        "type": "function",
        "name": "get_auction_start_date",
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
        "name": "get_auction_end_date",
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
        "name": "get_option_settlement_date",
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
        "name": "starting_liquidity",
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
        "name": "total_premiums",
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
        "name": "total_payout",
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
        "name": "get_auction_clearing_price",
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
        "name": "total_options_sold",
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
        "name": "get_bid_details",
        "inputs": [
          {
            "name": "bid_id",
            "type": "core::felt252"
          }
        ],
        "outputs": [
          {
            "type": "pitch_lake_starknet::types::Bid"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_bidding_nonce_for",
        "inputs": [
          {
            "name": "option_buyer",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u32"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_bids_for",
        "inputs": [
          {
            "name": "option_buyer",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::array::Array::<pitch_lake_starknet::types::Bid>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_refundable_bids_for",
        "inputs": [
          {
            "name": "option_buyer",
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
        "name": "get_total_options_balance_for",
        "inputs": [
          {
            "name": "option_buyer",
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
        "name": "get_payout_balance_for",
        "inputs": [
          {
            "name": "option_buyer",
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
        "name": "get_tokenizable_options_for",
        "inputs": [
          {
            "name": "option_buyer",
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
        "name": "vault_address",
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
        "name": "get_constructor_params",
        "inputs": [],
        "outputs": [
          {
            "type": "pitch_lake_starknet::types::OptionRoundConstructorParams"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_state",
        "inputs": [],
        "outputs": [
          {
            "type": "pitch_lake_starknet::types::OptionRoundState"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_strike_price",
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
        "name": "get_cap_level",
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
        "name": "get_reserve_price",
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
        "name": "get_total_options_available",
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
        "name": "get_round_id",
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
        "name": "update_round_params",
        "inputs": [
          {
            "name": "reserve_price",
            "type": "core::integer::u256"
          },
          {
            "name": "cap_level",
            "type": "core::integer::u128"
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
        "name": "start_auction",
        "inputs": [
          {
            "name": "starting_liquidity",
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
        "name": "settle_option_round",
        "inputs": [
          {
            "name": "settlement_price",
            "type": "core::integer::u256"
          }
        ],
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
            "type": "pitch_lake_starknet::types::Bid"
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
            "name": "new_amount",
            "type": "core::integer::u256"
          },
          {
            "name": "new_price",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "pitch_lake_starknet::types::Bid"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "refund_unused_bids",
        "inputs": [
          {
            "name": "option_bidder",
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
        "name": "tokenize_options",
        "inputs": [],
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
    "type": "impl",
    "name": "ERC20Impl",
    "interface_name": "openzeppelin::token::erc20::interface::IERC20"
  },
  {
    "type": "interface",
    "name": "openzeppelin::token::erc20::interface::IERC20",
    "items": [
      {
        "type": "function",
        "name": "total_supply",
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
        "name": "balance_of",
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
        "name": "allowance",
        "inputs": [
          {
            "name": "owner",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "spender",
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
        "name": "transfer",
        "inputs": [
          {
            "name": "recipient",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "amount",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "transfer_from",
        "inputs": [
          {
            "name": "sender",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "recipient",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "amount",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "approve",
        "inputs": [
          {
            "name": "spender",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "amount",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "external"
      }
    ]
  },
  {
    "type": "impl",
    "name": "ERC20CamelOnlyImpl",
    "interface_name": "openzeppelin::token::erc20::interface::IERC20CamelOnly"
  },
  {
    "type": "interface",
    "name": "openzeppelin::token::erc20::interface::IERC20CamelOnly",
    "items": [
      {
        "type": "function",
        "name": "totalSupply",
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
        "name": "balanceOf",
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
        "name": "transferFrom",
        "inputs": [
          {
            "name": "sender",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "recipient",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "amount",
            "type": "core::integer::u256"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "external"
      }
    ]
  },
  {
    "type": "constructor",
    "name": "constructor",
    "inputs": [
      {
        "name": "vault_address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "round_id",
        "type": "core::integer::u256"
      },
      {
        "name": "auction_start_date",
        "type": "core::integer::u64"
      },
      {
        "name": "auction_end_date",
        "type": "core::integer::u64"
      },
      {
        "name": "option_settlement_date",
        "type": "core::integer::u64"
      },
      {
        "name": "reserve_price",
        "type": "core::integer::u256"
      },
      {
        "name": "cap_level",
        "type": "core::integer::u128"
      },
      {
        "name": "strike_price",
        "type": "core::integer::u256"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::AuctionStarted",
    "kind": "struct",
    "members": [
      {
        "name": "total_options_available",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::BidAccepted",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "nonce",
        "type": "core::integer::u32",
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
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::BidRejected",
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
        "name": "price",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::BidUpdated",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "id",
        "type": "core::felt252",
        "kind": "data"
      },
      {
        "name": "old_amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "old_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "new_amount",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "new_price",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::AuctionEnded",
    "kind": "struct",
    "members": [
      {
        "name": "clearing_price",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "total_options_sold",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::OptionRoundSettled",
    "kind": "struct",
    "members": [
      {
        "name": "total_payout",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "payout_per_option",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "settlement_price",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::OptionsExercised",
    "kind": "struct",
    "members": [
      {
        "name": "account",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "num_options",
        "type": "core::integer::u256",
        "kind": "data"
      },
      {
        "name": "amount",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::UnusedBidsRefunded",
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
      }
    ]
  },
  {
    "type": "struct",
    "name": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::Node",
    "members": [
      {
        "name": "value",
        "type": "pitch_lake_starknet::types::Bid"
      },
      {
        "name": "left",
        "type": "core::felt252"
      },
      {
        "name": "right",
        "type": "core::felt252"
      },
      {
        "name": "parent",
        "type": "core::felt252"
      },
      {
        "name": "color",
        "type": "core::bool"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::InsertEvent",
    "kind": "struct",
    "members": [
      {
        "name": "node",
        "type": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::Node",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "InsertEvent",
        "type": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::InsertEvent",
        "kind": "nested"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::OptionsTokenized",
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
      }
    ]
  },
  {
    "type": "event",
    "name": "openzeppelin::token::erc20::erc20::ERC20Component::Transfer",
    "kind": "struct",
    "members": [
      {
        "name": "from",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "to",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "value",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "openzeppelin::token::erc20::erc20::ERC20Component::Approval",
    "kind": "struct",
    "members": [
      {
        "name": "owner",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "spender",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "value",
        "type": "core::integer::u256",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "openzeppelin::token::erc20::erc20::ERC20Component::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "Transfer",
        "type": "openzeppelin::token::erc20::erc20::ERC20Component::Transfer",
        "kind": "nested"
      },
      {
        "name": "Approval",
        "type": "openzeppelin::token::erc20::erc20::ERC20Component::Approval",
        "kind": "nested"
      }
    ]
  },
  {
    "type": "event",
    "name": "pitch_lake_starknet::option_round::contract::OptionRound::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "AuctionStarted",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::AuctionStarted",
        "kind": "nested"
      },
      {
        "name": "BidAccepted",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::BidAccepted",
        "kind": "nested"
      },
      {
        "name": "BidRejected",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::BidRejected",
        "kind": "nested"
      },
      {
        "name": "BidUpdated",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::BidUpdated",
        "kind": "nested"
      },
      {
        "name": "AuctionEnded",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::AuctionEnded",
        "kind": "nested"
      },
      {
        "name": "OptionRoundSettled",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::OptionRoundSettled",
        "kind": "nested"
      },
      {
        "name": "OptionsExercised",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::OptionsExercised",
        "kind": "nested"
      },
      {
        "name": "UnusedBidsRefunded",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::UnusedBidsRefunded",
        "kind": "nested"
      },
      {
        "name": "BidTreeEvent",
        "type": "pitch_lake_starknet::library::red_black_tree::RBTreeComponent::Event",
        "kind": "flat"
      },
      {
        "name": "OptionsTokenized",
        "type": "pitch_lake_starknet::option_round::contract::OptionRound::OptionsTokenized",
        "kind": "nested"
      },
      {
        "name": "ERC20Event",
        "type": "openzeppelin::token::erc20::erc20::ERC20Component::Event",
        "kind": "flat"
      }
    ]
  }
] as const;
