// Earth Rally downloads dashboard Worker. The mod sends nothing (no telemetry: the owner, 2026-11-16); this only serves
// the owner's page, which reads GitHub's public download counts itself. No database, no key, no logs. Setup:
// server/README.md.
//
//   GET /dashboard, /dashboard.js   the page and its script (src/dashboard.js); https only
//   GET /                           to /dashboard

import { DASHBOARD_HTML, DASHBOARD_JS } from "./dashboard.js"

const LOCAL = new Set(["localhost", "127.0.0.1", "[::1]"])

const empty = status => new Response(null, { status })

function page(js) {
  return new Response(js ? DASHBOARD_JS : DASHBOARD_HTML, { headers: {
    "content-type": js ? "text/javascript; charset=utf-8" : "text/html; charset=utf-8",
    "cache-control": "no-store", "x-robots-tag": "noindex", "referrer-policy": "no-referrer",
    "x-frame-options": "DENY", "x-content-type-options": "nosniff",
    // (script from this Worker only, never inline; the only other address the page talks to is GitHub's API)
    "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; " +
      "connect-src https://api.github.com; img-src 'self' data:; form-action 'none'; frame-ancestors 'none'; base-uri 'none'",
  } })
}

export default {
  async fetch(req) {
    const url = new URL(req.url)
    const get = req.method === "GET" || req.method === "HEAD"
    if (!get) return empty(405)
    if (url.protocol === "http:" && !LOCAL.has(url.hostname)) {
      url.protocol = "https:"
      return Response.redirect(url.toString(), 301)
    }
    let r
    if (url.pathname === "/") r = Response.redirect(new URL("/dashboard", url).toString(), 302)
    else if (url.pathname === "/dashboard" || url.pathname === "/dashboard.js") r = page(url.pathname === "/dashboard.js")
    else r = empty(404)
    return req.method === "HEAD" ? new Response(null, { status: r.status, headers: r.headers }) : r
  },
}
