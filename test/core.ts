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

describe("Core Test", () => {
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
            // get current timestamp
            let t0 = await getLastBlockTimestamp();

            // forward time
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();

            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // approve another user address
            await core.approve(walletOne.address, true);

            // insert frac value at timestamp
            await core.insert(t1, wad(90).div(100));

            // forward time
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t2 = await getLastBlockTimestamp();

            // insert frac value at new timestamp
            await core.insert(t2, wad(80).div(100));

            // issue zero and claim at new timestamp, and future maturity
            let t3 = t2.add(ONE_DAY_IN_SECONDS);
            await core.issue(owner.address, t2, t3, wad(5000));

            // withdraw some balance
            await core.withdraw(owner.address, t3, wad(1250)); // 5000/6250 notional remaining

            // rewind claim to first frac value timestamp
            await core.rewind(owner.address, t2, t3, t1, wad(5000));

            // insert frac value at mid way and at maturity
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            await core.insert(t3, wad(70).div(100));

            // fast forward to after maturity
            // forward time
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(2));
            let t4 = await getLastBlockTimestamp();

            // redeem zero at maturity
            await core.redeem(owner.address, t3, t3, wad(5000));
            
            // collect claim at maturity
            await core.collect(owner.address, t1, t3, t3, wad(5000));

        });
    });

    // describe("when balances are minted and burnt", async () => {
    //     beforeEach(async () => {
    //     });

    //     it("should increase zero balance with mint", async () => {

    //     });

    //     it("should decrease zero balance with burn", async () => {

    //     });

    //     it("should increase claim balance with mint", async () => {

    //     });

    //     it("should decrease claim balance with burn", async () => {

    //     });
    // });

    describe("when zero balance is transferred", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if insufficient balance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            let transferResponse = core.moveZero(owner.address, walletOne.address, zeroClass, wad(10001)); // 1 additional for failure
            await expect(transferResponse).to.be.revertedWith("zBal/insufficient-balance");
        });

        it("should update both addresses", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await core.moveZero(owner.address, walletOne.address, zeroClass, wad(10000));
            
            let srcBal = await core.zBal(owner.address, zeroClass);
            let dstBal = await core.zBal(walletOne.address, zeroClass);
            expect(srcBal).to.be.eq(wad(0));
            expect(dstBal).to.be.eq(wad(10000));
        });

        it("should fail if user is not approved or owner", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            let transferResponse = core.connect(walletOne.signer).moveZero(owner.address, walletOne.address, zeroClass, wad(10000));
            await expect(transferResponse).to.be.revertedWith("user/not-authorized");
        });
    });

    describe("when claim balance is transferred", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if insufficient balance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            let transferResponse = core.moveClaim(owner.address, walletOne.address, claimClass, wad(10001)); // 1 additional for failure
            await expect(transferResponse).to.be.revertedWith("cBal/insufficient-balance");
        });

        it("should update both addresses", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await core.moveClaim(owner.address, walletOne.address, claimClass, wad(10000));
            
            let srcBal = await core.cBal(owner.address, claimClass);
            let dstBal = await core.cBal(walletOne.address, claimClass);
            expect(srcBal).to.be.eq(wad(0));
            expect(dstBal).to.be.eq(wad(10000));
        });

        it("should fail if user is not approved or owner", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.9));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            let transferResponse = core.connect(walletOne.signer).moveClaim(owner.address, walletOne.address, claimClass, wad(10000));
            await expect(transferResponse).to.be.revertedWith("user/not-authorized");
        });
    });

    describe("when user issues zero and claim balances", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // forward time
            let t1 = await getLastBlockTimestamp();

            let issueResponse = core.connect(walletOne.signer).issue(owner.address, t0, t5, wad(5000));
            await expect(issueResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if issuance falls after close", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.80));

            await core.close();

            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t2 = await getLastBlockTimestamp();

            let issueResponse = core.issue(owner.address, t2, t2.add(ONE_DAY_IN_SECONDS), wad(5000));
            await expect(issueResponse).to.be.revertedWith("after-close");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.80));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.70));
            
            // issuance <= latestFracTimestamp && latestFracTimestamp <= maturity 
            // maturity lower than issuance timestamps
            let response1 = core.issue(owner.address, t1, t0, wad(5000));
            await expect(response1).to.be.revertedWith("timestamp/invalid");

            // issuance greater than latest
            let response2 = core.issue(owner.address, t2.add(ONE_DAY_IN_SECONDS), t2, wad(5000));
            await expect(response2).to.be.revertedWith("timestamp/invalid");

            // maturity greater than latest
            let response3 = core.issue(owner.address, t0, t1, wad(5000));
            await expect(response3).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if frac value is not present at issuance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();

            let issueResponse = core.issue(owner.address, t0.sub(1), t0.add(ONE_DAY_IN_SECONDS), wad(5000));
            await expect(issueResponse).to.be.revertedWith("frac/invalid");
        });

        it("should issue zero and claim balances for notional amount", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();

            await core.issue(owner.address, t0, t1, wad(9000));
            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t1]);
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t1]);
            
            expect(await core.zBal(owner.address, zeroClass)).to.be.eq(wad(10000));
            expect(await core.cBal(owner.address, claimClass)).to.be.eq(wad(10000));
        });

        it("should transfer token balance from user to deco", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            let t1 = await getLastBlockTimestamp();

            await core.issue(owner.address, t0, t1, wad(9000));

            let tokenBalance = await token.balanceOf(owner.address);
            expect(tokenBalance).to.be.eq(wad(1000));
        });
    });

    describe("when user withdraws zero and claim balances", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            let withdrawResponse = core.connect(walletOne.signer).withdraw(owner.address, t5, wad(5000));
            await expect(withdrawResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if claim balance is not collected until latest frac timestamp", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            let withdrawResponse = core.connect(walletOne.signer).withdraw(owner.address, t5, wad(5000));
            await expect(withdrawResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should burn both zero and claim balances", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);

            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);
            await core.issue(owner.address, t0, t5, wad(4500));

            await core.withdraw(owner.address, t5, wad(5000));
            
            expect(await core.zBal(owner.address, zeroClass)).to.be.eq(wad(0));
            expect(await core.cBal(owner.address, claimClass)).to.be.eq(wad(0));
        });

        it("should transfer token balance from deco to user", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS);
            await core.issue(owner.address, t0, t5, wad(4500));

            await core.withdraw(owner.address, t5, wad(5000));

            let tokenBalance = await token.balanceOf(owner.address);
            expect(tokenBalance).to.be.eq(wad(10000));
        });
    });

    describe("when user redeems with zero balance after maturity", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t5, toFrac(0.80));

            let redeemResponse = core.connect(walletOne.signer).redeem(owner.address, t5, t5, wad(10000));
            await expect(redeemResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if maturity falls after close", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 4 days
            await core.close();

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(2)); // 6 days
            // await core.insert(t5, toFrac(0.80)); // will fail since closed

            let redeemResponse = core.redeem(owner.address, t5, t5, wad(10000));
            await expect(redeemResponse).to.be.revertedWith("after-close");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();

            await core.insert(t5, toFrac(0.80));

            let redeemResponse1 = core.redeem(owner.address, t5, t0, wad(10000)); // redeem lower than maturity
            await expect(redeemResponse1).to.be.revertedWith("timestamp/invalid");

            let redeemResponse2 = core.redeem(owner.address, t5, t6, wad(10000)); // redeem greater than latest frac timestamp
            await expect(redeemResponse2).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if collect frac value does not exist", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();
            await core.insert(t6, toFrac(0.80));

            let redeemResponse = core.redeem(owner.address, t5, t5, wad(10000));
            await expect(redeemResponse).to.be.revertedWith("frac/invalid");
        });

        it("should burn zero balance", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();

            await core.insert(t5, toFrac(0.80));
            await core.redeem(owner.address, t5, t5, wad(10000));

            let zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);
            expect(await core.zBal(owner.address, zeroClass)).to.be.eq(wad(0));
        });

        it("should transfer token balance from deco to user", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();

            await core.insert(t5, toFrac(0.80));
            await core.redeem(owner.address, t5, t5, wad(10000));

            let tokenBal = await token.balanceOf(owner.address);
            expect(tokenBal).to.be.eq(wad(9000)); // remaining 1000 collected by claim balance
        });
    });

    describe("when user collects with claim balance after maturity", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t5, toFrac(0.80));

            let collectResponse = core.connect(walletOne.signer).collect(owner.address, t0, t5, t5, wad(10000));
            await expect(collectResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if maturity falls after close", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 4 days
            await core.close();

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(2)); // 6 days
            // await core.insert(t5, toFrac(0.80)); // will fail since closed

            let collectResponse = core.collect(owner.address, t0, t5, t5, wad(10000));
            await expect(collectResponse).to.be.revertedWith("after-close");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(3)); // 9 days
            let t9 = await getLastBlockTimestamp();

            await core.insert(t5, toFrac(0.80));
            await core.insert(t6, toFrac(0.75));

            let collectResponse1 = core.collect(owner.address, t0, t5, t6, wad(10000)); // collect greater than maturity
            await expect(collectResponse1).to.be.revertedWith("timestamp/invalid");

            let collectResponse2  = core.collect(owner.address, t0, t5, t9, wad(10000)); // collect greater than latest frac timestamp
            await expect(collectResponse2).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if either collect or issuance frac values do not exist", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            let t6 = await getLastBlockTimestamp();
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(3)); // 9 days
            let t9 = await getLastBlockTimestamp();

            await core.insert(t5, toFrac(0.80));

            let collectResponse = core.collect(owner.address, t0, t5, t6, wad(10000));
            await expect(collectResponse).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if issuance frac value is equal to collect", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days

            await core.insert(t5, toFrac(0.80));

            let collectResponse = core.collect(owner.address, t0, t5, t0, wad(10000));
            await expect(collectResponse).to.be.revertedWith("frac/no-difference");
        });

        it("should fail if issuance frac value is lower than collect", async () => {
            let t0 = await getLastBlockTimestamp();
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));
            await core.insert(t0, toFrac(0.90));
            await core.issue(owner.address, t0, t5, wad(9000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t5, toFrac(0.95));  // invalid frac value
            
            let collectResponse = core.collect(owner.address, t0, t5, t5, wad(10000));
            await expect(collectResponse).to.be.revertedWith("frac/no-difference");
        });

        it("should burn entire claim balance if collecting on total period", async () => {
            let t0 = await getLastBlockTimestamp();
            let t6 = t0.add(ONE_DAY_IN_SECONDS.mul(6));
            await core.insert(t0, toFrac(1.0));
            await core.issue(owner.address, t0, t6, wad(10000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t6, toFrac(0.80));
            
            await core.collect(owner.address, t0, t6, t6, wad(10000)); // collect entire amount for full time period

            // no balance left
            let claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t6]);
            let claimBalance = await core.cBal(owner.address, claimClass);
            expect(claimBalance).to.be.eq(wad(0));
        });

        it("should burn original and mint new claim balance if collecting on partial period", async () => {
            let t0 = await getLastBlockTimestamp();
            let t3 = t0.add(ONE_DAY_IN_SECONDS.mul(3));
            let t6 = t0.add(ONE_DAY_IN_SECONDS.mul(6));
            await core.insert(t0, toFrac(1.0));
            await core.issue(owner.address, t0, t6, wad(10000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t3, toFrac(0.90));
            await core.insert(t6, toFrac(0.80));
            
            await core.collect(owner.address, t0, t6, t3, wad(10000)); // collect entire amount for half period

            let originalClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t6]);
            let originalClaimBalance = await core.cBal(owner.address, originalClaimClass);
            expect(originalClaimBalance).to.be.eq(wad(0)); // balance is 0
            
            let collectedClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t3]);
            let collectedClaimBalance = await core.cBal(owner.address, collectedClaimClass);
            expect(collectedClaimBalance).to.be.eq(wad(0)); // balance is 0

            let newClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t3, t6]);
            let newClaimBalance = await core.cBal(owner.address, newClaimClass);
            expect(newClaimBalance).to.be.eq(wad(10000)); // balance remains
        });

        it("should transfer token balance from deco to user", async () => {
            let t0 = await getLastBlockTimestamp();
            let t6 = t0.add(ONE_DAY_IN_SECONDS.mul(6));
            await core.insert(t0, toFrac(1.0));
            await core.issue(owner.address, t0, t6, wad(10000));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(6)); // 6 days
            await core.insert(t6, toFrac(0.80));
            
            await core.collect(owner.address, t0, t6, t6, wad(10000)); // collect entire amount for full time period
            expect(await token.balanceOf(owner.address)).to.be.eq(wad(2000)); // collected amount
        });
    });

    describe("when user rewinds issuance timestamp on their claim balance", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(5)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let rewindResponse = core.connect(walletOne.signer).rewind(owner.address, t1, t5, t0, wad(10000));
            await expect(rewindResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.95));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let rewindResponse = core.rewind(owner.address, t1, t5, t2, wad(10000));
            await expect(rewindResponse).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if either collect or issuance frac values do not exist", async () => {
            let t0 = await getLastBlockTimestamp();
            // await core.insert(t0, toFrac(1.0)); // frac value does not exist
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.95));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let rewindResponse = core.rewind(owner.address, t1, t5, t0, wad(10000));
            await expect(rewindResponse).to.be.revertedWith("frac/invalid");
        });

        it("should fail if issuance frac value is equal to collect", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.95));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let rewindResponse = core.rewind(owner.address, t1, t5, t1, wad(10000));
            await expect(rewindResponse).to.be.revertedWith("frac/no-difference");
        });

        it("should fail if collect frac value is lower than issuance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.80)); // invalid frac value (lower)
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.95));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let rewindResponse = core.rewind(owner.address, t1, t5, t0, wad(10000));
            await expect(rewindResponse).to.be.revertedWith("frac/no-difference");
        });

        it("should burn entire claim balance and mint new claim balance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.95));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t1, t5, wad(9000)); // 1000 token balance left
            await core.rewind(owner.address, t1, t5, t0, wad(10000)); // use 500 token balance to rewind

            let originalClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t1, t5]);
            let originalClaimBalance = await core.cBal(owner.address, originalClaimClass);
            expect(originalClaimBalance).to.be.eq(wad(0)); // balance is 0
            
            let collectedClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);
            let collectedClaimBalance = await core.cBal(owner.address, collectedClaimClass);
            expect(collectedClaimBalance).to.be.eq(wad(10000)); // balance is shifted to this class
        });

        it("should transfer difference amount from user to deco", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(0.95));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t1, t5, wad(9000)); // 1000 token balance left

            let tokenBalanceBefore = await token.balanceOf(owner.address);
            await core.rewind(owner.address, t1, t5, t0, wad(10000)); // use 500 token balance to rewind
            let tokenBalanceAfter = await token.balanceOf(owner.address);
            
            expect(tokenBalanceBefore).to.be.eq(tokenBalanceAfter.add(wad(500)));
        });
    });

    describe("when user slices their claim balance", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(5)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t0, t5, wad(9000));

            let sliceResponse = core.connect(walletOne.signer).slice(owner.address, t0, t1, t5, wad(10000));
            await expect(sliceResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(5)); // 6 days
            await core.insert(t5, toFrac(0.80));

            let t6 = await getLastBlockTimestamp();
            
            await core.issue(owner.address, t1, t5, wad(9000));

            let sliceResponse1 = core.slice(owner.address, t1, t0, t5, wad(9000));
            await expect(sliceResponse1).to.be.revertedWith("timestamp/invalid");

            let sliceResponse2 = core.slice(owner.address, t1, t6, t5, wad(9000));
            await expect(sliceResponse2).to.be.revertedWith("timestamp/invalid");
        });

        it("should burn original balance and mint two new claim balances", async () => {
            let t0 = await getLastBlockTimestamp();
            let t1 = t0.add(ONE_DAY_IN_SECONDS);
            let t2 = t0.add(ONE_DAY_IN_SECONDS.mul(2));
            let t6 = t0.add(ONE_DAY_IN_SECONDS.mul(6));

            await core.insert(t0, toFrac(1.0));
            await core.issue(owner.address, t0, t6, wad(10000));
            await core.slice(owner.address, t0, t1, t6, wad(10000));
            await core.slice(owner.address, t1, t2, t6, wad(10000));

            let fullClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t6]);
            let fullClaimBalance = await core.cBal(owner.address, fullClaimClass);
            expect(fullClaimBalance).to.be.eq(wad(0)); // balance is 0

            let firstClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t1]);
            let firstClaimBalance = await core.cBal(owner.address, firstClaimClass);
            expect(firstClaimBalance).to.be.eq(wad(10000)); // balance stays same
            
            let secondClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t1, t2]);
            let secondClaimBalance = await core.cBal(owner.address, secondClaimClass);
            expect(secondClaimBalance).to.be.eq(wad(10000)); // balance stays same

            let thirdClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t2, t6]);
            let thirdClaimBalance = await core.cBal(owner.address, thirdClaimClass);
            expect(thirdClaimBalance).to.be.eq(wad(10000)); // balance stays same
        });
    });

    describe("when user merges two claim balances", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.90));
            
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(5)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let mergeResponse = core.connect(walletOne.signer).merge(owner.address, t0, t1, t5, wad(9000));
            await expect(mergeResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.95));

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            await core.insert(t5, toFrac(0.80));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let mergeResponse = core.merge(owner.address, t0, t5, t2, wad(9000));
            await expect(mergeResponse).to.be.revertedWith("timestamp/invalid");
        });

        it("should burn balances from two classes and mint one class of claim balance", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            let t5 = t1.add(ONE_DAY_IN_SECONDS.mul(5));
            
            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));
            await core.merge(owner.address, t0, t1, t5, wad(9000));

            let firstClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t1]);
            let firstClaimBalance = await core.cBal(owner.address, firstClaimClass);
            expect(firstClaimBalance).to.be.eq(wad(0)); // balance is 0
            
            let secondClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t1, t5]);
            let secondClaimBalance = await core.cBal(owner.address, secondClaimClass);
            expect(secondClaimBalance).to.be.eq(wad(0)); // balance is 0

            let fullClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);
            let fullClaimBalance = await core.cBal(owner.address, fullClaimClass);
            expect(fullClaimBalance).to.be.eq(wad(9000)); // old balance restored
        });
    });

    describe("when user activates their claim balance", async () => {
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);
        });

        it("should fail if address is not approved", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            // await core.insert(t1, toFrac(0.95)); // frac value shouldnt exist at slice point

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let activateResponse = core.connect(walletOne.signer).activate(owner.address, t1, t2, t5, wad(9000));
            await expect(activateResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail when timestamp order is mismatched", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            // await core.insert(t1, toFrac(0.95)); // frac value shouldnt exist at slice point

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            // await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let activateResponse = core.activate(owner.address, t1, t5, t2, wad(9000));
            await expect(activateResponse).to.be.revertedWith("timestamp/invalid");
        });

        it("should fail if issuance frac value is valid", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.95)); // issuance frac value valid

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            // await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let activateResponse = core.activate(owner.address, t1, t2, t5, wad(9000));
            await expect(activateResponse).to.be.revertedWith("frac/valid");
        });

        it("should fail if collect frac value is invalid", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.95)); // issuance frac value valid

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            // await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let activateResponse = core.activate(owner.address, t1, t2, t5, wad(9000)); //activating t1 t5 claim balance
            await expect(activateResponse).to.be.revertedWith("frac/valid");
        });

        it("should fail if issuance and collect timestamps are equal", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();
            await core.insert(t1, toFrac(0.95)); // issuance frac value valid

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            // await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            let activateResponse = core.activate(owner.address, t1, t1, t5, wad(9000)); // activating again at issuance
            await expect(activateResponse).to.be.revertedWith("timestamp/invalid");
        });

        it("should burn one claim balance and issue another", async () => {
            let t0 = await getLastBlockTimestamp();
            await core.insert(t0, toFrac(1.0));
            
            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            let t1 = await getLastBlockTimestamp();

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 2 days
            let t2 = await getLastBlockTimestamp();
            await core.insert(t2, toFrac(0.90));
            
            let t5 = t2.add(ONE_DAY_IN_SECONDS.mul(4));
            await increaseTimeAsync(ONE_DAY_IN_SECONDS.mul(4)); // 6 days
            // await core.insert(t5, toFrac(0.80));

            await core.issue(owner.address, t0, t5, wad(9000));
            await core.slice(owner.address, t0, t1, t5, wad(9000));

            await core.activate(owner.address, t1, t2, t5, wad(9000));
            // await expect(activateResponse).to.be.revertedWith("timestamp/invalid");
            
            let firstClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t1, t5]);
            let firstClaimBalance = await core.cBal(owner.address, firstClaimClass);
            expect(firstClaimBalance).to.be.eq(wad(0)); // balance is 0
            
            let secondClaimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t2, t5]);
            let secondClaimBalance = await core.cBal(owner.address, secondClaimClass);
            expect(secondClaimBalance).to.be.eq(wad(9000)); // balance is restored here
        });
    });
});