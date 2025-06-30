"use client";
import { useEffect, useState } from "react";
import io from "socket.io-client";

export default function Home() {
  const [fee, setFee] = useState("…");
  useEffect(() => {
    const wsUrl = process.env.NEXT_PUBLIC_WS || "ws://localhost:6380";
    const sock = io(wsUrl, { transports:["websocket"] });
    sock.on("blobFee", (d:string) => setFee(d));
    return () => sock.close();
  }, []);
  return (
    <main className="p-4">
      <h1 className="text-xl mb-4">Blob Fee (gwei): {fee}</h1>
      {/* TODO: add buy/bet forms */}
    </main>
  );
} 