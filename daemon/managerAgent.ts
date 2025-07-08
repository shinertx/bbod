import fs from "fs";
import { spawn, ChildProcessWithoutNullStreams } from "child_process";
import cron from "node-cron";
import fsWatcher from "fs";
import pm2 from "pm2";

interface AgentSpec {
  name: string;
}

let spec: { agents: AgentSpec[] } = JSON.parse(fs.readFileSync("config/agents.json", "utf8"));

// Map agent names to their launch commands.
function commandFor(name: string): string[] | null {
  switch (name) {
    case "OracleFeeder_Agent":
      return ["pnpm", "ts-node", "daemon/oracleBot.ts"];
    case "BlobDaemon_Agent":
      return ["pnpm", "ts-node", "daemon/blobDaemon.ts"];
    case "CommitReveal_Agent":
      return ["pnpm", "ts-node", "bots/commitRevealBot.ts"];
    case "ThresholdManager_Agent":
      return ["pnpm", "ts-node", "bots/thresholdBot.ts"];
    case "SeedLiquidity_Agent":
      return ["pnpm", "ts-node", "bots/seedBot.ts"];
    case "IVTuning_Agent":
      return ["pnpm", "ts-node", "bots/ivBot.ts"];
    case "WSBridge_Agent":
      return ["pnpm", "ts-node", "daemon/wsBridge.ts"];
    case "Settlement_Agent":
      return ["pnpm", "ts-node", "bots/settleBot.ts"];
    default:
      return null;
  }
}

const children: Record<string, ChildProcessWithoutNullStreams> = {};

function startAgent(name: string) {
  const cmd = commandFor(name);
  if (!cmd) return;

  const child = spawn(cmd[0], cmd.slice(1), { stdio: "inherit" });
  children[name] = child;

  child.on("exit", (code) => {
    console.error(`[Manager] ${name} exited with code ${code}. Restarting in 5s…`);
    setTimeout(() => startAgent(name), 5_000);
  });
}

for (const a of spec.agents) {
  if (a.name === "Manager_Agent" || a.name === "Monitoring_Agent" || a.name === "CI_Agent" || a.name === "Deploy_Agent") continue;
  startAgent(a.name);
}

// ────────────────────────────────────────────────────────────
// Placeholder weekly key-rotation (Sunday 00:00) – stub logic
// ────────────────────────────────────────────────────────────
cron.schedule("0 0 * * 0", () => {
  console.log("[Manager] (stub) weekly key-rotation triggered – implement real logic here.");
});

console.log("Manager_Agent supervising", Object.keys(children).length, "agents…");

// Install pm2-logrotate module once at startup
pm2.connect((err) => {
  if (err) return;
  pm2.install("pm2-logrotate", () => {
    pm2.disconnect();
  });
});

// Live reload agents.json
fsWatcher.watch("config/agents.json", { persistent: false }, (_ev, _filename) => {
  try {
    const newSpec = JSON.parse(fs.readFileSync("config/agents.json", "utf8"));
    spec = newSpec;
    console.log("[Manager] Reloaded agent spec – restarting all agents…");
    for (const name in children) {
      children[name].kill();
    }
    for (const a of spec.agents) {
      if (a.name === "Manager_Agent" || a.name === "Monitoring_Agent" || a.name === "CI_Agent" || a.name === "Deploy_Agent") continue;
      startAgent(a.name);
    }
  } catch (err) {
    console.error("[Manager] Failed to reload agents.json", err);
  }
}); 