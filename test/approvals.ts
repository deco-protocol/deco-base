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

describe("Approvals Test", () => {
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

    describe("when approved user calls", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(walletOne.address, wad(10000));
            await token.connect(walletOne.signer).approve(core.address, MAX_UINT_256);
        });

        it("should allow owner to execute", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0)); // gov inserts frac value
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core.connect(walletOne.signer).issue(walletOne.address, t0, t5, wad(9000));
            expect(await core.zBal(walletOne.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(9000)); // works
        });

        it("should allow approved to execute", async () => {
            // walletOne approves walletTwo
            await core.connect(walletOne.signer).approve(walletTwo.address, true);

            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0)); // gov inserts frac value
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core.connect(walletTwo.signer).issue(walletOne.address, t0, t5, wad(9000)); // walletTwo executes for walletOne
            expect(await core.zBal(walletOne.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(9000)); // works
        });

        it("should fail if unapproved executes", async () => {
            // walletOne does not approve walletTwo
            
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0)); // gov inserts frac value
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            let issueResponse = core.connect(walletTwo.signer).issue(walletOne.address, t0, t5, wad(9000)); // walletTwo executes for walletOne
            await expect(issueResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail approved after same address is disapproved", async () => {
            // walletOne approves walletTwo
            await core.connect(walletOne.signer).approve(walletTwo.address, true);
            // walletOne removes approval
            await core.connect(walletOne.signer).approve(walletTwo.address, false);
            
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0)); // gov inserts frac value
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            let issueResponse = core.connect(walletTwo.signer).issue(walletOne.address, t0, t5, wad(9000)); // walletTwo executes for walletOne
            await expect(issueResponse).to.be.revertedWith("user/not-authorized");
        });
    });
});