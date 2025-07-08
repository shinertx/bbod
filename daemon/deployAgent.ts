import { exec } from "child_process";
import client from "prom-client";
import fs from "fs";

const deployCounter = new client.Counter({ name: "deploy_attempt_total", help: "Number of deploy attempts" });
const deploySuccess = new client.Counter({ name: "deploy_success_total", help: "Successful deploys" });
client.collectDefaultMetrics();

/**
 * Simple trigger: if file DEPLOY_TRIGGER exists, run SafeDeploy.ts then delete file.
 */
function checkTrigger() {
  if (fs.existsSync("DEPLOY_TRIGGER")) {
    fs.unlinkSync("DEPLOY_TRIGGER");
    deployCounter.inc();
    console.log("[Deploy] Trigger detected – starting SafeDeploy");
    const p = exec("pnpm ts-node scripts/SafeDeploy.ts", (err, stdout, stderr) => {
      console.log(stdout);
      console.error(stderr);
      if (err) {
        console.error("[Deploy] failed", err);
      } else {
        deploySuccess.inc();
        console.log("[Deploy] success");
      }
    });
    p.stdout?.pipe(process.stdout);
    p.stderr?.pipe(process.stderr);
  }
}

setInterval(checkTrigger, 30_000);
console.log("deployAgent running – create DEPLOY_TRIGGER file to deploy.");

import http from "http";
const port = Number(process.env.METRICS_PORT || 9464);
http.createServer(async (_req, res) => {
  res.writeHead(200, { "Content-Type": client.register.contentType });
  res.end(await client.register.metrics());
}).listen(port, () => console.log(`[deployAgent] metrics on ${port}`)); 