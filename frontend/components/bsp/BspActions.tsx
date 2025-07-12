"use client";

import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { BspRoundData, BspRoundInfoProps } from "./BspRoundInfo";
import { parseEther, keccak256, toHex, zeroHash } from "viem";
import { useState, useEffect } from "react";
import { bspContract } from "@/lib/contracts";

export function BspActions({ roundData, status }: BspRoundInfoProps) {
    const { address } = useAccount();
    const { data: hash, writeContract, isPending, error } = useWriteContract();
    const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

    const [amount, setAmount] = useState("");
    const [side, setSide] = useState<0 | 1>(0); // 0 for HI, 1 for LO
    const [salt, setSalt] = useState<`0x${string}`>(zeroHash);

    useEffect(() => {
        // Generate a new random salt whenever the component loads for a new round
        setSalt(keccak256(toHex(Math.random().toString())));
    }, [roundData[0]]); // Dependency on round ID

    const handleCommit = () => {
        if (!address) {
            alert("Please connect your wallet first.");
            return;
        }
        const commitHash = keccak256(
            toHex(address + side.toString() + salt.slice(2))
        );

        writeContract({
            ...bspContract,
            functionName: "commit",
            args: [commitHash],
            value: parseEther(amount),
        });
    };

    const handleReveal = () => {
        writeContract({
            ...bspContract,
            functionName: "reveal",
            args: [side, salt],
        });
    };
    
    const handleSettle = () => {
        writeContract({
            ...bspContract,
            functionName: "settle",
            args: [],
        });
    };

    const handleClaim = () => {
        // This is a simplification. In a real app, you'd need to track user's salt and side per round.
        // We are using the current salt and side, which might not be correct for claiming past rounds.
        alert("Claiming requires tracking the specific salt used for your commit. This is a placeholder.");
        // writeContract({
        //     ...bspContract,
        //     functionName: "claim",
        //     args: [roundData[0], side, salt],
        // });
    };


    return (
        <div className="space-y-4 pt-4 border-t border-gray-700">
            {status === "OPEN" && (
                <div className="flex flex-col gap-2">
                    <select
                        value={side}
                        onChange={(e) => setSide(Number(e.target.value) as 0 | 1)}
                        className="bg-gray-700 border border-gray-600 rounded-md p-2 text-white"
                    >
                        <option value={0}>HI</option>
                        <option value={1}>LO</option>
                    </select>
                    <input
                        type="text"
                        placeholder="Amount in ETH"
                        value={amount}
                        onChange={(e) => setAmount(e.target.value)}
                        className="bg-gray-700 border border-gray-600 rounded-md p-2 text-white"
                    />
                    <button
                        onClick={handleCommit}
                        disabled={isPending || !amount}
                        className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-900 text-white font-bold py-2 px-4 rounded"
                    >
                        {isPending ? "Committing..." : "Commit"}
                    </button>
                </div>
            )}

            {status === "REVEAL" && (
                 <div className="flex flex-col gap-2">
                    <p className="text-center text-sm">Reveal your vote for round {roundData[0].toString()}.</p>
                    <p className="text-center text-xs text-gray-400">Ensure you use the same side and salt from your commit.</p>
                     <select
                        value={side}
                        onChange={(e) => setSide(Number(e.target.value) as 0 | 1)}
                        className="bg-gray-700 border border-gray-600 rounded-md p-2 text-white"
                    >
                        <option value={0}>HI</option>
                        <option value={1}>LO</option>
                    </select>
                    <input
                        type="text"
                        placeholder="Your secret salt (auto-generated)"
                        value={salt}
                        onChange={(e) => setSalt(e.target.value as `0x${string}`)}
                        className="bg-gray-700 border border-gray-600 rounded-md p-2 text-white"
                    />
                    <button
                        onClick={handleReveal}
                        disabled={isPending}
                        className="bg-green-600 hover:bg-green-700 disabled:bg-green-900 text-white font-bold py-2 px-4 rounded"
                    >
                        {isPending ? "Revealing..." : "Reveal"}
                    </button>
                </div>
            )}

            {status === "SETTLEMENT" && (
                <button
                    onClick={handleSettle}
                    disabled={isPending}
                    className="w-full bg-purple-600 hover:bg-purple-700 disabled:bg-purple-900 text-white font-bold py-2 px-4 rounded"
                >
                    {isPending ? "Settling..." : "Settle Round"}
                </button>
            )}

            {status === "SETTLED" && (
                 <button
                    onClick={handleClaim}
                    disabled={isPending}
                    className="w-full bg-yellow-500 hover:bg-yellow-600 disabled:bg-yellow-800 text-white font-bold py-2 px-4 rounded"
                >
                    {isPending ? "Claiming..." : "Claim Winnings"}
                </button>
            )}

            {hash && <div className="text-center text-xs text-gray-400">Transaction Hash: {hash}</div>}
            {isConfirming && <div className="text-center text-sm">Waiting for confirmation...</div>}
            {isConfirmed && <div className="text-center text-sm text-green-400">Transaction confirmed.</div>}
            {error && <div className="text-center text-sm text-red-500">{error.shortMessage || error.message}</div>}
        </div>
    );
}
