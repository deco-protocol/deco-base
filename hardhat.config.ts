import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-solhint";
import "hardhat-typechain";
import "hardhat-deploy";
import "solidity-coverage";
import "@eth-optimism/smock/build/src/plugins/hardhat-storagelayout";

import { HardhatUserConfig } from 'hardhat/config'

const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

let mnemonic = process.env.MNEMONIC;
const accounts = {
  mnemonic,
};

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: 0,
  },
  solidity: {
    compilers: [
      { version: "0.7.6", settings: {} },
      {
        version: "0.5.12",
      },
    ],
  },
  networks: {
    hardhat: { accounts },
    localhost: {
      url: "http://localhost:8545",
      accounts,
    },
    coverage: {
      url: "http://127.0.0.1:8555", // Coverage launches its own ganache-cli client
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
