# Oiler PitchLake

[![Tests](https://github.com/OilerNetwork/pitchlake_starknet/actions/workflows/test.yaml/badge.svg)](https://github.com/OilerNetwork/pitchlake_starknet/actions/workflows/test.yaml)

[![Telegram Chat][tg-badge]][tg-url]

[tg-badge]: https://img.shields.io/endpoint?color=neon&logo=telegram&label=chat&style=flat-square&url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Foiler_official
[tg-url]: https://t.me/oiler_official

## Running Tests

The original codebase uses [Scarb](https://docs.swmansion.com/scarb/) (0.7.0) to build and test the contracts. Be sure to setup [asdf](https://asdf-vm.com/) as well, to handle versioning. The codebase will upgrade to the latest version of Scarb as the interface is stripped/updated.

To ensure you are setup, run the following command from the root of this directory and check the output matches:

```
➜ scarb --version
scarb 0.7.0 (58cc88efb 2023-08-23)
cairo: 2.2.0 (https://crates.io/crates/cairo-lang-compiler/2.2.0)
sierra: 1.3.0
```

Once Scarb is setup, you can run the full test suite via:

```
scarb test
```

To run specific tests, use the -f (filter) flag, followed by the string to match for. You can supply the file name, or specifc test names. The following command will run all the tests in the `vault_option_round_tests.cairo` file.

```
scarb test -f vault_option_round_tests
```

This command will run all tests that containing `auction` in their name:

```
scarb test -f auction
```

## Crash Course

The crash course is intended to catch devs up to speed on the technical aspects of the protocol, as well as help pre-prompt/train any LLMs for Pitchlake. This crash course can be found [here](./DOCUMENTATION.md).
