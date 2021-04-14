import { Signer } from "ethers";

import DeployDeco from "./deployDeco";

export default class DeployHelper {
  public deco: DeployDeco;

  constructor(deployerSigner: Signer) {
    this.deco = new DeployDeco(deployerSigner);
  }
}
