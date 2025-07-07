import { spawn } from 'child_process';
import { ethers } from 'ethers';

async function main() {
  const anvil = spawn('anvil', ['--silent']);
  await new Promise(r => setTimeout(r, 1000));

  const provider = new ethers.JsonRpcProvider('http://127.0.0.1:8545');
  const pk = '0x59c6995e998f97a5a0044976f9d7a64c7e2d7e02b9c77b7360a115b65b1d05b1';
  const wallet = new ethers.Wallet(pk, provider);

  const oracleJson = require('../../out/BlobFeeOracle.sol/BlobFeeOracle.json');
  const factory = new ethers.ContractFactory(oracleJson.abi, oracleJson.bytecode, wallet);
  const oracle = await factory.deploy([wallet.address], 1);
  await oracle.waitForDeployment();

  const domain = {
    name: 'BlobFeeOracle',
    version: '1',
    chainId: 31337,
    verifyingContract: oracle.target as string,
  };
  const types = { FeedMsg: [{ name: 'fee', type: 'uint256' }, { name: 'deadline', type: 'uint256' }] };
  const message = { fee: 42, deadline: Math.floor(Date.now() / 1000) + 30 };
  const sig = await wallet.signTypedData(domain, types, message);
  await oracle.push(message, [sig]);

  const stored = await oracle.lastFee();
  if (stored !== 42n) throw new Error('push failed');
  console.log('integration push OK');

  anvil.kill();
}

main().catch((e)=>{ console.error(e); process.exit(1); });
