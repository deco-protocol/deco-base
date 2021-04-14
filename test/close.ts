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

function toRatio(num: number) {
    return wad(num*100).div(100);
}

describe("Close Test", () => {
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

    describe("when deco is closed", async () => {
        beforeEach(async () => {
        });

        it("should fail if gov is not caller", async () => {
            let closeResponse = core.connect(walletOne.signer).close();
            await expect(closeResponse).to.be.revertedWith("gov/not-authorized");
        });

        it("should fail if already closed", async () => {
            await core.close();

            let closeResponse = core.close();
            await expect(closeResponse).to.be.revertedWith("closed");
        });

        it("should set closetimestamp to last frac timestamp", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await core.close();
            expect(await core.closeTimestamp()).to.be.eq(t1);
        });
    });

    describe("when ratio is calculated for a maturity timestamp", async () => {
        beforeEach(async () => {
        });

        it("should fail if gov is not caller", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            let calculateRatioResponse = core.connect(walletOne.signer).calculate(t2, toRatio(0.95));
            await expect(calculateRatioResponse).to.be.revertedWith("gov/not-authorized");
        });

        it("should fail if timestamp is before close", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            let calculateRatioResponse = core.calculate(t1.sub(1), toRatio(0.95)); // before close
            await expect(calculateRatioResponse).to.be.revertedWith("before-close");
        });

        it("should fail if not a fraction", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            let calculateRatioResponse = core.calculate(t2, wad(1).add(1)); // above wad
            await expect(calculateRatioResponse).to.be.revertedWith("ratio/not-fraction");
        });

        it("should fail if ratio already set at timestamp", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            await core.calculate(t2, toRatio(0.95));

            let calculateRatioResponse = core.calculate(t2, toRatio(0.90));
            await expect(calculateRatioResponse).to.be.revertedWith("ratio/present");
        });

        it("should set ratio for timestamp", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            await core.calculate(t2, toRatio(0.95));
            expect(await core.ratio(t2)).to.be.eq(wad(95).div(100));
        });
    });

    describe("when zero value is calculated", async () => {
        beforeEach(async () => {
        });

        it("should fail if ratio is not set for timestamp", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            // await core.calculate(t2, toRatio(0.95)); // not setting a ratio
            let zeroValueResponse = core.zero(t2, wad(1000));
            await expect(zeroValueResponse).to.be.revertedWith("ratio/not-set");
        });

        it("should report correct fraction for zero", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            await core.calculate(t2, toRatio(0.95));
            let zeroVal = await core.zero(t2, wad(1000));
            expect(zeroVal).to.be.eq(wad(950));
        });
    });

    describe("when claim value is calculated", async () => {
        beforeEach(async () => {
        });

        it("should fail if ratio is not set for timestamp", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            // await core.calculate(t2, toRatio(0.95)); // not setting a ratio
            let claimValueResponse = core.claim(t2, wad(1000));
            await expect(claimValueResponse).to.be.revertedWith("ratio/not-set");
        });

        it("should report correct fraction for claim", async () => {
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            await core.close();

            let t2 = t1.add(ONE_DAY_IN_SECONDS);

            await core.calculate(t2, toRatio(0.95));
            let claimVal = await core.claim(t2, wad(1000));
            expect(claimVal).to.be.eq(wad(50));
        });
    });

    describe("when zero balance is cashed", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close(); // close at t2

            await core.calculate(t2, toRatio(0.95));
            let cashZeroResponse = core.connect(walletOne.signer).cashZero(owner.address, t2, wad(10000));
            await expect(cashZeroResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if maturity falls before close", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(3)); // 3 days
            let t3 = await getLastBlockTimestamp();
            await core.insert(t3, toFrac(0.80));
            await core.close(); // close at t3

            // await core.calculate(t2, toRatio(0.95)); // will fail
            let cashZeroResponse = core.cashZero(owner.address, t2, wad(10000));
            await expect(cashZeroResponse).to.be.revertedWith("before-close");
        });

        it("should burn zero balance", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close();

            await core.calculate(t2, toRatio(0.95));
            await core.cashZero(owner.address, t2, wad(10000));

            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t2]);
            expect(await core.zBal(owner.address, zeroClass)).to.be.eq(wad(0));
        });

        it("should transfer token balance from deco to user", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close();

            await core.calculate(t2, toRatio(0.95));
            await core.cashZero(owner.address, t2, wad(10000));

            expect(await token.balanceOf(owner.address)).to.be.eq(wad(9550));
        });
    });

    describe("when claim balance is cashed", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close(); // close at t2

            await core.calculate(t2, toRatio(0.95));
            let cashClaimResponse = core.connect(walletOne.signer).cashClaim(owner.address, t2, wad(10000));
            await expect(cashClaimResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if maturity falls before close", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(3)); // 3 days
            let t3 = await getLastBlockTimestamp();
            await core.insert(t3, toFrac(0.80));
            await core.close(); // close at t3

            // await core.calculate(t2, toRatio(0.95)); // will fail
            let cashClaimResponse = core.cashClaim(owner.address, t2, wad(10000));
            await expect(cashClaimResponse).to.be.revertedWith("before-close");
        });

        it("should fail if balance is not collected until close timestamp", async () => {
            let t1 = await getLastBlockTimestamp(); // 1  day
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            let t3 = t2.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t3, wad(9000));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            await core.insert(t2, toFrac(0.80));
            await core.close(); // close at t2

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(2)); // 4 days
            
            await core.calculate(t3, toRatio(0.95));
            let cashClaimResponse = core.cashClaim(owner.address, t3, wad(10000)); // cash claim balance without collecting
            await expect(cashClaimResponse).to.be.revertedWith("cBal/insufficient-balance");
        });

        it("should burn claim balance", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close();

            await core.calculate(t2, toRatio(0.95));
            await core.cashClaim(owner.address, t2, wad(10000));

            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t1, t2]);
            expect(await core.cBal(owner.address, claimClass)).to.be.eq(wad(0));
        });

        it("should transfer token balance from deco to user", async () => {
            let t1 = await getLastBlockTimestamp();
            let t2 = t1.add(ONE_DAY_IN_SECONDS);
            await core.insert(t1, toFrac(0.90));
            await core.issue(owner.address, t1, t2, wad(9000));
            await core.close();

            await core.calculate(t2, toRatio(0.95));
            await core.cashClaim(owner.address, t2, wad(10000));

            expect(await token.balanceOf(owner.address)).to.be.eq(wad(1450));
        });
    });
});