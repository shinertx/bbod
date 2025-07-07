import axios from "axios";
import { IncomingWebhook } from "@slack/webhook";

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || "http://prometheus:9090";
const SLACK_WEBHOOK = process.env.SLACK_WEBHOOK || "";
const webhook = SLACK_WEBHOOK ? new IncomingWebhook(SLACK_WEBHOOK) : null;

async function checkHealth() {
  try {
    await axios.get(`${PROMETHEUS_URL}/-/healthy`, { timeout: 5_000 });
    console.log("[Monitoring] Prometheus healthy ✅");
  } catch (err) {
    const msg = `[Monitoring] Prometheus health check FAILED: ${(err as Error).message}`;
    console.error(msg);
    if (webhook) {
      await webhook.send({ text: msg });
    }
  }
}

setInterval(checkHealth, 30_000);
console.log("monitoringAgent running…"); 