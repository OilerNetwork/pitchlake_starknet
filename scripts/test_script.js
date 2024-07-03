const starknet = require("starknet");
const sierra = require("../target/dev/pitch_lake_starknet_Eth.contract_class.json");

async function main(port) {
  const provider = new starknet.RpcProvider({
    nodeUrl: `http://localhost:${port}`,
  });
  const account = new starknet.Account(
    provider,
    "0x4d75495e10ee26cae76478b6e491646ff0a10e0a062db1555131e47b07b7d24",
    "0x100801800000000310080180000000010030000000000005106801800206800",
    "1"
  );
  console.log("port here is: ", port);

  let constructorArgs = [
    1,
    0,
    "0x00c1cf1490de1352865301bb8705143f3ef938f97fdf892f1090dcb5ac7bcd1d",
  ];
  //   if (process.argv.length > 3) {
  //     constructorArgs = process.argv.slice(3);
  //   }

  const deployResult = await account.deploy({
    classHash: starknet.hash.computeContractClassHash(sierra),
    constructorCalldata: constructorArgs,
  });

  console.log("This is the deploy result - ", deployResult);
}

main(process.argv[2]);
