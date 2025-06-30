import { createServer } from "http";
import { Server } from "socket.io";
import Redis from "ioredis";

const redis = new Redis(process.env.REDIS || "redis://localhost:6379");
const http = createServer();
const io   = new Server(http,{ cors:{origin:"*"}});
redis.subscribe("blobFee");
redis.on("message", (_, msg)=> io.emit("blobFee", msg));
http.listen(6379, ()=> console.log("WS relay up :6379")); 