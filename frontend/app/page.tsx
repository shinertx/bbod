"use client";
import { useEffect, useState } from "react";
import io from "socket.io-client";
import { ethers } from "ethers";

const BSP_ABI = ["function betHi() payable","function betLo() payable","function claim(uint256)"];
const BBOD_ABI = ["function premium(uint256,uint256) view returns(uint256)","function buy(uint256,uint256) payable","function exercise(uint256)"];

export default function Home() {
  const [fee, setFee] = useState("…");
  const [provider, setProvider] = useState<ethers.BrowserProvider>();
  const [signer, setSigner] = useState<ethers.JsonRpcSigner>();
  const [error, setError] = useState<string | null>(null);
  const [amount, setAmount] = useState("0");
  const [optId, setOptId] = useState("1");
  const [qty, setQty] = useState("1");
  const alertMsg = process.env.NEXT_PUBLIC_ALERT;
  useEffect(() => {
    const wsUrl = process.env.NEXT_PUBLIC_WS || "ws://localhost:6380";
    const sock = io(wsUrl, { transports:["websocket"] });
    sock.on("blobFee", (d:string) => setFee(d));
    return () => sock.close();
  }, []);

  async function connect() {
    if (!window.ethereum) return setError("No wallet");
    const prov = new ethers.BrowserProvider(window.ethereum as any);
    await prov.send("eth_requestAccounts", []);
    setProvider(prov);
    setSigner(await prov.getSigner());
  }

  async function bet(hi:boolean) {
    if (!signer) return setError("connect wallet");
    setError(null);
    try {
      const c = new ethers.Contract(process.env.NEXT_PUBLIC_BSP!, BSP_ABI, signer);
      const tx = await c[hi ? "betHi" : "betLo"]({ value: ethers.parseEther(amount) });
      await tx.wait();
    } catch(e:any){ setError(e.message); }
  }

  async function buy() {
    if (!signer) return setError("connect wallet");
    setError(null);
    try {
      const bb = new ethers.Contract(process.env.NEXT_PUBLIC_BBOD!, BBOD_ABI, signer);
      const prem = await bb.premium(optId, Math.floor(Date.now()/1000)+3600);
      const tx = await bb.buy(optId, qty, { value: prem * BigInt(qty) });
      await tx.wait();
    } catch(e:any){ setError(e.message); }
  }

  async function claim() {
    if (!signer) return setError("connect wallet");
    setError(null);
    try {
      const c = new ethers.Contract(process.env.NEXT_PUBLIC_BSP!, BSP_ABI, signer);
      const tx = await c.claim(optId);
      await tx.wait();
    } catch(e:any){ setError(e.message); }
  }

  async function exercise() {
    if (!signer) return setError("connect wallet");
    setError(null);
    try {
      const bb = new ethers.Contract(process.env.NEXT_PUBLIC_BBOD!, BBOD_ABI, signer);
      const tx = await bb.exercise(optId);
      await tx.wait();
    } catch(e:any){ setError(e.message); }
  }
  return (
    <main className="p-4 space-y-4">
      {alertMsg && <div className="bg-red-200 p-2">{alertMsg}</div>}
      <h1 className="text-xl">Blob Fee (gwei): {fee}</h1>
      <button onClick={connect} className="px-4 py-1 bg-blue-200">Connect Wallet</button>

      <div>
        <h2>Bet Parimutuel</h2>
        <input value={amount} onChange={e=>setAmount(e.target.value)} className="border p-1 mr-2" /> ETH
        <button onClick={()=>bet(true)} className="px-2 py-1 bg-green-200 mr-2">Bet Hi</button>
        <button onClick={()=>bet(false)} className="px-2 py-1 bg-red-200">Bet Lo</button>
      </div>

      <div>
        <h2>Options</h2>
        <input value={optId} onChange={e=>setOptId(e.target.value)} className="border p-1 mr-2" placeholder="id" />
        <input value={qty} onChange={e=>setQty(e.target.value)} className="border p-1 mr-2" placeholder="qty" />
        <button onClick={buy} className="px-2 py-1 bg-yellow-200 mr-2">Buy</button>
        <button onClick={claim} className="px-2 py-1 bg-gray-200 mr-2">Claim</button>
        <button onClick={exercise} className="px-2 py-1 bg-purple-200">Exercise</button>
      </div>

      {error && <div className="text-red-500">{error}</div>}
    </main>
  );
}
