"use client";

import { useReadContract } from "wagmi";
import { bspContract } from "@/lib/contracts";
import { BspRoundInfo, BspRoundInfoProps } from "./BspRoundInfo";
import { BspActions } from "./BspActions";
import { useEffect, useState } from "react";

export type RoundStatus = "OPEN" | "REVEAL" | "SETTLEMENT" | "SETTLED" | "LOADING";

export function BspPanel() {
  const { data: commitRound, isLoading: isLoadingCommitRound } = useReadContract({
    ...bspContract,
    functionName: "commitRound",
    query: {
        refetchInterval: 5000,
    }
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

  const [status, setStatus] = useState<RoundStatus>("LOADING");

  useEffect(() => {
    if (isLoadingCommitRound || isLoadingRoundData) {
        setStatus("LOADING");
        return;
    }
    if (roundData) {
        const [, closeTs, revealTs, , , , , , , , , , settled, ] = roundData;
        const closeDate = new Date(Number(closeTs) * 1000);
        const revealDate = new Date(Number(revealTs) * 1000);
        const now = new Date();

        if (settled) {
            setStatus("SETTLED");
        } else if (now > revealDate) {
            setStatus("SETTLEMENT");
        } else if (now > closeDate) {
            setStatus("REVEAL");
        } else {
            setStatus("OPEN");
        }
    }
  }, [roundData, isLoadingCommitRound, isLoadingRoundData]);

  if (isLoadingCommitRound) {
    return <div className="bg-gray-800 p-6 rounded-lg"><p>Loading current round...</p></div>;
  }

  if (isLoadingRoundData) {
    return <div className="bg-gray-800 p-6 rounded-lg"><p>Loading round data...</p></div>;
  }

  if (error) {
    return <div className="bg-gray-800 p-6 rounded-lg"><p className="text-red-500">Error loading round data: {error.shortMessage || error.message}</p></div>
  }

  if (!roundData) {
    return <div className="bg-gray-800 p-6 rounded-lg"><p>No round data available for round {commitRound?.toString()}.</p></div>;
  }

  return (
    <div className="flex-1 bg-gray-800 p-6 rounded-lg flex flex-col gap-4">
        <h2 className="text-xl font-semibold mb-4 text-center">
            Hourly Parimutuel (BSP)
        </h2>
        <BspRoundInfo roundData={roundData} status={status} />
        <BspActions roundData={roundData} status={status} />
    </div>
  );
}
