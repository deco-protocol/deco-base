import { ContractTransaction as ContractTransactionType, BigNumber } from "ethers";
import { Signer } from "@ethersproject/abstract-signer";

export type Account = {
  address: Address;
  signer: Signer;
};

export type Address = string;
export type Bytes = string;

export type ContractTransaction = ContractTransactionType;
