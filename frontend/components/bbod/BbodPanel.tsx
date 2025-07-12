"use client";

import { useBbod } from "@/hooks/useBbod";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BbodBuy } from "./BbodBuy";
import { BbodExercise } from "./BbodExercise";

export function BbodPanel() {
  const { options, exercise, isLoading, error } = useBbod();

  if (isLoading) return <div>Loading BBOD options...</div>;
  if (error) return <div>Error loading options: {error.message}</div>;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Blob Option Desk (BBOD)</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h3 className="font-bold mb-2">Available Options</h3>
            <div className="space-y-4">
              {options.map((option) => (
                <div key={option.id} className="p-4 border rounded">
                  <p>ID: {option.id}</p>
                  <p>Strike: {option.strike.toString()}</p>
                  <p>Premium: {option.premium.toString()}</p>
                  <p>Expiry: {new Date(Number(option.expiry) * 1000).toLocaleString()}</p>
                </div>
              ))}
            </div>
          </div>
          <div className="space-y-6">
            <BbodBuy />
            <BbodExercise exercise={exercise} />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
