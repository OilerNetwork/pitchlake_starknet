export const setNextBlock = async (increase, url) => {
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
export const mineNextBlock = async (url) => {
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
export const timeskipNextBlock = async (increaseTime, url) => {
    await mineNextBlock(url);
    if (increaseTime > 0)
        await setNextBlock(increaseTime, url);
    await mineNextBlock(url);
};
export const getNow = async (provider) => {
    const data = await provider.getBlock();
    return data.timestamp;
};
