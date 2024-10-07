import { CairoUint256, Contract, } from "starknet";
import { erc20ABI } from "../../abi";
import { getCustomAccount } from "../helpers/common";
import { liquidityProviders, optionBidders } from "../constants";
export class ERC20Facade {
    erc20Contract;
    constructor(ercAddress, provider) {
        this.erc20Contract = new Contract(erc20ABI, ercAddress, provider).typedv2(erc20ABI);
    }
    async getBalance(account) {
        const balance = await this.erc20Contract.balance_of(account);
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
            this.erc20Contract.connect(devAccount);
            await this.erc20Contract.transfer(recipient, amount);
            // @note: don't delete it yet, waiting for response from starknet.js team
            // const result = await account.execute({
            //   contractAddress: ercContract,
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
        this.erc20Contract.connect(owner);
        try {
            await this.erc20Contract.approve(spender, amount);
        }
        catch (err) {
            console.log(err);
        }
    }
    async supplyERC20(devAccount, provider, erc20Address, approveFor) {
        const erc20Contract = new Contract(erc20ABI, erc20Address, provider).typedv2(erc20ABI);
        await this.supply(devAccount, "0x06Fb643e5c834feA33EACeFc10A2F856E1C317E700523c8eA45681F52D2B1D60", BigInt(10000000000));
        for (let i = 0; i < 6; i++) {
            const lp = getCustomAccount(provider, liquidityProviders[i].account, liquidityProviders[i].privateKey);
            const ob = getCustomAccount(provider, optionBidders[i].account, optionBidders[i].privateKey);
            await this.supply(devAccount, liquidityProviders[i].account, BigInt("1000000000000000000"));
            await this.approval({
                owner: lp,
                amount: BigInt("1000000000000000000"),
                spender: approveFor,
            });
            console.log(`Liquidity Provider ${i} funded `);
            await this.supply(devAccount, optionBidders[i].account, BigInt("1000000000000000000"));
            await this.approval({
                owner: ob,
                amount: BigInt("1000000000000000000"),
                spender: approveFor,
            });
            console.log(`Option Bidder ${i} funded `);
        }
    }
}
