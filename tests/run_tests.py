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
# the addon's files, in the toc's load order
FILES = [l.strip()[:-4] for l in open(os.path.join(ROOT, 'Holdfast.toc')) if l.strip().endswith('.lua') and not l.startswith('#')]

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
      NS.db.role = "auto"; MOCK.Group(true); MOCK.role = MOCK.Secret("TANK")
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
      NS.db.role = "tank"; NS.db.tank = "me"; MOCK.Group(true); MOCK.hiddenValues = true
      MOCK.threat.player = { tanking = true, status = 3, lead = 0 }
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      local st = NS.State.Get("nameplate1")
      assert(st.confidence == "state" and st.ownership == "player" and st.ownerObserved and st.lead == 0, st.confidence)
      MOCK.threat.player.lead = 2; assert(MOCK.Look() == "unstable unstable", "someone closing in: " .. MOCK.Look())
      MOCK.threat.player = { tanking = true, status = 2, lead = 3 }; assert(MOCK.Look() == "unstable unstable", "someone has more: " .. MOCK.Look())
      MOCK.threat.player = { tanking = false, status = 0, lead = 3 }; MOCK.threat.party1 = { tanking = true, status = 3 }
      assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      assert(NS.State.Get("nameplate1").ownership == "member" and NS.State.Get("nameplate1").ownerUnit == "party1")
      MOCK.threat.player = nil; assert(MOCK.Look() == "lost nothreat!", "not on its list, on the group: " .. MOCK.Look())
    ''')

@test("M2 not the tank, in a party: safe / close (status 1) / on you")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; MOCK.Group(true); MOCK.hiddenValues = true
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
      NS.db.role = "tank"; NS.db.warnAt = 80; MOCK.Group(true)
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
      MOCK.Set("showPercent", true); MOCK.Look(); assert(MOCK.Pct() == "94%", MOCK.Pct())
      local f = NS.Renderer.Indicator(MOCK.plate)
      assert(f.pct._color[1] == NS.db.colorsDps.unstable[1], "orange")
      MOCK.threat.player = { tanking = true, status = 3, pct = 130 }; MOCK.Look(); assert(MOCK.Pct() == "100%", MOCK.Pct())
      MOCK.Group(true); MOCK.hiddenValues = true; MOCK.threat.player = { tanking = false, status = 0, pct = 40 }
      MOCK.Look(); assert(MOCK.Pct() == "<game>", "hidden: drawn by the game: " .. MOCK.Pct())
      MOCK.hidden = true; MOCK.Look(); assert(MOCK.Pct() == "<game>", "all hidden: still drawn by the game")
      NS.db.role = "tank"; MOCK.hidden = false; MOCK.threat.player = { tanking = true, status = 3, lead = 0 }
      MOCK.Look(); assert(MOCK.Pct() == "", "tank in a party: others' % can't be compared: none")
    ''')

@test("M2 preview: the unstable look, with a sample %")
def _(L, ns):
    lua(L, '''
      UnitIsUnit = function() return true end
      MOCK.Set("showPercent", true); NS.preview = "unstable"
      assert(MOCK.Look():find("unstable$"), MOCK.Look())
      assert(MOCK.Pct() == "90%", MOCK.Pct())
    ''')

@test("M3 who it's attacking: you, your pet, a group tank, a member, a member's pet, or unknown")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; MOCK.hiddenValues = true; MOCK.roles = { party1 = "TANK" }; MOCK.Group(true)
      local function owner() MOCK.Look(); local st = NS.State.Get("nameplate1"); return st.ownership, st.ownerUnit, st.ownerObserved end
      MOCK.threat = { party1 = { status = 3 }, player = { status = 0 } }
      local o, u, seen = owner(); assert(o == "tank" and u == "party1" and seen, tostring(o))
      MOCK.threat = { partypet1 = { status = 3 }, player = { status = 0 } }
      o, u = owner(); assert(o == "member pet" and u == "partypet1", tostring(o))
      MOCK.roles = {}; MOCK.Group(true); MOCK.threat = { party1 = { status = 2 }, player = { status = 1 } }
      o = owner(); assert(o == "member", tostring(o))
      MOCK.threat = { player = { status = 3 } }; o = owner(); assert(o == "player", tostring(o))
      MOCK.threat = { player = { status = 0 } }; o, u, seen = owner()
      assert(o == "unknown" and u == nil and seen == false, "nobody of yours: inferred unknown")
    ''')

@test("M3 the group's tanks (healers): any tank holding it is good; two tanks; a member holding it is lost")
def _(L, ns):
    lua(L, '''
      NS.db.role = "dps"; NS.db.tank = "tanks"; MOCK.hiddenValues = true; MOCK.members = 3
      MOCK.roles = { party1 = "TANK", party2 = "TANK" }; MOCK.Group(true)
      assert(table.concat(NS.State.Followed(), ",") == "party1,party2")
      MOCK.threat = { party1 = { status = 3, lead = 0 }, player = { status = 0 } }
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      local st = NS.State.Get("nameplate1"); assert(st.dps == false and st.tank == "party1")
      MOCK.threat.party1.lead = 2; assert(MOCK.Look() == "unstable unstable", MOCK.Look())
      MOCK.threat = { party2 = { status = 3, lead = 0 } }; assert(MOCK.Look() == "secure aggro", "the other tank: " .. MOCK.Look())
      MOCK.threat = { party3 = { status = 3 }, party1 = { status = 0 } }; assert(MOCK.Look() == "lost nothreat!", MOCK.Look())
      MOCK.roles = {}; MOCK.Group(true); NS.db.role = "tank"
      assert(table.concat(NS.State.Followed(), ",") == "player", "no tank roles: you")
    ''')

@test("M3 me and my pet: either holding it is good; the pet dies, then only you")
def _(L, ns):
    lua(L, '''
      NS.db.tank = "both"; MOCK.pet = true; MOCK.Fire("UNIT_PET", "player"); MOCK.RunTimers()
      MOCK.threat = { pet = { status = 3, lead = 0 }, player = { status = 0 } }
      assert(MOCK.Look() == "secure aggro", MOCK.Look())
      MOCK.threat.pet.lead = 1; assert(MOCK.Look() == "unstable unstable", MOCK.Look())
      MOCK.threat = { player = { status = 3, lead = 0 }, pet = { status = 0 } }; assert(MOCK.Look() == "secure aggro", MOCK.Look())
      MOCK.petDead = true; MOCK.threat = { pet = { status = 3 }, player = { status = 0 } }
      assert(table.concat(NS.State.Followed(), ",") == "player")
      assert(MOCK.Look() == "lost nothreat!", "a dead pet doesn't count: " .. MOCK.Look())
    ''')

@test("M3 raids: you aren't counted twice (raidN includes you); the roster refreshes on roster events only")
def _(L, ns):
    lua(L, '''
      MOCK.raid = true; MOCK.members = 3
      MOCK.same = function(a, b) return a == "raid1" and b == "player" end
      MOCK.Group(true); NS.db.role = "tank"
      MOCK.threat = { player = { status = 3, lead = 0 }, raid1 = { status = 3 } }
      MOCK.Look(); local st = NS.State.Get("nameplate1")
      assert(st.ownership == "player", "raid1 is you: " .. tostring(st.ownership))
      local calls = 0
      local real = UnitExists
      UnitExists = function(u) calls = calls + 1; return real(u) end
      MOCK.Look(); MOCK.Look()
      UnitExists = real
      assert(calls < 20, "the roster isn't rebuilt on every update: " .. calls .. " UnitExists calls")
    ''')

@test("M4 animation manager: one driver, only the moving glows showing; none showing, it stops")
def _(L, ns):
    lua(L, '''
      local A = NS.Renderer.Anim
      MOCK.Set("glowStyle", "pixel"); NS.Renderer.Rebuild()
      NS.db.role = "tank"; MOCK.threat.player = { tanking = true, status = 3 }
      MOCK.Look(); assert(A.n == 1, "holding: one pixel glow animating, got " .. A.n)
      MOCK.threat.player = { tanking = false, status = 0 }; MOCK.Look(); assert(A.n == 1, "lost: still one, got " .. A.n)
      MOCK.hidden = true; MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look()
      assert(A.n == 2, "hidden: both glows shown (the game picks one), got " .. A.n)
      MOCK.hidden = false; MOCK.threat = {}; MOCK.Look()
      assert(A.n == 0, "nothing showing: nothing animating, got " .. A.n)
      MOCK.Set("glowStyle", "border"); NS.Renderer.Rebuild()
      MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look()
      assert(A.n == 0, "the border glow doesn't move: not in the manager")
    ''')

@test("M4 an unchanged plate isn't redrawn or restyled; a setting change restyles each plate once")
def _(L, ns):
    lua(L, '''
      local c = NS.Renderer.counters
      MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look()
      local r, k, st = c.renders, c.skipped, c.styles
      MOCK.Look(); MOCK.Look(); MOCK.Look()
      assert(c.renders == r and c.skipped == k + 3 and c.styles == st, "unchanged: skipped")
      MOCK.threat.player = { tanking = false, status = 0 }; MOCK.Look()
      assert(c.renders == r + 1 and c.styles == st, "a new state: redrawn, not restyled")
      MOCK.Set("showIcon", false); MOCK.Look(); MOCK.Look()
      assert(c.styles == st + 1, "a setting: restyled once")
      assert(MOCK.Glows() == "nothreat", "the \\"!\\" off: " .. MOCK.Glows())
      SlashCmdList.HOLDFAST("icon"); assert(MOCK.Glows() == "nothreat!", "/hf icon applies at once: " .. MOCK.Glows())
    ''')

@test("M4 driven by events: no polling out of combat; a 1 s check only in combat; bursts merged")
def _(L, ns):
    lua(L, '''
      local live = 0
      for _, t in ipairs(MOCK.tickers) do if not t.cancelled then live = live + 1 end end
      assert(live == 0, "out of combat: no timer")
      MOCK.combat = true; MOCK.Fire("PLAYER_REGEN_DISABLED"); MOCK.RunTimers()
      local t = MOCK.tickers[#MOCK.tickers]
      assert(t and t.sec == 1 and not t.cancelled, "in combat: a check every second")
      MOCK.combat = false; MOCK.Fire("PLAYER_REGEN_ENABLED"); MOCK.RunTimers()
      assert(t.cancelled, "out of combat again: stopped")
      local n, real = 0, NS.State.Update
      NS.State.Update = function(...) n = n + 1; return real(...) end
      for i = 1, 20 do MOCK.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate1") end
      for i = 1, 20 do MOCK.Fire("UNIT_THREAT_SITUATION_UPDATE", "party1") end
      assert(n == 0, "nothing yet: merged to the next frame")
      MOCK.RunTimers()
      assert(n == 1, "40 events, one evaluation of the one plate: " .. n)
      NS.State.Update = real
    ''')

@test("M4 adapters: EllesmereUI, FlareUI, the game's plate, or the plate itself")
def _(L, ns):
    lua(L, '''
      local A = NS.Adapters
      assert(A.Find(MOCK.plate, "nameplate1").kind == "blizzard")
      MOCK.euiShown = true; assert(A.Find(MOCK.plate, "nameplate1").kind == "eui"); MOCK.euiShown = false
      local parts = { box = MOCK.obj(), root = MOCK.obj(), level = MOCK.obj() }
      FlareUI = { Nameplates = { PartsFor = function() return parts end } }
      local ad, parent, bar = A.Find(MOCK.plate, "nameplate1")
      assert(ad.kind == "flare" and parent == parts.root and bar == parts.box)
      FlareUI.Nameplates.PartsFor = function() error("changed") end
      assert(A.Find(MOCK.plate, "nameplate1").kind == "blizzard", "FlareUI erroring: the next adapter")
      FlareUI = nil
      local bare = MOCK.obj()
      assert(A.Find(bare, "nameplate9").kind == "generic", "an unknown nameplate: the plate itself")
      PRINTS = {}; MOCK.threat.player = { tanking = true, status = 3 }; MOCK.Look(); SlashCmdList.HOLDFAST("perf")
      local out = table.concat(PRINTS, "\\n")
      assert(out:find("blizzard 1") and out:find("threat evaluations"), out)
    ''')

@test("M5 transition events (HoldfastAPI): aggro gained / lost, pet, unstable, secure, untrackable, target; no hidden values")
def _(L, ns):
    lua(L, '''
      local got = {}
      for _, e in ipairs(HoldfastAPI.Events) do
        HoldfastAPI.RegisterCallback(e, function(ev, p) got[#got + 1] = ev .. ":" .. p.kind; got.last = p end)
      end
      local function seen(ev) for _, g in ipairs(got) do if g:find("^" .. ev .. ":") then return true end end end
      NS.db.role = "dps"; MOCK.Group(true); MOCK.roles = { party1 = "TANK" }; MOCK.Group(true); MOCK.hiddenValues = true
      MOCK.threat = { party1 = { status = 3 }, player = { status = 0, pct = 40 } }; MOCK.Look()
      got = {}; MOCK.threat.player.status = 1; MOCK.Look()
      assert(seen("THREAT_UNSTABLE") and seen("STATE_CHANGED"), table.concat(got, " "))
      assert(got.last.percentage == nil, "a hidden % is never in a payload")
      got = {}; MOCK.threat = { player = { status = 3 }, party1 = { status = 0 } }; MOCK.Look()
      assert(seen("AGGRO_GAINED"), table.concat(got, " "))
      got = {}; MOCK.threat = { party1 = { status = 3 }, player = { status = 0 } }; MOCK.Look()
      assert(seen("AGGRO_LOST") and seen("THREAT_SECURE"), table.concat(got, " "))
      got = {}; MOCK.pet = true; MOCK.Fire("UNIT_PET", "player"); MOCK.RunTimers()
      MOCK.threat = { pet = { status = 3 }, player = { status = 0 } }; MOCK.Look()
      assert(seen("PET_AGGRO_GAINED"), "the pet took it, your state still safe: " .. table.concat(got, " "))
      got = {}; MOCK.threat = { party1 = { status = 3 }, player = { status = 0 } }; MOCK.Look()
      assert(seen("PET_AGGRO_LOST"), table.concat(got, " "))
      got = {}; MOCK.hidden = true; MOCK.threat = { player = { tanking = false, status = 0 } }; MOCK.Look()
      assert(seen("UNIT_UNTRACKABLE"), table.concat(got, " "))
      got = {}; MOCK.Fire("PLAYER_TARGET_CHANGED"); MOCK.RunTimers(); MOCK.RunTimers()
      assert(seen("TARGET_CHANGED"), table.concat(got, " "))
      assert(HoldfastAPI.GetState("nameplate1").kind == "hidden")
    ''')

@test("M5 alerts: off by default; red (not on joining the fight), orange if chosen; at most one every 2 s")
def _(L, ns):
    lua(L, '''
      NS.db.role = "tank"; MOCK.threat = { player = { status = 3, lead = 0 } }; MOCK.Look()
      MOCK.threat.player.status = 0; MOCK.Look(); assert(MOCK.sounds == 0, "off by default")
      NS.db.alerts.sound = true
      MOCK.threat.player.status = 3; MOCK.Look(); MOCK.now = MOCK.now + 5
      MOCK.threat.player.status = 0; MOCK.Look(); assert(MOCK.sounds == 1, "lost it: one sound")
      MOCK.threat.player.status = 3; MOCK.Look(); MOCK.threat.player.status = 0; MOCK.Look()
      assert(MOCK.sounds == 1, "again within 2 s: no sound")
      MOCK.now = MOCK.now + 5; MOCK.threat.player = { status = 3, lead = 2 }; MOCK.Look()
      assert(MOCK.sounds == 1, "orange: not chosen")
      NS.db.alerts.onUnstable = true; MOCK.threat.player.lead = 0; MOCK.Look(); MOCK.threat.player.lead = 1; MOCK.Look()
      assert(MOCK.sounds == 2, "orange, chosen")
      MOCK.now = MOCK.now + 5; MOCK.threat = {}; MOCK.Look()
      MOCK.threat = { party1 = { status = 3 } }; MOCK.Group(true); MOCK.Look()
      assert(MOCK.sounds == 2, "joining the fight on someone else: no alert")
      NS.db.alerts.screen = true; NS.Alerts.Test()
      UnitExists = function(u) return u ~= "target" and u ~= "pet" end
      local function t() return NS.Alerts.lastText end
      assert(t() == "Lost aggro: Mob", "with a target: its name: " .. tostring(t()))
      NS.Alerts.Test()
      assert(t() == "Lost aggro: Scarlet Monk", "the default, with a sample name: " .. tostring(t()))
      NS.db.alerts.text.lostTank = "Aggro lost on:"; NS.Alerts.Test("lostTank")
      assert(t() == "Aggro lost on: Scarlet Monk", "your text ends in ':': no second one: " .. tostring(t()))
      NS.db.alerts.text.lostDps = "AGGRO ON YOU!"; NS.db.alerts.names.lostDps = false; NS.Alerts.Test("lostDps")
      assert(t() == "AGGRO ON YOU!", "this one without the name: " .. tostring(t()))
      NS.Alerts.Test("unstableDps"); assert(t() == "Close to pulling: Scarlet Monk", tostring(t()))
      NS.db.alerts.text.lostTank = nil; NS.Alerts.Test(); assert(t() == "Lost aggro: Scarlet Monk", "emptied: the default again")
    ''')

@test("M5 overview: nothing built while off; most dangerous first; filters; hiding stops its updates")
def _(L, ns):
    lua(L, '''
      assert(not NS.Overview.IsShown())
      local before = #MOCK.tickers
      for i = 2, 4 do MOCK.AddPlate(i); MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
      NS.db.role = "tank"; MOCK.threat = { player = { status = 3, lead = 0 } }; MOCK.Look()
      SlashCmdList.HOLDFAST("overview")
      assert(NS.Overview.IsShown() and #MOCK.tickers == before + 1, "shown, with its half-second refresh")
      NS.Overview.Refresh()
      SlashCmdList.HOLDFAST("overview lost"); assert(NS.db.overview.filter == "lost")
      PRINTS = {}; SlashCmdList.HOLDFAST("overview nonsense"); assert(table.concat(PRINTS):find("overview filters"))
      SlashCmdList.HOLDFAST("overview")
      assert(not NS.Overview.IsShown() and MOCK.tickers[#MOCK.tickers].cancelled and NS.db.overview.show == false)
    ''')

@test("M6 diagnostics: /hf status, /hf threat, /hf profile, /hf reset (asks first)")
def _(L, ns):
    lua(L, '''
      MOCK.threat.player = { status = 3, lead = 0 }; MOCK.Look()
      PRINTS = {}; SlashCmdList.HOLDFAST("status")
      local out = table.concat(PRINTS, "\\n")
      assert(out:find("whose aggro: auto") and out:find("glow style") and out:find("nameplates: blizzard 1") and out:find("solo"), out)
      MOCK.same = function(a, b) return a == "nameplate1" and b == "target" end
      PRINTS = {}; SlashCmdList.HOLDFAST("threat")
      out = table.concat(PRINTS, "\\n")
      assert(out:find("target: secure") and out:find("everyone's status: player=3"), out)
      PRINTS = {}; SlashCmdList.HOLDFAST("profile 5"); MOCK.RunTimers()
      out = table.concat(PRINTS, "\\n")
      assert(out:find("profiling for 5 s") and out:find("profile of the last 5 s") and out:find("threat evaluations"), out)
      NS.db.glowStyle = "pixel"
      PRINTS = {}; SlashCmdList.HOLDFAST("reset"); assert(NS.db.glowStyle == "pixel" and table.concat(PRINTS):find("reset yes"))
      SlashCmdList.HOLDFAST("reset yes"); assert(NS.db.glowStyle == "auto", "reset")
      PRINTS = {}; SlashCmdList.HOLDFAST("help"); assert(table.concat(PRINTS, " "):find("/hf status"))
    ''')

@test("M6 edge cases: a group without roles; a healer; several enemies at once; a recycled nameplate")
def _(L, ns):
    lua(L, '''
      -- a group without roles: as when solo (you, as the tank)
      MOCK.Group(true); NS.db.role = "auto"; MOCK.role = "NONE"
      assert(NS.State.Mode() == "tank", NS.State.Mode())
      -- a healer: not the tank
      MOCK.role = "HEALER"; assert(NS.State.Mode() == "dps")
      -- several enemies: each its own state
      for i = 2, 4 do MOCK.AddPlate(i); MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
      MOCK.mobs = { nameplate1 = { party1 = { status = 3 }, player = { status = 0 } },
        nameplate2 = { player = { status = 3 } }, nameplate3 = { party1 = { status = 3 }, player = { status = 1 } }, nameplate4 = {} }
      NS.UpdateAll()
      local k = {}
      for i = 1, 4 do k[i] = NS.State.Get("nameplate" .. i).kind end
      assert(table.concat(k, " ") == "secure lost unstable none", table.concat(k, " "))
      -- a nameplate recycled for another enemy: the same frame, a new unit, its own state
      MOCK.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
      MOCK.plates.nameplate1 = nil; MOCK.plates.nameplate5 = MOCK.plate; MOCK.plate.namePlateUnitToken = "nameplate5"
      MOCK.mobs.nameplate5 = { player = { status = 3 } }
      MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
      assert(NS.State.Get("nameplate5").kind == "lost" and NS.State.Get("nameplate1") == nil)
      assert(MOCK.Glows() == "nothreat!", "the recycled frame shows the new enemy: " .. MOCK.Glows())
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
      MOCK.Look()
      assert(not uf.aggroHighlightBase:IsShown(), "hidden (Replace is on by default)")
      -- the game shows it again (through its UpdateAggroHighlight, which Holdfast hooks)
      uf.aggroHighlightShown = true
      uf.aggroHighlightBase:Show(); MOCK.RunHooks(uf, "UpdateAggroHighlight")
      assert(not uf.aggroHighlightBase:IsShown(), "hidden again after the game re-shows it")
      MOCK.Set("replaceGameHighlight", false); MOCK.Look()
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
      local made, shown = NS.Renderer.Counts()
      assert(shown == 0 and made == 1, "let go, kept for reuse: made " .. made .. ", showing " .. shown)
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
      assert(all:find("hidden %-> lost | on .- | on you=false status=0"), all)
    ''')

@test("threat overview's look: a shrunk shared font (EllesmereUI's tracker) isn't used; no style settings: EllesmereUI's look on its own")
def _(L, ns):
    lua(L, '''
      ObjectiveTrackerHeaderFont = MOCK.obj(); ObjectiveTrackerHeaderFont.GetFont = function() return "x.ttf", 1, "" end
      ObjectiveTrackerLineFont = MOCK.obj(); ObjectiveTrackerLineFont.GetFont = function() return "x.ttf", 1, "" end
      GameFontNormalMed2 = MOCK.obj(); GameFontNormalMed2.GetFont = function() return "f.ttf", 14, "" end
      GameFontHighlight = MOCK.obj(); GameFontHighlight.GetFont = function() return "f.ttf", 12, "" end
      local th = NS.UI.Theme()
      assert(th.headerFont == GameFontNormalMed2, "header font")
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

@test("bug report: the title bar's button and /hf report open the report window (link, line, counters)")
def _(L, ns):
    lua(L, '''
      NS.OpenOptions()
      SlashCmdList.HOLDFAST("report")
      local w = NS.ShowBugReport()
      assert(w and w._shown, "shown")
      assert(w.url:find("template=bug_report.yml", 1, true) and w.line:find("Holdfast; client 1.60.1", 1, true) and w.line:find("whose aggro", 1, true), w.line)
      assert(w.stats[1].text._shown ~= false and w.stats[6].icon._shown ~= false, "six counters")
      NS.ShowBugReport("idea")
      assert(w.url:find("feature_request", 1, true))
    ''')

@test("settings window (6.2.0): the game's Settings design, six pages, every setting searchable")
def _(L, ns):
    lua(L, '''
      MinimalSliderWithSteppersMixin = MinimalSliderWithSteppersMixin or { Label = { Right = 2 }, Event = { OnValueChanged = "OnValueChanged" } }
      local printed
      local p0 = NS.Print; NS.Print = function(m) printed = m end
      local w = NS.OpenOptions()
      if w and not w._shown then w = NS.OpenOptions() end
      NS.Print = p0
      assert(w and w.index and w._shown, tostring(printed))
      local per, where = {}, {}
      for _, e in ipairs(w.index) do per[e.page] = (per[e.page] or 0) + 1; where[e.label] = e.page end
      for i = 1, 6 do assert((per[i] or 0) >= 2, "page " .. i .. ": " .. tostring(per[i])) end
      assert(where["My role"] == 1 and where["Glow style"] == 2 and where["% distance"] == 3 and where["Sound"] == 4
        and where["Show the overview window"] == 5 and where["Reset to defaults"] == 6)
      w.Refresh()
      for i = 1, 6 do w.Select(i) end
    ''')

print(f"\n{count - len(failures)}/{count} passed")
sys.exit(1 if failures else 0)
