// The owner's stats dashboard (+stats; the design: docs/mockups-telemetry/dashboard.html, OK'd 2026-11-16), served by
// worker.js at GET /dashboard. The page holds no data and no key: it asks for the dashboard key once (kept in this
// browser's localStorage), then reads /api/summary with it. Every value from the database is escaped before it is
// shown (stage and rally names come from players' games).
//
// The page and its script are two responses (/dashboard, /dashboard.js) so the CSP can refuse every inline script.
// (Written without backticks or dollar-braces, so both can sit in String.raw here as is.)
export const DASHBOARD_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Earth Rally stats</title>
<style>
* { box-sizing: border-box; }
:root {
  --page: #0d0d0d; --surface: #1a1a19; --line: #2c2c2a; --grid: #2a2a28;
  --ink: #f0efec; --ink2: #c3c2b7; --muted: #8d8c84;
  --s1: #3987e5; --s2: #d95926; --accent: #c75b1e;
  --warn: #fab219; --crit: #d03b3b;
}
html, body { margin: 0; background: var(--page); color: var(--ink); font: 14px/1.45 "Segoe UI", system-ui, sans-serif; }
header { display: flex; align-items: center; gap: 18px; padding: 18px 28px; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
header h1 { margin: 0; font-size: 20px; } header h1 span { color: var(--accent); }
nav { display: flex; gap: 4px; margin-left: 24px; }
nav a { padding: 6px 12px; border-radius: 4px; color: var(--ink2); text-decoration: none; cursor: pointer; }
nav a.on { background: #2a2a28; color: var(--ink); }
.range { margin-left: auto; display: flex; border: 1px solid #3a3a37; border-radius: 4px; overflow: hidden; }
.range span { padding: 5px 11px; color: var(--ink2); cursor: pointer; } .range span.on { background: #3a3a37; color: var(--ink); }
.who { color: var(--muted); font-size: 12px; } .who a { color: var(--muted); cursor: pointer; text-decoration: underline; }
main { padding: 22px 28px 40px; max-width: 1400px; }
.view { display: none; } .view.on { display: block; }
.tiles { display: grid; grid-template-columns: repeat(6, 1fr); gap: 12px; margin-bottom: 18px; }
.tile { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 14px 16px; }
.tile .k { color: var(--ink2); font-size: 12.5px; } .tile .v { font-size: 28px; font-weight: 650; margin-top: 2px; }
.tile .d { color: var(--muted); font-size: 12px; }
.grid2 { display: grid; grid-template-columns: 1.7fr 1fr; gap: 14px; margin-bottom: 14px; }
.grid3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; margin-bottom: 14px; }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 16px 18px; min-width: 0; }
.card h2 { margin: 0 0 2px; font-size: 15px; } .card .sub { color: var(--muted); font-size: 12.5px; margin-bottom: 10px; }
.legend { display: flex; gap: 16px; font-size: 12.5px; color: var(--ink2); margin-bottom: 6px; }
.legend i { display: inline-block; width: 14px; height: 3px; border-radius: 2px; vertical-align: middle; margin-right: 6px; }
svg text { fill: var(--muted); font-size: 11px; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; color: var(--ink2); font-weight: 500; font-size: 12.5px; padding: 6px 8px; border-bottom: 1px solid var(--line); }
td { padding: 7px 8px; border-bottom: 1px solid #232321; } td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
tr:hover td { background: #222220; }
.bar { display: inline-block; height: 8px; background: var(--s1); border-radius: 0 4px 4px 0; vertical-align: middle; margin-right: 8px; }
.pill { font-size: 11.5px; padding: 1px 7px; border-radius: 9px; border: 1px solid; }
.pill.crit { color: #f08a8a; border-color: var(--crit); } .pill.warn { color: var(--warn); border-color: #8a6a1a; }
.foot { color: var(--muted); font-size: 12px; margin-top: 18px; line-height: 1.7; }
.empty { color: var(--muted); padding: 10px 0; }
.tip { position: fixed; pointer-events: none; background: #0b0b0b; border: 1px solid #3a3a37; border-radius: 4px; padding: 6px 9px; font-size: 12px; display: none; z-index: 20; white-space: pre-line; }
.hbar-row { display: grid; grid-template-columns: 150px 1fr 60px; gap: 10px; align-items: center; padding: 4px 0; }
.hbar-row .lbl { color: var(--ink2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.hbar-row .track { height: 10px; } .hbar-row .track div { height: 10px; background: var(--s1); border-radius: 0 4px 4px 0; }
.hbar-row .num { text-align: right; font-variant-numeric: tabular-nums; }
a.lnk { color: #86b6ef; }
#lock { max-width: 420px; margin: 12vh auto; background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 26px 28px; }
#lock h2 { margin: 0 0 6px; } #lock p { color: var(--ink2); }
#lock input { width: 100%; font: inherit; padding: 9px 10px; margin: 8px 0 12px; color: var(--ink); background: #0d0d0d; border: 1px solid #3a3a37; border-radius: 4px; }
#lock button { font: inherit; padding: 8px 16px; border-radius: 4px; border: 0; background: var(--accent); color: #fff; cursor: pointer; }
#lock .err { color: #f08a8a; min-height: 1.4em; }
@media (max-width: 1100px) { .tiles { grid-template-columns: repeat(3, 1fr); } .grid2, .grid3 { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<header>
  <h1><span>Earth</span> Rally stats</h1>
  <nav><a data-v="overview">Overview</a><a data-v="stages">Stages &amp; rallies</a><a data-v="versions">Versions &amp; errors</a></nav>
  <div class="range" id="range"><span data-d="7">7 days</span><span data-d="30">30 days</span><span data-d="90">90 days</span><span data-d="365">12 months</span></div>
  <div class="who" id="who"></div>
</header>

<div id="lock" style="display:none">
  <h2>Dashboard key</h2>
  <p>The DASHBOARD_KEY you set with wrangler. It is kept in this browser only.</p>
  <form id="lockForm"><input id="keyIn" type="password" autocomplete="current-password" autofocus>
    <div class="err" id="lockErr"></div><button type="submit">Open</button></form>
  <h2 style="margin-top:22px">Downloads per release</h2><p>The mod's zips on GitHub, all time (clicks, not people). Public, no key needed.</p>
  <div id="lockDl"></div>
</div>

<main id="main" style="display:none">
<div id="banner" style="display:none; margin-bottom:14px; padding:10px 14px; border:1px solid #8a6a1a; border-radius:6px; color:var(--warn)"></div>
<section class="view" id="v-overview">
  <div class="tiles" id="tiles"></div>
  <div class="grid2">
    <div class="card"><h2>Stages per day</h2><div class="sub" id="dailySub"></div>
      <div class="legend"><span><i style="background:var(--s1)"></i>Started</span><span><i style="background:var(--s2)"></i>Finished</span></div>
      <svg id="daily" width="100%" height="230"></svg></div>
    <div class="card"><h2>Downloads per release</h2><div class="sub">The mod's zips on GitHub, all time (clicks, not people)</div>
      <div id="dl"></div></div>
  </div>
  <div class="grid2">
    <div class="card"><h2>Most-run stages</h2><div class="sub" id="topSub"></div><table id="topStages"></table></div>
    <div class="card"><h2>New errors</h2><div class="sub" id="newErrSub"></div><table id="newErrors"></table>
      <div class="sub" style="margin-top:10px">"Open issue" starts a GitHub issue with the code, versions and counts filled in.</div></div>
  </div>
  <div class="foot" id="foot"></div>
</section>

<section class="view" id="v-stages">
  <div class="card" style="margin-bottom:14px"><h2>Stages</h2><div class="sub" id="allSub"></div><table id="allStages"></table></div>
  <div class="card"><h2>Rallies</h2><div class="sub">Started = the first stage of the running order begun; finished = every stage done in turn, in one game session.</div>
    <table id="rallies"></table></div>
  <div class="grid2" style="margin-top:14px">
    <div class="card"><h2>Car class</h2><div class="sub" id="clsSub"></div><div id="cls"></div></div>
    <div class="card"><h2>Top cars</h2><div class="sub" id="carsSub"></div><div id="cars"></div></div>
  </div>
</section>

<section class="view" id="v-versions">
  <div class="grid3">
    <div class="card"><h2>Mod version</h2><div class="sub" id="vSub1"></div><div id="vMod"></div></div>
    <div class="card"><h2>Game version</h2><div class="sub" id="vSub2"></div><div id="vGame"></div></div>
    <div class="card"><h2>BeamNG.Earth version</h2><div class="sub" id="vSub3"></div><div id="vEarth"></div></div>
  </div>
  <div class="card"><h2>Errors</h2><div class="sub">Error codes, with the newest short message (scrubbed by the companion before sending). Full logs come in through GitHub bug reports.</div>
    <table id="errors"></table></div>
</section>
</main>
<div class="tip" id="tip"></div>

<script src="/dashboard.js"></script>
</body>
</html>
`

export const DASHBOARD_JS = String.raw`"use strict";
var REPO = "DeRamp/BeamNG.Earth.Rally";
var KEY_NAME = "earthRallyDashboardKey";
var days = Number(localStorage.getItem("earthRallyDashboardDays")) || 30;
var data = null;
var downloads;           // undefined: loading; null: GitHub could not be reached
var view = "overview";

function $(id) { return document.getElementById(id); }
function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}
function num(n) { return (Number(n) || 0).toLocaleString("en-GB"); }
function pct(a, b) { return b ? Math.round(a / b * 100) + "%" : "–"; }
function mmss(s) {
  if (s == null) return "–";
  s = Math.round(s); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
  return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0");
}
function rallyName(r) { return r === "custom" ? "Own stages" : r; }
function rangeWords() { return days === 365 ? "12 months" : days + " days"; }

// ---- tooltips: any element with data-tip (escaped text, new lines kept)
var tip = $("tip");
document.addEventListener("mousemove", function (e) {
  var t = e.target.closest ? e.target.closest("[data-tip]") : null;
  if (!t) { if (!e.target.closest || !e.target.closest("#daily")) tip.style.display = "none"; return; }
  tip.textContent = t.getAttribute("data-tip");
  tip.style.display = "block"; tip.style.left = (e.clientX + 14) + "px"; tip.style.top = (e.clientY + 10) + "px";
});

// ---- the key
function key() { return localStorage.getItem(KEY_NAME) || ""; }
function lock(msg) {
  $("main").style.display = "none"; $("lock").style.display = "block"; $("lockErr").textContent = msg || "";
  $("who").textContent = ""; $("keyIn").focus();
  lockDownloads();
}
// (the downloads are public, so they show on the key screen too)
function lockDownloads() {
  if ($("lock").style.display === "none") return;
  hbars("lockDl", (downloads || []).slice(0, 8).map(function (r) { return [r.release, r.downloads]; }), null,
    downloads === undefined ? "Loading from GitHub…" : downloads ? "No releases yet." : "GitHub could not be reached.");
}
$("lockForm").onsubmit = function (e) {
  e.preventDefault();
  localStorage.setItem(KEY_NAME, $("keyIn").value.trim());
  $("keyIn").value = "";
  load();
};

// GitHub's download counts for the mod's own zips (earth_rally-*.zip), per release, all time
function loadDownloads() {
  fetch("https://api.github.com/repos/" + REPO + "/releases?per_page=100", { headers: { accept: "application/vnd.github+json" } })
    .then(function (r) { if (!r.ok) throw new Error(); return r.json(); })
    .then(function (rel) {
      downloads = rel.map(function (r) {
        var n = (r.assets || []).filter(function (x) { return /^earth_rally-.*\.zip$/.test(x.name || ""); })
          .reduce(function (a, x) { return a + (x.download_count || 0); }, 0);
        return { release: r.tag_name || r.name, downloads: n };
      }).filter(function (r) { return r.downloads > 0; });
    })
    .catch(function () { downloads = null; })
    .then(function () { if (data) draw(); else lockDownloads(); });
}

var asked = 0;
function load() {
  if (!key()) { lock(); return; }
  var mine = ++asked;
  fetch("/api/summary?days=" + days, { headers: { authorization: "Bearer " + key() }, cache: "no-store" })
    .then(function (r) {
      if (r.status === 401) { localStorage.removeItem(KEY_NAME); lock("That key did not work."); return null; }
      if (!r.ok) throw new Error("the server answered " + r.status);
      return r.json();
    })
    .then(function (d) { if (d && mine === asked) { data = d; days = d.days; banner(""); draw(); } })
    .catch(function (err) {
      if (mine !== asked) return;
      // (the key is fine: say so over the page, keep what is shown)
      if (data) banner("Could not load the stats: " + err.message + ". Showing the last ones loaded."); else lock("Could not load the stats: " + err.message);
    });
}

function banner(msg) { $("banner").textContent = msg; $("banner").style.display = msg ? "block" : "none"; }

// ---- drawing
function draw() {
  $("lock").style.display = "none"; $("main").style.display = "block";
  document.querySelectorAll("#range span").forEach(function (s) { s.classList.toggle("on", Number(s.dataset.d) === days); });
  var t = data.totals || {}, rw = rangeWords();
  $("who").innerHTML = (t.last_day ? "Last event " + esc(t.last_day) + " · " : "No events yet · ") + "<a id='forget'>forget key</a>";
  $("forget").onclick = function () { localStorage.removeItem(KEY_NAME); lock(); };
  var dlTotal = (downloads || []).reduce(function (a, r) { return a + (r.downloads || 0); }, 0);
  var tiles = [
    ["Downloads", downloads ? num(dlTotal) : "–", "Mod zips, all time (clicks, not people)"],
    ["Sessions", num(t.sessions), "Games started with stats on, " + rw],
    ["Stages per session", t.sessions ? (t.started / t.sessions).toFixed(1) : "–", "Average, " + rw],
    ["Stages run", num(t.started), "Started in " + rw],
    ["Finish rate", pct(t.finished, t.started), "Finished of started"],
    ["Rallies finished", num(t.rallies_finished), "Every stage done, " + rw],
  ];
  $("tiles").innerHTML = tiles.map(function (x) {
    return "<div class='tile'><div class='k'>" + esc(x[0]) + "</div><div class='v'>" + esc(x[1]) + "</div><div class='d'>" + esc(x[2]) + "</div></div>";
  }).join("");
  $("dailySub").textContent = "Started and finished, last " + rw;
  $("topSub").textContent = rw + ". Full list under Stages & rallies.";
  $("allSub").innerHTML = esc(rw) + ". Stages from packs; players' own imported maps count together as <b>Own stages</b> (their names are never sent).";
  ["vSub1", "vSub2", "vSub3"].forEach(function (id) { $(id).textContent = "Share of sessions, " + rw; });
  $("newErrSub").textContent = days >= 365 ? "Not shown for 12 months: choose a shorter range." :
    (t.since && t.since > data.since ? "First seen in the last " + rw + ". Stats began on " + t.since + ", so every error is new for now." :
      "Error codes first seen in the last " + rw);
  $("foot").textContent = "Sessions and runs count only players who said yes to stats, so they are a sample, not everyone. " +
    "Raw events are kept 12 months, then only monthly totals. " +
    (t.since ? "Data since " + t.since + ", last event received " + t.last_day + "." : "No data yet: nothing has been received.");

  hbars("dl", (downloads || []).slice(0, 8).map(function (r) { return [r.release, r.downloads]; }), null,
    downloads === undefined ? "Loading from GitHub…" : downloads ? "No releases yet." : "GitHub could not be reached.");
  stageTable("topStages", 5, false);
  stageTable("allStages", 200, true);
  rallies();
  var total = function (rows) { return rows.reduce(function (a, r) { return a + r.n; }, 0); };
  ["mod", "game", "earth"].forEach(function (k, i) {
    var rows = (data.versions && data.versions[k]) || [], all = total(rows);
    hbars(["vMod", "vGame", "vEarth"][i], rows.slice(0, 6).map(function (r) {
      return [r.v == null ? "unknown" : (k === "earth" ? "API " + r.v : r.v), all ? Math.round(r.n / all * 100) : 0];
    }), function (v) { return v + "%"; });
  });
  var cars = data.cars || {}, fin = total(cars.cls || []);
  $("clsSub").textContent = "Share of finished-or-ended stages, " + rw;
  $("carsSub").textContent = "Stage ends per car, " + rw + " (top 20)";
  hbars("cls", (cars.cls || []).map(function (r) { return [r.v == null ? "unknown" : r.v, fin ? Math.round(r.n / fin * 100) : 0]; }),
    function (v) { return v + "%"; });
  hbars("cars", (cars.top || []).map(function (r) { return [r.v, r.n]; }));
  errors();
  show(view);
}

function hbars(id, rows, fmt, emptyText) {
  if (!rows.length) { $(id).innerHTML = "<div class='empty'>" + esc(emptyText || "Nothing yet.") + "</div>"; return; }
  var max = Math.max.apply(null, rows.map(function (r) { return r[1]; })) || 1;
  $(id).innerHTML = rows.map(function (r) {
    var shown = fmt ? fmt(r[1]) : num(r[1]);
    return "<div class='hbar-row' data-tip='" + esc(r[0] + "\n" + shown) + "'><span class='lbl'>" + esc(r[0]) +
      "</span><span class='track'><div style='width:" + (r[1] / max * 100) + "%'></div></span><span class='num'>" + esc(shown) + "</span></div>";
  }).join("");
}

function stageTable(id, n, full) {
  var rows = (data.stages || []).slice(0, n);
  if (!rows.length) { $(id).innerHTML = "<tr><td class='empty'>No stages run yet.</td></tr>"; return; }
  var max = Math.max.apply(null, rows.map(function (s) { return s.runs; })) || 1;
  var h = "<tr><th>Stage</th>" + (full ? "<th>Rally</th>" : "") + "<th>Runs</th><th class='n'>Sessions</th><th class='n'>Finished</th>" +
    (full ? "<th class='n'>Median time</th><th class='n'>Resets / run</th><th class='n'>Retired</th><th class='n'>Quit</th><th class='n' title='Started, never ended: the game closed or crashed'>No ending</th>" : "") + "</tr>";
  rows.forEach(function (s) {
    var own = s.rally === "custom";
    h += "<tr><td>" + esc(own ? "Own stages" : s.stage) + "</td>" + (full ? "<td>" + esc(own ? "–" : s.rally) + "</td>" : "") +
      "<td><span class='bar' style='width:" + (s.runs / max * 120) + "px'></span>" + num(s.runs) + "</td><td class='n'>" + num(s.sessions) +
      "</td><td class='n'>" + pct(s.finished, s.runs) + "</td>" +
      (full ? "<td class='n'>" + (own ? "–" : mmss(s.median_s)) + "</td><td class='n'>" + (s.resets == null ? "–" : Number(s.resets).toFixed(1)) +
        "</td><td class='n'>" + num(s.failed) + "</td><td class='n'>" + num(s.quit) +
        "</td><td class='n'>" + num(Math.max(0, s.runs - s.finished - s.failed - s.quit)) + "</td>" : "") + "</tr>";
  });
  $(id).innerHTML = h;
}

function rallies() {
  var rows = data.rallies || [];
  if (!rows.length) { $("rallies").innerHTML = "<tr><td class='empty'>No rallies started yet.</td></tr>"; return; }
  var h = "<tr><th>Rally</th><th class='n'>Stages</th><th class='n'>Started</th><th class='n'>Finished</th><th class='n'>Finished %</th><th class='n'>Sessions</th></tr>";
  rows.forEach(function (r) {
    h += "<tr><td>" + esc(rallyName(r.rally)) + "</td><td class='n'>" + (r.stages == null ? "–" : num(r.stages)) + "</td><td class='n'>" + num(r.started) +
      "</td><td class='n'>" + num(r.finished) + "</td><td class='n'>" + pct(r.finished, r.started) + "</td><td class='n'>" + num(r.sessions) + "</td></tr>";
  });
  $("rallies").innerHTML = h;
}

function issueLink(e) {
  var bt = String.fromCharCode(96);    // (a backtick: none may be written in this page's source)
  var body = "Error code " + bt + e.code + bt + " in " + bt + (e.module || "?") + bt + ", Earth Rally " + (e.mod || "?") + ".\n\n" +
    (e.message ? "Message: " + e.message + "\n\n" : "") + "From the stats: " + e.times + " times in " + e.sessions + " sessions, first seen " + e.first_ever + ", last seen " + e.last + ".";
  return "https://github.com/" + REPO + "/issues/new?labels=bug&title=" + encodeURIComponent("Error " + e.code) + "&body=" + encodeURIComponent(body);
}
function pill(e) { return "<span class='pill " + (e.sessions >= 5 ? "crit" : "warn") + "'>" + esc(e.code) + "</span>"; }

function errors() {
  var rows = data.errors || [];
  // (new: the code was first seen, in any version, inside the range; one row per code and module, versions added up)
  var byCode = {}, fresh = [];
  rows.forEach(function (e) {
    if (days >= 365 || !(e.first_code >= data.since)) return;
    var k = e.code + "|" + e.module, f = byCode[k];
    if (!f) { f = byCode[k] = { code: e.code, module: e.module, mod: e.mod, message: e.message, times: 0, sessions: 0, first_ever: e.first_code, last: e.last }; fresh.push(f); }
    f.times += e.times; f.sessions += e.sessions; if (e.last > f.last) { f.last = e.last; f.mod = e.mod; f.message = e.message || f.message; }
  });
  fresh.sort(function (a, b) { return b.sessions - a.sessions; });
  fresh = fresh.slice(0, 5);
  $("newErrors").innerHTML = fresh.length
    ? "<tr><th>Code</th><th>Where</th><th class='n'>Sessions</th><th></th></tr>" + fresh.map(function (e) {
        return "<tr><td>" + pill(e) + "</td><td>" + esc(e.module) + "</td><td class='n'>" + num(e.sessions) +
          "</td><td><a class='lnk' target='_blank' rel='noopener' href='" + esc(issueLink(e)) + "'>Open issue</a></td></tr>";
      }).join("")
    : "<tr><td class='empty'>No new errors.</td></tr>";
  $("errors").innerHTML = rows.length
    ? "<tr><th>Code</th><th>Module</th><th>Mod version</th><th>Latest message</th><th class='n'>Times</th><th class='n'>Sessions</th><th>First seen</th><th>Last seen</th><th></th></tr>" +
      rows.map(function (e) {
        return "<tr><td>" + pill(e) + "</td><td>" + esc(e.module) + "</td><td>" + esc(e.mod) + "</td><td>" + esc(e.message || "–") + "</td><td class='n'>" + num(e.times) +
          "</td><td class='n'>" + num(e.sessions) + "</td><td>" + esc(e.first_ever) + "</td><td>" + esc(e.last) +
          "</td><td><a class='lnk' target='_blank' rel='noopener' href='" + esc(issueLink(e)) + "'>Open issue</a></td></tr>";
      }).join("")
    : "<tr><td class='empty'>No errors in " + esc(rangeWords()) + ".</td></tr>";
}

// ---- stages per day: one axis (both are stage counts), every day in the range, gaps as 0
function dailySeries() {
  var by = {};
  (data.daily || []).forEach(function (d) { by[d.day] = d; });
  var out = [], start = new Date(data.since + "T00:00:00Z");
  for (var i = 0; i < days; i++) {
    var day = new Date(start.getTime() + i * 86400000).toISOString().slice(0, 10);
    var d = by[day] || {};
    out.push({ day: day, s: d.started || 0, f: d.finished || 0 });
  }
  return out;
}
function niceStep(max) {
  var raw = max / 4, p = Math.pow(10, Math.floor(Math.log10(raw || 1))), m = raw / p;
  return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
}
function daily() {
  var svg = $("daily"), pts = dailySeries();
  var W = svg.clientWidth || 760, H = 230, L = 40, B = 22, T = 8;
  var step = niceStep(Math.max.apply(null, pts.map(function (d) { return d.s; })) || 4);
  var max = Math.max(step, Math.ceil(Math.max.apply(null, pts.map(function (d) { return d.s; })) / step) * step);
  var n = pts.length;
  function x(i) { return L + (n > 1 ? i * (W - L - 8) / (n - 1) : (W - L - 8) / 2); }
  function y(v) { return T + (H - T - B) * (1 - v / max); }
  var g = "";
  for (var v = 0; v <= max; v += step) {
    g += "<line x1='" + L + "' x2='" + (W - 8) + "' y1='" + y(v) + "' y2='" + y(v) + "' stroke='var(--grid)'/><text x='" + (L - 6) + "' y='" + (y(v) + 4) + "' text-anchor='end'>" + num(v) + "</text>";
  }
  var every = Math.max(1, Math.round(n / 5));
  pts.forEach(function (d, i) { if (i % every === 0) g += "<text x='" + x(i) + "' y='" + (H - 5) + "' text-anchor='middle'>" + d.day.slice(5) + "</text>"; });
  function path(k) { return pts.map(function (d, i) { return (i ? "L" : "M") + x(i).toFixed(1) + " " + y(d[k]).toFixed(1); }).join(""); }
  g += "<path d='" + path("s") + "' fill='none' stroke='var(--s1)' stroke-width='2'/><path d='" + path("f") + "' fill='none' stroke='var(--s2)' stroke-width='2'/>";
  g += "<line id='xh' y1='" + T + "' y2='" + (H - B) + "' stroke='#5a5a55' visibility='hidden'/>" +
    "<circle id='m1' r='4' fill='var(--s1)' stroke='var(--surface)' stroke-width='2' visibility='hidden'/>" +
    "<circle id='m2' r='4' fill='var(--s2)' stroke='var(--surface)' stroke-width='2' visibility='hidden'/>";
  g += "<rect x='" + L + "' y='0' width='" + (W - L) + "' height='" + H + "' fill='transparent' id='hit'/>";
  svg.innerHTML = g;
  var hit = svg.querySelector("#hit");
  hit.onmousemove = function (e) {
    var r = svg.getBoundingClientRect();
    var i = n > 1 ? Math.max(0, Math.min(n - 1, Math.round((e.clientX - r.left - L) / ((W - L - 8) / (n - 1))))) : 0;
    var d = pts[i];
    svg.querySelector("#xh").setAttribute("x1", x(i)); svg.querySelector("#xh").setAttribute("x2", x(i));
    svg.querySelector("#m1").setAttribute("cx", x(i)); svg.querySelector("#m1").setAttribute("cy", y(d.s));
    svg.querySelector("#m2").setAttribute("cx", x(i)); svg.querySelector("#m2").setAttribute("cy", y(d.f));
    svg.querySelectorAll("#xh,#m1,#m2").forEach(function (el) { el.setAttribute("visibility", "visible"); });
    tip.textContent = d.day + "\nStarted " + d.s + "\nFinished " + d.f + (d.s ? " (" + pct(d.f, d.s) + ")" : "");
    tip.style.display = "block"; tip.style.left = (e.clientX + 14) + "px"; tip.style.top = (e.clientY + 10) + "px";
  };
  hit.onmouseleave = function () { tip.style.display = "none"; svg.querySelectorAll("#xh,#m1,#m2").forEach(function (el) { el.setAttribute("visibility", "hidden"); }); };
}

// ---- views and range
function show(v) {
  if (["overview", "stages", "versions"].indexOf(v) < 0) v = "overview";
  view = v;
  document.querySelectorAll(".view").forEach(function (x) { x.classList.toggle("on", x.id === "v-" + v); });
  document.querySelectorAll("nav [data-v]").forEach(function (b) { b.classList.toggle("on", b.dataset.v === v); });
  if (v === "overview" && data) daily();
}
document.querySelectorAll("nav [data-v]").forEach(function (b) { b.onclick = function () { location.hash = b.dataset.v; }; });
window.onhashchange = function () { show(location.hash.slice(1)); };
window.onresize = function () { if (data && view === "overview") daily(); };
document.querySelectorAll("#range span").forEach(function (s) {
  s.onclick = function () { days = Number(s.dataset.d); localStorage.setItem("earthRallyDashboardDays", days); load(); };
});
view = location.hash.slice(1) || "overview";
load();
loadDownloads();
`
