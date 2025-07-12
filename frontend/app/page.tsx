"use client";
import { useEffect, useState } from "react";
import io from "socket.io-client";
import { ethers } from "ethers";

const BSP_ABI = [
  "function commit(bytes32) payable",
  "function reveal(uint8,bytes32)",
  "function claim(uint256,uint8,bytes32)"
];
const BBOD_ABI = ["function premium(uint256,uint256) view returns(uint256)","function buy(uint256,uint256) payable","function exercise(uint256)"];

export default function Home() {
  const [fee, setFee] = useState("…");
  const [provider, setProvider] = useState<ethers.BrowserProvider>();
  const [signer, setSigner] = useState<ethers.JsonRpcSigner>();
  const [error, setError] = useState<string | null>(null);
  const [amount, setAmount] = useState("0");
  const [optId, setOptId] = useState("1");
  const [qty, setQty] = useState("1");
  const [betSalt, setBetSalt] = useState<string>();
  const [betSide, setBetSide] = useState<number>();
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

  async function bet(hi: boolean) {
    if (!signer) return setError("connect wallet");
    setError(null);
    try {
      const c = new ethers.Contract(process.env.NEXT_PUBLIC_BSP!, BSP_ABI, signer);
      const salt = ethers.hexlify(ethers.randomBytes(32));
      const addr = await signer.getAddress();
      const side = hi ? 0 : 1;
      const commit = ethers.keccak256(
        ethers.solidityPacked(["address", "uint8", "bytes32"], [addr, side, salt])
      );
      const tx = await c.commit(commit, { value: ethers.parseEther(amount) });
      await tx.wait();
      setBetSalt(salt);
      setBetSide(side);
      setTimeout(async () => {
        try {
          await (await c.reveal(side, salt)).wait();
        } catch (e) {
          console.error(e);
        }
      }, 305_000);
    } catch (e: any) {
      setError(e.message);
    }
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
      if (!betSalt || betSide === undefined) return setError("no bet");
      const tx = await c.claim(optId, betSide, betSalt);
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
    <main className="flex min-h-screen flex-col items-center justify-center p-24 bg-gray-900 text-white">
      <div className="z-10 max-w-5xl w-full items-center justify-between font-mono text-sm lg:flex">
        <h1 className="text-4xl font-bold text-center">
          Blob Fee Volatility Market
        </h1>
      </div>
    </main>
  )
}
