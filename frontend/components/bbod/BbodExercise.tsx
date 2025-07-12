"use client";

import { useState } from "react";
import { useBbod } from "@/hooks/useBbod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export function BbodExercise({ exerciseOptions }) {
  const { exercise } = useBbod();
  const [selectedOption, setSelectedOption] = useState(null);
  const [amount, setAmount] = useState("1");

  const handleExercise = () => {
    if (selectedOption) {
      exercise(selectedOption.id, BigInt(amount));
    }
  };

  return (
    <div className="space-y-4">
      <div>
        <Label>Select Option to Exercise</Label>
        <Select
          onValueChange={(value) => {
            const option = exerciseOptions.find((o) => o.id.toString() === value);
            setSelectedOption(option);
          }}
        >
          <SelectTrigger>
            <SelectValue placeholder="Select an option to exercise" />
          </SelectTrigger>
          <SelectContent>
            {exerciseOptions?.map((option) => (
              <SelectItem key={option.id} value={option.id.toString()}>
                Strike: {option.strike.toString()} - Expiry:{" "}
                {new Date(Number(option.expiry) * 1000).toLocaleString()}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {selectedOption && (
        <div>
          <Label htmlFor="exercise-amount">Amount</Label>
          <Input
            id="exercise-amount"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            type="number"
            min="1"
          />
        </div>
      )}
      <Button onClick={handleExercise} disabled={!selectedOption || !amount}>
        Exercise Options
      </Button>
    </div>
  );
}
