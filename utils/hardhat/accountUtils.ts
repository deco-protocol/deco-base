import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { Account, Address } from "../types";

const provider = ethers.provider;

export const getAccounts = async (): Promise<Account[]> => {
  const accounts: Account[] = [];

  const signers = await ethers.getSigners();
  for (let i = 0; i < signers.length; i++) {
    accounts.push({
      signer: signers[i],
      address: await signers[i].getAddress(),
    });
  }

  return accounts;
};

// Use the last wallet to ensure it has Ether
export const getRandomAccount = async (): Promise<Account> => {
  const accounts = await getAccounts();
  return accounts[accounts.length - 1];
};

export const getRandomAddress = async (): Promise<Address> => {
  const wallet = ethers.Wallet.createRandom().connect(provider);
  return await wallet.getAddress();
};

export const getEthBalance = async (account: Address): Promise<BigNumber> => {
  return await provider.getBalance(account);
};
