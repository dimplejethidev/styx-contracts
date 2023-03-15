import type { HardhatUserConfig, NetworkUserConfig } from "hardhat/types";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-truffle5";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "solidity-coverage";
import "dotenv/config";
import "hardhat-deploy";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
dotenv.config();

let deployer = process.env.DEPLOYER_PRIVATE_KEY as string;

if (!deployer) {
  console.warn("Please set your DEPLOYER in a .env file");
  // Hardhat account #0 - Do not use
  deployer =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
}

const RPC_URL = process.env.RPC_URL;
if (!RPC_URL) {
  throw new Error("Missing env variable `RPC_URL`");
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: RPC_URL,
      },
    },
    goerli: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      accounts: [deployer],
      chainId: 5,
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            // You should disable the optimizer when debugging
            // https://hardhat.org/hardhat-network/#solidity-optimizer-support
            enabled: true,
            runs: 99999,
          },
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: false,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
