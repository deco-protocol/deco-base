import { ContractTransaction, Signer, BigNumber, providers } from "ethers";

import DeployHelper from "../deploys";
import { ether, usdc, wad, ray, rad, ProtocolUtils } from "../common";
import { Address } from "../types";
import { MAX_UINT_256 } from "../constants";

import { Core, ZeroAdapterERC20, ClaimAdapterERC20, ZeroAdapterERC721, ClaimAdapterERC721, ERC20, DSDeed } from "../contracts";

import {
  getDecoFixture,
  addSnapshotBeforeRestoreAfterEach,
  increaseTimeAsync,
  getAccounts,
  getWaffleExpect,
  getRandomAccount,
  getRandomAddress,
  getTransactionTimestamp,
  getLastBlockTimestamp,
  preciseMul,
  impersonateAccount,
  getBlockchainUtils,
  bn
} from "@utils/index";

import { ethers } from "hardhat";

import { smoddit, ModifiableContract } from "@eth-optimism/smock";
export class DecoFixture {
  private _provider: providers.Web3Provider | providers.JsonRpcProvider;
  private _ownerAddress: Address;
  private _ownerSigner: Signer;
  private _deployer: DeployHelper;

  public token: ERC20;
  public core: Core;
  public zeroAdapterERC20: ZeroAdapterERC20;
  public claimAdapterERC20: ClaimAdapterERC20;
  public zeroAdapterERC721: ZeroAdapterERC721;
  public claimAdapterERC721: ClaimAdapterERC721;

  constructor(provider: providers.Web3Provider | providers.JsonRpcProvider, ownerAddress: Address) {
    this._provider = provider;
    this._ownerAddress = ownerAddress;
    this._ownerSigner = provider.getSigner(ownerAddress);
    this._deployer = new DeployHelper(this._ownerSigner);
  }

  public async initialize(decimals: number): Promise<void> {
    this.token = await this._deployer.deco.deployToken(decimals);
    this.core = await this._deployer.deco.deployCore(this.token.address);
    this.zeroAdapterERC20 = await this._deployer.deco.deployZeroAdapterERC20(this.core.address);
    this.claimAdapterERC20 = await this._deployer.deco.deployClaimAdapterERC20(this.core.address);
    this.zeroAdapterERC721 = await this._deployer.deco.deployZeroAdapterERC721(this.core.address);
    this.claimAdapterERC721 = await this._deployer.deco.deployClaimAdapterERC721(this.core.address);
  }
}
