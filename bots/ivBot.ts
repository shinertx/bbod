import { ethers } from "ethers";
import "dotenv/config";

/*
 * ivBot – improved implied-volatility autopilot with circuit breakers
 * -----------------------------------------------------------------
 * Monitors blob fee volatility and adjusts pricing parameters with
 * safety mechanisms to prevent catastrophic mispricing during vol spikes.
 */

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const writer   = new ethers.Wallet(process.env.PRIV!, provider);

// Option desk owned by `writer`.
const desk = new ethers.Contract(
  process.env.BBOD!,
  [
    "function k() view returns(uint256)",
    "function setK(uint256) external", 
    "function pause(bool) external",
  ],
  writer
);

const oracle = new ethers.Contract(
  process.env.ORACLE!,
  ["function blobBaseFee() view returns(uint256)"],
  provider
);

// Circuit breaker constants
const MAX_K_CHANGE_PCT = 20; // Max 20% change per adjustment
const MIN_K = BigInt(1e12);   // Minimum k value
const MAX_K = BigInt(1e16);   // Maximum k value
const VOL_SPIKE_THRESHOLD = 5; // 5x normal vol triggers circuit breaker

let feeHistory: number[] = [];
let lastK = BigInt(0);
let circuitBreakerActive = false;

async function tick() {
  try {
    // Get current blob fee and track history
    const currentFee = await oracle.blobBaseFee();
    const feeGwei = Number(currentFee) / 1e9;
    
    feeHistory.push(feeGwei);
    if (feeHistory.length > 100) feeHistory.shift(); // Keep last 100 samples
    
    // Calculate realized volatility
    const volatility = calculateVolatility();
    
    // Circuit breaker: pause during extreme volatility
    if (volatility > VOL_SPIKE_THRESHOLD) {
      if (!circuitBreakerActive) {
        console.log(`⚠️ Circuit breaker activated: vol=${volatility}`);
        await desk.pause(true);
        circuitBreakerActive = true;
      }
      return;
    } else if (circuitBreakerActive && volatility < VOL_SPIKE_THRESHOLD * 0.5) {
      console.log(`✅ Circuit breaker deactivated: vol=${volatility}`);
      await desk.pause(false);
      circuitBreakerActive = false;
    }

    // Get current pricing parameter
    const currentK: bigint = await desk.k();
    if (lastK === BigInt(0)) lastK = currentK;
    
    // Adaptive pricing based on realized volatility  
    const targetK = calculateTargetK(volatility, feeGwei);
    
    // Apply position sizing to limit risk
    const maxChange = currentK * BigInt(MAX_K_CHANGE_PCT) / BigInt(100);
    let delta = targetK - currentK;
    
    // Clamp delta to maximum allowed change
    if (delta > maxChange) delta = maxChange;
    if (delta < -maxChange) delta = -maxChange;
    
    const nextK = currentK + delta;
    
    // Safety bounds check
    const boundedK = nextK < MIN_K ? MIN_K : (nextK > MAX_K ? MAX_K : nextK);
    
    if (boundedK !== currentK && Math.abs(Number(boundedK - currentK)) > Number(currentK) * 0.01) {
      const tx = await desk.setK(boundedK);
      console.log(`📊 setK(${boundedK}) vol=${volatility.toFixed(2)} → ${tx.hash}`);
      lastK = boundedK;
    }

  } catch (err) {
    console.error("ivBot error:", err);
  }
}

function calculateVolatility(): number {
  if (feeHistory.length < 10) return 0;
  
  // Calculate returns
  const returns: number[] = [];
  for (let i = 1; i < feeHistory.length; i++) {
    if (feeHistory[i-1] > 0) {
      returns.push(Math.log(feeHistory[i] / feeHistory[i-1]));
    }
  }
  
  if (returns.length === 0) return 0;
  
  // Calculate standard deviation of returns
  const mean = returns.reduce((a, b) => a + b, 0) / returns.length;
  const variance = returns.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / returns.length;
  
  return Math.sqrt(variance) * Math.sqrt(365 * 24 * 60 / 12); // Annualized volatility
}

function calculateTargetK(volatility: number, currentFee: number): bigint {
  // Base k value
  const baseK = BigInt(7e15);
  
  // Adjust based on volatility (higher vol = higher premiums)
  const volAdjustment = Math.max(0.5, Math.min(3.0, volatility / 2.0));
  
  // Adjust based on current fee level (higher fees = higher premiums)
  const feeAdjustment = Math.max(0.8, Math.min(2.0, currentFee / 100));
  
  return BigInt(Math.floor(Number(baseK) * volAdjustment * feeAdjustment));
}

// Run every 2 minutes (less aggressive than original)
setInterval(tick, 120_000);
console.log("🤖 Enhanced ivBot with circuit breakers running…"); 