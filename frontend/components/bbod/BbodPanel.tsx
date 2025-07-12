"use client";

import { useBbod } from "@/hooks/useBbod";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BbodBuy } from "./BbodBuy";
import { BbodExercise } from "./BbodExercise";
import { formatUnits, formatEther } from "viem";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Terminal } from "lucide-react";

export function BbodPanel() {
  const { options, isLoading, error, buy, exercise, refetch } = useBbod();

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Blob Option Desk (BBOD)</CardTitle>
        </CardHeader>
        <CardContent>
          <p>Loading BBOD options...</p>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Blob Option Desk (BBOD)</CardTitle>
        </CardHeader>
        <CardContent>
          <Alert variant="destructive">
            <Terminal className="h-4 w-4" />
            <AlertTitle>Error</AlertTitle>
            <AlertDescription>
              Failed to load BBOD options: {error.message}
            </AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    );
  }

  const activeOptions = options.filter(
    (o) => Number(o.expiry) * 1000 > Date.now()
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Blob Option Desk (BBOD)</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold mb-2">
              Available Options to Buy
            </h3>
            <div className="space-y-4 max-h-96 overflow-y-auto pr-2">
              {activeOptions.length > 0 ? (
                activeOptions.map((option) => (
                  <div
                    key={option.id.toString()}
                    className="p-4 border rounded-lg"
                  >
                    <p className="font-mono text-sm">
                      Series ID: {option.id.toString()}
                    </p>
                    <p>Strike: {formatUnits(option.strike, 9)} gwei</p>
                    <p>Premium: {formatEther(option.premium)} ETH</p>
                    <p>
                      Expiry:{" "}
                      {new Date(Number(option.expiry) * 1000).toLocaleString()}
                    </p>
                    <p>
                      Available:{" "}
                      {formatUnits(option.cap - option.sold, 0)}
                    </p>
                  </div>
                ))
              ) : (
                <p>No active options available at the moment.</p>
              )}
            </div>
          </div>
          <div className="space-y-6">
            <BbodBuy options={activeOptions} buy={buy} refetch={refetch} />
            <BbodExercise />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
