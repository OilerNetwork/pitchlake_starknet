# Contributing to Pitchlake

We want to make contributing to this project as easy and transparent as
possible.

## Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/) - v0.7.0
  ```
    ➜ scarb --version
    scarb 0.7.0 (58cc88efb 2023-08-23)
    cairo: 2.2.0 (https://crates.io/crates/cairo-lang-compiler/2.2.0)
    sierra: 1.3.0
  ```

- Read the [documentation](./documentation.md).

## Pull Requests

We actively welcome your pull requests.

If you're new, we encourage you to take a look at issues tagged with [good first issue](https://github.com/OilerNetwork/pitchlake_starknet/issues?q=is%3Aopen+label%3A%22good+first+issue%22+sort%3Aupdated-desc)

## Making your changes

Fork, then clone the repo:

```
git@github.com:OilerNetwork/pitchlake_starknet.git
```

Build the project:

```
scarb build
```

Change the code/docs with your contribution
Make your change. Add tests for your change. Make the tests pass:

```
scarb test
```

Push to your fork and [submit a pull request][pr].

[pr]: https://github.com/OilerNetwork/pitchlake_starknet

At this point you're waiting on us. Some things that will increase the chance that your pull request
is accepted:

* Write tests.
* Write a [good commit message][commit].

[commit]: http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html

## Issues

We use GitHub issues to track public bugs. Please ensure your description is
clear and has sufficient instructions to be able to reproduce the issue.

## License

By contributing to examples, you agree that your contributions will be licensed
under the LICENSE file in the root directory of this source tree.
