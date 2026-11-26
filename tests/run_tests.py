#!/usr/bin/env python3
"""Holdfast offline tests: python3 tests/run_tests.py  (needs: pip install lupa)

Runs the addon's Lua files against a mock of the game's API (tests/mock.lua) and checks
the threat states, the renderer's frame and hook lifecycle, and the event paths.
These check the code's logic only. They don't prove anything about the real client: what
the game returns (and hides) is checked in game (see DEVELOPMENT.md, "Testing").
"""
import os, sys
from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FILES = ['Core', 'UnitRegistry', 'ThreatState', 'Renderer', 'UI', 'Options', 'Engine']

def load():
    L = LuaRuntime()
    L.execute(open(os.path.join(HERE, 'mock.lua')).read())
    ns = L.eval('{}')
    run = L.eval('function(src, n, ns) return assert(loadstring(src, "@" .. n))("Holdfast", ns) end')
    for f in FILES:
        run(open(os.path.join(ROOT, f + '.lua')).read(), f + '.lua', ns)
    L.globals().NS = ns
    L.eval('MOCK.Start')()
    return L, ns

failures, count = [], 0
def test(name):
    def wrap(fn):
        global count
        count += 1
        try:
            L, ns = load()
            fn(L, ns)
            print('ok   ', name)
        except Exception as e:  # noqa
            failures.append(name); print('FAIL ', name, '\n     ', e)
        return fn
    return wrap

def lua(L, code):
    return L.execute(code)

@test("states: tank and not the tank, readable answers")
def _(L, ns):
    lua(L, '''
      NS.db.role = "tank"; NS.db.tank = "me"
      MOCK.threat.player = { tanking = true, status = 3 }
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      MOCK.threat.player = { tanking = false, status = 0 }
      assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      NS.db.role = "dps"
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      MOCK.threat.player = { tanking = true, status = 3 }
      assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      MOCK.threat = {}
      assert(MOCK.Look() == "none", "nobody on its threat list: " .. MOCK.Look())
    ''')

@test("states: hidden answers go to the glows unread (SetAlphaFromBoolean)")
def _(L, ns):
    lua(L, '''
      NS.db.role = "tank"; NS.db.tank = "me"
      MOCK.hidden = true; MOCK.threat.player = { tanking = true, status = 3 }
      local look = MOCK.Look()
      assert(look == "hidden aggro~ nothreat~!", look)
    ''')

@test("states: a hidden group role is no role (no comparison on a hidden value)")
def _(L, ns):
    lua(L, '''
      NS.db.role = "auto"; MOCK.inGroup = true; MOCK.role = MOCK.Secret("TANK")
      assert(NS.State.Role() == nil)
      MOCK.role = "DAMAGER"; assert(NS.State.Role() == "dps")
    ''')

@test("states: pet tanking (Auto, no role), pet dead or gone")
def _(L, ns):
    lua(L, '''
      NS.db.role = "auto"; NS.db.tank = "auto"; MOCK.inGroup = false
      MOCK.pet = true; MOCK.threat.pet = { tanking = true, status = 3 }; MOCK.threat.player = { tanking = false, status = 0 }
      assert(NS.State.Mode() == "pet"); assert(MOCK.Look() == "secure aggro", MOCK.Look())
      MOCK.petDead = true
      assert(NS.State.Mode() == "tank"); assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      NS.db.tank = "pet"; MOCK.petDead = false; MOCK.pet = false
      assert(MOCK.Look() == "none", "My pet, no pet out: " .. MOCK.Look())
    ''')

@test("renderer: a host switch (EllesmereUI plate shows late) reuses indicators, no new frames")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }
      MOCK.Look()
      local made = NS.Renderer.Counts()
      for i = 1, 20 do
        MOCK.euiShown = (i % 2 == 0); MOCK.Look()
      end
      local made2, shown = NS.Renderer.Counts()
      assert(made2 == made + 1, "indicators made: " .. made .. " then " .. made2)
      assert(shown == 1, "plates showing one: " .. shown)
    ''')

@test("renderer: glow style changes reuse indicators; hooks are set once per game frame")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }
      MOCK.Look()
      local hooks = MOCK.HookCount()
      for i = 1, 10 do
        NS.db.glowStyle = (i % 2 == 0) and "outline" or "border"; NS.Renderer.Rebuild(); MOCK.Look()
      end
      local made = NS.Renderer.Counts()
      assert(made == 2, "one indicator per style: " .. made)
      assert(MOCK.HookCount() == hooks, "hooks: " .. hooks .. " then " .. MOCK.HookCount())
    ''')

@test("renderer: the game's flare is hidden while replacing, and given back when turned off")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }
      local uf = MOCK.plate.UnitFrame
      uf.aggroHighlightShown = true; uf.aggroHighlightBase:Show()
      NS.db.replaceGameHighlight = true; MOCK.Look()
      assert(not uf.aggroHighlightBase:IsShown(), "hidden")
      uf.aggroHighlightBase:Show(); MOCK.RunHooks(uf, "UpdateAggroHighlight")
      assert(not uf.aggroHighlightBase:IsShown(), "hidden again after the game re-shows it")
      NS.db.replaceGameHighlight = false; MOCK.Look()
      assert(uf.aggroHighlightBase:IsShown(), "given back")
      uf.aggroHighlightBase:Hide(); MOCK.Look()
      assert(not uf.aggroHighlightBase:IsShown(), "and then left to the game")
    ''')

@test("renderer: a removed nameplate shows nothing; the recycled plate draws the new enemy")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = false, status = 0 }; NS.db.role = "tank"
      assert(MOCK.Look() == "lost nothreat!")
      MOCK.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
      assert(MOCK.Glows() == "", "removed: " .. MOCK.Glows())
      assert(NS.State.Get("nameplate1") == nil)
      MOCK.threat.player = { tanking = true, status = 3 }
      MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      assert(MOCK.Glows() == "aggro", MOCK.Glows())
    ''')

@test("events: a threat list update named by another token updates the plates (batched)")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }; NS.db.role = "tank"
      MOCK.Look()
      MOCK.threat.player = { tanking = false, status = 0 }
      MOCK.Fire("UNIT_THREAT_LIST_UPDATE", "target")
      assert(MOCK.Glows() == "aggro", "not yet: batched to the next frame")
      MOCK.RunTimers()
      assert(MOCK.Glows() == "nothreat!", MOCK.Glows())
    ''')

@test("events: role changes are listened to")
def _(L, ns):
    lua(L, 'assert(MOCK.registered.PLAYER_ROLES_ASSIGNED, "PLAYER_ROLES_ASSIGNED")')

@test("settings: old designs start fresh; a newer version's settings are kept")
def _(L, ns):
    lua(L, '''
      HoldfastDB = { version = 2, showIcon = false }; NS.LoadDB()
      assert(NS.db.showIcon == true and NS.db.version == 5)
      HoldfastDB = { version = 6, glowStyle = "pixel", iconV2 = true }; NS.LoadDB()
      assert(NS.db.glowStyle == "pixel", "kept")
      HoldfastDB = { version = 3, colors = { aggro = { 0, 1, 0 }, loss = { 1, 0.4, 0 } }, glowAlpha = 0.7 }; NS.LoadDB()
      assert(NS.db.colors.unstable[2] == 0.4 and NS.db.states.nothreat.alpha == 0.7, "3 -> 5 migration")
    ''')

@test("/hf debug: each threat call shown as a value, nil, <hidden>, error or n/a")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look()
      PRINTS = {}; SlashCmdList.HOLDFAST("debug")
      local all = table.concat(PRINTS, "\\n")
      assert(all:find("on you=true status=3 lead=n/a pct=50 ofLead=n/a"), all)
      MOCK.hidden = true; UnitThreatLeadSituation = function() error("nope") end
      C_Secrets = { ShouldUnitThreatStateBeSecret = function() return false end, ShouldUnitThreatValuesBeSecret = function() return true end }
      PRINTS = {}; SlashCmdList.HOLDFAST("debug"); SlashCmdList.HOLDFAST("debug")
      all = table.concat(PRINTS, "\\n")
      assert(all:find("on you=<hidden> status=<hidden> lead=error pct=<hidden>"), all)
      assert(all:find("secret: state=false values=true"), all)
    ''')

@test("settings window: a shrunk shared font (EllesmereUI's tracker) isn't used; no style settings: EllesmereUI's look on its own")
def _(L, ns):
    lua(L, '''
      ObjectiveTrackerHeaderFont = MOCK.obj(); ObjectiveTrackerHeaderFont.GetFont = function() return "x.ttf", 1, "" end
      ObjectiveTrackerLineFont = MOCK.obj(); ObjectiveTrackerLineFont.GetFont = function() return "x.ttf", 1, "" end
      GameFontNormalMed2 = MOCK.obj(); GameFontNormalMed2.GetFont = function() return "f.ttf", 14, "" end
      GameFontHighlight = MOCK.obj(); GameFontHighlight.GetFont = function() return "f.ttf", 12, "" end
      local th = NS.UI.Theme()
      assert(th.headerFont == GameFontNormalMed2, "header font")
      assert(th.lineFont == GameFontHighlight, "line font")
      -- the window follows EllesmereUI when it's installed (an old saved "style off" is never read)
      HoldfastDB = { version = 5, euiStyle = false, windowStyle = "plain", iconV2 = true }; NS.LoadDB()
      NS.UI.euiSkin = { GetAccentColor = function() return 1, 0, 0 end, GetFont = function() return "e.ttf", "" end }
      assert(NS.UI.Theme().eui == true, "EllesmereUI's look")
    ''')

@test("slash commands run without errors")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look()
      for _, c in ipairs({ "icon", "icon", "aggro", "aggro", "debug", "debug", "tank", "tip", "help" }) do SlashCmdList.HOLDFAST(c) end
    ''')

print(f"\n{count - len(failures)}/{count} passed")
sys.exit(1 if failures else 0)
