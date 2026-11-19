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
/* sortable tables, the Leaderboards tab (docs/mockups-1.8.2/dashboard-leaderboards.html) */
th.sort { cursor: pointer; white-space: nowrap; } th.sort::after { content: " \2195"; color: #55554f; }
th.sort.on { color: var(--ink); } th.sort.on::after { content: " \25BE"; color: var(--accent); } th.sort.on.up::after { content: " \25B4"; }
td.best { color: #e9c46a; }
main.wide { max-width: none; }
.pill { white-space: nowrap; }
.pill.ok { color: #8fd6aa; border-color: #2f6e48; } .pill.mute { color: var(--muted); border-color: #3a3a37; }
.btn { font: inherit; font-size: 12px; padding: 2px 8px; border-radius: 4px; border: 1px solid #3a3a37; background: #232321; color: var(--ink2); cursor: pointer; white-space: nowrap; }
.btn:hover { border-color: #5a5a55; color: var(--ink); } .btn:disabled { opacity: .5; cursor: default; }
.btn.go { border-color: #2f6e48; color: #8fd6aa; } .btn.bad { border-color: #6e2f2f; color: #f08a8a; }
.btn.solid-bad { background: var(--crit); border-color: var(--crit); color: #fff; }
.acts { display: flex; flex-wrap: wrap; gap: 5px; justify-content: flex-end; }
.lb { display: grid; grid-template-columns: 280px minmax(0, 1fr); gap: 14px; }
.picker input { width: 100%; font: inherit; padding: 7px 10px; margin-bottom: 8px; color: var(--ink); background: #0d0d0d; border: 1px solid #3a3a37; border-radius: 4px; }
.st { display: grid; grid-template-columns: 1fr auto auto; gap: 8px; align-items: center; padding: 7px 10px; border-radius: 4px; cursor: pointer; border-left: 3px solid transparent; }
.st:hover { background: #222220; } .st.on { background: #2a2a28; border-left-color: var(--accent); }
.st .c { color: var(--ink2); font-variant-numeric: tabular-nums; font-size: 12.5px; }
.grp { color: var(--muted); font-size: 11.5px; text-transform: uppercase; letter-spacing: .06em; margin: 10px 10px 2px; }
.boards { display: grid; grid-template-columns: 1fr; gap: 14px; }
.board td, .board th { padding: 6px 4px; font-size: 12.5px; } .board .btn { padding: 1px 6px; font-size: 11.5px; } .board .acts { gap: 3px; } .card.board { padding: 14px 12px; }
.board th { font-size: 12px; }
.board td { white-space: nowrap; } .board td.stat { white-space: normal; max-width: 120px; line-height: 1.9; } .board td.car { max-width: 96px; overflow: hidden; text-overflow: ellipsis; }
tr.dim td { color: #5f5f59; } tr.dim td .pill { opacity: .7; }
tr.flag td { background: rgba(250,178,25,.05); }
tr.confirm td { white-space: normal !important; background: #2a1a1a; border-bottom: 1px solid var(--crit); color: #f0c0c0; font-size: 12.5px; }
tr.trace td { background: #141413; }
.stagehead { display: flex; align-items: baseline; gap: 14px; margin-bottom: 12px; flex-wrap: wrap; }
.stagehead h2 { margin: 0; font-size: 18px; } .stagehead .m { color: var(--muted); font-size: 12.5px; }
.chips { margin-left: auto; display: flex; border: 1px solid #3a3a37; border-radius: 4px; overflow: hidden; font-size: 12.5px; }
.chips span { padding: 3px 10px; color: var(--ink2); cursor: pointer; } .chips span.on { background: #3a3a37; color: var(--ink); }
.count { font-size: 11px; font-weight: 600; padding: 0 6px; border-radius: 9px; background: #4a3a10; color: var(--warn); }
.lbErr { color: #f08a8a; margin-bottom: 10px; }
@media (max-width: 1100px) { .tiles { grid-template-columns: repeat(3, 1fr); } .grid2, .grid3 { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<header>
  <h1><span>Earth</span> Rally stats</h1>
  <nav><a data-v="overview">Overview</a><a data-v="stages">Stages &amp; rallies</a><a data-v="versions">Versions &amp; errors</a><a data-v="boards">Leaderboards</a></nav>
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
  <div class="card" style="margin-bottom:14px"><h2>Players</h2><div class="sub">Different installs that sent stats: each counts once
      however often it plays. Counted from a number sent on its own, never with stages, and new after the player says No.</div>
    <div class="tiles" id="players" style="grid-template-columns: repeat(3, 1fr); margin-bottom:12px"></div>
    <div class="sub" id="playersSub"></div><div id="playersDaily"></div></div>
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

<section class="view" id="v-boards">
  <div class="lbErr" id="lbErr" style="display:none"></div>
  <div class="card" style="margin-bottom:14px; border-color:#5a4512"><h2>Flagged <span class="count" id="flagCount"></span></h2>
    <div class="sub">Runs the server held back (off the board until looked at) and runs other players reported. Approve puts it on the board and clears its reports; Hide takes it off (Restore undoes it). Every board, newest first.</div>
    <table id="flagged"></table></div>
  <div class="lb">
    <div class="card picker"><h2>Stages</h2><div class="sub">Every stage with a time on the online board. Number = runs; badge = flagged or reported.</div>
      <input id="stageFind" placeholder="Find a stage or rally">
      <div id="stageList"></div></div>
    <div>
      <div class="card" style="margin-bottom:14px">
        <div class="stagehead"><h2 id="stName">Choose a stage</h2><span class="m" id="stMeta"></span>
          <div class="chips" id="chips"><span data-mode="best">Best per player</span><span data-mode="all">Every run</span></div></div>
        <div class="sub" style="margin:0">Greyed: hidden, or a banned player (off the board, kept). Flagged rows show where they would place, with no position. Move: the run goes to the other board (both boards are worked out again).</div>
      </div>
      <div class="boards">
        <div class="card board"><h2>Stock</h2><div class="sub" id="subStock"></div><table id="bStock"></table></div>
        <div class="card board"><h2>Open</h2><div class="sub" id="subOpen"></div><table id="bOpen"></table></div>
      </div>
      <div class="foot">Changes go live on the board at once (the companion reads it the next time a stage ends). Ban takes every time of that player off every board; Unban puts them back. Reports: how many players reported the run; hover for their reasons.</div>
    </div>
  </div>
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
  $("allSub").innerHTML = esc(rw) + ". Times from the stats (stage ends, finished only): anonymous, every car and both boards together, so they read as " +
    "how fast people drive it, not a leaderboard. Click a column to sort. Players' own imported maps count together as <b>Own stages</b> (their names are never sent, so no times).";
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
  allStages();
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
  players();
  errors();
  show(view);
}

function players() {
  var p = data.players || {}, rw = rangeWords();
  $("players").innerHTML = [["All time", p.all_time, "The 12 months kept"], ["Last 7 days", p.last7, "Different players"],
    ["Last " + rw, p.in_range, "Different players"]].map(function (x) {
    return "<div class='tile'><div class='k'>" + esc(x[0]) + "</div><div class='v'>" + esc(num(x[1])) + "</div><div class='d'>" + esc(x[2]) + "</div></div>";
  }).join("");
  $("playersSub").textContent = "Per day, newest first (up to 14 days)";
  hbars("playersDaily", (p.daily || []).slice(-14).reverse().map(function (d) { return [d.day, d.players]; }), null,
    "No players counted yet.");
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

// ---- the full Stages table: sortable (click a heading; again to turn it round)
var sortBy = "runs", sortUp = false;
var STAGE_COLS = [
  ["Rally", "rally", false], ["Stage", "stage", false], ["Starts", "runs", false], ["Finishes", "finished", true],
  ["Finish rate", "rate", true], ["Best time", "best_s", true], ["Median time", "median_s", true],
  ["Resets / run", "resets", true], ["Retired", "failed", true], ["Quit", "quit", true], ["No ending", "noend", true],
];
function stageVal(s, k) {
  var own = s.rally === "custom";
  if (k === "rally") return rallyName(s.rally).toLowerCase();
  if (k === "stage") return own ? "" : String(s.stage || "").toLowerCase();
  if (k === "rate") return s.runs ? s.finished / s.runs : null;
  if (k === "noend") return Math.max(0, s.runs - s.finished - s.failed - s.quit);
  if ((k === "best_s" || k === "median_s") && own) return null;
  return s[k] == null ? null : Number(s[k]);
}
function allStages() {
  var rows = (data.stages || []).slice();
  if (!rows.length) { $("allStages").innerHTML = "<tr><td class='empty'>No stages run yet.</td></tr>"; return; }
  rows.sort(function (a, b) {
    var x = stageVal(a, sortBy), y = stageVal(b, sortBy);
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    var c = x < y ? -1 : x > y ? 1 : 0;
    return sortUp ? c : -c;
  });
  var max = Math.max.apply(null, rows.map(function (s) { return s.runs; })) || 1;
  var h = "<tr>" + STAGE_COLS.map(function (c) {
    return "<th class='sort" + (c[2] ? " n" : "") + (c[1] === sortBy ? " on" + (sortUp ? " up" : "") : "") + "' data-sort='" + c[1] + "'" +
      (c[1] === "noend" ? " title='Started, never ended: the game closed or crashed'" : "") + ">" + esc(c[0]) + "</th>";
  }).join("") + "</tr>";
  rows.forEach(function (s) {
    var own = s.rally === "custom";
    h += "<tr><td>" + esc(rallyName(s.rally)) + "</td><td>" + esc(own ? "–" : s.stage) + "</td>" +
      "<td><span class='bar' style='width:" + (s.runs / max * 120) + "px'></span>" + num(s.runs) + "</td><td class='n'>" + num(s.finished) +
      "</td><td class='n'>" + pct(s.finished, s.runs) + "</td><td class='n best'>" + (own ? "–" : mmss(s.best_s)) +
      "</td><td class='n'>" + (own ? "–" : mmss(s.median_s)) + "</td><td class='n'>" + (s.resets == null ? "–" : Number(s.resets).toFixed(1)) +
      "</td><td class='n'>" + num(s.failed) + "</td><td class='n'>" + num(s.quit) +
      "</td><td class='n'>" + num(stageVal(s, "noend")) + "</td></tr>";
  });
  $("allStages").innerHTML = h;
}
$("allStages").addEventListener("click", function (e) {
  var th = e.target.closest("th[data-sort]");
  if (!th) return;
  var k = th.getAttribute("data-sort");
  if (k === sortBy) sortUp = !sortUp; else { sortBy = k; sortUp = k === "rally" || k === "stage"; }
  allStages();
});

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

// ---- Leaderboards: the online board's moderation, through this Worker's /api/board/... (the Worker holds the board's
// admin token; this page holds only the dashboard key). After each action everything shown is read again.
var lb = { loaded: false, stages: [], flagged: [], stage: null, runs: [], sel: null, mode: "best", find: "", confirm: null, trace: null, busy: false };
function api(method, path) {
  return fetch("/api/board/" + path, { method: method, headers: { authorization: "Bearer " + key() }, cache: "no-store" })
    .then(function (r) {
      if (r.status === 401) { localStorage.removeItem(KEY_NAME); lock("That key did not work."); throw new Error("locked"); }
      return r.json().catch(function () { return {}; }).then(function (b) {
        if (!r.ok) throw new Error(b.error || "the server answered " + r.status);
        return b;
      });
    });
}
function lbError(msg) { $("lbErr").textContent = msg; $("lbErr").style.display = msg ? "block" : "none"; }
function loadBoards() {
  lb.loaded = true;
  var sel = lb.sel;
  return Promise.all([api("GET", "flagged"), api("GET", "stages"),
    sel ? api("GET", "stages/" + sel + "/runs").catch(function () { return null; }) : null])
    .then(function (x) {
      lb.flagged = x[0].runs || []; lb.stages = x[1].stages || [];
      if (sel && sel === lb.sel) {
        if (x[2]) { lb.stage = x[2].stage; lb.runs = x[2].runs || []; } else { lb.sel = null; lb.stage = null; lb.runs = []; }
      }
      lbError(""); drawBoards();
    })
    .catch(function (e) { if (e.message !== "locked") { lbError("Could not load the online board: " + e.message); drawBoards(); } });
}
function openStage(id) {
  lb.sel = id; lb.confirm = null; lb.trace = null;
  drawBoards();
  return api("GET", "stages/" + id + "/runs").then(function (b) {
    if (lb.sel !== id) return;
    lb.stage = b.stage; lb.runs = b.runs || []; lbError(""); drawBoards();
  }).catch(function (e) { if (e.message !== "locked") lbError("Could not load the stage: " + e.message); });
}
function ms(t) {
  if (t == null) return "–";
  var d = Math.round(t / 100), m = Math.floor(d / 600), x = d - m * 600;
  return m + ":" + String(Math.floor(x / 10)).padStart(2, "0") + "." + (x % 10);
}
function pen(t) { return t ? mmss(t / 1000) : ""; }
function two(n) { return String(n).padStart(2, "0"); }
function shortDay(at) { var d = new Date(at); return two(d.getDate()) + "/" + two(d.getMonth() + 1); }
function when(at) {
  var d = new Date(at);
  return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()] + " " + two(d.getHours()) + ":" + two(d.getMinutes());
}
function flagPills(f, mute) {
  return String(f || "").split(",").filter(Boolean).map(function (x) {
    return "<span class='pill " + (mute ? "mute" : /^(clock|resets|jump|speed)$/.test(x) ? "crit" : "warn") + "'>" + esc(x) + "</span>";
  }).join(" ");
}
function btn(a, r, label, cls) {
  return "<button class='btn" + (cls ? " " + cls : "") + "' data-act='" + a + "' data-run='" + esc(r.id) + "' data-player='" + esc(r.playerId) + "'" +
    (lb.busy ? " disabled" : "") + ">" + label + "</button>";
}
function drawBoards() {
  $("flagCount").textContent = lb.flagged.length;
  $("flagCount").style.display = lb.flagged.length ? "" : "none";
  // flagged and reported, every board
  var h = lb.flagged.length ? "<tr><th>When</th><th>Stage</th><th>Board</th><th>Player</th><th class='n'>Time</th><th>Car</th><th>Flags</th>" +
    "<th class='n' title='Server clock from token to submission, over the stage time'>Clock ratio</th><th class='n'>Reports</th><th></th></tr>" : "";
  lb.flagged.forEach(function (r) {
    h += "<tr class='flag'><td>" + esc(when(r.at)) + "</td><td><a class='lnk' href='#boards' data-stage='" + esc(r.stageId) + "'>" + esc(r.stage) + "</a></td><td>" +
      esc(r.board === "open" ? "Open" : "Stock") + "</td><td>" + esc(r.player) + "</td><td class='n'>" + esc(ms(r.timeMs)) + "</td><td>" + esc(r.car || "–") +
      "</td><td>" + (r.flags ? flagPills(r.flags) : "<span style='color:var(--muted)'>–</span>") + "</td><td class='n'>" + (r.wallRatio == null ? "–" : esc(Number(r.wallRatio).toFixed(2))) +
      "</td><td class='n'>" + num(r.reports) + "</td><td><div class='acts'>" + btn("trace", r, "View trace") + btn("approve", r, "Approve", "go") + btn("hide", r, "Hide", "bad") + "</div></td></tr>";
    if (lb.trace && lb.trace.id === r.id) h += traceRow(10);
  });
  $("flagged").innerHTML = h || "<tr><td class='empty'>Nothing flagged or reported.</td></tr>";
  // the stage list, by rally
  var q = lb.find.toLowerCase(), groups = {}, order = [];
  lb.stages.forEach(function (s) {
    if (q && (String(s.name) + " " + String(s.rally || "")).toLowerCase().indexOf(q) < 0) return;
    var g = s.rally || "No rally (own stages)";
    if (!groups[g]) { groups[g] = []; order.push(g); }
    groups[g].push(s);
  });
  $("stageList").innerHTML = order.length ? order.map(function (g) {
    return "<div class='grp'>" + esc(g) + "</div>" + groups[g].map(function (s) {
      var bad = (s.flagged || 0) + (s.reported || 0);
      return "<div class='st" + (s.id === lb.sel ? " on" : "") + "' data-stage='" + esc(s.id) + "'><span>" + esc(s.name) + "</span><span class='c'>" + num(s.runs) + "</span>" +
        (bad ? "<span class='count' data-tip='" + esc(num(s.flagged) + " flagged, " + num(s.reported) + " reported") + "'>" + bad + "</span>" : "<span></span>") + "</div>";
    }).join("");
  }).join("") : "<div class='empty'>" + (lb.stages.length ? "No stage matches." : lb.loaded ? "No stages on the online board yet." : "Loading…") + "</div>";
  // the chosen stage
  document.querySelectorAll("#chips span").forEach(function (c) { c.classList.toggle("on", c.getAttribute("data-mode") === lb.mode); });
  var st = lb.sel ? lb.stage : null;
  $("stName").textContent = st ? st.name : lb.sel ? "Loading…" : "Choose a stage";
  $("stMeta").textContent = st ? [st.rally || "No rally", st.lengthM ? (st.lengthM / 1000).toFixed(1) + " km" : null,
    st.createdAt ? "first run " + new Date(st.createdAt).toISOString().slice(0, 10) : null, "stage id " + st.id].filter(Boolean).join(" · ") : "";
  boardTable("stock", st); boardTable("open", st);
}
function traceRow(span) {
  var t = lb.trace;
  if (!t.points) return "<tr class='trace'><td colspan='" + span + "'>" + esc(t.error || "Loading the trace…") + "</td></tr>";
  var p = t.points.filter(function (x) { return Array.isArray(x) && isFinite(x[1]) && isFinite(x[2]); }), W = 900, H = 260;
  if (p.length < 2) return "<tr class='trace'><td colspan='" + span + "'>No trace.</td></tr>";
  var la = p.map(function (x) { return x[1]; }), lo = p.map(function (x) { return x[2]; });
  var la0 = Math.min.apply(null, la), la1 = Math.max.apply(null, la), lo0 = Math.min.apply(null, lo), lo1 = Math.max.apply(null, lo);
  var k = Math.cos((la0 + la1) / 2 * Math.PI / 180), sc = Math.min((W - 20) / ((lo1 - lo0) * k || 1e-9), (H - 20) / ((la1 - la0) || 1e-9));
  var xy = p.map(function (x) { return [(10 + (x[2] - lo0) * k * sc).toFixed(1), (H - 10 - (x[1] - la0) * sc).toFixed(1)]; });
  var resets = (t.resets || []).length;
  return "<tr class='trace'><td colspan='" + span + "'><svg width='" + W + "' height='" + H + "' style='max-width:100%'>" +
    "<polyline fill='none' stroke='var(--s1)' stroke-width='2' points='" + xy.map(function (q) { return q.join(","); }).join(" ") + "'/>" +
    "<circle r='5' fill='#4fb87a' cx='" + xy[0][0] + "' cy='" + xy[0][1] + "'/></svg>" +
    "<div class='sub'>" + esc(p.length + " points over " + ms(p[p.length - 1][0]) + (resets ? ", " + resets + " resets" : "") +
      (t.slow_ms ? ", slow motion " + ms(t.slow_ms) : "") + ". Green: the start.") + "</div></td></tr>";
}
function boardTable(board, st) {
  var id = board === "stock" ? "bStock" : "bOpen", other = board === "stock" ? "Open" : "Stock";
  var all = st ? lb.runs.filter(function (r) { return r.board === board; }) : [];
  var on = all.filter(function (r) { return r.isBest && r.status === "ok" && !r.banned; }).length;
  $(board === "stock" ? "subStock" : "subOpen").textContent = (board === "stock" ? "The game's own cars as they come" : "Anything") +
    (st ? " · " + on + " on the board · " + all.length + (all.length === 1 ? " run" : " runs") : "");
  if (!st) { $(id).innerHTML = ""; return; }
  var rows = lb.mode === "all" ? all.slice() : all.filter(function (r) { return r.isBest || r.status !== "ok"; });
  rows.sort(function (a, b) { return a.timeMs - b.timeMs || a.id - b.id; });
  if (!rows.length) { $(id).innerHTML = "<tr><td class='empty'>No runs on this board.</td></tr>"; return; }
  var h = "<tr><th class='n'>Pos</th><th>Player</th><th class='n'>Time</th><th class='n'>Pen.</th><th>Car</th><th>Date</th><th>Mod</th><th>Status, flags</th><th class='n' title='Reports'>Rep.</th><th></th></tr>";
  var placed = 0, pos = 0, lastT = null;
  rows.forEach(function (r) {
    var s = r.banned ? "banned" : r.status, dim = s === "hidden" || s === "banned", p = "–";
    if (r.isBest && r.status === "ok" && !r.banned) { placed++; if (r.timeMs !== lastT) { pos = placed; lastT = r.timeMs; } p = pos; }
    var acts = s === "banned" ? btn("unban", r, "Unban", "go") :
      s === "hidden" ? btn("restore", r, "Restore", "go") :
      s === "flagged" ? btn("approve", r, "Approve", "go") + btn("hide", r, "Hide", "bad") :
      (r.reports ? btn("approve", r, "Approve", "go") : "") + btn("hide", r, "Hide");
    acts += btn("move", r, "&#8594; " + other);
    if (s !== "banned") acts += btn("ban", r, "Ban", "bad");
    var stp = s === "ok" ? "<span class='pill ok'>ok</span>" : s === "flagged" ? "<span class='pill warn'>flagged</span>" : "<span class='pill mute'>" + esc(s) + "</span>";
    h += "<tr class='" + (dim ? "dim" : s === "flagged" ? "flag" : "") + "'><td class='n'>" + p + "</td><td>" + esc(r.player) + "</td><td class='n'" + (p === 1 ? " style='color:#e9c46a'" : "") + ">" +
      esc(ms(r.timeMs)) + "</td><td class='n'>" + esc(pen(r.penaltyMs)) + "</td><td class='car' title='" + esc(r.car || "") + "'>" + esc(r.car || "–") + "</td><td>" + esc(shortDay(r.at)) +
      "</td><td>" + esc(r.modVersion || "–") + "</td><td class='stat'>" + stp + (r.flags ? " " + flagPills(r.flags, dim) : "") +
      "</td><td class='n'" + (r.reasons ? " data-tip='" + esc(r.reasons) + "'" : "") + ">" + (r.reports ? num(r.reports) : "") + "</td><td><div class='acts'>" + acts + "</div></td></tr>";
    var c = lb.confirm;
    if (c && c.id === r.id) {
      var say = c.act === "ban"
        ? "Ban <b>" + esc(r.player) + "</b>? Every time of theirs leaves every board, and the game refuses their new runs. Unban undoes it."
        : "Move this run of <b>" + esc(r.player) + "</b> (" + esc(ms(r.timeMs)) + ") to the " + other + " board? Both boards are worked out again.";
      h += "<tr class='confirm'><td></td><td colspan='8'>" + say + "</td><td><div class='acts'>" +
        btn("do-" + c.act, r, c.act === "ban" ? "Ban" : "Move", "solid-bad") + "<button class='btn' data-act='cancel'>Cancel</button></div></td></tr>";
    }
  });
  $(id).innerHTML = h;
}
function act(a, run, player) {
  if (a === "cancel") { lb.confirm = null; drawBoards(); return; }
  if (a === "ban" || a === "move") { lb.confirm = { id: Number(run), act: a }; drawBoards(); return; }
  if (a === "trace") {
    if (lb.trace && lb.trace.id === Number(run)) { lb.trace = null; drawBoards(); return; }
    var t = lb.trace = { id: Number(run) };
    drawBoards();
    api("GET", "runs/" + run).then(function (b) { t.points = b.trace || []; t.resets = b.resets; t.slow_ms = b.slow_ms; })
      .catch(function (e) { t.error = "Could not load the trace: " + e.message; })
      .then(function () { if (lb.trace === t) drawBoards(); });
    return;
  }
  var path = a === "do-ban" ? "players/" + player + "/ban" : a === "unban" ? "players/" + player + "/unban" :
    a === "do-move" ? "runs/" + run + "/move" : "runs/" + run + "/" + a;
  lb.busy = true; lb.confirm = null; drawBoards();
  api("POST", path).then(function () { lbError(""); return true; })
    .catch(function (e) { if (e.message !== "locked") lbError("That did not work: " + e.message); return false; })
    .then(function (ok) {
      lb.busy = false;
      if (!ok) { drawBoards(); return; }
      return loadBoards();
    });
}
$("v-boards").addEventListener("click", function (e) {
  var b = e.target.closest("button[data-act]");
  if (b) { if (!b.disabled) act(b.getAttribute("data-act"), b.getAttribute("data-run"), b.getAttribute("data-player")); return; }
  var s = e.target.closest("[data-stage]");
  if (s) { e.preventDefault(); openStage(s.getAttribute("data-stage")); return; }
  var c = e.target.closest("#chips span");
  if (c) { lb.mode = c.getAttribute("data-mode"); lb.confirm = null; drawBoards(); }
});
$("stageFind").addEventListener("input", function () { lb.find = this.value; drawBoards(); });

// ---- views and range
function show(v) {
  if (["overview", "stages", "versions", "boards"].indexOf(v) < 0) v = "overview";
  view = v;
  document.querySelectorAll(".view").forEach(function (x) { x.classList.toggle("on", x.id === "v-" + v); });
  document.querySelectorAll("nav [data-v]").forEach(function (b) { b.classList.toggle("on", b.dataset.v === v); });
  if (v === "overview" && data) daily();
  $("main").classList.toggle("wide", v === "boards");
  if (v === "boards" && data && !lb.loaded) loadBoards();
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
