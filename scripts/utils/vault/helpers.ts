import { Contract } from "starknet";

const loopDepositWithdraw = (
  addresses: Array<string>,
  amounts: Array<number>,
  operation: (address: string, value: number) => {}
) => {
  addresses.forEach((address: string, index: number) => {
    operation(address, amounts[index]);
  });
};


const createVaultContract = ()=>{
    
}