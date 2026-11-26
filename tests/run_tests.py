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

@test("M2 tank, in a party (state readable, values hidden): holding / losing it / lost from the game's states")
def _(L, ns):
    lua(L, '''
      NS.db.role = "tank"; NS.db.tank = "me"; MOCK.inGroup = true; MOCK.hiddenValues = true
      MOCK.threat.player = { tanking = true, status = 3, lead = 0 }
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      local st = NS.State.Get("nameplate1")
      assert(st.confidence == "state" and st.ownership == "followed" and st.lead == 0, st.confidence)
      MOCK.threat.player.lead = 2; assert(MOCK.Look() == "unstable unstable", "someone closing in: " .. MOCK.Look())
      MOCK.threat.player = { tanking = true, status = 2, lead = 3 }; assert(MOCK.Look() == "unstable unstable", "someone has more: " .. MOCK.Look())
      MOCK.threat.player = { tanking = false, status = 0, lead = 3 }; MOCK.threat.party1 = { tanking = true, status = 3 }
      assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      assert(NS.State.Get("nameplate1").ownership == "other")
      MOCK.threat.player = nil; assert(MOCK.Look() == "lost nothreat!", "not on its list, on the group: " .. MOCK.Look())
    ''')

@test("M2 not the tank, in a party: safe / close (status 1) / on you")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; MOCK.inGroup = true; MOCK.hiddenValues = true
      MOCK.threat.party1 = { tanking = true, status = 3 }
      MOCK.threat.player = { tanking = false, status = 0, pct = 85 }
      assert(MOCK.Look() == "secure aggro", "the % is hidden, so it can't warn from it: " .. MOCK.Look())
      MOCK.threat.player.status = 1; assert(MOCK.Look() == "unstable unstable", MOCK.Look())
      MOCK.threat.player = { tanking = true, status = 3 }; assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      MOCK.threat.player = nil; assert(MOCK.Look() == "secure aggro", "not on its list: safe: " .. MOCK.Look())
    ''')

@test("M2 solo (values readable): Warn at, for you and for anyone close to taking it from you")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; NS.db.warnAt = 80
      MOCK.threat.player = { tanking = false, status = 0, pct = 85 }
      assert(MOCK.Look() == "unstable unstable", MOCK.Look())
      assert(NS.State.Get("nameplate1").confidence == "values")
      MOCK.threat.player.pct = 50; assert(MOCK.Look() == "secure aggro", MOCK.Look())
      NS.db.warnAt = 90; MOCK.threat.player.pct = 85; assert(MOCK.Look() == "secure aggro", MOCK.Look())
      NS.db.role = "tank"; NS.db.warnAt = 80; MOCK.inGroup = true
      MOCK.threat.player = { tanking = true, status = 3, lead = 0, pct = 100 }
      MOCK.threat.party1 = { tanking = false, status = 1, pct = 92 }
      assert(MOCK.Look() == "unstable unstable", MOCK.Look())
      assert(NS.State.Get("nameplate1").percentage == 92)
    ''')

@test("M2 the %: off by default; readable shown capped; hidden handed to the game; in the state's colour")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; MOCK.threat.player = { tanking = false, status = 1, pct = 93.6 }
      MOCK.Look(); assert(MOCK.Pct() == "", "off by default")
      NS.db.showPercent = true; MOCK.Look(); assert(MOCK.Pct() == "94%", MOCK.Pct())
      local f = NS.Renderer.Indicator(MOCK.plate)
      assert(f.pct._color[1] == NS.db.colorsDps.unstable[1], "orange")
      MOCK.threat.player = { tanking = true, status = 3, pct = 130 }; MOCK.Look(); assert(MOCK.Pct() == "100%", MOCK.Pct())
      MOCK.inGroup = true; MOCK.hiddenValues = true; MOCK.threat.player = { tanking = false, status = 0, pct = 40 }
      MOCK.Look(); assert(MOCK.Pct() == "<game>", "hidden: drawn by the game: " .. MOCK.Pct())
      MOCK.hidden = true; MOCK.Look(); assert(MOCK.Pct() == "<game>", "all hidden: still drawn by the game")
      NS.db.role = "tank"; MOCK.hidden = false; MOCK.threat.player = { tanking = true, status = 3, lead = 0 }
      MOCK.Look(); assert(MOCK.Pct() == "", "tank in a party: others' % can't be compared: none")
    ''')

@test("M2 preview: the unstable look, with a sample %")
def _(L, ns):
    lua(L, '''
      UnitIsUnit = function() return true end
      NS.db.showPercent = true; NS.preview = "unstable"
      assert(MOCK.Look():find("unstable$"), MOCK.Look())
      assert(MOCK.Pct() == "90%", MOCK.Pct())
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
      assert(all:find("on you=true status=3 lead=nil pct=50 ofLead=n/a"), all)
      MOCK.hidden = true; UnitThreatLeadSituation = function() error("nope") end
      C_Secrets = { ShouldUnitThreatStateBeSecret = function() return false end, ShouldUnitThreatValuesBeSecret = function() return true end }
      PRINTS = {}; SlashCmdList.HOLDFAST("scan")
      all = table.concat(PRINTS, "\\n")
      assert(all:find("on you=<hidden> status=<hidden> lead=error pct=<hidden>"), all)
      assert(all:find("secret: state=false values=true"), all)
      -- with debug on, each change prints the same line, at that moment
      PRINTS = {}; MOCK.hidden = false; MOCK.threat.player = { tanking = false, status = 0 }; NS.db.role = "tank"; MOCK.Look()
      all = table.concat(PRINTS, "\\n")
      assert(all:find("hidden %-> lost | on you=false status=0"), all)
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
