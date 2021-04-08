import { ContractTransaction, Signer, BigNumber, providers } from "ethers";

import DeployHelper from "../deploys";
import { ether, ProtocolUtils } from "../common";
import { Address } from "../types";
import { MAX_UINT_256 } from "../constants";

import { smoddit, ModifiableContract } from "@eth-optimism/smock";
export class SplitFixture {
  private _provider: providers.Web3Provider | providers.JsonRpcProvider;
  private _ownerAddress: Address;
  private _ownerSigner: Signer;
  private _deployer: DeployHelper;

  constructor(provider: providers.Web3Provider | providers.JsonRpcProvider, ownerAddress: Address) {
    this._provider = provider;
    this._ownerAddress = ownerAddress;
    this._ownerSigner = provider.getSigner(ownerAddress);
    this._deployer = new DeployHelper(this._ownerSigner);
  }

  public async initialize(cvpa: Address): Promise<void> {

  }
}
