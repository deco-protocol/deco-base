require("module-alias/register");
import { ethers, waffle } from "hardhat";
import { BigNumber, ContractTransaction } from "ethers";

import { Address, Account } from "@utils/types";
import { ZERO } from "@utils/constants";
import {
  getSplitFixture,
  addSnapshotBeforeRestoreAfterEach,
  ether,
  increaseTimeAsync,
  getAccounts,
  getWaffleExpect,
  getRandomAccount,
  getRandomAddress,
  getTransactionTimestamp,
  getLastBlockTimestamp,
  preciseMul,
} from "@utils/index";
import { SplitFixture } from "@utils/fixtures";

const expect = getWaffleExpect();

describe("SampleTest", () => {
  let fixture: SplitFixture;
  
  let owner: Account;
  let walletOne: Account;
  let walletTwo: Account;

  before(async () => {
    [owner, walletOne, walletTwo] = await getAccounts();

    fixture = getSplitFixture(owner.address);
    await fixture.initialize(walletOne.address);
  });

  addSnapshotBeforeRestoreAfterEach();

  describe("#constructor", async () => {

  });
});
