import { createServer } from "http";
import { Server } from "socket.io";
import Redis from "ioredis";

const redis = new Redis(process.env.REDIS || "redis://localhost:6379");
const http = createServer();
const io   = new Server(http,{ cors:{origin:"*"}});
redis.subscribe("blobFee");
redis.on("message", (_, msg)=> io.emit("blobFee", msg));

const PORT = Number(process.env.WS_PORT || 6380);
http.listen(PORT, ()=> console.log(`WS relay up :${PORT}`)); 