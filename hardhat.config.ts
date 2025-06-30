import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: "0.8.23",
  networks: {
    mainnet: { url: process.env.RPC!, accounts:[process.env.PRIV!] },
    sepolia: { url: process.env.RPC!, accounts:[process.env.PRIV!] }
  }
};
export default config; 