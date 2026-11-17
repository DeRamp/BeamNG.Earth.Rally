// Offline test of the downloads dashboard Worker. Nothing to install.   node server/test_worker.mjs
import assert from "node:assert/strict"

const here = new URL(".", import.meta.url)
const worker = (await import(new URL("src/worker.js", here))).default
const { DASHBOARD_HTML, DASHBOARD_JS } = await import(new URL("src/dashboard.js", here))
const req = (url, method = "GET") => worker.fetch(new Request(url, { method }))

// the page and its script, https, with the CSP; GitHub the only outside address
let r = await req("https://x/dashboard")
assert.equal(r.status, 200)
assert.match(r.headers.get("content-type"), /text\/html/)
const csp = r.headers.get("content-security-policy")
assert.match(csp, /script-src 'self'/)
assert.match(csp, /connect-src https:\/\/api\.github\.com;/)
assert.equal(await r.text(), DASHBOARD_HTML)
r = await req("https://x/dashboard.js")
assert.equal(r.status, 200)
assert.match(r.headers.get("content-type"), /javascript/)
assert.equal(await r.text(), DASHBOARD_JS)

// no inline script, no key, no stats left in the page
assert.doesNotMatch(DASHBOARD_HTML, /<script>/)
assert.doesNotMatch(DASHBOARD_HTML + DASHBOARD_JS, /api\/summary|DASHBOARD_KEY|localStorage/)
// every value from GitHub goes through esc() (tag names, file names, links)
assert.match(DASHBOARD_JS, /esc\(r\.tag\)/)
assert.match(DASHBOARD_JS, /esc\(r\.url\)/)

// plain http goes to https (except on this computer); / goes to the page
r = await req("http://x.workers.dev/dashboard")
assert.equal(r.status, 301)
assert.equal(r.headers.get("location"), "https://x.workers.dev/dashboard")
assert.equal((await req("http://localhost:8787/dashboard")).status, 200)
r = await req("https://x/")
assert.equal(r.status, 302)
assert.equal(r.headers.get("location"), "https://x/dashboard")

// the old stats addresses are gone; nothing is taken in
assert.equal((await req("https://x/v1/events", "POST")).status, 405)
assert.equal((await req("https://x/api/summary")).status, 404)
assert.equal((await req("https://x/nope")).status, 404)
r = await req("https://x/dashboard", "HEAD")
assert.equal(r.status, 200)
assert.equal(await r.text(), "")

// the page's script parses
new Function(DASHBOARD_JS)

console.log("test_worker: all passed")
