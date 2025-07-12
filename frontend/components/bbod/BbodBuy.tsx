"use client";

import { useState } from "react";
import { useBbod } from "@/hooks/useBbod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { formatEther } from "viem";

export function BbodBuy() {
  const { options, buy, isLoading: isBbodLoading, refetch } = useBbod();
  const [selectedOptionId, setSelectedOptionId] = useState<string>("");
  const [quantity, setQuantity] = useState("1");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const activeOptions = options.filter(
    (o) => Number(o.expiry) * 1000 > Date.now()
  );
  const selectedOption = activeOptions.find(
    (o) => o.id.toString() === selectedOptionId
  );
  const totalPremium = selectedOption
    ? selectedOption.premium * BigInt(quantity || 0)
    : BigInt(0);

  const handleBuy = async () => {
    if (!selectedOption) {
      setError("Please select an option.");
      return;
    }
    setIsLoading(true);
    setError("");
    setMessage("");
    try {
      const tx = await buy(
        selectedOption.id,
        BigInt(quantity),
        selectedOption.premium
      );
      setMessage(`Successfully purchased ${quantity} option(s).`);
      refetch();
    } catch (e: any) {
      setError(
        e.shortMessage || e.message || "An error occurred during purchase."
      );
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Buy Option</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <Select
          onValueChange={setSelectedOptionId}
          value={selectedOptionId}
        >
          <SelectTrigger>
            <SelectValue placeholder="Select an option series" />
          </SelectTrigger>
          <SelectContent>
            {activeOptions.map((option) => (
              <SelectItem key={option.id.toString()} value={option.id.toString()}>
                Strike:{" "}
                {formatEther(option.strike)} gwei, Expiry:{" "}
                {new Date(Number(option.expiry) * 1000).toLocaleString()}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Input
          type="number"
          placeholder="Quantity"
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
          min="1"
        />
        {selectedOption && (
          <div>
            <p>Premium per option: {formatEther(selectedOption.premium)} ETH</p>
            <p className="font-bold">
              Total Premium: {formatEther(totalPremium)} ETH
            </p>
          </div>
        )}
      </CardContent>
      <CardFooter className="flex-col items-start">
        <Button
          onClick={handleBuy}
          disabled={
            isLoading || isBbodLoading || !selectedOption || !quantity
          }
        >
          {isLoading ? "Purchasing..." : "Buy Option"}
        </Button>
        {error && <p className="text-red-500 text-sm mt-2">{error}</p>}
        {message && <p className="text-green-500 text-sm mt-2">{message}</p>}
      </CardFooter>
    </Card>
  );
}
