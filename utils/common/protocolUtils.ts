import { ethers, BigNumber, constants } from "ethers";

import { EMPTY_BYTES } from "../constants";
import { Address } from "../types";

const { AddressZero } = constants;

export class ProtocolUtils {
  public _provider: ethers.providers.Web3Provider | ethers.providers.JsonRpcProvider;

  constructor(_provider: ethers.providers.Web3Provider | ethers.providers.JsonRpcProvider) {
    this._provider = _provider;
  }
}
