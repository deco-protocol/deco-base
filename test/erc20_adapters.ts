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
import { ZeroAdapterERC20 } from "@typechain/ZeroAdapterERC20";
import { ClaimAdapterERC20 } from "@typechain/ClaimAdapterERC20";
import { keccak256 } from "@ethersproject/keccak256";
import { solidityKeccak256 } from "ethers/lib/utils";

import Web3 from 'web3';
import { ERC20__factory } from "@typechain/factories/ERC20__factory";

const expect = getWaffleExpect();

function toFrac(num: number) {
    return wad(num*100).div(100);
}

describe("ERC20 Balance Adapters Test", () => {
    let deco: DecoFixture;
    let core: Core;
    let token: ERC20;
    let zeroERC20 : ZeroAdapterERC20;
    let claimERC20 : ClaimAdapterERC20;
    
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

        zeroERC20 = deco.zeroAdapterERC20;
        claimERC20 = deco.claimAdapterERC20;
    });

    addSnapshotBeforeRestoreAfterEach();

    describe("#setup", async () => {
        beforeEach(async () => {
        });

        it("happy path works", async () => {
        });
    });

    describe("when a zero token is deployed from zero erc20 adapter", async () => {
        let zeroClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(zeroERC20.address, true); // user approves zero erc20 adapter contract address
        });

        it("should deploy token contract", async () => {
            await expect(zeroERC20.deployToken(t5)).to.emit(zeroERC20, 'NewZeroToken'); // token deployed
        });

        it("should set class value for deployed token address", async () => {
            await zeroERC20.deployToken(t5); // deploy token
            let tokenAddress = await zeroERC20.tokens(zeroClass);
            expect(tokenAddress).to.not.eq(bn(0)); //token address set for class value
            
            let zeroToken = ERC20__factory.connect(tokenAddress, owner.signer);
            expect(await zeroToken.totalSupply()).to.be.eq(bn(0));
        });

        it("should assign correct token name", async () => {
            await zeroERC20.deployToken(t5); // deploy token
            let zeroToken = ERC20__factory.connect(await zeroERC20.tokens(zeroClass), owner.signer);

            let expectedZeroTokenName = "ZERO-Y"+" "+t5.toString();
            expect(await zeroToken.name()).to.be.eq(expectedZeroTokenName);
        });

        it("should fail if token is already deployed", async () => {
            await zeroERC20.deployToken(t5); // deploy token

            let deployTokenResponse = zeroERC20.deployToken(t5); // try deploying again
            await expect(deployTokenResponse).to.be.revertedWith("zero/token-exists");
        });

        it("should allow any address to deploy a token", async () => {
            await expect(zeroERC20.connect(walletOne.signer).deployToken(t5)).to.emit(zeroERC20, 'NewZeroToken'); // token deployed
        });
    });
    

    describe("when a core zero balance is converted to token balance", async () => {
        let zeroClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(zeroERC20.address, true); // user approves zero erc20 adapter contract address
        });

        it("should fail if token not deployed", async () => {
            let zeroExitResponse = zeroERC20.exit(owner.address, owner.address, zeroClass, wad(123));
            await expect(zeroExitResponse).to.be.revertedWith("zero/token-not-deployed");
        });

        it("should fail if balance is not sufficient", async () => {
            await zeroERC20.deployToken(t5); // deploy token

            let zeroExitResponse = zeroERC20.exit(owner.address, owner.address, zeroClass, wad(10001)); // 1 more than balance present
            await expect(zeroExitResponse).to.be.revertedWith("zBal/insufficient-balance");
        });

        it("should fail if address is not approved", async () => {
            await zeroERC20.deployToken(t5); // deploy token

            // walletOne not approved by owner in core
            let zeroExitResponse = zeroERC20.connect(walletOne.signer).exit(owner.address, owner.address, zeroClass, wad(123));
            await expect(zeroExitResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should move balance from user to adapter contract", async () => {
            await zeroERC20.deployToken(t5); // deploy token
            await zeroERC20.exit(owner.address, owner.address, zeroClass, wad(2500)); // exit balance

            let userBal = await core.zBal(owner.address, zeroClass);
            let adapterBal = await core.zBal(zeroERC20.address, zeroClass);
            expect(userBal).to.be.eq(wad(7500)); // remaining balance
            expect(adapterBal).to.be.eq(wad(2500)); // balance now held by adapter
        });

        it("should give user the token balance", async () => {
            await zeroERC20.deployToken(t5); // deploy token
            let zeroToken = ERC20__factory.connect(await zeroERC20.tokens(zeroClass), owner.signer);
            
            await zeroERC20.exit(owner.address, walletOne.address, zeroClass, wad(2500)); // exit balance
            expect(await zeroToken.balanceOf(walletOne.address)).to.be.eq(wad(2500));
        });

        it("should allow approved user to move balance", async () => {
            await zeroERC20.deployToken(t5); // deploy token
            let zeroToken = ERC20__factory.connect(await zeroERC20.tokens(zeroClass), walletOne.signer);
            
            await core.approve(walletOne.address, true); // owner approves walletOne
            await zeroERC20.connect(walletOne.signer).exit(owner.address, owner.address, zeroClass, wad(2500)); // exit balance
            
            expect(await zeroToken.balanceOf(owner.address)).to.be.eq(wad(2500));
        });
    });
    
    
    describe("when a token balance is converted to core balance", async () => {
        let zeroClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            zeroClass = ethers.utils.solidityKeccak256(["uint256"], [t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(zeroERC20.address, true); // user approves zero erc20 adapter contract address

            await zeroERC20.deployToken(t5); // deploy token
            await zeroERC20.exit(owner.address, owner.address, zeroClass, wad(2500)); // exit balance, owner has zero token balance now
        });

        it("should fail if address is not approved", async () => {
            // walletOne not approved by owner in core
            let zeroJoinResponse = zeroERC20.connect(walletOne.signer).join(owner.address, owner.address, zeroClass, wad(123));
            await expect(zeroJoinResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if balance is not sufficient", async () => {
            let zeroJoinResponse = zeroERC20.join(owner.address, owner.address, zeroClass, wad(2501)); // 1 more than balance present
            await expect(zeroJoinResponse).to.be.revertedWith("insufficient-balance");
        });

        it("should fail if token and balance do not exist", async () => {
            let t6 = t5.add(ONE_DAY_IN_SECONDS);
            let newZeroClass = ethers.utils.solidityKeccak256(["uint256"], [t6]);

            let zeroJoinResponse = zeroERC20.join(owner.address, owner.address, newZeroClass, wad(123));
            await expect(zeroJoinResponse).to.be.revertedWith("zero/token-not-deployed");
        });

        it("should reduce token balance", async () => {
            let zeroToken = ERC20__factory.connect(await zeroERC20.tokens(zeroClass), owner.signer);
            
            await zeroERC20.join(owner.address, owner.address, zeroClass, wad(2000)); // join balance
            expect(await zeroToken.balanceOf(owner.address)).to.be.eq(wad(500)); // 2500 - 2000 = 500
        });

        it("should move balance from adapter to user", async () => {
            await zeroERC20.join(owner.address, owner.address, zeroClass, wad(2500)); // join entire balance

            let userBal = await core.zBal(owner.address, zeroClass);
            let adapterBal = await core.zBal(zeroERC20.address, zeroClass);
            expect(userBal).to.be.eq(wad(10000)); // remaining balance
            expect(adapterBal).to.be.eq(wad(0)); // balance now held by adapter
        });

        it("should allow approved user to move balance from adapter to user", async () => {
            await core.approve(walletOne.address, true); // owner approves walletOne
            await zeroERC20.connect(walletOne.signer).join(owner.address, owner.address, zeroClass, wad(2500)); // join entire balance

            let userBal = await core.zBal(owner.address, zeroClass);
            let adapterBal = await core.zBal(zeroERC20.address, zeroClass);
            expect(userBal).to.be.eq(wad(10000)); // remaining balance
            expect(adapterBal).to.be.eq(wad(0)); // balance now held by adapter
        });
    });

    describe("when a claim token is deployed from claim erc20 adapter", async () => {
        let claimClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(claimERC20.address, true); // user approves claim erc20 adapter contract address
        });

        it("should deploy token contract", async () => {
            await expect(claimERC20.deployToken(t0,t5)).to.emit(claimERC20, 'NewClaimToken'); // token deployed
        });

        it("should set class value for deployed token address", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token
            let tokenAddress = await claimERC20.tokens(claimClass);
            expect(tokenAddress).to.not.eq(bn(0)); //token address set for class value
            
            let claimToken = ERC20__factory.connect(tokenAddress, owner.signer);
            expect(await claimToken.totalSupply()).to.be.eq(bn(0));
        });

        it("should assign correct token name", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token
            let claimToken = ERC20__factory.connect(await claimERC20.tokens(claimClass), owner.signer);

            let expectedClaimTokenName = "CLAIM-Y"+" "+t0.toString()+" "+t5.toString();
            expect(await claimToken.name()).to.be.eq(expectedClaimTokenName);
        });

        it("should fail if token is already deployed", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token

            let deployTokenResponse = claimERC20.deployToken(t0,t5); // try deploying again
            await expect(deployTokenResponse).to.be.revertedWith("claim/token-exists");
        });

        it("should allow any address to deploy a token", async () => {
            await expect(claimERC20.connect(walletOne.signer).deployToken(t0,t5)).to.emit(claimERC20, 'NewClaimToken'); // token deployed
        });
    });
    

    describe("when a core claim balance is converted to token balance", async () => {
        let claimClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(claimERC20.address, true); // user approves claim erc20 adapter contract address
        });

        it("should fail if token not deployed", async () => {
            let claimExitResponse = claimERC20.exit(owner.address, owner.address, claimClass, wad(123));
            await expect(claimExitResponse).to.be.revertedWith("claim/token-not-deployed");
        });

        it("should fail if balance is not sufficient", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token

            let claimExitResponse = claimERC20.exit(owner.address, owner.address, claimClass, wad(10001)); // 1 more than balance present
            await expect(claimExitResponse).to.be.revertedWith("cBal/insufficient-balance");
        });

        it("should fail if address is not approved", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token

            // walletOne not approved by owner in core
            let claimExitResponse = claimERC20.connect(walletOne.signer).exit(owner.address, owner.address, claimClass, wad(123));
            await expect(claimExitResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should move balance from user to adapter contract", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token
            await claimERC20.exit(owner.address, owner.address, claimClass, wad(2500)); // exit balance

            let userBal = await core.cBal(owner.address, claimClass);
            let adapterBal = await core.cBal(claimERC20.address, claimClass);
            expect(userBal).to.be.eq(wad(7500)); // remaining balance
            expect(adapterBal).to.be.eq(wad(2500)); // balance now held by adapter
        });

        it("should give user the token balance", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token
            let claimToken = ERC20__factory.connect(await claimERC20.tokens(claimClass), owner.signer);
            
            await claimERC20.exit(owner.address, walletOne.address, claimClass, wad(2500)); // exit balance
            expect(await claimToken.balanceOf(walletOne.address)).to.be.eq(wad(2500));
        });

        it("should allow approved user to move balance", async () => {
            await claimERC20.deployToken(t0,t5); // deploy token
            let claimToken = ERC20__factory.connect(await claimERC20.tokens(claimClass), walletOne.signer);
            
            await core.approve(walletOne.address, true); // owner approves walletOne
            await claimERC20.connect(walletOne.signer).exit(owner.address, owner.address, claimClass, wad(2500)); // exit balance
            
            expect(await claimToken.balanceOf(owner.address)).to.be.eq(wad(2500));
        });
    });
    
    
    describe("when a token balance is converted to core balance", async () => {
        let claimClass: string;
        let t0: BigNumber;
        let t5: BigNumber;

        beforeEach(async () => {
            // mint some token balance
            await token.mint(owner.address, wad(10000));
            await token.approve(core.address, MAX_UINT_256);

            // issuance
            t0 = await getLastBlockTimestamp();

            await core.insert(t0, toFrac(0.9));
            t5 = t0.add(ONE_DAY_IN_SECONDS.mul(5));

            claimClass = ethers.utils.solidityKeccak256(["uint256", "uint256"], [t0, t5]);

            await increaseTimeAsync(ONE_DAY_IN_SECONDS); // 1 day
            await core.issue(owner.address, t0, t5, wad(9000)); // owner now has 10000 Zero and Claim balance
            await core.approve(claimERC20.address, true); // user approves claim erc20 adapter contract address

            await claimERC20.deployToken(t0,t5); // deploy token
            await claimERC20.exit(owner.address, owner.address, claimClass, wad(2500)); // exit balance, owner has claim token balance now
        });

        it("should fail if address is not approved", async () => {
            // walletOne not approved by owner in core
            let claimJoinResponse = claimERC20.connect(walletOne.signer).join(owner.address, owner.address, claimClass, wad(123));
            await expect(claimJoinResponse).to.be.revertedWith("user/not-authorized");
        });

        it("should fail if balance is not sufficient", async () => {
            let claimJoinResponse = claimERC20.join(owner.address, owner.address, claimClass, wad(2501)); // 1 more than balance present
            await expect(claimJoinResponse).to.be.revertedWith("insufficient-balance");
        });

        it("should fail if token and balance do not exist", async () => {
            let t6 = t5.add(ONE_DAY_IN_SECONDS);
            let newClaimClass = ethers.utils.solidityKeccak256(["uint256"], [t6]);

            let claimJoinResponse = claimERC20.join(owner.address, owner.address, newClaimClass, wad(123));
            await expect(claimJoinResponse).to.be.revertedWith("claim/token-not-deployed");
        });

        it("should reduce token balance", async () => {
            let claimToken = ERC20__factory.connect(await claimERC20.tokens(claimClass), owner.signer);
            
            await claimERC20.join(owner.address, owner.address, claimClass, wad(2000)); // join balance
            expect(await claimToken.balanceOf(owner.address)).to.be.eq(wad(500)); // 2500 - 2000 = 500
        });

        it("should move balance from adapter to user", async () => {
            await claimERC20.join(owner.address, owner.address, claimClass, wad(2500)); // join entire balance

            let userBal = await core.cBal(owner.address, claimClass);
            let adapterBal = await core.cBal(claimERC20.address, claimClass);
            expect(userBal).to.be.eq(wad(10000)); // remaining balance
            expect(adapterBal).to.be.eq(wad(0)); // balance now held by adapter
        });

        it("should allow approved user to move balance from adapter to user", async () => {
            await core.approve(walletOne.address, true); // owner approves walletOne
            await claimERC20.connect(walletOne.signer).join(owner.address, owner.address, claimClass, wad(2500)); // join entire balance

            let userBal = await core.cBal(owner.address, claimClass);
            let adapterBal = await core.cBal(claimERC20.address, claimClass);
            expect(userBal).to.be.eq(wad(10000)); // remaining balance
            expect(adapterBal).to.be.eq(wad(0)); // balance now held by adapter
        });
    });
});
