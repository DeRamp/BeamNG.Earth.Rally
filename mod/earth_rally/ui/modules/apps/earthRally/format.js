// Earth Rally's HUD: numbers as the player reads them (the streams send metres and seconds; units from the settings).
export const MILE_M = 1609.344

// A distance: "180 m" / "1.24 km", or "450 ft" / "0.42 mi"
export function dist(m, units) {
  if (m === null || m === undefined || isNaN(m)) return ""
  const a = Math.max(0, m)
  if (units === "mi") return a < 160 ? `${Math.round(a * 3.28084 / 10) * 10} ft` : `${(a / MILE_M).toFixed(2)} mi`
  return a < 1000 ? `${Math.round(a)} m` : `${(a / 1000).toFixed(2)} km`
}

// A stage length: "8.4 km" / "5.2 mi"
export function len(m, units) {
  if (m === null || m === undefined) return ""
  return units === "mi" ? `${(m / MILE_M).toFixed(1)} mi` : `${(m / 1000).toFixed(1)} km`
}
export function lenValue(m, units) { return ((m || 0) / (units === "mi" ? MILE_M : 1000)).toFixed(1) }
export function lenUnit(units) { return units === "mi" ? "mi" : "km" }

// A stage time: "6:08.9" (tenths)
export function time(s) {
  if (s === null || s === undefined) return "--:--.-"
  const t = Math.round(s * 10) / 10
  const m = Math.floor(t / 60)
  const r = t - m * 60
  return `${m}:${r < 10 ? "0" : ""}${r.toFixed(1)}`
}

// A difference: "−3.5 s" / "+2.1 s"
export function delta(s) {
  if (s === null || s === undefined) return ""
  return `${s < 0 ? "−" : "+"}${Math.abs(s).toFixed(1)} s`
}

// A time of day (s): "10:43:30"
export function clock(t) {
  if (t === null || t === undefined) return "--:--:--"
  const s = Math.floor(t + 0.5) % 86400
  const p = n => String(n).padStart(2, "0")
  return `${p(Math.floor(s / 3600))}:${p(Math.floor(s / 60) % 60)}:${p(s % 60)}`
}
