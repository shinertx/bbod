"use client";

import { useReadContract } from "wagmi";
import { bspContract } from "@/lib/contracts";
import { formatEther } from "viem";
import { useEffect, useState } from "react";

function Countdown({ to }: { to: Date }) {
    const [now, setNow] = useState(new Date());
    useEffect(() => {
        const timer = setInterval(() => setNow(new Date()), 1000);
        return () => clearInterval(timer);
    }, []);

    const diff = to.getTime() - now.getTime();
    if (diff <= 0) return <span>00:00:00</span>;

    const hours = Math.floor(diff / (1000 * 60 * 60)).toString().padStart(2, '0');
    const minutes = (Math.floor(diff / (1000 * 60)) % 60).toString().padStart(2, '0');
    const seconds = (Math.floor(diff / 1000) % 60).toString().padStart(2, '0');

    return <span>{hours}:{minutes}:{seconds}</span>;
}


export function BspRoundInfo() {
  const { data: commitRound, isLoading: isLoadingCommitRound } = useReadContract({
    ...bspContract,
    functionName: "commitRound",
  });

  const { data: roundData, isLoading: isLoadingRoundData, error } = useReadContract({
    ...bspContract,
    functionName: "rounds",
    args: [commitRound || BigInt(0)],
    query: {
        enabled: commitRound !== undefined,
        refetchInterval: 5000,
    }
  });

  if (isLoadingCommitRound) {
    return <p>Loading current round...</p>;
  }

  if (isLoadingRoundData) {
    return <p>Loading round data...</p>;
  }

  if (error) {
    return <p className="text-red-500">Error loading round data: {error.shortMessage || error.message}</p>
  }

  if (!roundData) {
    return <p>No round data available for round {commitRound?.toString()}.</p>;
  }

  const [id, closeTs, revealTs, settleTs, hiTotal, loTotal, totalCommits, winner, threshold, thresholdCommit, feeResult, settlePriceGwei, settled, bounty] = roundData;

  const closeDate = new Date(Number(closeTs) * 1000);
  const revealDate = new Date(Number(revealTs) * 1000);
  
  const now = new Date();
  let status = "OPEN";
  let timer: React.ReactNode = <Countdown to={closeDate} />;
  if (now > closeDate) {
      status = "REVEAL";
      timer = <Countdown to={revealDate} />;
  }
  if (now > revealDate) {
      status = "SETTLEMENT";
      timer = null;
  }
  if (settled) {
      status = "SETTLED";
      timer = null;
  }


  return (
    <div className="space-y-3 text-sm">
      <div className="flex justify-between items-center">
        <p><strong>Round:</strong> {id.toString()}</p>
        <p className={`px-2 py-1 text-xs font-bold rounded-full ${status === 'OPEN' ? 'bg-green-500' : status === 'REVEAL' ? 'bg-yellow-500' : 'bg-gray-500'}`}>{status}</p>
      </div>
      {timer && <div className="text-xl font-mono text-center py-2">{timer}</div>}
      <p><strong>Threshold:</strong> {formatEther(threshold)} gwei</p>
      <div className="grid grid-cols-2 gap-4 text-center">
        <div className="bg-gray-700 p-2 rounded">
            <p className="font-bold">HI</p>
            <p>{formatEther(hiTotal)} ETH</p>
        </div>
        <div className="bg-gray-700 p-2 rounded">
            <p className="font-bold">LO</p>
            <p>{formatEther(loTotal)} ETH</p>
        </div>
      </div>
      <p><strong>Total Commits:</strong> {totalCommits.toString()}</p>
      
      {settled && (
        <div className="pt-2 border-t border-gray-600">
            <p><strong>Winner:</strong> {winner === 0 ? "HI" : winner === 1 ? "LO" : "N/A"}</p>
            <p><strong>Settlement Price:</strong> {formatEther(settlePriceGwei)} gwei</p>
        </div>
      )}
    </div>
  );
}
