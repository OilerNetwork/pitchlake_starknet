import { CairoUint256 } from "starknet";
import { accelerateToAuctioning, accelerateToRunning, } from "../helpers/accelerators";
export class VaultFacade {
    vaultContract;
    constructor(vaultContract) {
        this.vaultContract = vaultContract;
    }
    async endAuction(account) {
        this.vaultContract.connect(account);
        const res = await this.vaultContract.end_auction();
    }
    async endAuctionBystander(provider) {
        await accelerateToRunning(provider, this.vaultContract);
    }
    async getTotalLocked() {
        const res = await this.vaultContract.get_total_locked_balance();
        return res;
    }
    async getTotalUnLocked() {
        const res = await this.vaultContract.get_total_unlocked_balance();
        return res;
    }
    async getLPLockedBalance(address) {
        const res = await this.vaultContract.get_lp_locked_balance(address);
        if (typeof res !== "bigint" && typeof res !== "number") {
            const data = new CairoUint256(res);
            return data.toBigInt();
        }
        return res;
    }
    async getLPLockedBalanceAll(accounts) {
        const balances = await Promise.all(accounts.map(async (account) => {
            const res = await this.getLPLockedBalance(account.address);
            return res;
        }));
        return balances;
    }
    async getLPUnlockedBalance(address) {
        const res = await this.vaultContract.get_lp_unlocked_balance(address);
        if (typeof res !== "bigint" && typeof res !== "number") {
            const data = new CairoUint256(res);
            return data.toBigInt();
        }
        return res;
    }
    async getLPUnlockedBalanceAll(accounts) {
        const balances = await Promise.all(accounts.map(async (account) => {
            const res = await this.getLPUnlockedBalance(account.address);
            return res;
        }));
        return balances;
    }
    async withdraw({ account, amount }) {
        this.vaultContract.connect(account);
        try {
            await this.vaultContract.withdraw_liquidity(amount);
        }
        catch (err) {
            console.log(err);
        }
    }
    async deposit({ from, beneficiary, amount }) {
        this.vaultContract.connect(from);
        try {
            await this.vaultContract.deposit_liquidity(amount, beneficiary);
        }
        catch (err) {
            console.log(err);
        }
    }
    async depositAll(depositData) {
        for (const depositArgs of depositData) {
            await this.deposit(depositArgs);
        }
    }
    async withdrawAll(withdrawData) {
        for (const withdrawArgs of withdrawData) {
            await this.withdraw(withdrawArgs);
        }
    }
    //State Transitions
    async startAuction(account) {
        this.vaultContract.connect(account);
        await this.vaultContract.start_auction();
    }
    //@note Only works for katana dev instance with a --dev flag
    async startAuctionBystander(provider) {
        await accelerateToAuctioning(provider, this.vaultContract);
    }
}
