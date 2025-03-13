import { CairoUint256 } from "starknet";
import { convertToBigInt } from "../helpers/common";
export class OptionRoundFacade {
    optionRoundContract;
    constructor(optionRoundContract) {
        this.optionRoundContract = optionRoundContract;
    }
    async createJobRequest() {
        const state = await this.optionRoundContract.get_state();
        const upperBound = state && Object.keys(state)[0] === "Open"
            ? Number(await this.optionRoundContract.get_auction_start_date())
            : Number(await this.optionRoundContract.get_option_settlement_date());
        const DAY = 24 * 3600;
        const job_request = {
            identifiers: ["PITCH_LAKE_V1"],
            params: {
                twap: [upperBound - 30 * DAY, upperBound],
                max_returns: [upperBound - 90 * DAY, upperBound],
                reserve_price: [upperBound - 90 * DAY, upperBound],
            },
        };
        return job_request;
        //
    }
    async getStartingLiquidity() {
        const res = await this.optionRoundContract.get_starting_liquidity();
        return convertToBigInt(res);
    }
    async getRoundId() {
        const res = await this.optionRoundContract.get_round_id();
        return convertToBigInt(res);
    }
    async getTotalPayout() {
        const res = await this.optionRoundContract.get_total_payout();
        return convertToBigInt(res);
    }
    async getTotalPremiums() {
        const res = await this.optionRoundContract.get_total_premium();
        return convertToBigInt(res);
    }
    async getTotalOptionsAvailable() {
        const res = await this.optionRoundContract.get_options_available();
        return convertToBigInt(res);
    }
    async getReservePrice() {
        const res = await this.optionRoundContract.get_reserve_price();
        return convertToBigInt(res);
    }
    async getBidsFor(address) {
        const res = await this.optionRoundContract.get_account_bids(address);
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
                id: data.bid_id,
                amount: amount,
                nonce: data.tree_nonce,
                owner: data.owner,
                price: price,
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
            const error = err;
            console.log(error.name, from, amount, price, error.message, error.cause);
        }
    }
    async placeBidsAll(placeBidData) {
        for (const placeBidArgs of placeBidData) {
            await this.placeBid(placeBidArgs);
        }
    }
    async getRefundableBidsFor({ optionBuyer }) {
        try {
            const res = await this.optionRoundContract.get_refundable_bids_for(optionBuyer);
            return convertToBigInt(res);
        }
        catch (err) {
            console.log(err);
        }
    }
    async getTotalOptionsBalanceForAll(optionBuyers) {
        try {
            const optionsBalances = await Promise.all(optionBuyers.map(async (account) => {
                const balance = await this.getTotalOptionsBalanceFor(account.address);
                return balance;
            }));
            return optionsBalances;
        }
        catch (err) {
            console.log(err);
        }
    }
    async getTotalOptionsBalanceFor(optionBuyer) {
        try {
            const res = await this.optionRoundContract.get_account_total_options(optionBuyer);
            return convertToBigInt(res);
        }
        catch (err) {
            console.log(err);
        }
    }
    async getPayoutBalanceFor({ optionBuyer }) {
        try {
            const res = await this.optionRoundContract.get_payout_balance_for(optionBuyer);
            return convertToBigInt(res);
        }
        catch (err) {
            console.log(err);
        }
    }
    async getTokenizableOptionsFor({ optionBuyer }) {
        try {
            const res = await this.optionRoundContract.get_tokenizable_options_for(optionBuyer);
            return convertToBigInt(res);
        }
        catch (err) {
            console.log(err);
        }
    }
    async refundUnusedBids({ from, optionBidder }) {
        this.optionRoundContract.connect(from);
        const data = await this.optionRoundContract.refund_unused_bids(optionBidder);
        console.log("refund unused bids inside -> ", data);
        // @note: here it will return the total refundable_balance
        // if (typeof res !== "bigint" && typeof res !== "number") {
        //   const data = new CairoUint256(res);
        //   return data.toBigInt();
        // } else return res;s
    }
    async refundUnusedBidsAll(refundUnusedBidsAllArgs) {
        for (const refundArgs of refundUnusedBidsAllArgs) {
            await this.refundUnusedBids(refundArgs);
        }
    }
    async exerciseOptions({ from }) {
        this.optionRoundContract.connect(from);
        const data = await this.optionRoundContract.exercise_options();
        // @note: here it will return the amount of transfer
        // if (typeof res !== "bigint" && typeof res !== "number") {
        //   const data = new CairoUint256(res);
        //   return data.toBigInt();
        // } else return res;
    }
    async exerciseOptionsAll(exerciseOptionData) {
        for (const exerciseOptionsArgs of exerciseOptionData) {
            await this.exerciseOptions(exerciseOptionsArgs);
        }
    }
    async tokenizeOptions({ from }) {
        try {
            this.optionRoundContract.connect(from);
            const data = await this.optionRoundContract.mint_options();
            // @note: here it will return the total number of tokenizable options
            // if (typeof res !== "bigint" && typeof res !== "number") {
            //   const data = new CairoUint256(res);
            //   return data.toBigInt();
            // } else return res;
        }
        catch (err) {
            console.log(err);
        }
    }
}
