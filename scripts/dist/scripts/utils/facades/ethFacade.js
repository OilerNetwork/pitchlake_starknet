import { CairoUint256, Contract, } from "starknet";
import { ethAbi } from "../../abi";
import { getCustomAccount } from "../helpers/common";
import { liquidityProviders, optionBidders } from "../constants";
export class EthFacade {
    ethContract;
    constructor(ethContract) {
        this.ethContract = ethContract;
    }
    async getBalancesAll(accounts) {
        const balances = await Promise.all(accounts.map(async (account) => {
            const balance = await this.getBalance(account.address);
            return balance;
        }));
        return balances;
    }
    async getBalance(account) {
        const balance = await this.ethContract.balance_of(account);
        //Parse U256 to CairoUint256 to BigInt
        if (typeof balance !== "bigint" && typeof balance !== "number") {
            const data = new CairoUint256(balance);
            return data.toBigInt();
        }
        else
            return balance;
    }
    async supply(devAccount, recipient, amount) {
        try {
            this.ethContract.connect(devAccount);
            await this.ethContract.transfer(recipient, amount);
            // @note: don't delete it yet, waiting for response from starknet.js team
            // const result = await account.execute({
            //   contractAddress: ethContract,
            //   entrypoint: "transfer",
            //   calldata: CallData.compile({
            //     recipient: liquidityProviders[0].account,
            //     amount: cairo.uint256(10000),
            //   }),
            // });
            // const result2 = await provider.waitForTransaction(result.transaction_hash);
            // console.log(result, result2);
        }
        catch (err) {
            console.log(err);
        }
    }
    async approval({ owner, amount, spender }) {
        this.ethContract.connect(owner);
        try {
            this.ethContract.approve(spender, amount);
        }
        catch (err) {
            console.log(err);
        }
    }
    async approveAll(approveData) {
        for (const approvalArgs of approveData) {
            await this.approval(approvalArgs);
        }
    }
    async supplyEth(devAccount, provider, ethAddress, approveFor) {
        const ethContract = new Contract(ethAbi, ethAddress, provider).typedv2(ethAbi);
        for (let i = 0; i < 6; i++) {
            const lp = getCustomAccount(provider, liquidityProviders[i].account, liquidityProviders[i].privateKey);
            const ob = getCustomAccount(provider, optionBidders[i].account, optionBidders[i].privateKey);
            await this.supply(devAccount, liquidityProviders[i].account, BigInt("1000000000000000"));
            await this.approval({
                owner: lp,
                amount: BigInt("1000000000000000"),
                spender: approveFor,
            });
            console.log(`Liquidity Provider ${i} funded `);
            await this.supply(devAccount, optionBidders[i].account, BigInt("1000000000000000"));
            await this.approval({
                owner: ob,
                amount: BigInt("1000000000000000"),
                spender: approveFor,
            });
            console.log(`Option Bidder ${i} funded `);
        }
    }
}
