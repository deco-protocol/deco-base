import { Signer, BigNumber } from "ethers";
import { Address } from "../types";

export default class DeploySplit {
  private _deployerSigner: Signer;

  constructor(deployerSigner: Signer) {
    this._deployerSigner = deployerSigner;
  }
}
