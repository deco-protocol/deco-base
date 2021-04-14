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
    ray,
    rad,
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
    
    let deco6: DecoFixture;
    let core6: Core;
    let token6: ERC20;

    let deco27: DecoFixture;
    let core27: Core;
    let token27: ERC20;

    let owner: Account;
    let walletOne: Account;
    let walletTwo: Account;

    before(async () => {
        [owner, walletOne, walletTwo] = await getAccounts();

        // deploy token and core with 18 decimals
        deco = getDecoFixture(owner.address);
        await deco.initialize(18);
        core = deco.core;
        token = deco.token;

        // deploy token and core with lower than 18 decimals
        deco6 = getDecoFixture(owner.address);
        await deco6.initialize(6);
        core6 = deco6.core;
        token6 = deco6.token;

        // deploy token and core with higher than 18 decimals
        deco27 = getDecoFixture(owner.address);
        await deco27.initialize(27);
        core27 = deco27.core;
        token27 = deco27.token;
    });

    addSnapshotBeforeRestoreAfterEach();

    describe("#setup", async () => {
        beforeEach(async () => {
        });

        it("happy path works", async () => {
        });
    });

    describe("when token balance is locked", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            await token6.mint(owner.address, usdc(10000));
            await token6.approve(core6.address, MAX_UINT_256);

            await token27.mint(owner.address, ray(10000));
            await token27.approve(core27.address, MAX_UINT_256);
        });
         
        it("should adjust decimals correctly for token with 18 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core.issue(owner.address, t0, t5, wad(9000));
            expect(await core.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(9000));
            expect(await token.balanceOf(owner.address)).to.be.eq(wad(1000));
        });

        it("should adjust decimals correctly for token with 6 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core6.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core6.issue(owner.address, t0, t5, usdc(9000));
            expect(await core6.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(9000));
            expect(await token6.balanceOf(owner.address)).to.be.eq(usdc(1000));
        });

        it("should adjust decimals correctly for token with 27 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core27.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core27.issue(owner.address, t0, t5, ray(9000));
            expect(await core27.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(9000));
            expect(await token27.balanceOf(owner.address)).to.be.eq(ray(1000));
        });
    });

    describe("when token balance is unlocked", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            await token6.mint(owner.address, usdc(10000));
            await token6.approve(core6.address, MAX_UINT_256);

            await token27.mint(owner.address, ray(10000));
            await token27.approve(core27.address, MAX_UINT_256);
        });

        it("should adjust decimals correctly for token with 18 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.withdraw(owner.address, t5, wad(9000));
            expect(await core.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(0));
            expect(await token.balanceOf(owner.address)).to.be.eq(wad(10000));
        });

        it("should adjust decimals correctly for token with 6 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core6.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core6.issue(owner.address, t0, t5, usdc(9000));
            await core6.withdraw(owner.address, t5, wad(9000));
            expect(await core6.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(0));
            expect(await token6.balanceOf(owner.address)).to.be.eq(usdc(10000));
        });

        it("should adjust decimals correctly for token with 27 decimals and transfer", async () => {
            let t0 = await getLastBlockTimestamp();
            await core27.insert(t0, toFrac(1.0));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            await core27.issue(owner.address, t0, t5, ray(9000));
            await core27.withdraw(owner.address, t5, wad(9000));
            expect(await core27.zBal(owner.address, ethers.utils.solidityKeccak256(["uint256"], [t5]))).to.be.eq(wad(0));
            expect(await token27.balanceOf(owner.address)).to.be.eq(ray(10000));
        });
    });
});