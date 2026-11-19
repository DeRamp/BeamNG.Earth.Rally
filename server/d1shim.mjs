// D1 stood in by Node's built-in SQLite (Node 22.5+), for test_worker.mjs and preview.mjs. Only the surface worker.js
// uses: prepare().bind().first()/all()/run(), batch().
import { DatabaseSync } from "node:sqlite"
import { readFileSync } from "node:fs"

export function makeDb() {
  const db = new DatabaseSync(":memory:")
  db.exec(readFileSync(new URL("schema.sql", import.meta.url), "utf8"))
  class Stmt {
    constructor(sql, args = []) { this.sql = sql; this.args = args }
    bind(...a) { return new Stmt(this.sql, a) }
    exec() {
      const s = db.prepare(this.sql)
      const named = this.sql.includes("?1")
      const args = named ? Object.fromEntries(this.args.map((v, i) => [String(i + 1), v])) : this.args
      if (/^\s*(SELECT|WITH)/i.test(this.sql)) return { results: named ? s.all(args) : s.all(...args) }
      named ? s.run(args) : s.run(...args)
      return { results: [] }
    }
    async first() { return this.exec().results[0] }
    async all() { return this.exec() }
    async run() { return this.exec() }
  }
  return { db, D1: { prepare: sql => new Stmt(sql), batch: async list => list.map(s => s.exec()) } }
}
