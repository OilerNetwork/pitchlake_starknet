import { CairoUint256 } from "starknet";
export class OptionRoundFacade {
    optionRoundContract;
    constructor(optionRoundContract) {
        this.optionRoundContract = optionRoundContract;
    }
    async getTotalPremiums() {
        const res = await this.optionRoundContract.total_premiums();
        if (typeof res !== "bigint" && typeof res !== "number") {
            const data = new CairoUint256(res);
            return data.toBigInt();
        }
        else
            return res;
    }
    async getTotalOptionsAvailable() {
        const res = await this.optionRoundContract.get_total_options_available();
        if (typeof res !== "bigint" && typeof res !== "number") {
            const data = new CairoUint256(res);
            return data.toBigInt();
        }
        else
            return res;
    }
    async getReservePrice() {
        const res = await this.optionRoundContract.get_reserve_price();
        if (typeof res !== "bigint" && typeof res !== "number") {
            const data = new CairoUint256(res);
            return data.toBigInt();
        }
        else
            return res;
    }
    async getBidsFor(address) {
        const res = await this.optionRoundContract.get_bids_for(address);
        const bids = [];
        for (let data of res) {
            let amount;
            let price;
            if (typeof data.amount !== "bigint" && typeof data.amount !== "number") {
                const res = new CairoUint256(data.amount);
                amount = res.toBigInt();
            }
            else {
                amount = data.amount;
            }
            if (typeof data.price !== "bigint" && typeof data.price !== "number") {
                const res = new CairoUint256(data.price);
                price = res.toBigInt();
            }
            else {
                price = data.price;
            }
            const bid = {
                id: data.id,
                amount: amount,
                nonce: data.nonce,
                owner: data.owner,
                price: price,
                isTokenized: data.is_tokenized,
                isRefunded: data.is_refunded,
            };
            bids.push(bid);
        }
        return bids;
    }
    async getBidsForAll(accounts) {
        const bids = await Promise.all(accounts.map(async (account) => {
            const bidData = await this.getBidsFor(account.address);
            return bidData;
        }));
        return bids;
    }
    async updateBid({ bidId, from, amount, price }) {
        this.optionRoundContract.connect(from);
        try {
            await this.optionRoundContract.update_bid(bidId, amount, price);
        }
        catch (err) {
            console.log(err);
        }
    }
    async placeBid({ from, amount, price }) {
        this.optionRoundContract.connect(from);
        try {
            const data = await this.optionRoundContract.place_bid(amount, price);
        }
        catch (err) {
            console.log(err);
        }
    }
    async placeBidsAll(placeBidData) {
        for (const placeBidArgs of placeBidData) {
            await this.placeBid(placeBidArgs);
        }
    }
}
