// A stand-in for Cloudflare D1 (env.DB) over Node's own SQLite (node:sqlite, Node 22+), so the Worker runs and
// tests on any computer with no Cloudflare account and nothing installed. Only the part of D1 the Worker uses:
// prepare(sql).bind(...).first() / .all() / .run().
import { DatabaseSync } from "node:sqlite"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

const SCHEMA = fileURLToPath(new URL("../schema.sql", import.meta.url))

class Statement {
  constructor(db, sql, args = []) { this.db = db; this.sql = sql; this.args = args }
  bind(...args) { return new Statement(this.db, this.sql, args.map(a => (a === undefined ? null : a))) }
  async first() { return this.db.prepare(this.sql).get(...this.args) ?? null }
  async all() { return { results: this.db.prepare(this.sql).all(...this.args), success: true } }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.args)
    return { success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } }
  }
}

export function makeD1(file = ":memory:") {
  const db = new DatabaseSync(file)
  db.exec(readFileSync(SCHEMA, "utf8"))
  return { prepare: sql => new Statement(db, sql), close: () => db.close() }
}
