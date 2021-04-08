import { Signer } from "ethers";

import DeploySplit from "./deploySplit";

export default class DeployHelper {
  public swap: DeploySplit;

  constructor(deployerSigner: Signer) {
    this.swap = new DeploySplit(deployerSigner);
  }
}
