# Pitchlake Simulator

## Install packages

To install the modules go to the scripts directory and run the following
```
yarn
#or
npm install
#or
pnpm install
```
The original codebase uses [Scarb](https://docs.swmansion.com/scarb/) (2.6.4) to build and test the contracts. Be sure to setup [asdf](https://asdf-vm.com/) as well, to handle versioning.

To ensure you are setup, run the following command from the root of this directory and check the output matches:

```
❯ scarb --version
scarb 2.6.4 (c4c7c0bac 2024-03-19)
cairo: 2.6.3 (https://crates.io/crates/cairo-lang-compiler/2.6.3)
sierra: 1.5.0
```

You also need to install dojo to spinup a local instance of starknet chain Katana. Read documentation [here](https://book.dojoengine.org/)

```
#Install dojo
curl -L https://install.dojoengine.org | bash
#or
asdf plugin add dojo https://github.com/dojoengine/asdf-dojo
asdf install dojo latest 
#Update dojo
dojoup
```

## Run simulation
To run the simulation you need to add the market data as marketData.json in scripts/simulationData directory. The simulation set's bidding price at reservePrice to run the rounds. To run the simulation execute the katana.sh bash script
```
bash katana.sh
```

