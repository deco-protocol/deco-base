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
import { ZeroAdapterERC721 } from "@typechain/ZeroAdapterERC721";
import { ClaimAdapterERC721 } from "@typechain/ClaimAdapterERC721";
import { keccak256 } from "@ethersproject/keccak256";
import { solidityKeccak256 } from "ethers/lib/utils";

import Web3 from 'web3';

const expect = getWaffleExpect();

function toFrac(num: number) {
    return wad(num*100).div(100);
}

describe("ERC721 NFT Balance Adapters Test", () => {
    let deco: DecoFixture;
    let core: Core;
    let token: ERC20;
    let zeroERC721 : ZeroAdapterERC721;
    let claimERC721 : ClaimAdapterERC721;
    
    let owner: Account;
    let walletOne: Account;
    let walletTwo: Account;

    before(async () => {
        [owner, walletOne, walletTwo] = await getAccounts();

        // deploy token and core
        deco = getDecoFixture(owner.address);
        await deco.initialize(18);

        core = deco.core;
        token = deco.token;

        zeroERC721 = deco.zeroAdapterERC721;
        claimERC721 = deco.claimAdapterERC721;
    });

    addSnapshotBeforeRestoreAfterEach();

    describe("#setup", async () => {
        beforeEach(async () => {
        });

        it("happy path works", async () => {
        });
    });

    describe("when zero balance is issued as NFT", async () => {
        let zeroClass: string;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            let t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(zeroERC721.address, true); // user approves zero erc721 adapter contract address
        });
         
        it("should fail if balance is not sufficient", async () => {
            let exitResponse = zeroERC721.exit(owner.address, owner.address, zeroClass, wad(10001));
            await expect(exitResponse).to.be.revertedWith("zBal/insufficient-balance");
        });

        it("should fail if address is not approved", async () => {
            let exitResponse = zeroERC721.connect(walletOne.signer).exit(owner.address, owner.address, zeroClass, wad(123));
            await expect(exitResponse).to.be.revertedWith("user/not-authorized");
        });
         
        it("should move balance from usr to zero nft adapter address", async () => {
            await zeroERC721.exit(owner.address, owner.address, zeroClass, wad(2500));

            let userBal = await core.zBal(owner.address, zeroClass);
            let adapterBal = await core.zBal(zeroERC721.address, zeroClass);
            expect(userBal).to.be.eq(wad(7500)); // remaining balance
            expect(adapterBal).to.be.eq(wad(2500)); // balance now held by adapter
        });
         
        it("should mint a token", async () => {
            await zeroERC721.exit(owner.address, owner.address, zeroClass, wad(2500)); // token 1
            await zeroERC721.exit(owner.address, owner.address, zeroClass, wad(2500)); // token 2
            let totalTokens = await zeroERC721.totalSupply();
            expect(totalTokens).to.be.eq(2);
        });
         
        it("should update correct metadata", async () => {
            await zeroERC721.exit(owner.address, owner.address, zeroClass, wad(2500));
            let class_ = await zeroERC721.class(bn(0));
            let amount = await zeroERC721.amount(bn(0));
            expect(class_).to.be.eq(zeroClass);
            expect(amount).to.be.eq(wad(2500));
        });
         
        it("should allow approved user to execute exit", async () => {
            // owner approves walletOne
            await core.approve(walletOne.address, true);

            // walletOne exits owner's zero balance
            await zeroERC721.connect(walletOne.signer).exit(owner.address, walletOne.address, zeroClass, wad(2500));
            expect(await zeroERC721.ownerOf(bn(0))).to.be.eq(walletOne.address); // walletOne is the nft owner
            expect(await zeroERC721.amount(bn(0))).to.be.eq(wad(2500)); // check amont in nft

            // walletOne exits owner's zero balance to owner
            await zeroERC721.connect(walletOne.signer).exit(owner.address, owner.address, zeroClass, wad(2500));
            expect(await zeroERC721.ownerOf(bn(1))).to.be.eq(owner.address); // owner is the nft owner
            expect(await zeroERC721.amount(bn(1))).to.be.eq(wad(2500)); // check amont in nft
        });
    });

    describe("when zero nft is converted back to internal balance", async () => {
        let zeroClass: string;
        
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            let t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(zeroERC721.address, true); // user approves zero erc721 adapter contract address

            await zeroERC721.exit(owner.address, owner.address, zeroClass, wad(2500)); // mint an nft 
        });
         
        it("should fail if address is not approved", async () => {
            // owner approving walletOne in ERC721 contract should have no impact
            zeroERC721.approve(walletOne.address, bn(0));
            
            let joinResponse = zeroERC721.connect(walletOne.signer).join(owner.address, owner.address, bn(0));
            await expect(joinResponse).to.be.revertedWith("user/not-authorized");
        });
         
        it("should move balance from adapter to user", async () => {
            await zeroERC721.join(owner.address, owner.address, bn(0));
            
            let userBal = await core.zBal(owner.address, zeroClass);
            let adapterBal = await core.zBal(zeroERC721.address, zeroClass);
            expect(userBal).to.be.eq(wad(10000)); // user has full amount in core
            expect(adapterBal).to.be.eq(wad(0)); // no balance held by adapter
        });
         
        it("should burn the token", async () => {
            await zeroERC721.join(owner.address, owner.address, bn(0));
            expect(await zeroERC721.totalSupply()).to.be.eq(bn(0));
        });
         
        it("should remove metadata for tokenid", async () => {
            await zeroERC721.join(owner.address, owner.address, bn(0));
            expect(await zeroERC721.class(bn(0))).to.be.eq(bn(0));
            expect(await zeroERC721.amount(bn(0))).to.be.eq(bn(0));
        });
    });

    describe("when claim balance is issued as NFT", async () => {
        let claimClass: string;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            let t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(claimERC721.address, true); // user approves claim erc721 adapter contract address
        });
         
        it("should fail if balance is not sufficient", async () => {
            let exitResponse = claimERC721.exit(owner.address, owner.address, claimClass, wad(10001));
            await expect(exitResponse).to.be.revertedWith("cBal/insufficient-balance");
        });

        it("should fail if address is not approved", async () => {
            let exitResponse = claimERC721.connect(walletOne.signer).exit(owner.address, owner.address, claimClass, wad(123));
            await expect(exitResponse).to.be.revertedWith("user/not-authorized");
        });
         
        it("should move balance from usr to claim nft adapter address", async () => {
            await claimERC721.exit(owner.address, owner.address, claimClass, wad(2500));

            let userBal = await core.cBal(owner.address, claimClass);
            let adapterBal = await core.cBal(claimERC721.address, claimClass);
            expect(userBal).to.be.eq(wad(7500)); // remaining balance
            expect(adapterBal).to.be.eq(wad(2500)); // balance now held by adapter
        });
         
        it("should mint a token", async () => {
            await claimERC721.exit(owner.address, owner.address, claimClass, wad(2500)); // token 1
            await claimERC721.exit(owner.address, owner.address, claimClass, wad(2500)); // token 2
            let totalTokens = await claimERC721.totalSupply();
            expect(totalTokens).to.be.eq(2);
        });
         
        it("should update correct metadata", async () => {
            await claimERC721.exit(owner.address, owner.address, claimClass, wad(2500));
            let class_ = await claimERC721.class(bn(0));
            let amount = await claimERC721.amount(bn(0));
            expect(class_).to.be.eq(claimClass);
            expect(amount).to.be.eq(wad(2500));
        });
         
        it("should allow approved user to execute exit", async () => {
            // owner approves walletOne
            await core.approve(walletOne.address, true);

            // walletOne exits owner's claim balance
            await claimERC721.connect(walletOne.signer).exit(owner.address, walletOne.address, claimClass, wad(2500));
            expect(await claimERC721.ownerOf(bn(0))).to.be.eq(walletOne.address); // walletOne is the nft owner
            expect(await claimERC721.amount(bn(0))).to.be.eq(wad(2500)); // check amont in nft

            // walletOne exits owner's claim balance to owner
            await claimERC721.connect(walletOne.signer).exit(owner.address, owner.address, claimClass, wad(2500));
            expect(await claimERC721.ownerOf(bn(1))).to.be.eq(owner.address); // owner is the nft owner
            expect(await claimERC721.amount(bn(1))).to.be.eq(wad(2500)); // check amont in nft
        });
    });

    describe("when claim nft is converted back to internal balance", async () => {
        let claimClass: string;
        
        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            let t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            let t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(claimERC721.address, true); // user approves claim erc721 adapter contract address

            await claimERC721.exit(owner.address, owner.address, claimClass, wad(2500)); // mint an nft 
        });
         
        it("should fail if address is not approved", async () => {
            // owner approving walletOne in ERC721 contract should have no impact
            claimERC721.approve(walletOne.address, bn(0));
            
            let joinResponse = claimERC721.connect(walletOne.signer).join(owner.address, owner.address, bn(0));
            await expect(joinResponse).to.be.revertedWith("user/not-authorized");
        });
         
        it("should move balance from adapter to user", async () => {
            await claimERC721.join(owner.address, owner.address, bn(0));
            
            let userBal = await core.cBal(owner.address, claimClass);
            let adapterBal = await core.cBal(claimERC721.address, claimClass);
            expect(userBal).to.be.eq(wad(10000)); // user has full amount in core
            expect(adapterBal).to.be.eq(wad(0)); // no balance held by adapter
        });
         
        it("should burn the token", async () => {
            await claimERC721.join(owner.address, owner.address, bn(0));
            expect(await claimERC721.totalSupply()).to.be.eq(bn(0));
        });
         
        it("should remove metadata for tokenid", async () => {
            await claimERC721.join(owner.address, owner.address, bn(0));
            expect(await claimERC721.class(bn(0))).to.be.eq(bn(0));
            expect(await claimERC721.amount(bn(0))).to.be.eq(bn(0));
        });
    });
});
