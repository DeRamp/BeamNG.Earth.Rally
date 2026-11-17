// See the dashboard with nothing deployed:  node server/preview.mjs  then open http://localhost:8787/dashboard
// The Worker runs as is; the page reads the real download counts from GitHub itself.
import { createServer } from "node:http"

const PORT = Number(process.env.PORT) || 8787
const worker = (await import("./src/worker.js")).default

createServer(async (req, res) => {
  const r = await worker.fetch(new Request("http://localhost:" + PORT + req.url, { method: req.method, headers: req.headers }))
  res.writeHead(r.status, Object.fromEntries(r.headers))
  res.end(Buffer.from(await r.arrayBuffer()))
}).listen(PORT, () => console.log("preview: http://localhost:" + PORT + "/dashboard"))
