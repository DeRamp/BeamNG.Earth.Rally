// The owner's downloads dashboard, served by worker.js at GET /dashboard. The mod sends nothing (no telemetry: the
// owner, 2026-11-16), so the only numbers are GitHub's download counts for the releases, read by the browser straight
// from GitHub's public API. The page holds no data and needs no key. Release names are escaped before they are shown.
//
// The page and its script are two responses (/dashboard, /dashboard.js) so the CSP can refuse every inline script.
// (Written without backticks or dollar-braces, so both can sit in String.raw here as is.)
export const DASHBOARD_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Earth Rally downloads</title>
<style>
* { box-sizing: border-box; }
:root {
  --page: #0d0d0d; --surface: #1a1a19; --line: #2c2c2a;
  --ink: #f0efec; --ink2: #c3c2b7; --muted: #8d8c84;
  --s1: #3987e5; --accent: #c75b1e; --warn: #fab219;
}
html, body { margin: 0; background: var(--page); color: var(--ink); font: 14px/1.45 "Segoe UI", system-ui, sans-serif; }
header { display: flex; align-items: center; gap: 18px; padding: 18px 28px; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
header h1 { margin: 0; font-size: 20px; } header h1 span { color: var(--accent); }
.who { margin-left: auto; color: var(--muted); font-size: 12px; } .who a { color: var(--muted); cursor: pointer; text-decoration: underline; }
main { padding: 22px 28px 40px; max-width: 1400px; }
.tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 18px; }
.tile { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 14px 16px; }
.tile .k { color: var(--ink2); font-size: 12.5px; } .tile .v { font-size: 28px; font-weight: 650; margin-top: 2px; }
.tile .d { color: var(--muted); font-size: 12px; }
.grid2 { display: grid; grid-template-columns: 1fr 1.3fr; gap: 14px; margin-bottom: 14px; }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 16px 18px; min-width: 0; }
.card h2 { margin: 0 0 2px; font-size: 15px; } .card .sub { color: var(--muted); font-size: 12.5px; margin-bottom: 10px; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; color: var(--ink2); font-weight: 500; font-size: 12.5px; padding: 6px 8px; border-bottom: 1px solid var(--line); }
td { padding: 7px 8px; border-bottom: 1px solid #232321; } td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
tr:hover td { background: #222220; }
.tag { font-size: 11px; color: var(--muted); border: 1px solid #3a3a37; border-radius: 9px; padding: 0 6px; margin-left: 6px; }
.foot { color: var(--muted); font-size: 12px; margin-top: 18px; line-height: 1.7; }
.empty { color: var(--muted); padding: 10px 0; }
.tip { position: fixed; pointer-events: none; background: #0b0b0b; border: 1px solid #3a3a37; border-radius: 4px; padding: 6px 9px; font-size: 12px; display: none; z-index: 20; white-space: pre-line; }
.hbar-row { display: grid; grid-template-columns: 150px 1fr 60px; gap: 10px; align-items: center; padding: 4px 0; }
.hbar-row .lbl { color: var(--ink2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.hbar-row .track { height: 10px; } .hbar-row .track div { height: 10px; background: var(--s1); border-radius: 0 4px 4px 0; }
.hbar-row .num { text-align: right; font-variant-numeric: tabular-nums; }
a.lnk { color: #86b6ef; }
#banner { display: none; margin-bottom: 14px; padding: 10px 14px; border: 1px solid #8a6a1a; border-radius: 6px; color: var(--warn); }
@media (max-width: 1100px) { .tiles { grid-template-columns: repeat(2, 1fr); } .grid2 { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<header>
  <h1><span>Earth</span> Rally downloads</h1>
  <div class="who" id="who"></div>
</header>
<main>
  <div id="banner"></div>
  <div class="tiles" id="tiles"></div>
  <div class="grid2">
    <div class="card"><h2>Mod downloads per release</h2><div class="sub">The mod's zip (earth_rally-*.zip), all time</div><div id="bars"></div></div>
    <div class="card"><h2>Releases</h2><div class="sub">Every release and what was downloaded from it</div><table id="releases"></table></div>
  </div>
  <div class="foot">Counts come live from GitHub each time this page loads. They count downloads (clicks), not people: one player
    can download the same release twice, and a copy passed on is never counted. GitHub keeps only the running total,
    so there is no history by day. The mod itself sends nothing.</div>
</main>
<div class="tip" id="tip"></div>
<script src="/dashboard.js"></script>
</body>
</html>
`

export const DASHBOARD_JS = String.raw`"use strict";
var REPO = "DeRamp/BeamNG.Earth.Rally";
var MOD_ZIP = /^earth_rally-.*\.zip$/;

function $(id) { return document.getElementById(id); }
function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}
function num(n) { return (Number(n) || 0).toLocaleString("en-GB"); }
function day(s) { return s ? String(s).slice(0, 10) : "–"; }

var tip = $("tip");
document.addEventListener("mousemove", function (e) {
  var t = e.target.closest ? e.target.closest("[data-tip]") : null;
  if (!t) { tip.style.display = "none"; return; }
  tip.textContent = t.getAttribute("data-tip");
  tip.style.display = "block"; tip.style.left = (e.clientX + 14) + "px"; tip.style.top = (e.clientY + 10) + "px";
});

function banner(msg) { $("banner").textContent = msg; $("banner").style.display = msg ? "block" : "none"; }

// One release: the mod's zip downloads and every other file's (rally packs and the like)
function summarise(r) {
  var mod = 0, other = 0, hasMod = false, files = [];
  (r.assets || []).forEach(function (a) {
    var n = a.download_count || 0;
    if (MOD_ZIP.test(a.name || "")) { mod += n; hasMod = true; } else other += n;
    files.push((a.name || "?") + ": " + num(n));
  });
  return { tag: r.tag_name || r.name || "?", url: r.html_url, date: r.published_at || r.created_at,
    pre: !!r.prerelease, hasMod: hasMod, mod: mod, other: other, files: files };
}

// (GitHub answers 100 releases a page; follow the pages until one comes back short)
function fetchAll(page, acc) {
  return fetch("https://api.github.com/repos/" + REPO + "/releases?per_page=100&page=" + page,
    { headers: { accept: "application/vnd.github+json" }, cache: "no-store" })
    .then(function (r) {
      if (r.status === 403 || r.status === 429) throw new Error("GitHub's hourly limit for this connection is used up; try again later");
      if (!r.ok) throw new Error("GitHub answered " + r.status);
      return r.json();
    })
    .then(function (list) {
      acc = acc.concat(list);
      return list.length === 100 && page < 10 ? fetchAll(page + 1, acc) : acc;
    });
}

function load() {
  banner("");
  $("who").textContent = "Loading from GitHub…";
  fetchAll(1, []).then(function (list) { draw(list.filter(function (r) { return !r.draft; }).map(summarise)); })
    .catch(function (err) {
      $("who").innerHTML = "<a id='again'>Try again</a>";
      $("again").onclick = load;
      banner("Could not read the download counts: " + err.message + ".");
      if (!$("tiles").innerHTML) draw([]);
    });
}

function draw(rows) {
  rows.sort(function (a, b) { return String(b.date).localeCompare(String(a.date)); });
  var modTotal = rows.reduce(function (a, r) { return a + r.mod; }, 0);
  var otherTotal = rows.reduce(function (a, r) { return a + r.other; }, 0);
  var latest = rows.filter(function (r) { return r.hasMod; })[0];
  var tiles = [
    ["Mod downloads", num(modTotal), "Every release, all time"],
    ["Latest release", latest ? num(latest.mod) : "–", latest ? latest.tag + ", out " + day(latest.date) : "No release yet"],
    ["Releases", num(rows.length), rows.length ? "Since " + day(rows[rows.length - 1].date) : "None yet"],
    ["Other files", num(otherTotal), "Rally packs and the like"],
  ];
  $("tiles").innerHTML = tiles.map(function (x) {
    return "<div class='tile'><div class='k'>" + esc(x[0]) + "</div><div class='v'>" + esc(x[1]) + "</div><div class='d'>" + esc(x[2]) + "</div></div>";
  }).join("");

  var withMod = rows.filter(function (r) { return r.mod > 0; });
  var max = Math.max.apply(null, withMod.map(function (r) { return r.mod; }).concat([1]));
  $("bars").innerHTML = withMod.length ? withMod.map(function (r) {
    return "<div class='hbar-row' data-tip='" + esc(r.tag + "\n" + num(r.mod) + " downloads\nout " + day(r.date)) + "'><span class='lbl'>" + esc(r.tag) +
      "</span><span class='track'><div style='width:" + (r.mod / max * 100) + "%'></div></span><span class='num'>" + num(r.mod) + "</span></div>";
  }).join("") : "<div class='empty'>No mod downloads yet.</div>";

  $("releases").innerHTML = rows.length
    ? "<tr><th>Release</th><th>Out</th><th class='n'>Mod zip</th><th class='n'>Other files</th></tr>" + rows.map(function (r) {
        return "<tr data-tip='" + esc(r.files.join("\n") || "No files") + "'><td><a class='lnk' target='_blank' rel='noopener' href='" + esc(r.url) + "'>" +
          esc(r.tag) + "</a>" + (r.pre ? "<span class='tag'>pre-release</span>" : "") + "</td><td>" + esc(day(r.date)) +
          "</td><td class='n'>" + num(r.mod) + "</td><td class='n'>" + num(r.other) + "</td></tr>";
      }).join("")
    : "<tr><td class='empty'>No releases yet.</td></tr>";
  $("who").innerHTML = "Read from GitHub " + esc(new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })) + " · <a id='again'>Refresh</a>";
  $("again").onclick = load;
}

load();
`
