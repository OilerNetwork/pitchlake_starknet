import { Provider } from "starknet";

export const setNextBlock = async (increase: number, url: string) => {
  const time = Date.now();
  const options = {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({
      id: 1,
      jsonrpc: "2.0",
      method: "dev_increaseNextBlockTimestamp",
      params: [increase],
    }),
  };

  await fetch(url, options)
    .then((response) => response.json())
    .then((response) => console.log(response))
    .catch((err) => console.error(err));
};
export const mineNextBlock = async (url: string) => {
  const options = {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({
      id: 1,
      jsonrpc: "2.0",
      method: "dev_generateBlock",
      params: [],
    }),
  };

  await fetch(url, options)
    .then((response) => response.json())
    .then((response) => console.log(response))
    .catch((err) => console.error(err));
};

export const setAndMineNextBlock = async (
  increaseTime: number,
  url: string
) => {
  if (increaseTime > 0) await setNextBlock(increaseTime, url);
  await mineNextBlock(url);
};

export const getNow = async (provider: Provider) => {
  const data = await provider.getBlock();
  return data.timestamp;
};
