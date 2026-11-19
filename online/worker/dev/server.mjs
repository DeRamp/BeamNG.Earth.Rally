// The Worker on this computer, for trying the online board without Cloudflare:
//   node online/worker/dev/server.mjs [--port 8787] [--db board.sqlite] [--admin TOKEN]
// then point the companion at it: --server http://127.0.0.1:8787 . The data is kept in --db (a file; :memory: by
// default, gone when it stops). Same code as on Cloudflare (src/index.js), with D1 stood in by dev/d1.mjs.
import http from "node:http"
import worker from "../src/index.js"
import { makeD1 } from "./d1.mjs"

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name)
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt
}
const port = Number(arg("--port", 8787))
const env = { DB: makeD1(arg("--db", ":memory:")), ADMIN_TOKEN: arg("--admin", process.env.ADMIN_TOKEN || "") }

const server = http.createServer(async (req, res) => {
  const chunks = []
  for await (const c of req) chunks.push(c)
  const body = Buffer.concat(chunks)
  const headers = new Headers()
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v)
  headers.set("cf-connecting-ip", req.socket.remoteAddress || "local")
  const r = await worker.fetch(new Request(`http://127.0.0.1:${port}${req.url}`, {
    method: req.method, headers, body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
  }), env)
  res.writeHead(r.status, Object.fromEntries(r.headers))
  res.end(Buffer.from(await r.arrayBuffer()))
})
server.listen(port, "127.0.0.1", () => console.log(`earth rally board on http://127.0.0.1:${port}`))
