require("module-alias/register");
import { ethers, waffle } from "hardhat";
import { BigNumber, ContractReceipt, ContractTransaction, utils } from "ethers";

import { Address, Account } from "@utils/types";
import { MAX_UINT_256, ONE, ONE_DAY_IN_SECONDS, ZERO } from "@utils/constants";
import {
    addSnapshotBeforeRestoreAfterEach,
    ether,
    usdc,
    wad,
    increaseTimeAsync,
    getAccounts,
    getWaffleExpect,
    getRandomAccount,
    getRandomAddress,
    getTransactionTimestamp,
    getLastBlockTimestamp,
    preciseMul,
    getDecoFixture,
    bn
} from "@utils/index";
import { DecoFixture } from "@utils/fixtures";
import { Core } from "@typechain/Core";
import { ERC20 } from "@typechain/ERC20";
import { keccak256 } from "@ethersproject/keccak256";
import { solidityKeccak256 } from "ethers/lib/utils";

import Web3 from 'web3';

const expect = getWaffleExpect();

function toFrac(num: number) {
    return wad(num*100).div(100);
}

describe("Token Test", () => {
    let deco: DecoFixture;

    let core: Core;
    let token: ERC20;

    let owner: Account;
    let walletOne: Account;
    let walletTwo: Account;

    before(async () => {
        [owner, walletOne, walletTwo] = await getAccounts();

        deco = getDecoFixture(owner.address);
        await deco.initialize(18);

        core = deco.core;
        token = deco.token;
    });

    addSnapshotBeforeRestoreAfterEach();

    describe("#setup", async () => {
        beforeEach(async () => {
        });

        it("happy path works", async () => {
        });
    });

    describe("when frac value is inserted by gov", async () => {
        beforeEach(async () => {
        });

        it("should fail if gov is not caller", async () => {

        });

        it("should fail if frac value above one", async () => {

        });

        it("should fail if frac value is inserted at future timestamp", async () => {

        });

        it("should fail if frac value is already present at timestamp", async () => {

        });

        it("should update frac value", async () => {

        });

        it("should update latest frac timestamp when new value is after", async () => {

        });
    });
});