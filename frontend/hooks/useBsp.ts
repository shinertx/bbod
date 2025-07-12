"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { bspContract } from "@/lib/contracts";
import { parseEther, keccak256, Hex, encodePacked, formatEther } from "viem";

type CommittedInfo = {
  round: bigint;
  salt: Hex;
  side: string;
  amount: string;
  hash: Hex;
};

export function useBsp() {
  const { address } = useAccount();
  const [committedInfo, setCommittedInfo] = useState<CommittedInfo | null>(null);
  const { data: hash, error, isPending, writeContract } = useWriteContract();

  const storageKey = address ? `bsp-commit-${address}-${bspContract.address}` : null;

  useEffect(() => {
    if (storageKey) {
      const storedInfo = localStorage.getItem(storageKey);
      if (storedInfo) {
        const parsed = JSON.parse(storedInfo);
        parsed.round = BigInt(parsed.round);
        setCommittedInfo(parsed);
      } else {
        setCommittedInfo(null);
      }
    }
  }, [storageKey]);

  const { data: commitRound, isLoading: isLoadingCommitRound } = useReadContract({
    ...bspContract,
    functionName: "commitRound",
  });

  const { data: roundData, isLoading: isLoadingRoundData, error: roundError, refetch: refetchRoundData } = useReadContract({
    ...bspContract,
    functionName: "rounds",
    args: [commitRound ?? BigInt(0)],
    query: {
      enabled: !!commitRound,
      refetchInterval: 5000,
    },
  });

  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isConfirmed && committedInfo && storageKey) {
        // This is a bit tricky, we don't know which tx was confirmed.
        // For now, let's assume commit was the last one if we have a hash in committedInfo
        if(hash === committedInfo.hash) {
            localStorage.setItem(storageKey, JSON.stringify(committedInfo));
        }
    }
  }, [isConfirmed, committedInfo, storageKey, hash]);

  const handleCommit = (amount: string, side: string) => {
    if (!address || !commitRound) {
      alert("Please connect your wallet and wait for round data to load.");
      return;
    }

    const randomValues = new Uint8Array(32);
    window.crypto.getRandomValues(randomValues);
    const randomSalt = `0x${Buffer.from(randomValues).toString("hex")}` as Hex;

    const newCommitHash = keccak256(
      encodePacked(["address", "uint8", "bytes32"], [address, Number(side), randomSalt])
    );

    setCommittedInfo({ round: commitRound, salt: randomSalt, side, amount, hash: newCommitHash });

    writeContract({
      ...bspContract,
      functionName: "commit",
      args: [newCommitHash],
      value: parseEther(amount),
    });
  };

  const handleReveal = () => {
    if (!committedInfo) {
      alert("No commit information found.");
      return;
    }
    writeContract({
      ...bspContract,
      functionName: "reveal",
      args: [Number(committedInfo.side), committedInfo.salt],
    });
  };

  const handleClaim = () => {
    if (!committedInfo) {
      alert("No commit information found.");
      return;
    }
    writeContract({
      ...bspContract,
      functionName: "claim",
      args: [committedInfo.round, Number(committedInfo.side), committedInfo.salt],
    });
  };
  
  const clearCommitment = () => {
      if(storageKey) {
          localStorage.removeItem(storageKey);
          setCommittedInfo(null);
      }
  }

  return {
    address,
    commitRound,
    isLoadingCommitRound,
    roundData,
    isLoadingRoundData,
    roundError,
    refetchRoundData,
    handleCommit,
    handleReveal,
    handleClaim,
    isPending,
    isConfirming,
    isConfirmed,
    error,
    committedInfo,
    clearCommitment,
  };
}
