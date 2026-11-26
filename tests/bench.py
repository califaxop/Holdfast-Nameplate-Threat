#!/usr/bin/env python3
"""Rough performance comparison on the mock client (not the game): 20 enemy nameplates, a party of
five, 10 seconds of combat at 60 frames a second, with the threat events a group fight sends
(several threat-list updates a frame, a situation update every few frames, a state change now
and then). Counts the work Holdfast does and its Lua time.

  python3 tests/bench.py            this checkout
  python3 tests/bench.py <folder>   another copy of the addon (e.g. an older version), same test
"""
import os, sys, time
from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(HERE)
FILES = [l.strip() for l in open(os.path.join(ROOT, 'Holdfast.toc')) if l.strip().endswith('.lua') and not l.startswith('#')]

L = LuaRuntime()
L.execute(open(os.path.join(HERE, 'mock.lua')).read())
ns = L.eval('{}')
run = L.eval('function(src, n, ns) return assert(loadstring(src, "@" .. n))("Holdfast", ns) end')
for f in FILES:
    run(open(os.path.join(ROOT, f)).read(), f, ns)
L.globals().NS = ns
L.execute('''
  MOCK.Start()
  for i = 2, 20 do MOCK.AddPlate(i); MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
  MOCK.members = 4; MOCK.roles = { party1 = "TANK" }; MOCK.Group(true)
  NS.db.role = "dps"; NS.db.glowStyle = "pixel"; NS.db.showPercent = (os and os.getenv and os.getenv("PCT") == "1"); MOCK.hiddenValues = true
  MOCK.threat = { party1 = { status = 3, lead = 0 }, player = { status = 0 },
    party2 = { status = 0 }, party3 = { status = 0 }, party4 = { status = 0 } }
  MOCK.combat = true; MOCK.Fire("PLAYER_REGEN_DISABLED"); MOCK.RunTimers()
  -- count every threat evaluation and every frame drawn on (texture or frame calls)
  BENCH = { evals = 0 }
  local real = NS.State.Update
  NS.State.Update = function(...) BENCH.evals = BENCH.evals + 1; return real(...) end
''')
step = L.eval('''function(frame)
  -- a frame of a group fight: 3 threat-list updates, a situation update every 10 frames,
  -- a state change every 2 seconds (someone gets close, then backs off)
  for k = 1, 3 do MOCK.Fire("UNIT_THREAT_LIST_UPDATE", "nameplate" .. ((frame * 3 + k) % 20 + 1)) end
  if frame % 10 == 0 then MOCK.Fire("UNIT_THREAT_SITUATION_UPDATE", "party2") end
  if frame % 120 == 0 then MOCK.threat.player.status = (MOCK.threat.player.status == 0) and 1 or 0 end
  -- timers: next-frame work, and tickers that are due (60 frames a second)
  local now = frame / 60
  for _, t in ipairs(MOCK.tickers) do
    t.next = t.next or t.sec
    if not t.cancelled and now >= t.next then t.next = t.next + t.sec; t.fn() end
  end
  MOCK.RunTimers()
end''')
t0 = time.process_time()
for frame in range(1, 601):
    step(frame)
dt = time.process_time() - t0
evals = L.eval('BENCH.evals')
c = L.eval('NS.Renderer.counters')
anim = L.eval('NS.Renderer.Anim')
print(f"{os.path.basename(ROOT) or ROOT}: 10 s, 20 plates: {evals} threat evaluations, "
      f"{(c and c['renders']) if c else 'n/a'} redraws, {(c and c['skipped']) if c else 'n/a'} unchanged, "
      f"{(c and c['styles']) if c else 'n/a'} restyles, Lua time {dt * 1000:.0f} ms (mock)")
