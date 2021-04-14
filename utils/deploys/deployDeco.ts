import { Signer, BigNumber } from "ethers";
import { Address } from "../types";
import {
  bn
} from "@utils/index";

import { Core, ZeroAdapterERC20, ClaimAdapterERC20, ZeroAdapterERC721, ClaimAdapterERC721, ERC20, DSDeed } from "../contracts";
import {
  Core__factory,
  ZeroAdapterERC20__factory,
  ClaimAdapterERC20__factory,
  ZeroAdapterERC721__factory,
  ClaimAdapterERC721__factory,
  ERC20__factory,
  DSDeed__factory,
} from "../../typechain/";

export default class DeployDeco {
  private _deployerSigner: Signer;

  constructor(deployerSigner: Signer) {
    this._deployerSigner = deployerSigner;
  }

  public async deployToken(decimals: number): Promise<ERC20> {
    return await new ERC20__factory(this._deployerSigner).deploy(bn(99),"yDAI","YDAI","1",bn(decimals));
  }

  public async deployCore(token: Address): Promise<Core> {
    return await new Core__factory(this._deployerSigner).deploy(token);
  }

  public async deployZeroAdapterERC20(core: Address): Promise<ZeroAdapterERC20> {
    return await new ZeroAdapterERC20__factory(this._deployerSigner).deploy(bn(99), core);
  }
  
  public async deployClaimAdapterERC20(core: Address): Promise<ClaimAdapterERC20> {
    return await new ClaimAdapterERC20__factory(this._deployerSigner).deploy(bn(99), core);
  }

  public async deployZeroAdapterERC721(core: Address): Promise<ZeroAdapterERC721> {
    return await new ZeroAdapterERC721__factory(this._deployerSigner).deploy(core);
  }

  public async deployClaimAdapterERC721(core: Address): Promise<ClaimAdapterERC721> {
    return await new ClaimAdapterERC721__factory(this._deployerSigner).deploy(core);
  }

  public async deployDSDeed(name: string, symbol: string): Promise<DSDeed> {
    return await new DSDeed__factory(this._deployerSigner).deploy(name, symbol);
  }
}
