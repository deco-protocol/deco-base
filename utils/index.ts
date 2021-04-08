import { ethers } from "hardhat";
import { Blockchain } from "./common";
import { Address } from "./types";

const provider = ethers.provider;
export const getBlockchainUtils = () => new Blockchain(provider);

import { SplitFixture } from "./fixtures";

export const getSplitFixture = (ownerAddress: Address) => new SplitFixture(provider, ownerAddress);

export {
  getAccounts,
  getEthBalance,
  getLastBlockTimestamp,
  getProvider,
  getTransactionTimestamp,
  getWaffleExpect,
  addSnapshotBeforeRestoreAfterEach,
  getRandomAccount,
  getRandomAddress,
  increaseTimeAsync,
  mineBlockAsync,
} from "./hardhat";

export {
  divDown,
  min,
  ether,
  gWei,
  preciseDiv,
  preciseDivCeil,
  preciseMul,
  preciseMulCeil,
  preciseMulCeilInt,
  preciseDivCeilInt,
} from "./common";
