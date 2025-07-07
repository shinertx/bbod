import fs from "fs";
import { spawn } from "child_process";

const spec = JSON.parse(fs.readFileSync("config/agents.json", "utf8"));

function run(cmd: string[], name: string) {
  const p = spawn(cmd[0], cmd.slice(1), { stdio: "inherit" });
  p.on("exit", (c) => console.log(`[${name}] exited →`, c));
}

for (const a of spec.agents) {
  switch (a.name) {
    case "OracleFeeder_Agent":
      run(["pnpm", "ts-node", "daemon/oracleBot.ts"], a.name);
      break;
    case "BlobDaemon_Agent":
      run(["pnpm", "ts-node", "daemon/blobDaemon.ts"], a.name);
      break;
    case "CommitReveal_Agent":
      run(["pnpm", "ts-node", "bots/commitRevealBot.ts"], a.name);
      break;
    case "ThresholdManager_Agent":
      run(["pnpm", "ts-node", "bots/thresholdBot.ts"], a.name);
      break;
    case "SeedLiquidity_Agent":
      run(["pnpm", "ts-node", "bots/seedBot.ts"], a.name);
      break;
    case "IVTuning_Agent":
      run(["pnpm", "ts-node", "bots/ivBot.ts"], a.name);
      break;
    case "WSBridge_Agent":
      run(["pnpm", "ts-node", "daemon/wsBridge.ts"], a.name);
      break;
    case "Settlement_Agent":
      run(["pnpm", "ts-node", "bots/settleBot.ts"], a.name);
      break;
    case "Monitoring_Agent":
      run(["pnpm", "ts-node", "daemon/monitoringAgent.ts"], a.name);
      break;
    case "Manager_Agent":
      run(["pnpm", "ts-node", "daemon/managerAgent.ts"], a.name);
      break;
    default:
      console.error("unknown agent", a.name);
  }
}
