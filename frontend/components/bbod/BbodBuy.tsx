"use client";

import { useState } from "react";
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
import { formatEther, formatUnits } from "viem";
import { OptionSeries } from "@/hooks/useBbod";

interface BbodBuyProps {
  options: OptionSeries[];
  buy: (id: bigint, num: bigint, premium: bigint) => Promise<any>;
  refetch: () => void;
}

export function BbodBuy({ options, buy, refetch }: BbodBuyProps) {
  const [selectedOptionId, setSelectedOptionId] = useState<string>("");
  const [quantity, setQuantity] = useState("1");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const selectedOption = options.find(
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
    if (BigInt(quantity) <= 0) {
      setError("Quantity must be greater than zero.");
      return;
    }
    if (BigInt(quantity) > (selectedOption.cap - selectedOption.sold)) {
        setError("Not enough options available to buy.");
        return;
    }

    setIsLoading(true);
    setError("");
    setMessage("");
    try {
      await buy(
        selectedOption.id,
        BigInt(quantity),
        selectedOption.premium
      );
      setMessage(`Successfully purchased ${quantity} option(s).`);
      refetch(); // Refetch options to update the list
    } catch (e: any) {
      setError(e.message || "An error occurred during purchase.");
    } finally {
      setIsLoading(false);
      setQuantity("1");
      setSelectedOptionId("");
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Buy Options</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Select
            onValueChange={setSelectedOptionId}
            value={selectedOptionId}
            disabled={options.length === 0}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select an option to buy" />
            </SelectTrigger>
            <SelectContent>
              {options.length > 0 ? (
                options.map((option) => (
                  <SelectItem key={option.id.toString()} value={option.id.toString()}>
                    {`Strike: ${formatUnits(option.strike, 9)} gwei - Premium: ${formatEther(option.premium)} ETH`}
                  </SelectItem>
                ))
              ) : (
                <SelectItem value="none" disabled>No options available</SelectItem>
              )}
            </SelectContent>
          </Select>
        </div>
        {selectedOption && (
          <>
            <div>
              <Input
                id="quantity"
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
                type="number"
                min="1"
                placeholder="Quantity"
              />
            </div>
            <div className="text-sm text-gray-500">
              Total Premium: {formatEther(totalPremium)} ETH
            </div>
          </>
        )}
        <Button
          onClick={handleBuy}
          disabled={!selectedOption || isLoading || !quantity}
          className="w-full"
        >
          {isLoading ? "Purchasing..." : "Buy Options"}
        </Button>
      </CardContent>
      <CardFooter className="flex flex-col items-start space-y-2">
        {message && <p className="text-green-600">{message}</p>}
        {error && <p className="text-red-600">{error}</p>}
      </CardFooter>
    </Card>
  );
}
