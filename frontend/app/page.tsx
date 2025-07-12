"use client";

import { ConnectWallet } from "@/components/ConnectWallet";
import { BspActions } from "@/components/bsp/BspActions";
import { BspRoundInfo } from "@/components/bsp/BspRoundInfo";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center p-4 sm:p-8 md:p-12 lg:p-24 bg-gray-900 text-white">
      <header className="w-full max-w-5xl flex justify-between items-center py-4">
        <h1 className="text-2xl sm:text-3xl font-bold">
          Blob Fee Volatility Market
        </h1>
        <ConnectWallet />
      </header>

      <div className="flex flex-col lg:flex-row w-full max-w-5xl mt-8 gap-8">
        {/* BSP Section */}
        <div className="flex-1 bg-gray-800 p-6 rounded-lg flex flex-col gap-4">
          <h2 className="text-xl font-semibold mb-4 text-center">
            Hourly Parimutuel (BSP)
          </h2>
          <BspRoundInfo />
          <BspActions />
        </div>

        {/* BBOD Section */}
        <div className="flex-1 bg-gray-800 p-6 rounded-lg">
          <h2 className="text-xl font-semibold mb-4">Blob Options (BBOD)</h2>
          {/* BBOD components will go here */}
          <p className="text-gray-400">Coming soon...</p>
        </div>
      </div>
    </main>
  );
}
