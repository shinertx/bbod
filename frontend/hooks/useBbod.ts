"use client";

import { useState, useEffect, useCallback } from "react";
import { useAccount } from "wagmi";
import { readContract, writeContract } from "@wagmi/core";
import { bbodContract } from "@/lib/contracts";
import { config } from "@/components/Web3Provider"; // Corrected import path
import { formatEther, parseEther } from "viem";

export interface OptionSeries {
  id: bigint;
  writer: `0x${string}`;
  strike: bigint;
  cap: bigint;
  expiry: bigint;
  sold: bigint;
  payoutPerUnit: bigint;
  margin: bigint;
  paidOut: boolean;
  premium: bigint;
  userBalance: bigint;
}

export const useBbod = () => {
  const { address: account } = useAccount();

  const [options, setOptions] = useState<OptionSeries[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchOptions = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const fetchedOptions: OptionSeries[] = [];
      // This is just an example, you might need a better way to discover series IDs
      for (let i = 0; i < 20; i++) {
        try {
          const id = BigInt(i);
          const seriesResult = await readContract(config, {
            ...bbodContract,
            functionName: "series",
            args: [id],
          });

          const [writer, strike, cap, expiry, sold, payoutPerUnit, margin, paidOut] = seriesResult;

          if (writer && writer !== "0x0000000000000000000000000000000000000000" && Number(expiry) > Date.now() / 1000) {
            const premiumData = await readContract(config, {
              ...bbodContract,
              functionName: "premium",
              args: [strike, expiry],
            });

            const userBalanceData = account
              ? await readContract(config, {
                  ...bbodContract,
                  functionName: "bal",
                  args: [account, id],
                })
              : BigInt(0);

            fetchedOptions.push({
              id,
              writer,
              strike,
              cap,
              expiry,
              sold,
              payoutPerUnit,
              margin,
              paidOut,
              premium: premiumData,
              userBalance: userBalanceData,
            });
          }
        } catch (e) {
          // This can happen if a series ID doesn't exist. We can ignore it and continue.
          // console.warn(`Could not fetch series ${i}:`, e);
        }
      }
      setOptions(fetchedOptions);
    } catch (e: any) {
      console.error("Failed to fetch BBOD options:", e);
      setError(e);
    } finally {
      setIsLoading(false);
    }
  }, [account]);

  const refetch = useCallback(() => {
    fetchOptions();
  }, [fetchOptions]);

  useEffect(() => {
    fetchOptions();
  }, [fetchOptions]);

  const buy = useCallback(
    async (id: bigint, num: bigint, premium: bigint) => {
      if (!account) {
        setError(new Error("Wallet not connected"));
        return;
      }

      try {
        const { hash } = await writeContract(config, {
          ...bbodContract,
          functionName: "buy",
          args: [id, num],
          value: premium * num,
        });
        return { hash };
      } catch (e: any) {
        console.error("Failed to buy BBOD options:", e);
        setError(e);
        throw e; // re-throw for the component to catch
      }
    },
    [account]
  );

  const exercise = useCallback(
    async (id: bigint) => {
      if (!account) {
        setError(new Error("Wallet not connected"));
        return;
      }

      try {
        const { hash } = await writeContract(config, {
          ...bbodContract,
          functionName: "exercise",
          args: [id],
        });
        return { hash };
      } catch (e: any) {
        console.error("Failed to exercise BBOD options:", e);
        setError(e);
        throw e; // re-throw for the component to catch
      }
    },
    [account]
  );

  return { options, isLoading, error, buy, exercise, refetch };
};
