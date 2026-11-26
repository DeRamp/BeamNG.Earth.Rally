<template>
  <!-- Earth Rally's menu page (docs/mockups-1.2.0/menu.html, redrawn for rally files in
       docs/mockups-rally-files/menu.html): a route of its own ("earthRally", index.js), opened by Ctrl+Alt+K, the
       pause menu's Earth Rally tab, or the results card. It opens on Home (EarthRallyHomeMenu.vue, 1.7.0 #39: Drive
       rally, EarthRallyPick.vue; Drive stage, the Rallies list; Settings). Views: Rallies (EarthRallyHome.vue), a season
       (EarthRallySeason.vue), a rally's stages, a stage, Settings. Home > Drive stage > Season > Rally > Stage in the crumbs,
       each one a way back. Data and buttons: earthRally_main (store.js). -->
  <!-- a controller (1.6.2, #14), as the game's own screens take one (its Logbook, OthersView): the d-pad / stick moves
       between everything marked bng-nav-item and the buttons, A presses, B goes back a page (and closes the menu from
       Home, as the Back / Close at the top does), Start closes the menu, the bumpers switch a rally's or a season's tabs, the
       right stick scrolls. The first row or card of a page takes the focus when it comes up with a controller in use
       (v-bng-ui-nav-focus; never for a mouse). The mouse moves the same one selection (#51, store.js pointTo). -->
  <div class="er-page" bng-ui-scope="earthRally" v-bng-on-ui-nav:back="back" v-bng-on-ui-nav:menu="closeMenu"
    v-bng-on-ui-nav:tab_l="tabPrev" v-bng-on-ui-nav:tab_r="tabNext" v-bng-on-ui-nav:context="contextPress" @mousemove="pointTo">
    <!-- the loading screen while the world loads (1.7.0, #49 / #40): in place of the page, which is not drawn under
         it (#60) -->
    <EarthRallyLoading @view="v => (v === 'timecard' ? openCard() : null)" @up="v => (loadingUp = v)" />
    <template v-if="!loadingUp">
    <div class="er-topbar">
      <div class="er-back" tabindex="0" bng-nav-item @click="back" @keydown.enter="back"><span>‹</span> {{ view === "home" || mp ? "Close" : "Back" }}</div>
      <div class="er-title"><span class="er-accent">Earth</span> Rally</div>
      <div class="er-crumbs"><span v-for="(c, i) in crumbs" :key="i" :class="{ 'er-cgo': c.go }" @click="c.go && c.go()">{{ c.label }}</span></div>
      <div class="er-right">
        <BngButton v-if="!mp && view !== 'settings' && view !== 'home'" :accent="ACCENTS.outlined" @click="openSettings">Settings</BngButton>
      </div>
    </div>

    <div class="er-content" :class="{ 'er-content-fill': view === 'home' }" v-bng-ui-nav-scroll>
      <!-- (plan F) in a BeamMP session the menu is this one card, whatever page it was on; Close (A or B) shuts it
           (docs/mockups-rally-loop/weather.html, c) -->
      <div v-if="mp" class="er-mp">
        <div class="er-card er-mpcard">
          <div class="er-mpkick"><svg viewBox="0 0 24 24"><g fill="none" stroke="#f26b1d" stroke-width="2"><circle cx="8" cy="8" r="3"/><circle cx="16" cy="8" r="3"/><path d="M2 20c0-3.5 2.7-6 6-6s6 2.5 6 6M12 15.2c1.1-.8 2.5-1.2 4-1.2 3.3 0 6 2.5 6 6"/></g></svg>Multiplayer session</div>
          <h2>Earth Rally is off in multiplayer</h2>
          <p>Leave the server to drive rallies.</p>
          <BngButton v-bng-ui-nav-focus="1" class="er-mpbtn" :accent="ACCENTS.main" @click="closeMenu">Close</BngButton>
        </div>
      </div>
      <template v-else>
      <!-- the run or the recce under way -->
      <div v-if="banner" class="er-banner">
        <span>{{ banner }}</span>
        <BngButton v-if="st.run && st.run.busy" :accent="ACCENTS.outlined" @click="action('abort')">Stop the run</BngButton>
        <!-- No Download / Not now here: the answer lives in the stage's own row and on its page, in the Auto
             recce column, so one press is answered where it was made. The banner still SAYS what is waiting. -->
        <BngButton v-if="auto" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">{{ autoStopLabel }}</BngButton>
        <template v-if="st.recce">
          <BngButton :accent="ACCENTS.main" @click="action('recceSave')">Save recce</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceSaveAnyway')">Save anyway</BngButton>
          <BngButton :accent="ACCENTS.outlined" @click="action('recceCancel')">Cancel recce</BngButton>
        </template>
      </div>
      <!-- a full rally under way (1.7.0): the way back to its time card from anywhere in the menu -->
      <!-- (not on Home, Drive rally or Drive stage: Home's Continue strip says it, #39) -->
      <div v-if="st.rallyActive && !['timecard', 'home', 'pick', 'rallies'].includes(view)" class="er-banner">
        <span>{{ st.rallyActive.name }}: {{ st.rallyActive.done ? "finished" : "rally under way" }}</span>
        <BngButton :accent="ACCENTS.main" @click="openCard">Time card</BngButton>
      </div>
      <div v-if="st.earthWhy" class="er-warnline">{{ st.earthWhy }}</div>
      <!-- (opened from the main menu: no world yet, and that is fine -- it loads with the first stage driven) -->
      <div v-else-if="st.earthNote" class="er-noteline">{{ st.earthNote }}</div>
      <!-- Something changed under the mod since it was built (versions.lua): the game's version, BeamNG.Earth's
           modding API, or one of the internals it has no API for. Empty in the normal case, so nothing shows. -->
      <div v-for="(n, i) in arr(st.versionNotes)" :key="'vn' + i" class="er-warnline">{{ n }}</div>
      <!-- (Home and Drive rally: why Continue did not go, e.g. a recce under way) -->
      <div v-if="busyMsg && (view === 'home' || view === 'pick')" class="er-warnline">{{ busyMsg }}</div>

      <!-- ===== Home and Drive rally (1.7.0, #39): where the menu opens, and the full rallies to pick from ===== -->
      <EarthRallyHomeMenu v-if="view === 'home'" :busy="busy" @pick="openPick" @stages="go('rallies')" @settings="go('settings')"
        @continue="resumeRally" @card="openCard" />
      <EarthRallyPick v-else-if="view === 'pick'" ref="pickView" :busy="busy" :pick-id="pickSel" @start="id => openStart(id, 'pick')"
        @continue="resumeRally" @card="openCard" @results="id => openResults(id, 'pick')" />

      <!-- ===== Rallies (Drive stage) ===== -->
      <EarthRallyHome v-else-if="view === 'rallies'" @season="openSeason" @rally="openRally" @stage="openStage" @action="action"
        @report="openReport" />
      <EarthRallyImportReport v-else-if="view === 'importReport'" :file="reportFile" @action="action" />

      <!-- ===== a season ===== -->
      <EarthRallySeason v-else-if="view === 'season' && ssn" ref="seasonView" :key="ssn.id" :s="ssn" @rally="openRally" />

      <!-- ===== the full rally (1.7.0): its start screen and its time card ===== -->
      <EarthRallyFull v-else-if="view === 'rallyStart'" kind="start" :id="sel.eventId" @view="fullView" />
      <EarthRallyFull v-else-if="view === 'timecard'" kind="card" @view="fullView" />

      <!-- ===== a rally ===== -->
      <section v-else-if="view === 'rally' && rly">
        <!-- the banner: the rally's photo behind, its logo (or a drawn plate), its round, dates and town -->
        <div class="er-rbanner">
          <EarthRallyPic class="er-rb-photo" bare :url="(rly.media && (rly.media.photo || rly.media.cover)) || ''" />
          <EarthRallyPic class="er-rb-logo" contain :url="(rly.media && rly.media.logo) || ''" :kind="rly.season && rly.season.round ? `ROUND ${rly.season.round}` : 'RALLY'" :name="rly.name" />
          <div class="er-rb-text">
            <div v-if="rly.season" class="er-rb-round">Round {{ rly.season.round }} · {{ rly.season.name }}</div>
            <div class="er-rb-name er-clip" :title="rly.name">{{ rly.name }}</div>
            <div class="er-rb-sub">{{ rallySub }}</div>
          </div>
          <div class="er-rb-stats">
            <div class="er-stat"><div class="er-v">{{ len(rly.lengthM) }}</div><div class="er-l">{{ rly.stages }} stages</div></div>
            <div class="er-stat"><div class="er-v">{{ rly.driven }} / {{ rly.stages }}</div><div class="er-l">driven</div></div>
          </div>
        </div>
        <!-- the full rally (1.7.0): Start, the one saved (Continue), your best finished one; only with an event file -->
        <!-- (#55: opened for its results from Drive rally or the time card, the page is its results alone) -->
        <div v-if="rly.fullRally && !resultsFrom" class="er-card er-fullbar">
          <div class="er-fb-text">
            <b>Full rally</b>
            <span v-if="rly.rallyActive && rly.rallyActive.id === rly.id">Under way.</span>
            <span v-else-if="rly.rallySaved">Saved at {{ rly.rallySaved.at }} · {{ rly.rallySaved.mode === "realistic" ? "Realistic" : "Casual" }} · {{ rly.rallySaved.class }} · {{ rly.rallySaved.done }} {{ rly.rallySaved.done === 1 ? "stage" : "stages" }} done</span>
            <span v-else>Every stage in order, with service between them.</span>
            <span v-if="rly.rallyFinished" class="er-muted">Best: {{ longTime(rly.rallyFinished.totalS) }}<template v-if="rly.rallyFinished.pos"> · P{{ rly.rallyFinished.pos }} of {{ rly.rallyFinished.of }} · {{ rly.rallyFinished.class }} {{ ord(rly.rallyFinished.classPos) }}</template><template v-if="rly.rallyFinished.unclassified"> · not classified</template> · {{ rly.rallyFinished.mode === "realistic" ? "Realistic" : "Casual" }}</span>
          </div>
          <BngButton v-if="rly.rallyActive && rly.rallyActive.id === rly.id" :accent="ACCENTS.main" @click="openCard">Time card</BngButton>
          <!-- (#28) Retire: the saved rally deleted, after a confirm in the bar itself -->
          <template v-else-if="retireAsk === rly.id">
            <span class="er-fb-warn">Retire? Your saved progress is deleted.</span>
            <BngButton :accent="ACCENTS.main" :disabled="busy" @click="retireRally(rly.id)">Retire</BngButton>
            <BngButton :accent="ACCENTS.outlined" @click="retireAsk = null">Cancel</BngButton>
          </template>
          <template v-else>
            <!-- (at the main menu, a rally saved before cars were remembered: its car found once in the game's picker) -->
            <BngButton v-if="rly.rallySaved && rly.savedCar && !rly.savedCar.known" :accent="ACCENTS.main" :disabled="busy" @click="pickCar(rly.id, 'resume')">Find the {{ rly.savedCar.name }}…</BngButton>
            <BngButton v-if="rly.rallySaved" :accent="ACCENTS.main" :disabled="busy || !!(rly.savedCar && !rly.savedCar.known)" @click="resumeRally(rly.id)">{{ rly.savedCar && rly.savedCar.known ? `Continue in the ${rly.savedCar.name}` : "Continue" }}</BngButton>
            <BngButton :accent="rly.rallySaved ? ACCENTS.outlined : ACCENTS.main" :disabled="busy" @click="openStart(rly.id)">{{ rly.rallySaved ? "Start again" : "Start the rally" }}</BngButton>
            <BngButton v-if="rly.rallySaved" :accent="ACCENTS.outlined" :disabled="busy" @click="retireAsk = rly.id">Retire</BngButton>
          </template>
        </div>
        <!-- Results (with real results) and Rules (when the file has any): no tabs at all on a rally with neither -->
        <div v-if="(rallyTabs.length > 1 || legend) && !resultsFrom" class="er-under-banner">
          <div v-if="rallyTabs.length > 1" class="er-tabs">
            <span v-for="t in rallyTabs" :key="t.id" tabindex="0" bng-nav-item :class="{ on: curTab === t.id }" @click="rallyTab = t.id" @keydown.enter="rallyTab = t.id">{{ t.label }}</span>
          </div>
          <div v-if="legend && curTab === 'stages'" class="er-legend">
            <template v-if="rly.anyCancelled"><s>{{ cancelledSs }}</s> pass cancelled on the day</template><template v-if="rly.anyCancelled && rly.hasBoard"> · </template><template v-if="rly.hasBoard"><b>Place</b>: your best against the real field</template>
          </div>
        </div>
        <div v-if="curTab === 'results' && rly.rallyFinished" class="er-card er-yourfull">
          <b>Your full rally</b> · {{ longTime(rly.rallyFinished.totalS) }}<template v-if="rly.rallyFinished.roadPenaltyS != null"> · <template v-if="rly.rallyFinished.roadPenaltyS > 0">incl. transit penalties <span class="er-rp">{{ roadText(rly.rallyFinished.roadPenaltyS) }}</span></template><span v-else class="er-rp0">no transit penalties</span></template><template v-if="rly.rallyFinished.pos"> · P{{ rly.rallyFinished.pos }} of {{ rly.rallyFinished.of }} National · {{ rly.rallyFinished.class }} {{ ord(rly.rallyFinished.classPos) }} of {{ rly.rallyFinished.classOf }}</template><template v-if="rly.rallyFinished.unclassified"> · not classified</template> · {{ rly.rallyFinished.mode === "realistic" ? "Realistic" : "Casual" }}<template v-if="rly.rallyFinished.car"> · {{ rly.rallyFinished.car }}</template>
          <!-- (additions A) a timed rally: each stage's time with the road penalty getting to it, and a stop only where
               it cost something. Untimed, or finished before this: no passes from the Lua, no chips -->
          <div v-if="fullChips.length" class="er-chips">
            <span v-for="(c, i) in fullChips" :key="i" class="er-chip" :class="{ stop: c.stop, sr: c.sr }">{{ c.label }}<span v-if="c.timeS != null" class="er-mono">{{ time(c.timeS) }}</span><i v-if="c.penS > 0">{{ roadText(c.penS) }}</i></span>
          </div>
        </div>
        <EarthRallyResults v-if="curTab === 'results'" :r="rly.results" />
        <div v-else-if="curTab === 'rules'" class="er-card er-rules">
          <div v-for="(l, i) in arr(rly.rules)" :key="i" class="er-rule">
            <span>{{ l.label }}</span><span><span class="er-rv">{{ l.value }}</span><span v-if="l.inGame" class="er-in">IN GAME</span></span>
          </div>
        </div>
        <template v-else>
        <!-- Seven columns: the seventh holds the Auto recce button (docs/mockups-1.3.0/auto-recce-button.html,
             section 3). Its header cell is deliberately empty -- an AUTO RECCE heading over a column blank on most
             rows reads as data, and advertises on every row something half of them cannot do. -->
        <div class="er-card er-stages">
          <div class="er-srow er-hdr" :style="srowCols"><span>Stage</span><span>Name</span><span class="er-r">Length</span><span class="er-st">Status</span><span></span><span class="er-r">Best</span><span v-if="rly.hasBoard" class="er-r">Place</span><span></span></div>
          <div v-for="(s, i) in arr(rly.list)" :key="s.id" v-bng-ui-nav-focus="i === 0 ? 1 : undefined" class="er-srow er-click" :class="{ 'er-running': autoRow(s) }" :style="srowCols" tabindex="0" bng-nav-item @click="openStage(rly.id, s.id)" @keydown.enter="rowEnter($event, s)">
            <!-- a stage run twice is one row: SS2 · SS4, a pass cancelled on the day struck out -->
            <span v-if="s.notRun" class="er-ss er-notrun">Not run</span>
            <span v-else class="er-ss"><span v-for="(p, k) in passList(s)" :key="k"><s v-if="p.cancelled">{{ p.ss }}</s><template v-else>{{ p.ss }}</template><template v-if="k < passList(s).length - 1"> · </template></span></span>
            <span class="er-clip">{{ s.name }}</span><span class="er-r er-mono">{{ len(s.lengthM) }}</span>
            <span class="er-st">
              <span v-if="autoRow(s)" class="er-pill working" :class="{ live: autoLive }" :style="{ '--er-done': autoPct }">{{ STATUS.working.label }} <span class="er-wn">{{ autoLeg }}</span></span>
              <span v-else class="er-pill" :class="pill(s.status).cls">{{ pill(s.status).label }}</span>
            </span>
            <!-- @click.stop: the whole row opens the stage, so without it the button would do both. The row's
                 Enter is guarded the same way, in rowEnter: Enter on a focused button fires its click AND bubbles. -->
            <span class="er-act">
              <!-- Everything about the auto recce answers in THIS cell (the user, 2026-11-14: "move that to a
                   button in the same collum as autp recce. all indication should be there"). The banner is easy to
                   miss and the question can arrive while the player is looking at the list, so while one waits on
                   an answer the cell holds the answer; the rest of the time it holds Stop. -->
              <template v-if="autoRow(s) && autoAsk">
                <BngButton :accent="ACCENTS.main" @click.stop="action('autoRecceDownload')">Download</BngButton>
                <BngButton :accent="ACCENTS.outlined" @click.stop="action('autoRecceSkip')">Not now</BngButton>
              </template>
              <BngButton v-else-if="autoRow(s)" :accent="ACCENTS.outlined" @click.stop="action('autoRecceStop')">{{ autoStopLabel }}</BngButton>
              <BngButton v-else-if="st.autoOk && s.status === 'none'" :accent="ACCENTS.secondary" :disabled="busy" @click.stop="action('autoRecce', rly.id, s.id)">{{ outcomeFor(s) ? "Try again" : "Auto recce" }}</BngButton>
              <!-- Reset takes the same cell on a stage that HAS a line, so every row has exactly one control and
                   the column reads as one question. Deliberately NOT gated on st.autoOk: it removes files and asks
                   BeamNG.Earth for nothing, so a player on a stock BeamNG.Earth still has their way back from a
                   recce they are unhappy with -- gating it the way Auto recce is gated would lock out exactly the
                   players with no auto recce to fall back on. A driven recce, or any line with times on it (they
                   stop being placed), is confirmed on the stage page, where there is room to say what is lost; the
                   row opens it rather than deleting from under them. -->
              <BngButton v-else-if="s.line === 'matched' && !s.best" :accent="ACCENTS.outlined" :disabled="busy" @click.stop="action('reset', rly.id, s.id)">Reset</BngButton>
              <BngButton v-else-if="s.line" :accent="ACCENTS.outlined" @click.stop="askReset(rly.id, s.id)">Reset</BngButton>
            </span>
            <!-- Old line: it has times, none on the line it runs on now (menu.lua, oldLine): not placed, not driven -->
            <span v-if="s.oldLine" class="er-r er-none" :title="time(s.best)">Old line</span>
            <span v-else class="er-r er-mono" :class="{ 'er-none': !s.best }">{{ s.best ? time(s.best) : "–" }}</span>
            <!-- Place: the better of your placings over the stage's passes, against the real field -->
            <span v-if="rly.hasBoard" class="er-plc"><template v-if="s.place">{{ ord(s.place.pos) }}<small>of {{ s.place.of }}</small></template><span v-else class="er-none">–</span></span>
            <span class="er-go">›</span>
          </div>
        </div>
        <!-- how an auto recce ended, one line per stage: the pill only ever says whether the stage can be driven -->
        <div v-if="arr(rly.autoLines).length" class="er-under">
          <div v-for="l in arr(rly.autoLines)" :key="l.stageId" class="er-outcome" :class="outcomeCls(l.kind)">
            <span v-if="l.ssLabel" class="er-ssx">{{ l.ssLabel }}</span>{{ l.text }}
          </div>
        </div>
        <div class="er-muted er-help">
          <b>Ready</b>: notes from the stage's own roads or your recce. <b>Missing road segments</b>: part of the stage has
          no road on the map (no notes there) until you drive its recce. <b>Recce stops short</b>: your recce ends before
          the finish; drive it again. <b>Recce needed</b>:
          {{ st.autoOk ? "run the auto recce, or drive its recce." : "drive its recce." }}
        </div>
        <details v-if="arr(rly.report).length" class="er-report er-report-full">
          <summary>Import report</summary>
          <div v-for="(l, i) in arr(rly.report)" :key="i">{{ l }}</div>
        </details>
        </template>
      </section>

      <!-- ===== a stage ===== -->
      <section v-else-if="view === 'stage' && stg" class="er-stage-page">
        <div>
          <div class="er-stage-ss">{{ ssLine }}</div>
          <div class="er-stage-name">{{ stg.name }}</div>
          <div class="er-muted">{{ controlsLine }}</div>
          <div class="er-tiles">
            <div class="er-card er-tile"><div class="er-v">{{ lenNum(stg.lengthM) }}<small>{{ units() }}</small></div><div class="er-l">Length</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ dash(stg.corners) }}</div><div class="er-l">Corners</div></div>
            <!-- Gain and Loss, from the stage's own line (menu.lua, events.lineFigures): the height it climbs and
                 the height it gives back, each counted once a move has gone 2 m from the last one counted. They
                 took the places of Junctions and Bridges, so the grid is the same four tracks it always was. -->
            <div class="er-card er-tile"><div class="er-v">{{ riseNum(stg.gainM) }}<small>{{ riseUnit() }}</small></div><div class="er-l">Gain</div></div>
            <div class="er-card er-tile"><div class="er-v">{{ riseNum(stg.lossM) }}<small>{{ riseUnit() }}</small></div><div class="er-l">Loss</div></div>
          </div>
          <!-- The organisers' four kinds of point, from the stage's map (menu.lua, events.stageMarks), on the tiles'
               own grid: each one From the map (n marked: the dressing puts them there), Random (none marked: the
               dressing places them, seeded per stage) or None (medical with none marked: never invented; a radio or
               spectator kind the rally marks on other stages only: none here, stg.marked). An icon
               and a word for each state, so nothing rests on colour (docs/mockups-1.6.0/stage-points.html). -->
          <template v-if="stg.marks">
            <div class="er-pts">
              <div v-for="p in pts" :key="p.key" class="er-card er-pt" :class="p.state">
                <svg class="er-pi" viewBox="0 0 24 24">
                  <template v-if="p.key === 'radio'"><rect x="7" y="8" width="10" height="14" rx="2"/><path d="M9.5 8V2"/><path d="M10 13h4M10 16.5h4"/></template>
                  <path v-else-if="p.key === 'medical'" d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/>
                  <template v-else-if="p.key === 'marshal'"><path d="M5 22V3"/><path d="M5 4h13l-3 4.5 3 4.5H5"/></template>
                  <template v-else><circle cx="8" cy="8" r="3"/><circle cx="16.5" cy="9" r="2.5"/><path d="M2.5 20c0-3.6 2.5-6 5.5-6s5.5 2.4 5.5 6"/><path d="M14.5 14.3c.6-.2 1.3-.3 2-.3 2.6 0 5 2 5 5.5"/></template>
                </svg>
                <div>
                  <div class="er-l">{{ p.label }}</div>
                  <div v-if="p.state === 'map'" class="er-pv"><svg class="er-ps" viewBox="0 0 24 24"><path d="M12 22s7-6.6 7-12a7 7 0 0 0-14 0c0 5.4 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/></svg><b>{{ p.n }}</b>on the map</div>
                  <div v-else-if="p.state === 'rnd'" class="er-pv"><svg class="er-ps" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="17" height="17" rx="3.5"/><circle class="f" cx="8.5" cy="8.5" r="1.6"/><circle class="f" cx="15.5" cy="15.5" r="1.6"/><circle class="f" cx="15.5" cy="8.5" r="1.6"/><circle class="f" cx="8.5" cy="15.5" r="1.6"/><circle class="f" cx="12" cy="12" r="1.6"/></svg>Random</div>
                  <div v-else class="er-pv"><svg class="er-ps" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M6 18L18 6"/></svg>None</div>
                </div>
              </div>
            </div>
            <div class="er-pts-help">
              <template v-if="ptsHelp.all">All four are where the organisers put them.</template>
              <template v-else>
                <template v-if="ptsHelp.rnd"><b>Random</b>: the map doesn't mark {{ ptsHelp.rnd }} on this stage, so they're placed for you where the stage has room.</template>
                <template v-if="ptsHelp.rnd && ptsHelp.none">{{ " " }}</template>
                <template v-if="ptsHelp.none"><b>None</b>:</template>
                <template v-if="ptsHelp.elsewhere">{{ " " }}this rally's map marks {{ ptsHelp.elsewhere }} on other stages but not this one, so there are none here.</template>
                <template v-if="ptsHelp.medical">{{ " " }}{{ ptsHelp.elsewhere ? "And medical" : "medical" }} points only go where the organisers mark one.</template>
              </template>
            </div>
          </template>
          <!-- (1.7.2) the auto recce under way: the four steps of one press, a real bar, the time, and a line when the
               count sits still. BeamNG.Earth reports items, not bytes, and the items differ a lot in size, so the
               fill only moves on its count while the stripes say it is still going (docs/mockups-1.7.2). -->
          <div v-if="autoHere" class="er-card er-dl">
            <div class="er-dl-steps">
              <span v-for="(p, k) in autoSteps" :key="k" :class="p.state" :data-n="k + 1">{{ p.label }}</span>
            </div>
            <div class="er-dl-top"><b>{{ autoWhat }}</b><span class="er-mono">{{ autoCount }}</span></div>
            <div class="er-dl-bar" :class="{ live: autoLive }"><i :style="{ width: autoFill }"></i></div>
            <div class="er-dl-foot er-mono"><span>{{ autoFootL }}</span><span>{{ autoFootR }}</span></div>
            <div class="er-dl-note">
              <template v-if="auto.phase === 'going'">Waiting for the world to load. A road graph can only be asked for near where you are.</template>
              <template v-else-if="auto.phase === 'planning'">Working out what map data is missing along the stage.</template>
              <template v-else-if="auto.phase === 'asking'">BeamNG.Earth needs {{ MB(auto.ask && auto.ask.bytes) }} of map data along the stage: Download, or Not now.</template>
              <template v-else-if="auto.phase === 'downloading'">
                <span v-if="autoQuiet" class="er-dl-wait">Still going: a big piece is downloading, and the count jumps when it lands ({{ auto.quietS }} s since the last).</span>
                <template v-else>Gated so it cannot slow the world down, so it can take a few minutes.</template>
                It carries on if you leave this page.<template v-if="auto.area && auto.area.msg"> {{ auto.area.msg }}</template>
              </template>
              <template v-else>No map data is downloaded now. You can leave this page.</template>
            </div>
          </div>
          <div v-else class="er-card er-line-note"><span class="er-pill" :class="pill(stg.status).cls">{{ pill(stg.status).label }}</span><span>{{ stg.note }}</span></div>
          <!-- Auto recce is the fourth button, before Recce, so the two recce buttons sit together and the cheap
               one comes first. While one runs it is replaced in place by its Stop, not joined by a fifth button. -->
          <!-- (plan G) Weather, one row the start screen's look, cycled with left / right or a click on the arrows:
               Current (nothing set), Rally day (only when the pass shown has stored weather), BeamNG.Earth's
               presets. Kept between stages; set as the stage loads (stageWeather.lua). Not without the hook. -->
          <div v-if="stg.wxCan" class="er-wxrow">
            <span class="er-wxl">Weather</span>
            <span class="er-cyc" v-bng-on-ui-nav:focus_l="() => wxNav(-1)" v-bng-on-ui-nav:focus_r="() => wxNav(1)">
              <span class="er-ar" @click="wxStep(-1)">‹</span>
              <span ref="wxVal" class="er-val" tabindex="0" bng-nav-item @keydown.enter="wxStep(1)" @click="wxStep(1)">
                <svg v-if="wxShown.icon" viewBox="0 0 24 24" v-html="wxIcon(wxShown)"></svg>{{ wxShown.label }}</span>
              <span class="er-ar" @click="wxStep(1)">›</span>
            </span>
          </div>
          <div class="er-actions">
            <BngButton v-bng-ui-nav-focus="1" :accent="ACCENTS.main" :disabled="!stg.canDrive || busy" @click="action('drive', stg.eventId, stg.id)">Drive stage</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="action('route', stg.eventId, stg.id)">Route to start</BngButton>
            <template v-if="autoHere && autoAsk">
              <BngButton :accent="ACCENTS.main" @click="action('autoRecceDownload')">Download {{ MB(autoAsk.bytes) }}</BngButton>
              <BngButton :accent="ACCENTS.outlined" @click="action('autoRecceSkip')">Not now</BngButton>
            </template>
            <BngButton v-else-if="autoHere" :accent="ACCENTS.outlined" @click="action('autoRecceStop')">{{ auto.prepLeft > 1 ? autoStopLabel : "Stop the auto recce" }}</BngButton>
            <BngButton v-else-if="stg.autoCan" :accent="ACCENTS.secondary" :disabled="busy || !st.autoOk" @click="action('autoRecce', stg.eventId, stg.id)">Auto recce</BngButton>
            <!-- menu.lua sets autoCan only on a stage with no line, so on a stage that has one the Auto recce
                 button is already absent and Reset is simply its v-else-if: the row keeps four buttons, never
                 five. A matched line goes at once (1.25 s to make again); a driven recce asks first, because it
                 cost the stage, driven, and cannot be got back. -->
            <BngButton v-else-if="stg.line === 'matched' && !stg.best" :accent="ACCENTS.outlined" :disabled="busy" @click="action('reset', stg.eventId, stg.id)">Reset</BngButton>
            <BngButton v-else-if="stg.line && !confirmReset" :accent="ACCENTS.outlined" @click="confirmRecce = false; confirmReset = true">Reset</BngButton>
            <BngButton :accent="ACCENTS.secondary" :disabled="busy" @click="recce">Recce</BngButton>
          </div>
          <!-- The confirm: for a driven recce, and for a matched line with times on it (they stop being placed).
               A matched line with no times is not confirmed: confirming the cheap case would teach clicking
               through, and the once it mattered that habit would carry. -->
          <div v-if="confirmReset && stg.line" class="er-card er-confirm">
            <div>
              <b>{{ stg.line === "matched" ? "Remove the matched line?" : "Remove the recce you drove?" }}</b><br>
              <!-- It does NOT promise the auto recce will manage one here: whether the map has roads for this
                   stage on this computer is only known by asking for them, and a confirm that guessed would be
                   worse than one that does not say. -->
              <span v-if="stg.line === 'matched'">Afterwards you can run the auto recce again, or drive the recce.</span>
              <span v-else>This cannot be undone. Afterwards you can run the auto recce, or drive the recce again.</span>
              <template v-if="stg.best"><br><span>{{ PLACED_WARN }}</span></template>
            </div>
            <div class="er-confirm-row">
              <BngButton :accent="ACCENTS.outlined" @click="confirmReset = false">Keep it</BngButton>
              <BngButton :accent="ACCENTS.main" :disabled="busy" @click="confirmReset = false; action('reset', stg.eventId, stg.id)">{{ stg.line === "matched" ? "Remove the line" : "Remove the recce" }}</BngButton>
            </div>
          </div>
          <!-- A new recce over a line with times on it: said once before it starts (the new line replaces this one) -->
          <div v-if="confirmRecce && stg.line && stg.best" class="er-card er-confirm">
            <div><b>Drive a new recce?</b><br><span>{{ PLACED_WARN }}</span></div>
            <div class="er-confirm-row">
              <BngButton :accent="ACCENTS.outlined" @click="confirmRecce = false">Not now</BngButton>
              <BngButton :accent="ACCENTS.main" :disabled="busy" @click="confirmRecce = false; action('recce', stg.eventId, stg.id)">Recce</BngButton>
            </div>
          </div>
          <!-- beside the row, never a tooltip: a disabled BngButton takes no pointer events and can never show one -->
          <div v-if="stg.autoWhy" class="er-msg">{{ stg.autoWhy }}</div>
          <div v-if="stg.autoLine" class="er-outcome" :class="outcomeCls(stg.autoLine.kind)">{{ stg.autoLine.text }}</div>
          <div v-if="busyMsg" class="er-msg">{{ busyMsg }}</div>
          <div class="er-act-help">
            <b>Drive stage</b>: takes you to the {{ stg.atc ? "time control before the start" : "start" }}, then through the stage as in a real rally.<br>
            <b>Route to start</b>: the way there on the GPS, arrows on the road. No teleport.<br>
            <template v-if="stg.autoCan"><b>Auto recce</b>: {{ !st.autoOk
              ? "works the line out from the map's roads. Not available with this BeamNG.Earth."
              : st.autoWalks
                ? "works the line out from the map's roads. Takes the car along the stage to read them, then brings it back."
              : st.autoCanFetch
                ? "takes you to the start, then works the line out from the map's roads. Where the map data is missing it tells you how much there is to download and asks first."
                : "works the line out from the map's roads." }}<br></template>
            <template v-if="stg.line"><b>Reset</b>: removes this stage's line, so you can make it again -- with the auto recce or by driving a recce. Your times are kept.<br></template>
            <b>Recce</b>: drive the stage once at your own pace; the line you drive gives the notes.
          </div>
        </div>
        <!-- the Leaderboard card above Your runs (the user, 2026-11-14), which then shows the last two -->
        <div class="er-rcol">
        <!-- (prototype) Offline: the rally pack's real results; Online: players' own times (EarthRallyOnline), only
             once the player has turned the online board on in Settings. The switch shows when there are both. -->
        <div v-if="stg.board && onlineOn" class="er-lbswitch">
          <span v-for="t in LB_TABS" :key="t.id" tabindex="0" bng-nav-item :class="{ on: lbTab === t.id }"
            @click="lbTab = t.id" @keydown.enter="lbTab = t.id">{{ t.label }}</span>
        </div>
        <EarthRallyBoard v-if="stg.board && (lbTab === 'offline' || !onlineOn)" :b="stg.board" :best="stg.best" @pass="choosePass" />
        <EarthRallyOnline v-else-if="onlineOn" :event-id="stg.eventId" :stage-id="stg.id" />
        <div class="er-card er-runs">
          <h3>Your runs</h3>
          <div v-if="stg.best" class="er-best-box"><span class="er-t">{{ time(stg.best) }}</span><span class="er-badge">BEST</span></div>
          <!-- (additions A) the splits the HUD compares with: one run's, on the line the stage runs on now -->
          <div v-if="stg.bestSplits" class="er-bsplits">
            <div class="er-bsh"><span>Best splits</span><span>{{ stg.bestSplits.rally ? "a full-rally pass" : "your run" }}{{ dayOf(stg.bestSplits.date) ? (stg.bestSplits.rally ? ", " : " of ") + dayOf(stg.bestSplits.date) : "" }}</span></div>
            <div class="er-sg4">
              <div v-for="(t, k) in bestSplitTimes" :key="k"><small>{{ SPLIT_LABELS[k] }}</small>{{ time(t) }}</div>
            </div>
          </div>
          <template v-for="(r, i) in runsShown" :key="i">
            <div class="er-run">
              <span>{{ when(r.date) }} <span v-if="r.last" class="er-dim">· last</span></span>
              <span class="er-mono">{{ time(r.timeS) }}</span>
              <span :class="r.penaltyS > 0 ? 'er-pen' : 'er-clean'">{{ r.text }}</span>
            </div>
            <div v-if="arr(r.splits).length === 4" class="er-sg4 er-rsp">
              <div v-for="(x, k) in arr(r.splits)" :key="k">{{ time(x.timeS) }}<span v-if="r.bestSplits && k === 0" class="er-z">best</span><span v-else-if="x.gapS != null" :class="x.gapS < 0 ? 'er-a' : x.gapS > 0 ? 'er-b' : 'er-z'">{{ splitGap(x.gapS) }}</span></div>
            </div>
          </template>
          <div v-if="!arr(stg.runs).length" class="er-muted">No runs yet.</div>
          <div class="er-muted er-small">Times include penalties.</div>
        </div>
        </div>
      </section>

      <!-- ===== Settings ===== -->
      <section v-else-if="view === 'settings'" class="er-settings-page">
        <div class="er-card"><EarthRallySettings /></div>
        <div>
          <div class="er-card"><EarthRallyPrivacy /></div>
          <p class="er-dim er-small">Earth Rally {{ st.version }}</p>
        </div>
      </section>

      <div v-else class="er-muted">Loading...</div>
      </template>
    </div>

    <!-- the stats question (#76): once, when the leaderboard is turned on; its own yes or no -->
    <template v-if="!mp">
    <EarthRallyConsent v-if="onlineOn && st.stats && st.stats.consent === 'ask'" />
    <!-- the Leaderboards helper not answering (#77): how to install it; never over the stats question (main.lua) -->
    <EarthRallyHelperPrompt v-else-if="st.helperPrompt" :online-on="onlineOn" />
    <!-- no leaderboard name yet (main.lua namePromptWanted): after the two above, one at a time -->
    <EarthRallyNamePrompt v-else-if="st.namePrompt" :naming="st.naming" />
    </template>
    <EarthRallyPrompts :top="view === 'home' || mp" :results="!mp && view === 'pick' && !!(pickView && pickView.hasResults)" />
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { BngButton, ACCENTS } from "@/common/components/base"
import { vBngOnUiNav, vBngUiNavScroll, vBngUiNavFocus } from "@/common/directives"
import { useUINavScope } from "@/services/uiNav"
import EarthRallySettings from "./EarthRallySettings.vue"
import EarthRallyPrivacy from "./EarthRallyPrivacy.vue"
import EarthRallyConsent from "./EarthRallyConsent.vue"
import EarthRallyHelperPrompt from "./EarthRallyHelperPrompt.vue"
import EarthRallyNamePrompt from "./EarthRallyNamePrompt.vue"
import EarthRallyHome from "./EarthRallyHome.vue"
import EarthRallyImportReport from "./EarthRallyImportReport.vue"
import EarthRallyHomeMenu from "./EarthRallyHomeMenu.vue"
import EarthRallyPick from "./EarthRallyPick.vue"
import EarthRallyPrompts from "./EarthRallyPrompts.vue"
import EarthRallySeason from "./EarthRallySeason.vue"
import EarthRallyPic from "./EarthRallyPic.vue"
import EarthRallyBoard from "./EarthRallyBoard.vue"
import EarthRallyOnline from "./EarthRallyOnline.vue"
import EarthRallyResults from "./EarthRallyResults.vue"
import EarthRallyFull from "./EarthRallyFull.vue"
import EarthRallyLoading from "./EarthRallyLoading.vue"
import {
  state, season, rally, stage, busyMsg, action as luaAction, refreshState, takeOpenAt, loadSeason, loadRally, loadStage,
  closeMenu, pickCar, keep, lastPlace, setSetting, wxIcon, helperPromptClose, namePromptLater, loadRallyStart, loadRallyCard, rallyAction, loadDrive, pointTo,
  arr, mmss, units, len, lenNum, riseNum, riseUnit, time, longTime, when, ord, days, ssName, STATUS, AUTO_OUTCOME, RUN_WORDS,
} from "./store.js"

useUINavScope("earthRally")   // (the controller's events fire from inside bng-ui-scope="earthRally": the page)

const view = ref("home")
// pass: the stage leaderboard's pass the player picked (null: the one they place best on, chosen in Lua)
const sel = ref({ seasonId: null, eventId: null, stageId: null, pass: null })
const st = computed(() => state.value || {})
// (plan F) a BeamMP session: the menu is one card (main.lua uiState().multiplayer)
const mp = computed(() => !!st.value.multiplayer)
const ssn = computed(() => (season.value && !season.value.missing && season.value.id === sel.value.seasonId) ? season.value : null)
const rly = computed(() => (rally.value && !rally.value.missing && rally.value.id === sel.value.eventId) ? rally.value : null)
// (the rally as well as the stage: a stage's id is its line's name, and two rallies can both have a "Wildcat")
// the stage page's leaderboard: the rally pack's real results (offline) or players' times (online)
const LB_TABS = [{ id: "offline", label: "Rally results" }, { id: "online", label: "Leaderboard" }]
const lbTab = ref("offline")
const onlineOn = computed(() => !!(state.value.settings && state.value.settings.settings && state.value.settings.settings.onlineBoard))
const stg = computed(() => (stage.value && !stage.value.missing && stage.value.id === sel.value.stageId &&
  stage.value.eventId === sel.value.eventId) ? stage.value : null)
// An auto recce holds the page as a recce does: the Lua does one window at a time, so every other action is
// greyed while one runs (the running row's own Stop is not disabled, and is the way out).
const busy = computed(() => !!(st.value.recce || st.value.auto || (st.value.run && st.value.run.busy)))

// the auto recce running, if any: which row it is, how far through, and the window it is on. progress().done
// counts the windows finished, while the pill and the banner name the one in flight -- so it is never "0 / 19".
const auto = computed(() => st.value.auto || null)
const autoWindow = computed(() => {
  const a = auto.value
  return a ? Math.min((a.done || 0) + 1, a.windows || 1) : 0
})
const autoPct = computed(() => {
  const a = auto.value
  if (a && a.phase === "downloading" && a.area && a.area.total) {
    return `${Math.round((100 * (a.area.done || 0)) / a.area.total)}%`
  }
  // the legs with nothing to count: a filled pill would claim progress it does not have, an empty one would read
  // as stuck, so they sit at a tenth -- enough to look alive, not enough to be read as a measurement
  if (a && a.phase && a.phase !== "matching") return "10%"
  return a && a.windows ? `${Math.round((100 * autoWindow.value) / a.windows)}%` : "0%"
})
const MB = b => `${((b || 0) / 1e6).toFixed(b && b < 1e7 ? 1 : 0)} MB`
// One press is one thing, so every leg answers in the same place: the pill's own tail. Matching keeps its window
// count, which is the only leg with a real measurement in it.
const autoLeg = computed(() => {
  const a = auto.value
  if (!a) return ""
  if (a.phase === "going") return "going there"
  if (a.phase === "planning") return "checking"
  if (a.phase === "asking") return a.ask ? MB(a.ask.bytes) + "?" : "your call"
  if (a.phase === "downloading") return `${a.area && a.area.total ? `${a.area.done || 0}/${a.area.total}` : "starting"} · ${mmss(a.waitedS)}`
  return `${autoWindow.value} / ${a.windows || 1}`
})
// What is waiting on the player, or null. `bytes` is the only figure shown: BeamNG.Earth's own documentation says
// not to show `seconds` (a serial model with no bandwidth in it -- it said 132 s for a download that took 43) and
// `km2` is the corridor's geometry, far smaller than the ground actually fetched.
const autoAsk = computed(() => (auto.value && auto.value.phase === "asking" && auto.value.ask) || null)
// (1.7.2) the stage page's progress card and the Stop labels (docs/mockups-1.7.2/download.html)
const AUTO_STEP = { planning: 0, asking: 1, downloading: 1, going: 2, matching: 3 }
const autoSteps = computed(() => {
  const a = auto.value
  const at = a && a.phase in AUTO_STEP ? AUTO_STEP[a.phase] : 3
  // (Download crossed out once it is behind and nothing was downloaded: the ground was already here, or BeamNG.Earth
  // would not take the area -- the stage's ending line says which)
  return ["Check", "Download", "Go to the start", "Match the line"].map((label, k) => ({ label,
    state: k < at ? (k === 1 && !(a && a.downloaded) ? "skip" : "done") : k === at ? "on" : "" }))
})
const autoWhat = computed(() => ({ planning: "Checking the map data", asking: "Map data to download",
  downloading: "Downloading the map data", going: "Going to the start of the stage" }[auto.value && auto.value.phase]
  || "Matching the line to the map's roads"))
const autoCount = computed(() => {
  const a = auto.value
  if (!a) return ""
  if (a.phase === "downloading") return a.area && a.area.total ? `${a.area.done || 0} of ${a.area.total} pieces` : "starting"
  if (a.phase === "matching") return `window ${autoWindow.value} of ${a.windows || 1}`
  if (a.phase === "asking") return MB(a.ask && a.ask.bytes)
  return ""
})
// the card's bar fills only on a real count: the items arrived, the windows finished; nothing on the other legs
// (autoPct is the pill's, which shows a tenth on the legs with no count and the window in flight while matching)
const autoFill = computed(() => {
  const a = auto.value
  if (a && a.phase === "downloading" && a.area && a.area.total) return `${Math.round((100 * (a.area.done || 0)) / a.area.total)}%`
  if (a && a.phase === "matching" && a.windows) return `${Math.round((100 * (a.done || 0)) / a.windows)}%`
  return "0%"
})
// the stripes: a leg that is working with no count moving to show for it (the match's windows move on their own)
const autoLive = computed(() => !!(auto.value && auto.value.phase !== "matching" && auto.value.phase !== "asking"))
const autoQuiet = computed(() => {
  const a = auto.value
  return !!(a && a.phase === "downloading" && (a.quietS || 0) >= 15 && a.area && a.area.total &&
    (a.area.done || 0) < a.area.total)
})
const autoFootL = computed(() => {
  const a = auto.value
  if (!a) return ""
  return a.phase === "matching" ? `${a.stepM} m at a time, from what is on this computer` : `${mmss(a.waitedS)} so far`
})
const autoFootR = computed(() => {
  const a = auto.value
  return a && a.phase === "downloading" && a.bytes ? `about ${MB(a.bytes)} in all` : ""
})
// (1.7.2) a full rally getting its stages ready: Stop stops them all, and says how many
const autoStopLabel = computed(() => (auto.value && auto.value.prepLeft > 1 ? `Stop all ${auto.value.prepLeft}` : "Stop"))
const autoRow = s => !!(auto.value && rly.value && auto.value.eventId === rly.value.id && auto.value.stageId === s.id)
const autoHere = computed(() => !!(auto.value && stg.value &&
  auto.value.eventId === stg.value.eventId && auto.value.stageId === stg.value.id))
const outcomeFor = s => arr(rly.value && rly.value.autoLines).find(l => l.stageId === s.id) || null
const outcomeCls = kind => AUTO_OUTCOME[kind] || "flat"
// Enter on the row opens the stage -- but only when the row itself has the focus. Enter on a button inside it
// already fires that button's own click, and the keydown bubbles up here as well, so without this the Stop button
// would stop the auto recce and open the stage in the one keypress (the keyboard twin of needing @click.stop).
function rowEnter(e, s) { if (e.target === e.currentTarget) openStage(rly.value.id, s.id) }

// Home > Drive stage > Season > Rally > Stage, Home > Drive rally > Start the rally: { label, go } each, go (a way
// back) on all but the last (#39). Home > Drive rally > X results (#55), Home > Time card > X results.
const crumbs = computed(() => {
  const home = { label: "Home", go: () => openHome() }
  if (view.value === "home" || mp.value) return [{ label: "Home" }]
  if (view.value === "pick") return [home, { label: "Drive rally" }]
  if (view.value === "rally" && resultsFrom.value) {
    const from = resultsFrom.value === "pick" ? { label: "Drive rally", go: () => openPick(true) } : { label: "Time card", go: () => openCard() }
    return [home, from, { label: `${(rly.value && rly.value.name) || "Rally"} results` }]
  }
  if (view.value === "settings") return settingsFrom.value === "timecard"
    ? [home, { label: "Time card", go: () => openCard() }, { label: "Settings" }] : [home, { label: "Settings" }]
  if (view.value === "timecard") return [home, { label: "Time card" }]
  if (view.value === "importReport") return [home, { label: "Drive stage", go: () => go("rallies") }, { label: "Import report" }]
  if (view.value === "rallyStart") {
    if (startFrom.value === "pick") return [home, { label: "Drive rally", go: () => openPick(true) }, { label: "Start the rally" }]
    return [home, { label: "Drive stage", go: () => go("rallies") },
      { label: (rly.value && rly.value.name) || "Rally", go: () => openRally(sel.value.eventId, false) },
      { label: "Start the rally" }]
  }
  const c = [home, { label: "Drive stage", go: () => go("rallies") }]
  const seasonCrumb = s => ({ label: s.name, go: () => openSeason(s.id) })
  if (view.value === "season") c.push({ label: (ssn.value && ssn.value.name) || "" })
  if (view.value === "rally" && rly.value) {
    if (rly.value.season) c.push(seasonCrumb(rly.value.season))
    c.push({ label: rly.value.name })
  }
  if (view.value === "stage" && stg.value) {
    const s = stg.value
    if (!s.single) {
      if (s.season) c.push(seasonCrumb(s.season))
      c.push({ label: s.rally, go: () => openRally(s.eventId, false) })
    }
    c.push({ label: s.name })
  }
  return c
})

// ---- a rally's page
// Stages / Results / Rules: Results with real results to show, Rules when the file has any
const rallyTab = ref("stages")
const rallyTabs = computed(() => {
  const r = rly.value
  const t = [{ id: "stages", label: "Stages" }]
  if (r && r.results) t.push({ id: "results", label: "Results" })
  if (r && arr(r.rules).length) t.push({ id: "rules", label: "Rules" })
  return t
})
const curTab = computed(() => (rallyTabs.value.some(t => t.id === rallyTab.value) ? rallyTab.value : "stages"))
// (#55) where a rally's results were opened from: 'pick' (Drive rally), 'timecard' (a finished rally's Full results),
// or null (its own page). Set by openResults, cleared by every other way into a rally's page.
const resultsFrom = ref(null)
// the bumpers (a controller's tab_l / tab_r): a rally's tabs, or a season's (EarthRallySeason.vue), round the ends
const seasonView = ref(null)
function stepTab(d) {
  if (view.value === "season") {
    if (seasonView.value) seasonView.value.stepTab(d)
    return
  }
  const t = rallyTabs.value
  if (view.value !== "rally" || t.length < 2 || resultsFrom.value) return
  const i = t.findIndex(x => x.id === curTab.value)
  rallyTab.value = t[(i + d + t.length) % t.length].id
}
// (the helper pop-up up, #77: the page under it does not move)
const tabPrev = () => { if (!mp.value && !st.value.helperPrompt && !st.value.namePrompt) stepTab(-1) }
const tabNext = () => { if (!mp.value && !st.value.helperPrompt && !st.value.namePrompt) stepTab(1) }
const legend = computed(() => !!(rly.value && (rly.value.anyCancelled || rly.value.hasBoard)))
const cancelledSs = computed(() => {
  for (const s of arr(rly.value && rly.value.list)) {
    const p = arr(s.passes).find(x => x.cancelled)
    if (p) return p.ss
  }
  return ""
})
// a row's passes (menu.lua: the itinerary's, or SS1, SS2... in map order with none). A line the itinerary never
// runs has none and says "Not run" (s.notRun): it is never given a made-up SS number.
const passList = s => arr(s && s.passes)
// The columns: the SS cell is as wide as the rally's longest label ("SS3 · SS7 · SS11"), and Place comes in with
// real results. The seventh column (Auto recce / Reset) keeps its 210px whatever else changes (see .er-srow).
// SS_CH_PX: one character of the cell's 18px Overpass Mono (0.6 em, rounded up); before, the cell was 100 or 170px,
// and a stage run three times or more ran its label over the name (the user, 2026-11-14).
const SS_CH_PX = 11
const ssText = s => passList(s).map(p => p.ss).join(" · ")
const srowCols = computed(() => {
  const r = rly.value
  const chars = Math.max(0, ...arr(r && r.list).map(s => (s.notRun ? 0 : ssText(s).length)))
  const ss = Math.max(100, Math.ceil(chars * SS_CH_PX) + 20)
  return { gridTemplateColumns: `${ss}px minmax(0, 1fr) 130px 260px 210px 150px ${r && r.hasBoard ? "130px " : ""}30px` }
})
const rallySub = computed(() => {
  const r = rly.value
  if (!r) return ""
  const parts = [days(r.dates, true), r.place].filter(Boolean)
  if (parts.length) return parts.join(" · ")
  return `From ${r.file || "your map"} · ${r.stages} ${r.stages === 1 ? "stage" : "stages"}`
})

// ---- a stage's page
// "SS2 · SS4 · OLYMPUS RALLY 2026"; "NOT RUN · ..." for a line the itinerary never runs; "STAGE" for a stage on
// its own
const ssLine = computed(() => {
  const s = stg.value
  if (!s) return ""
  if (s.single) return "STAGE"
  const ss = s.notRun ? "NOT RUN" : arr(s.passes).map(p => p.ss).join(" · ")
  return [ss, (s.rally || "").toUpperCase()].filter(Boolean).join(" · ")
})
// The points row under the tiles: each kind's state from the map's count -- n > 0 "map", 0 "rnd", except medical
// "none" (the dressing never invents a medical point) and a radio / spectator kind the rally's map marks on another
// stage, "none" too (stg.marked, events.markedKinds: the dressing puts none of it here; 1.6.0's note 5). Marshals stay
// "rnd" at 0: the junction marshals at taped turns go up whatever the map marks. And the one help line, naming only
// what is Random / None
const PT_KINDS = [
  { key: "radio", label: "Radio", words: "radio points" },
  { key: "medical", label: "Medical", words: "medical points" },
  { key: "marshal", label: "Marshals", words: "marshal posts" },
  { key: "spectator", label: "Spectators", words: "spectator areas" },
]
const ptState = (key, n, marked) =>
  n > 0 ? "map" : key === "medical" ? "none" : key !== "marshal" && marked && marked[key] ? "none" : "rnd"
const pts = computed(() => {
  const m = (stg.value && stg.value.marks) || {}
  const marked = (stg.value && stg.value.marked) || {}
  return PT_KINDS.map(k => ({ ...k, n: m[k.key] || 0, state: ptState(k.key, m[k.key] || 0, marked) }))
})
const joinWords = (l, conj) => (l.length < 2 ? l.join("") : l.slice(0, -1).join(", ") + " " + conj + " " + l[l.length - 1])
const ptsHelp = computed(() => {
  const rnd = pts.value.filter(p => p.state === "rnd").map(p => p.words)
  const none = pts.value.filter(p => p.state === "none")
  const elsewhere = none.filter(p => p.key !== "medical").map(p => p.words)
  const medical = none.some(p => p.key === "medical")
  return { rnd: joinWords(rnd, "or"), none: none.length > 0, elsewhere: joinWords(elsewhere, "and"), medical,
           all: !rnd.length && !none.length }
})
const runsShown = computed(() => {
  const runs = arr(stg.value && stg.value.runs)
  return stg.value && stg.value.board ? runs.slice(0, 2) : runs
})

// (additions A) Best splits: 1/4, 1/2, 3/4 and the finish of one run (menu.stageBase's bestSplits)
const SPLIT_LABELS = ["1/4", "1/2", "3/4", "Finish"]
const bestSplitTimes = computed(() => {
  const b = stg.value && stg.value.bestSplits
  if (!b) return []
  return [...arr(b.splits).slice(0, 3), b.timeS]
})
// A split's gap to the best splits: "−0.3" ahead, "+0.6" slower, "0.0" level
function splitGap(s) {
  const a = Math.abs(Math.round(s * 10) / 10)
  if (a === 0) return "0.0"
  return (s < 0 ? "−" : "+") + (a < 60 ? a.toFixed(1) : longTime(a))
}
// The day a run was driven, "16 Nov" (where the best splits came from)
function dayOf(iso) {
  if (!iso) return ""
  const d = new Date(iso)
  return isNaN(d.getTime()) ? "" : d.toLocaleDateString([], { day: "numeric", month: "short" })
}
// A road penalty: "+20 s" under a minute, "+1:10" from one up
function roadText(s) {
  const t = Math.round(s || 0)
  return t < 60 ? `+${t} s` : `+${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`
}
// The full rally's chips: its passes in order, each stop that cost something after the pass before it
const fullChips = computed(() => {
  const f = rly.value && rly.value.rallyFinished
  if (!f) return []
  const stops = arr(f.stops)
  const out = []
  for (const p of arr(f.passes)) {
    out.push({ label: p.ss, timeS: p.timeS, penS: p.roadS, sr: !!p.superRally })
    for (const s of stops) if (s.after === p.ss) out.push({ label: s.label, penS: s.penaltyS, stop: true })
  }
  return out
})

const banner = computed(() => {
  const s = st.value
  if (s.auto) {
    const n = `Auto recce of ${ssName(s.auto)}`
    if (s.auto.phase === "going") return `${n}: going to the start, waiting for the world to load`
    if (s.auto.phase === "planning") return `${n}: checking what map data is missing`
    if (s.auto.phase === "asking") return `${n}: ${MB(s.auto.ask && s.auto.ask.bytes)} of map data to download -- your call`
    if (s.auto.phase === "downloading") {
      const a = s.auto.area
      return `${n}: downloading the map data${a && a.total ? `, ${a.done || 0} of ${a.total} pieces` : ""}, ${mmss(s.auto.waitedS)}`
    }
    // "no map data is downloaded" is not padding: someone watching a progress bar assumes it is downloading, and
    // the matching leg reads only what is already on this computer -- which is still true, and is why this
    // sentence belongs to the matching leg alone now rather than to the whole button.
    return `${n}: window ${autoWindow.value} of ${s.auto.windows}, no map data is downloaded`
  }
  if (s.recce) {
    const pct = Math.round((s.recce.share || 0) * 100)
    return s.recce.started ? `Recce of ${s.recce.stageName}: ${pct} % driven` : `Recce of ${s.recce.stageName}: drive to the start of the stage; recording begins there`
  }
  if (s.run && s.run.busy) return `${ssName(s.run)}: ${RUN_WORDS[s.run.state] || s.run.state}`
  if (s.run && s.run.state === "failed") return `${s.run.stageName}: stopped (${s.run.error || ""})`
  return ""
})

const controlsLine = computed(() => {
  const s = stg.value
  if (!s) return ""
  const parts = []
  if (s.atc) parts.push("Time control before the start")
  if (s.stop) parts.push("stop control after the flying finish")
  return parts.length ? parts.join(" · ") : "Start line and flying finish"
})

function go(v) { if (v === "settings") settingsFrom.value = null; view.value = v; busyMsg.value = "" }
// (an import's report, from the Rallies page's Last import lines)
const reportFile = ref("")
function openReport(file) { reportFile.value = file || ""; go("importReport") }
// (notes-rally-loop 6) Settings opened from the time card goes back to it; from anywhere else, Home (#39)
const settingsFrom = ref(null)
function openSettings() { const from = view.value === "timecard" ? "timecard" : null; go("settings"); settingsFrom.value = from }
// Where the menu was left, for the next time it opens with no page asked for (the pause menu's button, Ctrl+Alt+K):
// the user, 2026-11-14, "the rally menu should also now remember where it was when you close and open it".
// (not the leaderboard's pass: after another drive the board opens on the pass you place best on, as Lua picks it)
watch([view, sel, rallyTab, settingsFrom], () => {
  lastPlace.at = { view: view.value, sel: { ...sel.value, pass: null }, rallyTab: rallyTab.value,
    settingsFrom: settingsFrom.value }
}, { deep: true })
function resume(at) {
  const s = at.sel || {}
  if (at.view === "stage" && s.eventId && s.stageId) {
    openStage(s.eventId, s.stageId)
  } else if (at.view === "rally" && s.eventId) {
    openRally(s.eventId, false)
    if (at.rallyTab) rallyTab.value = at.rallyTab
  } else if (at.view === "season" && s.seasonId) openSeason(s.seasonId)
  else if (at.view === "settings") { go("settings"); settingsFrom.value = at.settingsFrom || null }
  else if (at.view === "timecard") openCard()
  else if (at.view === "rallies") go("rallies")
  else if (at.view === "pick") openPick()
  else return
  // the season the rally or stage was reached through, for Back and the crumbs
  if (s.seasonId) sel.value = { ...sel.value, seasonId: s.seasonId }
}
// A remembered page whose rally, season or stage has gone (removed from the import folder): Rallies, rather than
// "Loading..." for ever. Each reply is checked against the page asked for (main.lua's missing replies carry their
// ids), so an old "missing" left in the store from an earlier page cannot send the player back.
watch(season, x => {
  if (x && x.missing && view.value === "season" && x.id === sel.value.seasonId) go("rallies")
})
watch(rally, x => {
  if (x && x.missing && view.value === "rally" && x.id === sel.value.eventId) go("rallies")
})
watch(stage, x => {
  if (x && x.missing && view.value === "stage" && x.eventId === sel.value.eventId && x.id === sel.value.stageId) {
    go("rallies")
  }
})
const pill = status => STATUS[status] || STATUS.none
const dash = v => (v === null || v === undefined ? "–" : v)
function openSeason(id) {
  sel.value = { seasonId: id, eventId: null, stageId: null, pass: null }
  loadSeason(id)
  go("season")
}
// redirect: a rally of one stage and no season opens on its stage (Back from that stage goes to Rallies, so it never
// comes back through here; false from the stage's own crumb all the same)
function openRally(id, redirect = true) {
  resultsFrom.value = null
  if (sel.value.eventId !== id) rallyTab.value = "stages"
  sel.value = { ...sel.value, eventId: id, stageId: null, pass: null }
  loadRally(id, r => {
    if (redirect && r && r.single && r.id === id && view.value === "rally" && sel.value.eventId === id) {
      const first = arr(r.list)[0]
      if (first) openStage(id, first.id)
    }
  })
  go("rally")
}
// Reset's confirm, for a driven recce (the matched case needs none). Held here rather than per stage because
// it must not survive leaving the page: a confirm still up when another stage is opened would sit over a line it
// was never asked about.
const confirmReset = ref(false)
// A new recce over a line that has times on it asks first, as Reset does: those times stop being placed.
const confirmRecce = ref(false)
const PLACED_WARN = "If the new line runs differently, your times here stop counting on the leaderboards (they stay in Your runs)."
function recce() {
  const s = stg.value
  if (s && s.line && s.best) { confirmReset.value = false; confirmRecce.value = true }
  else if (s) action("recce", s.eventId, s.id)
}

function openStage(eventId, stageId) {
  sel.value = { ...sel.value, eventId, stageId, pass: null }
  confirmReset.value = false
  confirmRecce.value = false
  loadStage(eventId, stageId)
  go("stage")
}
// the leaderboard's pass toggle
function choosePass(ss) {
  sel.value = { ...sel.value, pass: ss }
  loadStage(sel.value.eventId, sel.value.stageId, ss)
}

// Reset pressed on a list row whose line was driven, or that has times: open the stage and put the confirm up
// there, rather than deleting from under the player in a row that has no room to say what is lost.
function askReset(eventId, stageId) {
  openStage(eventId, stageId)
  confirmReset.value = true
}
// ---- the full rally (1.7.0)
// Home and Drive rally (#39): each asks for the full rallies as it opens (menu.lua M.drive: it reads save files, so
// it is not polled)
function openHome() {
  loadDrive()
  go("home")
}
// keep: back to Drive rally from a page it opened (a rally's results, the start screen) with the same rally picked
// (#55); else Drive rally picks as it always has (the one under way, the last saved, the first)
const pickSel = ref(null)
function openPick(keep) {
  if (!keep) pickSel.value = null
  loadDrive()
  go("pick")
}
// Y on Drive rally: the picked rally's Results, its page on the Results tab alone (#55)
const pickView = ref(null)
function contextPress() { if (mp.value || st.value.helperPrompt || st.value.namePrompt) return; if (view.value === "pick" && pickView.value) pickView.value.results() }
function openResults(id, from) {
  if (from === "pick") pickSel.value = id
  openRally(id, false)
  rallyTab.value = "results"
  resultsFrom.value = from || null
}
// where the start screen was opened from ('pick': Drive rally, else a rally's page), for Back and the crumbs
const startFrom = ref(null)
function openStart(id, from) {
  startFrom.value = from || null
  keep.startFrom = startFrom.value
  if (from === "pick") pickSel.value = id
  sel.value = { ...sel.value, eventId: id }
  loadRallyStart(id)
  go("rallyStart")
}
function openCard() {
  loadRallyCard()
  go("timecard")
}
function resumeRally(id) {
  rallyAction("resume", id, null, r => { if (r.ok) openCard() })
}
// (#28) Retire from the rally page: its confirm is in the bar (retireAsk = the rally's id while it is up)
const retireAsk = ref(null)
function retireRally(id) {
  retireAsk.value = null
  rallyAction("abandon", id, null, () => loadRally(id))
}
// (the full rally's pages asking for another: the time card after Start, the rally's page after Quit, a finished
// rally's Full results and Home after New rally, #71)
function fullView(v, id) {
  if (v === "timecard") openCard()
  else if (v === "rally") openRally(id || sel.value.eventId, false)
  else if (v === "results") openResults(id || sel.value.eventId, "timecard")
  else if (v === "home") openHome()
  else go(v)
}
// (the loading screen up: no page under it to go back through, #60)
const loadingUp = ref(false)
function back() {
  if (loadingUp.value) return
  if (mp.value) return closeMenu()
  if (st.value.helperPrompt) return helperPromptClose(false)   // (B on the helper pop-up, #77: Got it)
  if (st.value.namePrompt) return namePromptLater()             // (B on the name pop-up: Later)
  if (view.value === "rallyStart") {
    if (startFrom.value === "pick") openPick(true)
    else openRally(sel.value.eventId, false)
    return
  }
  if (view.value === "rally" && resultsFrom.value) {
    if (resultsFrom.value === "pick") openPick(true)
    else openCard()
    return
  }
  // (#39: Drive rally, Drive stage and Settings go back to Home; so does the time card, where Home's Continue strip
  // is: the mock-up's homeSaved)
  if (view.value === "settings" && settingsFrom.value === "timecard") { openCard(); return }
  if (view.value === "importReport") { go("rallies"); return }
  if (["timecard", "pick", "rallies", "settings"].includes(view.value)) {
    openHome()
    return
  }
  if (view.value === "stage") {
    const single = stg.value ? stg.value.single : (rly.value && rly.value.single)
    if (single) go("rallies")
    else openRally(sel.value.eventId, false)
  } else if (view.value === "rally") {
    const s = rly.value && rly.value.season
    if (s) openSeason(s.id)
    else go("rallies")
  } else if (view.value === "season") go("rallies")
  else closeMenu()
}
// (plan G) the stage page's Weather row: the picks in order, Rally day only when the shown pass has stored weather
// (a remembered Rally day reads as Current where there is none, and comes back on a stage that has it)
const WX_PICKS = [["current", "Current"], ["rallyday", "Rally day"], ["clear", "Clear", "sun"], ["cloudy", "Cloudy", "cloud"],
  ["rain", "Rain", "rain"], ["storm", "Storm", "storm"], ["snow", "Snow", "snow"], ["fog", "Fog", "fog"]]
const wxVal = ref(null)
// (Rally day only with stored weather for the shown pass; a preset only when this BeamNG.Earth has it)
const wxPicks = computed(() => WX_PICKS.filter(p => p[0] === "current"
  || (p[0] === "rallyday" ? !!(stg.value && stg.value.wxDay) : arr(stg.value && stg.value.wxPresets).includes(p[0]))))
const wxPick = computed(() => {
  const v = st.value.settings && st.value.settings.settings && st.value.settings.settings.stageWeather
  return wxPicks.value.some(p => p[0] === v) ? v : "current"
})
const wxShown = computed(() => {
  const p = wxPicks.value.find(x => x[0] === wxPick.value) || WX_PICKS[0]
  // (the weather only: a single stage keeps BeamNG.Earth's hour, so no "night" and no moon here)
  if (p[0] === "rallyday") {
    const w = stg.value.wxDay
    return { icon: w.icon === "moon" ? "sun" : w.icon, label: "Rally day · " + w.text }
  }
  return { icon: p[2], label: p[1] }
})
function wxStep(d) {
  const ps = wxPicks.value
  const i = Math.max(0, ps.findIndex(p => p[0] === wxPick.value))
  setSetting("stageWeather", ps[(i + d + ps.length) % ps.length][0])
}
// (the D-pad / stick and the arrow keys, as BeamNG's UI nav sends them: only while the row has the focus)
function wxNav(d) { if (wxVal.value && document.activeElement === wxVal.value) wxStep(d) }
function action(what, eventId, stageId) {
  luaAction(what, eventId, stageId, () => {
    if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId, sel.value.pass)
    if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  })
}

// the poll: the state every second, the page's own data every two
let timer = null
let tick = 0
function poll() {
  refreshState()
  if (view.value === "timecard") loadRallyCard()
  if (++tick % 2) return
  if (view.value === "season" && sel.value.seasonId) loadSeason(sel.value.seasonId)
  if (view.value === "rally" && sel.value.eventId) loadRally(sel.value.eventId)
  if (view.value === "stage" && sel.value.stageId) loadStage(sel.value.eventId, sel.value.stageId, sel.value.pass)
}

onMounted(() => {
  // (opened at a page: the results card's Rally menu, a pause-menu rally)
  refreshState()
  loadDrive()   // (Home's Continue strip; Drive rally asks again as it opens)
  takeOpenAt(at => {
    if (at && at.view === "timecard") openCard()
    else if (at && at.view === "stage" && at.eventId && at.stageId) openStage(at.eventId, at.stageId)
    else if (at && at.view === "rally" && at.eventId) openRally(at.eventId)
    else if (at && at.view === "rallyStart" && at.eventId) openStart(at.eventId, keep.startFrom)
    else if (at && at.view === "season" && at.eventId) openSeason(at.eventId)
    else if (at && at.view === "settings") go("settings")
    else if (at && at.view === "rallies") go("rallies")
    else if (at && at.view === "home") { /* asked for: Home */ }
    else if (lastPlace.at) resume(lastPlace.at)
  })
  timer = setInterval(poll, 1000)
})
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<style lang="scss" scoped>
.er-page {
  --er-orange: #f26b1d;
  --er-orange-500: #c75b1e;
  --er-muted: #b8bcc6;
  --er-dim: #8a909a;
  --er-blue: #1f8fff;
  position: absolute; inset: 0; display: flex; flex-direction: column; color: #f0f0f0;
  font-family: "Noto Sans", sans-serif; font-size: 16px;
  background: rgba(10, 12, 16, 0.72);
}
.er-topbar {
  height: 84px; flex-shrink: 0; display: flex; align-items: center; gap: 20px; padding: 0 64px;
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.8), rgba(0, 0, 0, 0.35));
}
.er-back { display: flex; align-items: center; gap: 10px; padding: 8px 16px 8px 10px; border-radius: 0.25rem; background: rgba(0, 0, 0, 0.4); color: var(--er-muted); font-size: 18px; cursor: pointer; }
.er-title { font-size: 30px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; }
.er-accent { color: var(--er-orange); }
.er-crumbs { font-size: 18px; color: var(--er-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0;
  span + span::before { content: "›"; margin: 0 10px; color: #6f7480; }
  span:last-child { color: #fff; }
  .er-cgo { cursor: pointer; }
  .er-cgo:hover { color: #fff; text-decoration: underline; } }
.er-right { margin-left: auto; display: flex; gap: 12px; }
.er-content { flex: 1; padding: 28px 64px 24px; overflow-y: auto; }
/* Home: a column, its lines at their height and the tiles in what is left (notes-1.7.4 #3) */
.er-content-fill { display: flex; flex-direction: column; > * { flex-shrink: 0; } }
/* (a controller's focus on the small things -- tabs, Back, a setting's choice, a leaderboard pass -- that have no
   :focus look of their own; the cards and rows keep theirs) */
.er-page :deep(span[bng-nav-item]:focus), .er-back:focus { outline: 2px solid var(--er-orange); outline-offset: 2px; }

.er-card { background: rgba(0, 0, 0, 0.6); border-radius: 0.5rem; }
/* (plan F) the multiplayer card, alone in the middle of the page */
.er-mp { min-height: 100%; display: flex; align-items: center; justify-content: center; }
.er-mpcard { width: 940px; max-width: 100%; padding: 48px 56px 44px; border-left: 6px solid var(--er-orange); border-radius: 0 0.5rem 0.5rem 0;
  h2 { margin: 12px 0 18px; font-size: 48px; text-transform: uppercase; line-height: 1.1; }
  p { margin: 0 0 34px; font-size: 22px; line-height: 1.5; color: #dfe2e8; max-width: 800px; }
  .er-mpbtn { --bng-button-margin: 0; font-size: 26px; line-height: 32px; padding: 14px 40px; letter-spacing: 0.04em; } }
.er-mpkick { display: flex; align-items: center; gap: 12px; font-size: 15px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--er-orange); font-weight: 700;
  svg { width: 26px; height: 26px; } }
.er-lbswitch { display: flex; gap: 4px; align-self: flex-start; margin-bottom: -10px; background: rgba(0, 0, 0, 0.6); border-radius: 0.25rem; padding: 4px;
  span { padding: 6px 18px; border-radius: 3px; font-size: 16px; font-weight: 600; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; } }
.er-muted { color: var(--er-muted); }
.er-dim { color: var(--er-dim); font-size: 15px; }
.er-small { font-size: 14px; margin-top: 12px; }
.er-mono { font-family: "Overpass Mono", monospace; }
.er-row { display: flex; gap: 12px; flex-wrap: wrap; }
.er-banner { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; padding: 12px 18px; border-radius: 0.5rem; background: rgba(31, 143, 255, 0.25); border-left: 4px solid var(--er-blue); font-size: 18px; span { margin-right: auto; } }
.er-warnline { margin-bottom: 14px; color: #ffd36b; }
.er-noteline { margin-bottom: 14px; color: var(--er-muted); }
.er-fb-warn { color: #ffd36b; align-self: center; }
.er-msg { margin-top: 12px; color: #ffd36b; }
.er-stat .er-v { font-family: "Overpass Mono", monospace; font-size: 32px; font-weight: 700; }
.er-stat .er-l, .er-tile .er-l, .er-pt .er-l { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }

.er-pill { display: inline-flex; align-items: center; gap: 8px; font-size: 15px; font-weight: 600; padding: 3px 12px; border-radius: 999px; white-space: nowrap;
  &::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
  &.ready { background: rgba(40, 140, 80, 0.55); color: #d9ffe6; }
  &.recce { background: rgba(190, 140, 30, 0.45); color: #fff1cc; }
  &.none { background: rgba(170, 60, 60, 0.45); color: #ffdede; }
  /* the auto recce running: the pill IS the progress bar. Its background is a two-stop gradient whose hard edge
     sits at --er-done, set per row from the window count, so it fills left to right as the windows come in. A 58px
     row has no second line for a bar of its own, and a bar across the row would read as a selection. */
  &.working {
    color: #cfe8ff;
    background: linear-gradient(to right, rgba(31, 143, 255, 0.62) var(--er-done, 0%), rgba(31, 143, 255, 0.22) var(--er-done, 0%));
    .er-wn { font-family: "Overpass Mono", monospace; font-weight: 700; margin-left: -2px; }
    &::before { animation: er-pulse 1.2s ease-in-out infinite; }
    /* (1.7.2) stripes along the unfilled part while it works, so a count that sits still never reads as stuck;
       the fill still only moves on a real number */
    &.live { background: linear-gradient(to right, rgba(31, 143, 255, 0.62) var(--er-done, 0%), transparent var(--er-done, 0%)),
        repeating-linear-gradient(-45deg, rgba(31, 143, 255, 0.3) 0 8px, rgba(31, 143, 255, 0.16) 8px 16px);
      background-size: 100% 100%, 22.6px 100%; animation: er-run 1s linear infinite; }
  }
}
@keyframes er-run { to { background-position: 0 0, 22.6px 0; } }
@keyframes er-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

.er-clip { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.er-report { background: rgba(0, 0, 0, 0.4); border-radius: 0.25rem; padding: 12px 14px; font-size: 15px; line-height: 1.5; }
.er-report-full { margin-top: 18px; summary { cursor: pointer; font-weight: 600; } }

/* a rally's banner: its photo behind a dark fade, the logo (or a drawn plate), the name and its numbers */
.er-rbanner { position: relative; height: 196px; border-radius: 0.5rem; overflow: hidden; display: flex; align-items: center; gap: 34px; padding: 0 34px; margin-bottom: 18px;
  > :not(.er-rb-photo) { position: relative; z-index: 1; } }
.er-rbanner .er-rb-photo { position: absolute; inset: 0;
  &::after { content: ""; position: absolute; inset: 0; z-index: 1;
    background: linear-gradient(90deg, rgba(8, 10, 14, 0.92) 0%, rgba(8, 10, 14, 0.78) 45%, rgba(8, 10, 14, 0.25) 100%); } }
.er-rbanner .er-rb-logo { width: 290px; height: 145px; flex-shrink: 0; background: none;
  :deep(.er-plate) { min-width: 100%; padding: 18px 16px 14px; }
  :deep(.er-pn) { font-size: 24px; } }
.er-rb-text { min-width: 0; }
.er-rb-round { font-size: 14px; font-weight: 700; letter-spacing: 0.14em; color: var(--er-orange); text-transform: uppercase; }
.er-rb-name { font-size: 46px; font-weight: 700; line-height: 1.1; }
.er-rb-sub { font-size: 19px; color: #dfe3ea; margin-top: 4px; }
.er-rb-stats { margin-left: auto; display: flex; gap: 36px; flex-shrink: 0;
  .er-stat { text-align: right; }
  .er-v { font-size: 30px; }
  .er-l { font-size: 13px; } }
.er-under-banner { display: flex; align-items: center; gap: 20px; margin-bottom: 14px; }
.er-legend { margin-left: auto; font-size: 15px; color: var(--er-muted); s { color: #6f7480; } }
/* in-page tabs: the game's segmented look */
.er-tabs { display: flex; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  span { padding: 8px 22px; border-radius: 3px; font-size: 18px; font-weight: 600; color: var(--er-muted); cursor: pointer; }
  span.on { background: var(--er-orange-500); color: #fff; } }
.er-rules { max-width: 760px; padding: 12px 0; }
.er-rule { display: grid; grid-template-columns: 1fr auto; padding: 18px 30px; font-size: 22px; align-items: center;
  & + .er-rule { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  .er-rv { font-family: "Overpass Mono", monospace; font-weight: 700; }
  .er-in { font-size: 13px; font-weight: 700; letter-spacing: 0.06em; padding: 2px 8px; margin-left: 12px; border-radius: 3px; background: var(--er-blue); vertical-align: 3px; } }
.er-stages { padding: 8px 0; }
/* Seven tracks: the action column comes out of Name's 1fr, NOT out of Status -- Status already holds the longest
   pill ("Missing road segments", about 183px) with its 30px padding, and below about 215px that pill overruns the
   column. 210px rather than 1.3.0's 160px, because the cell now holds TWO controls while a download waits on an
   answer: at the row's own button size (15px on a 20px line, no min-width, no margin) "Download" is about 92px
   and "Not now" about 83px, which with a 12px gap is 187px. Name goes from about 1066px to 856px at 1920, and the
   longest name in a real rally is about 460px. */
.er-srow { display: grid; grid-template-columns: 100px 1fr 130px 260px 210px 150px 30px; align-items: center; height: 58px; padding: 0 28px; font-size: 20px; border-left: 4px solid transparent;
  & + .er-srow { border-top: 1px solid rgba(255, 255, 255, 0.06); }
  &.er-hdr { height: 40px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); }
  &.er-click { cursor: pointer; }
  &.er-click:focus { background: rgba(199, 91, 30, 0.22); border-left-color: var(--er-orange); outline: none; }
  /* The stage being matched, findable while scrolling a long rally: the left border it already has, in blue.
     This has to beat the focus rule above on SPECIFICITY, not on order -- it is three classes plus the
     pseudo-class against their two, so it holds wherever it sits in the file. Written the other way round (same
     specificity, later in the file) the mark would vanish the moment anyone moved this block, or the focus. */
  &.er-running, &.er-running.er-click:focus { border-left-color: var(--er-blue); }
  .er-ss { font-family: "Overpass Mono", monospace; font-weight: 700; color: var(--er-muted); white-space: nowrap; font-size: 18px;
    s { color: #6f7480; text-decoration-thickness: 2px; } }
  .er-notrun { font-family: "Noto Sans", sans-serif; font-weight: 600; font-size: 15px; color: #6f7480; }
  .er-plc { font-family: "Overpass Mono", monospace; font-weight: 700; text-align: right;
    small { font-weight: 400; color: var(--er-dim); font-size: 14px; margin-left: 4px; } }
  .er-r { text-align: right; }
  .er-st { padding-left: 30px; }
  .er-none { color: #6f7480; }
  .er-go { color: var(--er-dim); text-align: right; }
  /* The action column. The button is sized by the game's own hooks rather than by overriding its rules: it sets
     font-size / line-height itself ("default value to be overriden with the parent component's styles",
     utility/button.vue:91-92) so those need :deep, while min-width (6em -- more than this cell has) and margin are
     custom properties it reads from whatever contains it. 15px text on a 20px line is a 29px button in a 58px row. */
  .er-act { padding-left: 24px; --bng-button-min-width: 0; --bng-button-margin: 0;
    display: flex; gap: 12px; align-items: center;
    :deep(.bng-button) { font-size: 15px; line-height: 20px; } }
}
.er-help { margin-top: 14px; font-size: 15px; }
/* how an auto recce ended, under the card, aligned with the rows above it */
.er-under { padding: 0 28px; }
.er-outcome { margin-top: 14px; font-size: 15px; line-height: 1.5;
  &.warn { color: #ffd36b; }
  &.flat { color: var(--er-muted); }
  &.err { color: #ff8a8a; }
  .er-ssx { font-family: "Overpass Mono", monospace; font-weight: 700; margin-right: 6px; }
}

.er-stage-page { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap: 28px; align-items: start; }
.er-rcol { display: flex; flex-direction: column; gap: 20px; min-width: 0; }
/* (plan G) the Weather row (docs/mockups-rally-loop/weather.html, screen d) */
.er-wxrow { display: flex; align-items: center; gap: 16px; margin-top: 22px;
  .er-wxl { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--er-muted); } }
.er-cyc { display: inline-flex; align-items: center; gap: 4px; background: rgba(0, 0, 0, 0.45); border-radius: 0.25rem; padding: 4px;
  .er-ar { padding: 8px 12px; font-size: 18px; font-weight: 700; color: var(--er-muted); cursor: pointer; }
  .er-val { display: inline-flex; align-items: center; gap: 8px; min-width: 250px; justify-content: center; padding: 8px 16px;
    border-radius: 3px; background: #c75b1e; color: #fff; font-size: 18px; font-weight: 600; white-space: nowrap; cursor: pointer;
    svg { width: 20px; height: 20px; flex: none; } }
  &:focus-within { outline: 2px solid var(--er-orange); outline-offset: 2px; .er-ar { color: #fff; } } }
.er-stage-ss { font-family: "Overpass Mono", monospace; font-size: 20px; color: var(--er-orange); font-weight: 700; letter-spacing: 0.05em; }
.er-stage-name { font-size: 52px; font-weight: 700; line-height: 1.1; }
.er-tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 26px 0; }
.er-tile { padding: 18px 20px; .er-v { font-family: "Overpass Mono", monospace; font-size: 40px; font-weight: 700; line-height: 1.1; small { font-size: 18px; margin-left: 4px; color: var(--er-muted); } } }
/* the stage's points: the tiles' own grid, so each cell sits under a tile. Its -10px top margin collapses with
   .er-tiles' 26px bottom one to a 16px gap -- the gap between the tiles themselves -- so the eight read as one block. */
.er-pts { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: -10px 0 10px; }
.er-pt { display: flex; align-items: center; gap: 12px; padding: 12px 16px; min-width: 0; }
.er-pt .er-pi { width: 28px; height: 28px; flex-shrink: 0; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.er-pv { display: flex; align-items: center; gap: 6px; font-size: 17px; font-weight: 600; white-space: nowrap; }
.er-pv b { font: 700 22px "Overpass Mono", monospace; line-height: 1; }
.er-pv .er-ps { width: 16px; height: 16px; flex-shrink: 0; fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
.er-pv .er-ps .f { fill: currentColor; stroke: none; }
.er-pt.map { color: #fff; }
.er-pt.rnd { color: var(--er-muted); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.22); border: 1px dashed rgba(255, 255, 255, 0.28); padding: 11px 15px; background: rgba(0, 0, 0, 0.45); }
.er-pt.rnd .er-pv { color: #dfe3ea; }
.er-pt.none { color: #6f7480; background: rgba(0, 0, 0, 0.35); }
.er-pt.none .er-l { color: #6f7480; }
.er-pts-help { margin: 0 0 22px; font-size: 15px; line-height: 1.5; color: var(--er-muted); }
.er-pts-help b { color: #fff; }
/* (1.7.2) the auto recce's progress card on the stage page */
.er-dl { padding: 16px 18px 14px; }
.er-dl-steps { display: flex; margin-bottom: 14px; font-size: 14px;
  span { flex: 1; display: flex; align-items: center; gap: 8px; color: var(--er-muted); }
  span::before { content: attr(data-n); width: 22px; height: 22px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font: 700 12px "Overpass Mono", monospace; background: rgba(255, 255, 255, 0.08); }
  .done { color: #9fd8b2; }
  .done::before { content: "\2713"; background: rgba(40, 140, 80, 0.55); color: #d9ffe6; }
  .skip { text-decoration: line-through; }
  .skip::before { content: "\2013"; }
  .on { color: #fff; font-weight: 600; }
  .on::before { background: #1f8fff; color: #fff; }
}
.er-dl-top { display: flex; justify-content: space-between; align-items: baseline; font-size: 17px; margin-bottom: 8px;
  b { font-weight: 600; } .er-mono { font-weight: 600; color: #cfe8ff; } }
.er-dl-bar { position: relative; height: 14px; border-radius: 7px; overflow: hidden; background: rgba(255, 255, 255, 0.1);
  &.live { background: repeating-linear-gradient(-45deg, rgba(31, 143, 255, 0.26) 0 10px, rgba(31, 143, 255, 0.12) 10px 20px);
    background-size: 28.3px 100%; animation: er-run2 1s linear infinite; }
  i { position: absolute; left: 0; top: 0; bottom: 0; background: #1f8fff; border-radius: 7px; transition: width 0.6s ease; }
}
@keyframes er-run2 { to { background-position: 28.3px 0; } }
.er-dl-foot { display: flex; justify-content: space-between; font-size: 14px; color: var(--er-muted); margin-top: 8px; }
.er-dl-note { font-size: 15px; line-height: 1.45; margin-top: 10px; }
.er-dl-wait { color: #ffe08a; }
.er-line-note { display: flex; align-items: center; gap: 14px; padding: 14px 18px; font-size: 17px; }
.er-actions { display: flex; gap: 14px; margin-top: 24px; flex-wrap: wrap; }
.er-act-help { margin-top: 16px; font-size: 15px; line-height: 1.7; color: var(--er-muted); }
/* Reset's confirm. Orange rather than red: the game has no destructive-red anywhere else, and one red card in a
   menu that has none would read as an error rather than a question. */
.er-confirm { display: flex; align-items: center; justify-content: space-between; gap: 20px; flex-wrap: wrap;
  margin-top: 14px; padding: 16px 20px; font-size: 16px; line-height: 1.5;
  box-shadow: inset 0 0 0 1px var(--er-orange-500);
  b { font-size: 17px; }
  span { color: var(--er-muted); }
}
.er-confirm-row { display: flex; gap: 12px; flex-shrink: 0; }
.er-runs { padding: 22px 26px; h3 { margin: 0 0 12px; font-size: 20px; } }
.er-best-box { display: flex; align-items: center; gap: 14px; margin-bottom: 12px; .er-t { font: 700 44px "Overpass Mono", monospace; } }
.er-badge { background: rgb(0, 200, 0); color: #002a00; font-weight: 800; padding: 2px 10px; border-radius: 6px; }
.er-run { display: grid; grid-template-columns: 1fr auto 1fr; gap: 14px; padding: 9px 0; border-top: 1px solid rgba(255, 255, 255, 0.07); font-size: 17px;
  .er-pen { color: #ffd36b; text-align: right; } .er-clean { color: #6fd39a; text-align: right; } }

.er-fullbar { display: flex; align-items: center; gap: 16px; padding: 14px 20px; margin-bottom: 14px; border-left: 4px solid var(--er-orange);
  .er-fb-text { display: flex; flex-direction: column; gap: 2px; margin-right: auto; font-size: 17px; b { font-size: 19px; } } }
.er-yourfull { padding: 14px 20px; margin-bottom: 14px; font-size: 18px; border-left: 4px solid var(--er-orange);
  .er-rp { color: #ffd36b; font-family: "Overpass Mono", monospace; font-weight: 700; } .er-rp0 { color: #6fd39a; } }
.er-chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
.er-chip { font-size: 16px; padding: 5px 12px; border-radius: 999px; background: rgba(40, 140, 80, 0.4); color: #d9ffe6; white-space: nowrap;
  .er-mono { margin-left: 6px; }
  i { font-style: normal; font-family: "Overpass Mono", monospace; font-weight: 700; color: #ffd36b; margin-left: 8px; }
  &.stop { background: rgba(255, 211, 107, 0.14); color: #ffe7ad; i { margin-left: 6px; } }
  &.sr { background: rgba(229, 83, 61, 0.25); color: #ffd0c8; } }
.er-bsplits { margin: 0 0 14px; padding: 10px 14px 12px; border-radius: 8px; background: rgba(255, 255, 255, 0.05);
  .er-sg4 { margin-top: 6px; div { font: 700 22px "Overpass Mono", monospace; } }
  small { display: block; font: 600 12px "Noto Sans", sans-serif; color: var(--er-dim); letter-spacing: 0.1em; } }
.er-bsh { display: flex; justify-content: space-between; font-size: 14px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--er-muted); font-weight: 600;
  span:last-child { text-transform: none; letter-spacing: 0; font-weight: 400; } }
.er-sg4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
.er-rsp { margin: 0 0 8px; font-size: 14px; color: var(--er-muted);
  div { font-family: "Overpass Mono", monospace; white-space: nowrap; }
  .er-a { color: #6fd39a; margin-left: 6px; } .er-b { color: #ffd36b; margin-left: 6px; }
  .er-z { color: var(--er-dim); margin-left: 6px; font-family: "Noto Sans", sans-serif; } }
.er-settings-page { display: grid; grid-template-columns: 1.6fr 1fr; gap: 28px; align-items: start; }
</style>
