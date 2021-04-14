import { ethers, BigNumber } from "ethers";

export const ether = (amount: number): BigNumber => {
  const weiString = ethers.utils.parseEther(amount.toString());
  return BigNumber.from(weiString);
};

export const gWei = (amount: number): BigNumber => {
  const weiString = BigNumber.from("1000000000").mul(amount);
  return BigNumber.from(weiString);
};

export const usdc = (amount: number): BigNumber => {
  const usdcString = BigNumber.from("1000000").mul(amount);
  return BigNumber.from(usdcString);
};

export const wad = (amount: number): BigNumber => {
  const wadString = BigNumber.from("1000000000000000000").mul(amount);
  return BigNumber.from(wadString);
};

export const ray = (amount: number): BigNumber => {
  const rayString = BigNumber.from("1000000000000000000000000000").mul(amount);
  return BigNumber.from(rayString);
};

export const rad = (amount: number): BigNumber => {
  const radString = BigNumber.from("1000000000000000000000000000000000000000000000").mul(amount);
  return BigNumber.from(radString);
};