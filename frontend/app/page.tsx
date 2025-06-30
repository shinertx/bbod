"use client";
import { useEffect, useState } from "react";
import io from "socket.io-client";

export default function Home() {
  const [fee, setFee] = useState("…");
  useEffect(() => {
    const sock = io("ws://localhost:6379", { transports:["websocket"] });
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