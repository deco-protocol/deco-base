import { ethers, BigNumber } from "ethers";

export const ether = (amount: number): BigNumber => {
  const weiString = ethers.utils.parseEther(amount.toString());
  return BigNumber.from(weiString);
};

export const gWei = (amount: number): BigNumber => {
  const weiString = BigNumber.from("1000000000").mul(amount);
  return BigNumber.from(weiString);
};
