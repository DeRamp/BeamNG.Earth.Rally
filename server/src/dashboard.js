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
@media (hover: hover) { tr:hover td { background: #222220; } }
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
@media (hover: hover) { .btn:hover { border-color: #5a5a55; color: var(--ink); } }
.btn:disabled { opacity: .5; cursor: default; }
.btn.go { border-color: #2f6e48; color: #8fd6aa; } .btn.bad { border-color: #6e2f2f; color: #f08a8a; }
.btn.solid-bad { background: var(--crit); border-color: var(--crit); color: #fff; }
.acts { display: flex; flex-wrap: wrap; gap: 5px; justify-content: flex-end; }
.lb { display: grid; grid-template-columns: 280px minmax(0, 1fr); gap: 14px; }
.picker input { width: 100%; font: inherit; padding: 7px 10px; margin-bottom: 8px; color: var(--ink); background: #0d0d0d; border: 1px solid #3a3a37; border-radius: 4px; }
.st { display: grid; grid-template-columns: 1fr auto auto; gap: 8px; align-items: center; padding: 7px 10px; border-radius: 4px; cursor: pointer; border-left: 3px solid transparent; }
@media (hover: hover) { .st:hover { background: #222220; } }
.st.on { background: #2a2a28; border-left-color: var(--accent); }
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
/* the Board stats tab (docs/mockups-board-stats/dashboard.html) */
.grid2e { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
@media (max-width: 1100px) { .tiles { grid-template-columns: repeat(3, 1fr); } .grid2, .grid3, .grid2e { grid-template-columns: 1fr; } }
/* a phone (docs/mockups-board-stats/dashboard.html, Proposed): .desk only on a wide screen, .phonly only on a phone */
.phonly, .gone { display: none; }
.pickBtn { align-items: center; justify-content: space-between; gap: 8px; width: 100%; font: inherit; padding: 10px 12px; color: var(--ink); background: #0d0d0d; border: 1px solid #3a3a37; border-radius: 6px; text-align: left; cursor: pointer; }
.pickBtn .sm { color: var(--muted); font-size: 12px; }
.mrow { display: grid; grid-template-columns: 30px minmax(0, 1fr) auto; gap: 8px; align-items: center; padding: 9px 4px; border-bottom: 1px solid #232321; cursor: pointer; }
.mrow .p { color: var(--ink2); text-align: right; font-variant-numeric: tabular-nums; }
.mrow .nm div { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; } .mrow .nm .s { color: var(--muted); font-size: 12px; }
.mrow .t { font-variant-numeric: tabular-nums; text-align: right; }
.mrow.open { background: #222220; border-bottom: 0; } .mrow.dim, .mrow.dim .p { color: #5f5f59; } .mrow.flag { background: rgba(250,178,25,.05); }
.mdet { background: #222220; padding: 4px 8px 10px 42px; border-bottom: 1px solid #232321; font-size: 12.5px; color: var(--ink2); overflow-wrap: anywhere; }
.mdet .acts, .mflag .acts { justify-content: flex-start; margin-top: 8px; gap: 6px; }
.mdet .btn, .mflag .btn { padding: 8px 12px; font-size: 13px; min-height: 36px; }
.mconf { margin-top: 8px; padding: 8px 10px; background: #2a1a1a; border: 1px solid var(--crit); border-radius: 4px; color: #f0c0c0; }
.mflag { padding: 10px 2px; border-bottom: 1px solid #232321; overflow-wrap: anywhere; }
.mflag .l1 { display: flex; justify-content: space-between; gap: 8px; } .mflag .l2 { color: var(--muted); font-size: 12px; margin: 2px 0 6px; }
.mflag .mut { color: var(--muted); font-size: 12px; }
.mtrace { margin-top: 8px; }
.boardSw { display: flex; border: 1px solid #3a3a37; border-radius: 4px; overflow: hidden; margin: 2px 0 8px; }
.boardSw span { flex: 1; text-align: center; padding: 9px 0; color: var(--ink2); cursor: pointer; } .boardSw span.on { background: #3a3a37; color: var(--ink); }
@media (max-width: 700px) {
  header { padding: 12px 14px 0; gap: 8px; }
  header h1 { font-size: 17px; }
  .who { margin-left: auto; }
  nav { order: 5; margin: 0 -14px; padding: 0 10px 8px; width: calc(100% + 28px); overflow-x: auto; flex-wrap: nowrap; scrollbar-width: none; }
  nav::-webkit-scrollbar { display: none; }
  nav a { white-space: nowrap; flex: none; }
  .range { order: 6; margin: 0 0 10px; width: 100%; }
  .range span { flex: 1; text-align: center; padding: 6px 0; }
  body.norange .range { display: none; }
  main { padding: 12px 10px 30px; }
  .tiles { grid-template-columns: 1fr 1fr !important; gap: 8px; }
  .tile { padding: 10px 12px; min-width: 0; } .tile .v { font-size: 22px; }
  .grid2, .grid2e, .grid3, .lb { grid-template-columns: 1fr; gap: 10px; }
  .card { padding: 12px; }
  .hbar-row { grid-template-columns: 110px minmax(0, 1fr) 44px; }
  .legend { flex-wrap: wrap; }
  .desk { display: none !important; } .phonly { display: block; } .pickBtn.phonly { display: flex; }
  .gone { display: none !important; }
  .scrollx { overflow-x: auto; }
  .picker.shut { display: none; }
  #lock { margin: 6vh 12px; padding: 20px; }
}
</style>
</head>
<body>
<header>
  <h1><span>Earth</span> Rally stats</h1>
  <nav><a data-v="overview">Overview</a><a data-v="stages">Stages &amp; rallies</a><a data-v="versions">Versions &amp; errors</a><a data-v="boards">Leaderboards</a><a data-v="bstats">Board stats</a></nav>
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
      however often it plays. Counted from a number sent in a message of its own and kept in a table apart from sessions and stages, with nothing linking them; new after the player says No.</div>
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
    <div class="card"><h2>Most-run stages</h2><div class="sub" id="topSub"></div><div class="scrollx"><table id="topStages"></table></div></div>
    <div class="card"><h2>New errors</h2><div class="sub" id="newErrSub"></div><div class="scrollx"><table id="newErrors"></table></div>
      <div class="sub" style="margin-top:10px">"Open issue" starts a GitHub issue with the code, versions and counts filled in.</div></div>
  </div>
  <div class="foot" id="foot"></div>
</section>

<section class="view" id="v-stages">
  <div class="card" style="margin-bottom:14px"><h2>Stages</h2><div class="sub" id="allSub"></div><div class="scrollx"><table id="allStages"></table></div></div>
  <div class="card"><h2>Rallies</h2><div class="sub">Started = the first stage of the running order begun; finished = every stage done in turn, in one game session.</div>
    <div class="scrollx"><table id="rallies"></table></div></div>
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
    <div class="scrollx"><table id="errors"></table></div></div>
</section>

<section class="view" id="v-boards">
  <div class="lbErr" id="lbErr" style="display:none"></div>
  <div class="card" style="margin-bottom:14px; border-color:#5a4512"><h2>Flagged <span class="count" id="flagCount"></span></h2>
    <div class="sub desk">Runs the server held back (off the board until looked at) and runs other players reported. Approve puts it on the board and clears its reports; Hide takes it off (Restore undoes it). Every board, newest first.</div>
    <div class="desk scrollx"><table id="flagged"></table></div><div class="phonly" id="flaggedPh"></div></div>
  <div class="lb">
    <button class="pickBtn phonly" id="pickBtn"></button>
    <div class="card picker" id="pickerCard"><h2>Stages</h2><div class="sub">Every stage with a time on the online board. Number = runs; badge = flagged or reported.</div>
      <input id="stageFind" placeholder="Find a stage or rally">
      <div id="stageList"></div></div>
    <div>
      <div class="card" style="margin-bottom:14px">
        <div class="stagehead"><h2 id="stName">Choose a stage</h2><span class="m" id="stMeta"></span>
          <div class="chips" id="chips"><span data-mode="best">Best per player</span><span data-mode="all">Every run</span></div></div>
        <div class="sub desk" style="margin:0">Greyed: hidden, or a banned player (off the board, kept). Flagged rows show where they would place, with no position. Move: the run goes to the other board (both boards are worked out again).</div>
      </div>
      <div class="boards">
        <div class="card board desk"><h2>Stock</h2><div class="sub" id="subStock"></div><table id="bStock"></table></div>
        <div class="card board desk"><h2>Open</h2><div class="sub" id="subOpen"></div><table id="bOpen"></table></div>
        <div class="card board phonly" id="bPhone"></div>
      </div>
      <div class="foot desk">Changes go live on the board at once (the companion reads it the next time a stage ends). Ban takes every time of that player off every board; Unban puts them back. Reports: how many players reported the run; hover for their reasons.</div>
    </div>
  </div>
</section>

<section class="view" id="v-bstats">
  <div class="lbErr" id="bsErr" style="display:none"></div>
  <div class="tiles" id="bsTiles"></div>
  <div class="grid2">
    <div class="card"><h2>Runs per day</h2><div class="sub" id="bsDailySub"></div>
      <div class="legend"><span><i style="background:var(--s1); height:10px; width:12px"></i>Runs</span><span><i style="background:var(--s2)"></i>Players that day</span></div>
      <svg id="bsDaily" width="100%" height="210"></svg></div>
    <div class="card"><h2>Players over time</h2><div class="sub">Everyone who has sent a time, by the day of their first</div>
      <svg id="bsGrowth" width="100%" height="210"></svg></div>
  </div>
  <div class="grid2e">
    <div class="card"><h2>Players</h2><div class="sub">Every name on the board. Fastest = stage records held<span class="desk">; podiums = top-3 places, either board</span></div>
      <div class="scrollx"><table id="bsPlayers"></table></div></div>
    <div class="card"><h2>Stages</h2><div class="sub">Most driven first. Record = fastest on the Stock board</div>
      <div class="scrollx"><table id="bsStages"></table></div></div>
  </div>
  <div class="grid2e">
    <div class="card"><h2>Rallies</h2><div class="sub">Runs per rally</div><div id="bsRallies"></div></div>
    <div class="card"><h2>Cars</h2><div class="sub">Runs per car</div><div id="bsCars"></div></div>
  </div>
  <div class="grid2e">
    <div class="card"><h2>Mod version</h2><div class="sub" id="bsModsSub"></div><div id="bsMods"></div></div>
    <div class="card"><h2>Time of day</h2><div class="sub">When runs are sent, your local time</div>
      <svg id="bsHours" width="100%" height="110"></svg></div>
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

// ---- tooltips: any element with data-tip (escaped text, new lines kept); none on a touch screen (a tap would leave
// one standing)
var tip = $("tip");
var noHover = !!(window.matchMedia && window.matchMedia("(hover: none)").matches);
function isPhone() { return !!(window.matchMedia && window.matchMedia("(max-width: 700px)").matches); }
document.addEventListener("mousemove", function (e) {
  if (noHover) return;
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
    "how fast people drive it, not a leaderboard. Click a column to sort. Players' own stages are sent by name from 1.8.2; rows from older versions, sent as <code>custom</code>, count together as <b>Own stages</b> (no names, so no times).";
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
    if (noHover) return;
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
var lb = { loaded: false, stages: [], flagged: [], stage: null, runs: [], sel: null, mode: "best", find: "", confirm: null, trace: null, busy: false,
  pickOpen: false, phBoard: "stock", phOpen: null };     // (the phone's stage list open, its board, its opened row)
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
  lb.sel = id; lb.confirm = null; lb.trace = null; lb.pickOpen = false; lb.phOpen = null;
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
  // (the same on a phone: a card each)
  $("flaggedPh").innerHTML = lb.flagged.length ? lb.flagged.map(function (r) {
    return "<div class='mflag'><div class='l1'><b>" + esc(r.player) + "</b><span>" + esc(ms(r.timeMs)) + "</span></div>" +
      "<div class='l2'><a class='lnk' href='#boards' data-stage='" + esc(r.stageId) + "'>" + esc(r.stage) + "</a> · " +
      esc((r.board === "open" ? "Open" : "Stock") + " · " + (r.car || "–") + " · " + when(r.at)) + "</div>" +
      "<div>" + (r.flags ? flagPills(r.flags) + " " : "") + "<span class='mut'>" + esc((r.wallRatio == null ? "" : "clock ratio " + Number(r.wallRatio).toFixed(2) + " · ") +
        num(r.reports) + (Number(r.reports) === 1 ? " report" : " reports")) + "</span></div>" +
      "<div class='acts'>" + btn("trace", r, "View trace") + btn("approve", r, "Approve", "go") + btn("hide", r, "Hide", "bad") + "</div>" +
      (lb.trace && lb.trace.id === r.id ? "<div class='mtrace'>" + traceInner() + "</div>" : "") + "</div>";
  }).join("") : "<div class='empty'>Nothing flagged or reported.</div>";
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
  // the chosen stage (on a phone the stage list is one button that opens it)
  var cur = lb.sel ? lb.stage : null;
  $("pickBtn").innerHTML = "<span>" + (cur ? esc(cur.name) + " <span class='sm'>· " + esc(cur.rally || "No rally") + "</span>" :
    lb.sel ? "Loading…" : "Choose a stage") + "</span><span>" + (lb.pickOpen ? "&#9652;" : "&#9662;") + "</span>";
  $("pickerCard").classList.toggle("shut", !lb.pickOpen);
  document.querySelectorAll("#chips span").forEach(function (c) { c.classList.toggle("on", c.getAttribute("data-mode") === lb.mode); });
  var st = lb.sel ? lb.stage : null;
  $("stName").textContent = st ? st.name : lb.sel ? "Loading…" : "Choose a stage";
  $("stMeta").innerHTML = st ? esc([st.rally || "No rally", st.lengthM ? (st.lengthM / 1000).toFixed(1) + " km" : null].filter(Boolean).join(" · ")) +
    "<span class='desk'>" + esc([st.createdAt ? "first run " + new Date(st.createdAt).toISOString().slice(0, 10) : null, "stage id " + st.id]
      .filter(Boolean).map(function (x) { return " · " + x; }).join("")) + "</span>" : "";
  boardTable("stock", st); boardTable("open", st); phoneBoard(st);
}
function traceRow(span) { return "<tr class='trace'><td colspan='" + span + "'>" + traceInner() + "</td></tr>"; }
// (the trace drawn to fit: 900 wide at most, narrower on a phone)
function traceInner() {
  var t = lb.trace;
  if (!t.points) return esc(t.error || "Loading the trace…");
  var p = t.points.filter(function (x) { return Array.isArray(x) && isFinite(x[1]) && isFinite(x[2]); }), W = 900, H = 260;
  if (p.length < 2) return "No trace.";
  var la = p.map(function (x) { return x[1]; }), lo = p.map(function (x) { return x[2]; });
  var la0 = Math.min.apply(null, la), la1 = Math.max.apply(null, la), lo0 = Math.min.apply(null, lo), lo1 = Math.max.apply(null, lo);
  var k = Math.cos((la0 + la1) / 2 * Math.PI / 180), sc = Math.min((W - 20) / ((lo1 - lo0) * k || 1e-9), (H - 20) / ((la1 - la0) || 1e-9));
  var xy = p.map(function (x) { return [(10 + (x[2] - lo0) * k * sc).toFixed(1), (H - 10 - (x[1] - la0) * sc).toFixed(1)]; });
  var resets = (t.resets || []).length;
  return "<svg viewBox='0 0 " + W + " " + H + "' width='" + W + "' height='" + H + "' style='max-width:100%; height:auto'>" +
    "<polyline fill='none' stroke='var(--s1)' stroke-width='2' points='" + xy.map(function (q) { return q.join(","); }).join(" ") + "'/>" +
    "<circle r='5' fill='#4fb87a' cx='" + xy[0][0] + "' cy='" + xy[0][1] + "'/></svg>" +
    "<div class='sub'>" + esc(p.length + " points over " + ms(p[p.length - 1][0]) + (resets ? ", " + resets + " resets" : "") +
      (t.slow_ms ? ", slow motion " + ms(t.slow_ms) : "") + ". Green: the start.") + "</div>";
}
// A board's rows as shown: sorted, placed (equal times share a place; flagged and greyed rows get none), with their
// status and actions. Used by the wide table and the phone's list alike.
function boardRows(board, st) {
  var other = board === "stock" ? "Open" : "Stock";
  var all = st ? lb.runs.filter(function (r) { return r.board === board; }) : [];
  var on = all.filter(function (r) { return r.isBest && r.status === "ok" && !r.banned; }).length;
  var rows = lb.mode === "all" ? all.slice() : all.filter(function (r) { return r.isBest || r.status !== "ok"; });
  rows.sort(function (a, b) { return a.timeMs - b.timeMs || a.id - b.id; });
  var placed = 0, pos = 0, lastT = null;
  return { all: all, on: on, other: other, rows: rows.map(function (r) {
    var s = r.banned ? "banned" : r.status, dim = s === "hidden" || s === "banned", p = "–";
    if (r.isBest && r.status === "ok" && !r.banned) { placed++; if (r.timeMs !== lastT) { pos = placed; lastT = r.timeMs; } p = pos; }
    var acts = s === "banned" ? btn("unban", r, "Unban", "go") :
      s === "hidden" ? btn("restore", r, "Restore", "go") :
      s === "flagged" ? btn("approve", r, "Approve", "go") + btn("hide", r, "Hide", "bad") :
      (r.reports ? btn("approve", r, "Approve", "go") : "") + btn("hide", r, "Hide");
    acts += btn("move", r, "&#8594; " + other);
    if (s !== "banned") acts += btn("ban", r, "Ban", "bad");
    return { r: r, s: s, dim: dim, p: p, acts: acts };
  }) };
}
function statusPill(s) {
  return s === "ok" ? "<span class='pill ok'>ok</span>" : s === "flagged" ? "<span class='pill warn'>flagged</span>" : "<span class='pill mute'>" + esc(s) + "</span>";
}
function confirmSay(c, r, other) {
  return c.act === "ban"
    ? "Ban <b>" + esc(r.player) + "</b>? Every time of theirs leaves every board, and the game refuses their new runs. Unban undoes it."
    : "Move this run of <b>" + esc(r.player) + "</b> (" + esc(ms(r.timeMs)) + ") to the " + other + " board? Both boards are worked out again.";
}
function confirmBtns(c, r) {
  return btn("do-" + c.act, r, c.act === "ban" ? "Ban" : "Move", "solid-bad") + "<button class='btn' data-act='cancel'>Cancel</button>";
}
function boardTable(board, st) {
  var id = board === "stock" ? "bStock" : "bOpen", b = boardRows(board, st);
  $(board === "stock" ? "subStock" : "subOpen").textContent = (board === "stock" ? "The game's own cars as they come" : "Anything") +
    (st ? " · " + b.on + " on the board · " + b.all.length + (b.all.length === 1 ? " run" : " runs") : "");
  if (!st) { $(id).innerHTML = ""; return; }
  if (!b.rows.length) { $(id).innerHTML = "<tr><td class='empty'>No runs on this board.</td></tr>"; return; }
  var h = "<tr><th class='n'>Pos</th><th>Player</th><th class='n'>Time</th><th class='n'>Pen.</th><th>Car</th><th>Date</th><th>Mod</th><th>Status, flags</th><th class='n' title='Reports'>Rep.</th><th></th></tr>";
  b.rows.forEach(function (x) {
    var r = x.r, p = x.p;
    h += "<tr class='" + (x.dim ? "dim" : x.s === "flagged" ? "flag" : "") + "'><td class='n'>" + p + "</td><td>" + esc(r.player) + "</td><td class='n'" + (p === 1 ? " style='color:#e9c46a'" : "") + ">" +
      esc(ms(r.timeMs)) + "</td><td class='n'>" + esc(pen(r.penaltyMs)) + "</td><td class='car' title='" + esc(r.car || "") + "'>" + esc(r.car || "–") + "</td><td>" + esc(shortDay(r.at)) +
      "</td><td>" + esc(r.modVersion || "–") + "</td><td class='stat'>" + statusPill(x.s) + (r.flags ? " " + flagPills(r.flags, x.dim) : "") +
      "</td><td class='n'" + (r.reasons ? " data-tip='" + esc(r.reasons) + "'" : "") + ">" + (r.reports ? num(r.reports) : "") + "</td><td><div class='acts'>" + x.acts + "</div></td></tr>";
    var c = lb.confirm;
    if (c && c.id === r.id) {
      h += "<tr class='confirm'><td></td><td colspan='8'>" + confirmSay(c, r, b.other) + "</td><td><div class='acts'>" + confirmBtns(c, r) + "</div></td></tr>";
    }
  });
  $(id).innerHTML = h;
}
// The phone's board: one at a time (Stock / Open), a row a run; a tap opens its details and actions.
function phoneBoard(st) {
  var el = $("bPhone");
  el.classList.toggle("gone", !st);
  if (!st) { el.innerHTML = ""; return; }
  var sb = boardRows("stock", st), so = boardRows("open", st), b = lb.phBoard === "open" ? so : sb;
  var h = "<div class='boardSw'><span data-sw='stock' class='" + (b === sb ? "on" : "") + "'>Stock · " + sb.on + "</span>" +
    "<span data-sw='open' class='" + (b === so ? "on" : "") + "'>Open · " + so.on + "</span></div>";
  if (!b.rows.length) h += "<div class='empty'>No runs on this board.</div>";
  b.rows.forEach(function (x) {
    var r = x.r, open = lb.phOpen === r.id, c = lb.confirm;
    h += "<div class='mrow" + (open ? " open" : "") + (x.dim ? " dim" : x.s === "flagged" ? " flag" : "") + "' data-row='" + esc(r.id) + "'>" +
      "<span class='p'>" + x.p + "</span><div class='nm'><div>" + esc(r.player) + (x.s === "ok" ? "" : " " + statusPill(x.s)) + "</div>" +
      "<div class='s'>" + esc((r.car || "–") + " · " + shortDay(r.at)) + "</div></div>" +
      "<div class='t'" + (x.p === 1 ? " style='color:#e9c46a'" : "") + ">" + esc(ms(r.timeMs)) + "</div></div>";
    if (!open) return;
    h += "<div class='mdet'>" + esc("Mod " + (r.modVersion || "–") + " · " + (r.penaltyMs ? "penalty " + pen(r.penaltyMs) : "no penalty") + " · " +
        (r.reports ? num(r.reports) + (Number(r.reports) === 1 ? " report" : " reports") + (r.reasons ? ": " + r.reasons : "") : "no reports") + " · ") +
      statusPill(x.s) + (r.flags ? " " + flagPills(r.flags, x.dim) : "") +
      (c && c.id === r.id ? "<div class='mconf'>" + confirmSay(c, r, b.other) + "</div><div class='acts'>" + confirmBtns(c, r) + "</div>"
        : "<div class='acts'>" + btn("trace", r, "View trace") + x.acts + "</div>") +
      (lb.trace && lb.trace.id === r.id ? "<div class='mtrace'>" + traceInner() + "</div>" : "") + "</div>";
  });
  el.innerHTML = h + "<div class='sub' style='margin:8px 0 0'>Tap a row for its details and actions.</div>";
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
  if (c) { lb.mode = c.getAttribute("data-mode"); lb.confirm = null; drawBoards(); return; }
  // (the phone's: the stage list button, the Stock / Open switch, a row opened or closed)
  if (e.target.closest("#pickBtn")) { lb.pickOpen = !lb.pickOpen; drawBoards(); return; }
  var sw = e.target.closest("[data-sw]");
  if (sw) { lb.phBoard = sw.getAttribute("data-sw"); lb.phOpen = null; lb.confirm = null; lb.trace = null; drawBoards(); return; }
  var row = e.target.closest("[data-row]");
  if (row) { var id = Number(row.getAttribute("data-row")); lb.phOpen = lb.phOpen === id ? null : id; lb.confirm = null; lb.trace = null; drawBoards(); }
});
$("stageFind").addEventListener("input", function () { lb.find = this.value; drawBoards(); });

// ---- Board stats: the online board's own numbers (/api/board/stats), read when the tab opens and when the range
// changes on it
var bs = { data: null, days: null, asked: 0 };
function bsError(msg) { $("bsErr").textContent = msg; $("bsErr").style.display = msg ? "block" : "none"; }
function loadBStats() {
  var mine = ++bs.asked;
  bs.days = days;
  api("GET", "stats?days=" + days).then(function (d) {
    if (mine !== bs.asked) return;
    bs.data = d; bsError(""); drawBStats();
  }).catch(function (e) {
    if (mine !== bs.asked || e.message === "locked") return;
    bsError("Could not load the board stats: " + e.message + (bs.data ? ". Showing the last ones loaded (" + bsRange(bs.data) + ")." : ""));
  });
}
function bsRange(d) { return d.days === 365 ? "12 months" : d.days + " days"; }
function drawBStats() {
  var d = bs.data;
  if (!d) return;
  var t = d.totals || {};
  var tiles = [
    ["Players", num(t.players), "With a name on the board"], ["Driving", num(t.drivers), "Sent at least one time"],
    ["Active, 7 days", num(t.active7), "Sent a time this week"], ["Runs", num(t.runs), "Times sent, every board"],
    ["Stages", num(t.stages), "With a time, in " + num(t.rallies) + (t.rallies === 1 ? " rally" : " rallies")],
    ["Distance", num(Math.round(t.km || 0)) + " km", "Every run, end to end"], ["Time driven", t.timeMs ? mmss(t.timeMs / 1000) : "–", "Every run's clock"],
    ["Runs per player", t.drivers ? (t.runs / t.drivers).toFixed(1) : "–", "Average"],
    ["Stock / Open", t.runs ? pct(t.stock, t.runs) + " / " + pct(t.open, t.runs) : "–", "Share of runs"],
    ["Flagged", pct(t.flagged, t.runs), "Held back by the server"],
    ["Resets per run", t.resetsPerRun == null ? "–" : Number(t.resetsPerRun).toFixed(1), "Average"], ["New this week", num(t.new7), "First time sent"],
  ];
  $("bsTiles").innerHTML = tiles.map(function (x) {
    return "<div class='tile'><div class='k'>" + esc(x[0]) + "</div><div class='v'>" + esc(x[1]) + "</div><div class='d'>" + esc(x[2]) + "</div></div>";
  }).join("");
  $("bsDailySub").textContent = "Last " + bsRange(d);
  $("bsModsSub").textContent = "Share of runs, last " + bsRange(d);
  bsCharts();
  // players: most runs first
  var pl = (d.players || []).slice(0, 100);
  $("bsPlayers").innerHTML = pl.length ? "<tr><th>Player</th><th class='n'>Runs</th><th class='n'>Stages</th><th class='n'>Fastest</th>" +
    "<th class='n desk'>Podiums</th><th class='desk'>Last run</th></tr>" + pl.map(function (p) {
      return "<tr><td>" + esc(p.name) + "</td><td class='n'>" + num(p.runs) + "</td><td class='n'>" + num(p.stages) + "</td><td class='n best'>" +
        (p.records ? num(p.records) : "–") + "</td><td class='n desk'>" + (p.podiums ? num(p.podiums) : "–") + "</td><td class='desk'>" +
        (p.lastAt ? esc(when(p.lastAt)) : "–") + "</td></tr>";
    }).join("") : "<tr><td class='empty'>No players yet.</td></tr>";
  var sts = d.stages || [];
  $("bsStages").innerHTML = sts.length ? "<tr><th>Stage</th><th class='desk'>Rally</th><th class='n desk'>Length</th><th class='n'>Runs</th><th class='n'>Players</th>" +
    "<th class='n'>Record</th><th class='n desk'>Record speed</th></tr>" + sts.map(function (s) {
      return "<tr><td>" + esc(s.name) + "</td><td class='desk'>" + esc(s.rally || "Own stages") + "</td><td class='n desk'>" +
        (s.lengthM ? esc((s.lengthM / 1000).toFixed(1)) + " km" : "–") + "</td><td class='n'>" + num(s.runs) + "</td><td class='n'>" + num(s.players) +
        "</td><td class='n best'>" + esc(ms(s.recordMs)) + "</td><td class='n desk'>" + (s.recordKmh ? esc(Math.round(s.recordKmh)) + " km/h" : "–") + "</td></tr>";
    }).join("") : "<tr><td class='empty'>No runs yet.</td></tr>";
  hbars("bsRallies", (d.rallies || []).map(function (r) { return [r.rally || "Own stages", r.runs]; }), null, "No runs yet.");
  hbars("bsCars", (d.cars || []).map(function (r) { return [r.car, r.runs]; }), null, "No runs yet.");
  var mods = d.mods || [], modAll = mods.reduce(function (a, r) { return a + r.runs; }, 0);
  hbars("bsMods", mods.map(function (r) { return [r.v == null ? "unknown" : r.v, modAll ? Math.round(r.runs / modAll * 100) : 0]; }),
    function (v) { return v + "%"; }, "No runs in " + bsRange(d) + ".");
}
// (the three charts, drawn to the width they have: again on a resize)
function bsCharts() {
  var d = bs.data;
  if (!d || view !== "bstats") return;
  var phone = isPhone();
  // runs per day (bars) and players that day (line): every day in the range, gaps as 0
  var by = {}, pts = [], start = new Date(d.since + "T00:00:00Z");
  (d.daily || []).forEach(function (x) { by[x.day] = x; });
  for (var i = 0; i < d.days; i++) {
    var day = new Date(start.getTime() + i * 86400000).toISOString().slice(0, 10);
    pts.push({ day: day, runs: (by[day] || {}).runs || 0, players: (by[day] || {}).players || 0 });
  }
  var svg = $("bsDaily"), W = svg.clientWidth || 760, H = phone ? 160 : 210, L = 34, B = 20, T = 6, n = pts.length;
  svg.setAttribute("height", H);
  var top = Math.max.apply(null, pts.map(function (x) { return x.runs; })), step = niceStep(top || 4);
  var max = Math.max(step, Math.ceil(top / step) * step), bw = (W - L - 6) / n, g = "";
  function y(v) { return T + (H - T - B) * (1 - v / max); }
  for (var v = 0; v <= max; v += step) g += "<line x1='" + L + "' x2='" + (W - 6) + "' y1='" + y(v) + "' y2='" + y(v) + "' stroke='var(--grid)'/><text x='" + (L - 5) + "' y='" + (y(v) + 4) + "' text-anchor='end'>" + num(v) + "</text>";
  pts.forEach(function (x, i) {
    if (x.runs) g += "<rect x='" + (L + i * bw + (bw > 3 ? 1 : 0)).toFixed(1) + "' y='" + y(x.runs).toFixed(1) + "' width='" + Math.max(1, bw - (bw > 3 ? 2 : 0)).toFixed(1) +
      "' height='" + (y(0) - y(x.runs)).toFixed(1) + "' fill='var(--s1)' rx='1'/>";
  });
  g += "<path fill='none' stroke='var(--s2)' stroke-width='2' d='" + pts.map(function (x, i) { return (i ? "L" : "M") + (L + i * bw + bw / 2).toFixed(1) + " " + y(x.players).toFixed(1); }).join("") + "'/>";
  var every = Math.max(1, Math.round(n / (phone ? 3 : 5)));
  pts.forEach(function (x, i) { if (i % every === 0) g += "<text x='" + (L + i * bw + bw / 2).toFixed(1) + "' y='" + (H - 4) + "' text-anchor='middle'>" + x.day.slice(5) + "</text>"; });
  pts.forEach(function (x, i) {
    g += "<rect x='" + (L + i * bw).toFixed(1) + "' y='0' width='" + bw.toFixed(1) + "' height='" + (H - B) + "' fill='transparent' data-tip='" + esc(x.day + "\nRuns " + x.runs + "\nPlayers " + x.players) + "'/>";
  });
  svg.innerHTML = g;
  // players over time: everyone so far, by the day of their first run, up to today
  var gr = d.growth || [], gs = $("bsGrowth"), GW = gs.clientWidth || 440, GH = phone ? 140 : 210, GL = 34;
  gs.setAttribute("height", GH);
  if (!gr.length) gs.innerHTML = "<text x='" + GL + "' y='" + (GH / 2) + "'>No players yet.</text>";
  else {
    var g0 = new Date(gr[0].day + "T00:00:00Z").getTime(), today = new Date(new Date().toISOString().slice(0, 10) + "T00:00:00Z").getTime();
    var gn = Math.max(1, Math.round((today - g0) / 86400000)), gtop = gr[gr.length - 1].players, gstep = niceStep(gtop || 4);
    var gmax = Math.max(gstep, Math.ceil(gtop / gstep) * gstep), gg = "";
    var gx = function (t) { return GL + (t - g0) / 86400000 / gn * (GW - GL - 6); }, gy = function (v) { return T + (GH - T - B) * (1 - v / gmax); };
    for (var w = 0; w <= gmax; w += gstep) gg += "<line x1='" + GL + "' x2='" + (GW - 6) + "' y1='" + gy(w) + "' y2='" + gy(w) + "' stroke='var(--grid)'/><text x='" + (GL - 5) + "' y='" + (gy(w) + 4) + "' text-anchor='end'>" + num(w) + "</text>";
    var dpath = "M" + gx(g0).toFixed(1) + " " + gy(0).toFixed(1), last = 0;
    gr.forEach(function (x) {
      var px = gx(new Date(x.day + "T00:00:00Z").getTime()).toFixed(1);
      dpath += "L" + px + " " + gy(last).toFixed(1) + "L" + px + " " + gy(x.players).toFixed(1);
      last = x.players;
    });
    dpath += "L" + gx(Math.max(today, g0)).toFixed(1) + " " + gy(last).toFixed(1);
    gg += "<path fill='none' stroke='var(--s1)' stroke-width='2' d='" + dpath + "'/>";
    [0, 0.5, 1].forEach(function (f) {
      var t = g0 + Math.round(gn * f) * 86400000;
      gg += "<text x='" + gx(t).toFixed(1) + "' y='" + (GH - 4) + "' text-anchor='" + (f === 0 ? "start" : f === 1 ? "end" : "middle") + "'>" + new Date(t).toISOString().slice(5, 10) + "</text>";
    });
    gs.innerHTML = gg;
  }
  // time of day: the browser's own hours
  var hrs = [], hs = $("bsHours"), HW = hs.clientWidth || 400, HH = phone ? 90 : 110;
  for (var k = 0; k < 24; k++) hrs.push(0);
  (d.times || []).forEach(function (at) { hrs[new Date(at).getHours()]++; });
  hs.setAttribute("height", HH);
  var hmax = Math.max.apply(null, hrs) || 1, hg = "", cw = HW / 24;
  hrs.forEach(function (c, h) {
    var bh = c / hmax * (HH - 18);
    hg += "<rect x='" + (h * cw + 1).toFixed(1) + "' y='" + (HH - 16 - bh).toFixed(1) + "' width='" + Math.max(1, cw - 2).toFixed(1) + "' height='" + bh.toFixed(1) + "' fill='var(--s1)' rx='1'/>" +
      "<rect x='" + (h * cw).toFixed(1) + "' y='0' width='" + cw.toFixed(1) + "' height='" + HH + "' fill='transparent' data-tip='" + esc(two(h) + ":00\n" + c + (c === 1 ? " run" : " runs")) + "'/>";
  });
  [0, 6, 12, 18].forEach(function (h) { hg += "<text x='" + (h * cw + 2).toFixed(1) + "' y='" + (HH - 3) + "'>" + two(h) + ":00</text>"; });
  hs.innerHTML = hg;
}

// ---- views and range
var shown = null;
function show(v) {
  if (["overview", "stages", "versions", "boards", "bstats"].indexOf(v) < 0) v = "overview";
  view = v;
  document.body.classList.toggle("norange", v === "boards");   // (the range does nothing there: off on a phone)
  document.querySelectorAll(".view").forEach(function (x) { x.classList.toggle("on", x.id === "v-" + v); });
  document.querySelectorAll("nav [data-v]").forEach(function (b) { b.classList.toggle("on", b.dataset.v === v); });
  // (on a phone the tabs scroll sideways: the chosen one brought into sight)
  var nav = document.querySelector("nav"), on = document.querySelector("nav a.on");
  if (on && nav.scrollWidth > nav.clientWidth) {
    var nr = nav.getBoundingClientRect(), orr = on.getBoundingClientRect();
    if (orr.left < nr.left || orr.right > nr.right) nav.scrollLeft += orr.left - nr.left - 10;
  }
  if (v === "overview" && data) daily();
  $("main").classList.toggle("wide", v === "boards");
  if (v === "boards" && data && !lb.loaded) loadBoards();
  if (v === "bstats" && data) {
    if (shown !== "bstats" || bs.days !== days) loadBStats(); else bsCharts();
  }
  if (data) shown = v;
}
document.querySelectorAll("nav [data-v]").forEach(function (b) { b.onclick = function () { location.hash = b.dataset.v; }; });
window.onhashchange = function () { show(location.hash.slice(1)); };
window.onresize = function () { if (data && view === "overview") daily(); if (data && view === "bstats") bsCharts(); };
document.querySelectorAll("#range span").forEach(function (s) {
  s.onclick = function () {
    days = Number(s.dataset.d); localStorage.setItem("earthRallyDashboardDays", days); load();
    if (view === "bstats") loadBStats();
  };
});
view = location.hash.slice(1) || "overview";
load();
loadDownloads();
`
