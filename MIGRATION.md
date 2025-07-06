# Migration Guide

## BlobFeeOracle
- Constructor now `BlobFeeOracle(address[] signers, uint256 minSigners)`.
- New `push(FeedMsg, bytes[])` requires EIP-712 signatures from at least `minSigners` addresses.

## Off-chain Oracle Bot
- Replace feedA/B with `daemon/oracleBot.ts`.
- Configure `.env` with `ORACLE_KEYS` (comma separated private keys) used for signing.

Run the bot with `pnpm ts-node daemon/oracleBot.ts`.
