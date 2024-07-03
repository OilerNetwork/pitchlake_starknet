const starknet = require("starknet");

async function main(port) {
  const provider = new starknet.RpcProvider({
    nodeUrl: `http://localhost:${port}`,
  });
  const account = new starknet.Account(
    provider,
    "0x4",
    "0x00c1cf1490de1352865301bb8705143f3ef938f97fdf892f1090dcb5ac7bcd1d",
    "1"
  );
  console.log("port here is: ", port);

  //   const currentDir = process.cwd();
  //   const sierra = require(`${currentDir}/${sierraPath}`);

  //   let constructorArgs = [];
  //   if (process.argv.length > 3) {
  //     constructorArgs = process.argv.slice(3);
  //   }

  //   const deployResult = await account.deploy({
  //     classHash: starknet.hash.computeContractClassHash(sierra),
  //     constructorCalldata: constructorArgs,
  //   });

  //   console.log("This is the deploy result - ", deployResult);
}

main(process.argv[2]);
