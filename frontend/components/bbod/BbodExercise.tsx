"use client";

import { useState } from "react";
import { useBbod } from "@/hooks/useBbod";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useAccount } from "wagmi";
import { formatUnits } from "viem";

export function BbodExercise() {
  const { address } = useAccount();
  const { options, exercise, refetch, isLoading: isBbodLoading } = useBbod();
  const [selectedOptionId, setSelectedOptionId] = useState<string>("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  if (!address) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Exercise Options</CardTitle>
        </CardHeader>
        <CardContent>
          <p>Please connect your wallet to see your options to exercise.</p>
        </CardContent>
      </Card>
    );
  }

  const exercisableOptions = options.filter(
    (o) =>
      o.userBalance > 0 &&
      Number(o.expiry) * 1000 < Date.now() &&
      !o.paidOut
  );

  const handleExercise = async () => {
    if (!selectedOptionId) {
      setError("Please select an option to exercise.");
      return;
    }
    setIsLoading(true);
    setError("");
    setMessage("");
    try {
      await exercise(BigInt(selectedOptionId));
      setMessage("Successfully exercised your options. Payout should arrive shortly.");
      refetch(); // Refetch options to update the list
    } catch (e: any) {
      setError(e.message || "An error occurred during exercise.");
    } finally {
      setIsLoading(false);
      setSelectedOptionId("");
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Exercise Your Options</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Select
            onValueChange={setSelectedOptionId}
            value={selectedOptionId}
            disabled={isBbodLoading || exercisableOptions.length === 0}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select an expired option you own" />
            </SelectTrigger>
            <SelectContent>
              {isBbodLoading ? (
                <SelectItem value="loading" disabled>
                  Loading...
                </SelectItem>
              ) : exercisableOptions.length > 0 ? (
                exercisableOptions.map((option) => (
                  <SelectItem
                    key={option.id.toString()}
                    value={option.id.toString()}
                  >
                    {`ID: ${option.id} - Balance: ${formatUnits(
                      option.userBalance,
                      0
                    )}`}
                  </SelectItem>
                ))
              ) : (
                <SelectItem value="none" disabled>
                  No exercisable options found
                </SelectItem>
              )}
            </SelectContent>
          </Select>
        </div>
        <Button
          onClick={handleExercise}
          disabled={!selectedOptionId || isLoading || isBbodLoading}
          className="w-full"
        >
          {isLoading ? "Exercising..." : "Exercise Options"}
        </Button>
      </CardContent>
      <CardFooter className="flex flex-col items-start space-y-2">
        {message && <p className="text-green-600">{message}</p>}
        {error && <p className="text-red-600">{error}</p>}
      </CardFooter>
    </Card>
  );
}
