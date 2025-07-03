# Automating BSP Threshold

Run `pnpm ts-node scripts/setThreshold.ts` after each settle to update the next round's threshold based on the latest blob fee. This can be scheduled via cron:
```
0 * * * * cd /app && pnpm ts-node scripts/setThreshold.ts >> logs/threshold.log
```
Ensure `RPC`, `PRIV`, and `BSP` are configured in the environment.
