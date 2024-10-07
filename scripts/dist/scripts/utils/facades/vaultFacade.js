import { Contract } from "starknet";
import { optionRoundABI, vaultABI } from "../../abi";
import { convertToBigInt } from "../helpers/common";
export class VaultFacade {
    vaultContract;
    currentOptionRound;
    constructor(vaultAddress, provider, optionRoundAddress) {
        this.vaultContract = new Contract(vaultABI, vaultAddress, provider).typedv2(vaultABI);
        if (optionRoundAddress)
            this.currentOptionRound = new Contract(optionRoundABI, optionRoundAddress, provider).typedv2(optionRoundABI);
    }
    async getTotalLocked() {
        const res = await this.vaultContract.get_vault_locked_balance();
        return convertToBigInt(res);
    }
    async getTotalUnLocked() {
        const res = await this.vaultContract.get_vault_unlocked_balance();
        return convertToBigInt(res);
    }
    async getLPLockedBalance(address) {
        const res = await this.vaultContract.get_account_locked_balance(address);
        return convertToBigInt(res);
    }
    async getLPUnlockedBalance(address) {
        const res = await this.vaultContract.get_account_unlocked_balance(address);
        return convertToBigInt(res);
    }
    async withdraw({ account, amount }) {
        this.vaultContract.connect(account);
        await this.vaultContract.withdraw(amount);
    }
    async deposit({ from, beneficiary, amount }) {
        this.vaultContract.connect(from);
        try {
            const data = await this.vaultContract.deposit(amount, beneficiary);
            data;
        }
        catch (err) {
            console.log(err);
        }
    }
    //State Transitions
    async startAuction(account) {
        this.vaultContract.connect(account);
        await this.vaultContract.start_auction();
    }
    async endAuction(account) {
        this.vaultContract.connect(account);
        await this.vaultContract.end_auction();
    }
    async settleOptionRound(account, job_request) {
        this.vaultContract.connect(account);
        await this.vaultContract.settle_round(job_request);
    }
}
