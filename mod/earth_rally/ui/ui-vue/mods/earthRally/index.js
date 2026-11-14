import { lua } from "@/bridge"

// Earth Rally's menu (ui/ui-vue/mods/README.md, as BeamNG.Earth's own mod does it):
//   a full-screen route "earthRally" (EarthRally.vue: Rallies, a rally, a stage, Settings), opened from Lua with
//     ui_router.navigate('earthRally') (earthRally_main.openMenu / toggleMenu: Ctrl+Alt+K)
//   an "Earth Rally" tab of its own in the pause menu: Rallies (EarthRallyTab.vue) and Settings
//     (EarthRallySettings.vue), EarthRallySide.vue as its second card
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
  try {
    await lua.extensions.ui_pause_actions.registerModTab({
      id: TAB_ID,
      label: "Earth Rally",
      icon: "flag",
      card2ComponentName: `${MOD_ROOT}/EarthRallySide.vue`,
    })
    await lua.extensions.ui_pause_actions.registerModButton({
      id: "earthRally-rallies",
      tabId: TAB_ID,
      label: "Rallies",
      icon: "flag",
      componentName: `${MOD_ROOT}/EarthRallyTab.vue`,
    })
    await lua.extensions.ui_pause_actions.registerModButton({
      id: "earthRally-settings",
      tabId: TAB_ID,
      label: "Settings",
      icon: "cogOutline",
      componentName: `${MOD_ROOT}/EarthRallySettings.vue`,
      props: { card: true },
    })
  } catch (e) {
    console.error("Earth Rally: pause menu tab failed", e)
  }
}

export async function onLoad() {
  await registerPauseTab()
  await registerRoute()
}

export async function onUnload() {
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
