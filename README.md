## Blob Edge Stack

* **BBOD** – Blob-Base fixed-strike call options  
* **BSP**  – Hourly HI/LO parimutuel blob-fee pools  

Deployable by a single EOA with ≤ 0.1 ETH gas & no off-chain trust.

### Quick start

```bash
git clone https://github.com/you/blob-edge-stack
cd blob-edge-stack
cp .env.example .env   # fill keys
foundryup
npm i
forge test -vv
forge script script/Deploy.s.sol --fork-url $RPC --broadcast --private-key $PRIV
node daemon/blobDaemon.ts
```
