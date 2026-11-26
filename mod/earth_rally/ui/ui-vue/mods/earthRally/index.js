import { lua, useBridge } from "@/bridge"

// Earth Rally's menu (ui/ui-vue/mods/README.md, as BeamNG.Earth's own mod does it):
//   a full-screen route "earthRally" (EarthRally.vue: Rallies, a rally, a stage, Settings), opened from Lua with
//     ui_router.navigate('earthRally') (earthRally_main.openMenu / toggleMenu: Ctrl+Alt+K)
//   an "Earth Rally" tab of its own in the pause menu (EarthRallyTab.vue): one button into the menu page, which opens
//     where it was left (the user, 2026-11-14: "simplify it and just have it have a button that takes you to the
//     rally menu"). The game's mod tabs show a component per button, not a bare button, so that is its one page.
// Lua side: lua/ge/extensions/earthRally/main.lua. A failure in one part is logged and leaves the other alone.
const TAB_ID = "earthRally"
const MOD_ROOT = "/ui/ui-vue/mods/earthRally"
const SOURCE = "earthRally.routes"

function routesWith(EarthRally) {
  return [
    {
      path: "/earth-rally",
      name: "earthRally",
      component: EarthRally,
      meta: {
        // (#53) the game's own bottom strip (its version line, the player, its button hints) off on our page: it
        // drew over our prompt bar, which already says what the buttons do. The router's ui.infoBar, as the
        // game's own full-screen routes set it (mapview, play: InfoBarDefaultsHidden).
        infoBar: { visible: false, showSysInfo: false },
        luaRoute: {
          title: "Earth Rally",
          backTarget: "play",
        },
      },
    },
  ]
}

function toLuaRoutes(records) {
  return records.map(record => ({ name: record.name, path: record.path, meta: record.meta }))
}

async function registerRoute() {
  try {
    if (!window.bngRoutes || !lua.extensions.ui_router_routeManager) return
    const routes = routesWith((await import("./EarthRally.vue")).default)
    window.bngRoutes.add([{ path: SOURCE, routes }])
    const result = await lua.extensions.ui_router_routeManager.registerModRoutes(SOURCE, toLuaRoutes(routes))
    if (!result?.success) {
      window.bngRoutes.remove([SOURCE])
      console.error("Earth Rally: menu route not registered", result?.errors)
    }
  } catch (e) {
    console.error("Earth Rally: menu route failed", e)
  }
}

async function registerPauseTab() {
  // (a UI reload keeps the game's Lua, and with it the Settings button an older build registered here)
  try { await lua.extensions.ui_pause_actions.unregisterModButton("earthRally-settings") } catch (e) { /* none */ }
  try {
    await lua.extensions.ui_pause_actions.registerModTab({
      id: TAB_ID,
      label: "Earth Rally",
      icon: "flag",
    })
    await lua.extensions.ui_pause_actions.registerModButton({
      id: "earthRally-rallies",
      tabId: TAB_ID,
      label: "Rally menu",
      icon: "flag",
      componentName: `${MOD_ROOT}/EarthRallyTab.vue`,
    })
  } catch (e) {
    console.error("Earth Rally: pause menu tab failed", e)
  }
}

// (2026-11-26) A Rally menu button over BeamNG.Earth's map while a full rally runs: back to the time card. The map is
// BeamNG.Earth's page, so the button is ours, laid over it: shown and hidden by Lua (main.lua mapButtonSync, event
// EarthRallyMapButton), the pad's Select doing the same. Plain DOM, no part of BeamNG.Earth's page touched.
const MAP_BTN_ID = "earthRallyMapButton"
const MAP_BTN_EVENT = "EarthRallyMapButton"
let mapBtnOn = null
function mapButtonEl() {
  let el = document.getElementById(MAP_BTN_ID)
  if (el) return el
  el = document.createElement("button")
  el.id = MAP_BTN_ID
  el.type = "button"
  el.innerHTML = '<span style="display:inline-block;min-width:1.6em;padding:0 0.35em;margin-right:0.55em;border:1px solid ' +
    'rgba(255,255,255,0.6);border-radius:0.3em;font-size:0.8em;line-height:1.5em">Select</span>Rally menu'
  Object.assign(el.style, {
    position: "fixed", left: "50%", top: "4.6em", transform: "translateX(-50%)", zIndex: "10000", display: "none",
    alignItems: "center", padding: "0.45em 1.1em", border: "0", borderRadius: "0.35em", cursor: "pointer",
    background: "rgba(14, 18, 24, 0.88)", color: "#fff", font: "600 15px/1.3 sans-serif",
    boxShadow: "0 2px 10px rgba(0, 0, 0, 0.45)",
  })
  el.addEventListener("click", () => {
    if (window.bngApi && window.bngApi.engineLua) window.bngApi.engineLua("if earthRally_main then earthRally_main.mapToMenu() end")
  })
  document.body.appendChild(el)
  return el
}
function onMapButton(d) {
  try { mapButtonEl().style.display = d && d.show ? "flex" : "none" } catch (e) { /* no page yet */ }
}
function mapButtonOn() {
  try {
    if (mapBtnOn) return
    const bridge = useBridge()
    bridge.events.on(MAP_BTN_EVENT, onMapButton)
    mapBtnOn = bridge
  } catch (e) {
    console.error("Earth Rally: map button failed", e)
  }
}
function mapButtonOff() {
  try { if (mapBtnOn) mapBtnOn.events.off(MAP_BTN_EVENT, onMapButton) } catch (e) { /* gone */ }
  mapBtnOn = null
  const el = document.getElementById(MAP_BTN_ID)
  if (el) el.remove()
}

export async function onLoad() {
  mapButtonOn()
  await registerPauseTab()
  await registerRoute()
}

export async function onUnload() {
  mapButtonOff()
  try { await lua.extensions.ui_pause_actions.unregisterModTab(TAB_ID) } catch (e) { /* none */ }   // (its buttons with it)
  try {
    if (window.bngRoutes) window.bngRoutes.remove([SOURCE])
    if (lua.extensions.ui_router_routeManager) {
      await lua.extensions.ui_router_routeManager.unregisterModRoutes(SOURCE, { fallbackRoute: "play" })
    }
  } catch (e) {
    console.error("Earth Rally: menu unload failed", e)
  }
}
