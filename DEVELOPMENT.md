# Holdfast: development notes

Holdfast draws threat glows on enemy nameplates in WoW: Forever (Interface 16001, a Midnight 12.x
client running Classic content). This file maps how the addon runs, records what is done and what
isn't, and tracks the milestone plan. API facts and their verification status live in
[API_COMPATIBILITY.md](API_COMPATIBILITY.md); user-facing changes in [CHANGELOG.md](CHANGELOG.md).

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Audit and stabilize the existing implementation | Done in 5.0.2, validated in game (step 5, the flare given back, still to see) |
| 2 | Threat classification and percentage engine | Done in 5.1.0, validated in game (tank: all three states; not the tank: the hidden %). Orange as not the tank and "Warn at" solo still to see |
| 3 | Multi-unit ownership and pet tracking | Done in 5.2.0, validated in game (ownership in a party). "The group's tanks", "Me and my pet" still to see |
| 4 | Rendering and performance improvements | Done in 5.3.0, validated in game (0.1 ms passes; animation driver on and off with the fight; safety check only in combat) |
| 5 | Notifications, overview and customization | Done in 5.4.0, validated in game (alerts, the overview, a totem shown as inferred) |
| 6 | Diagnostics, validation and release preparation | **Done in 6.0.0, waiting for the final in-game check** |

## Architecture (as it actually runs, 6.0.0)

Load order (Holdfast.toc): Core → UnitRegistry → ThreatState → Adapters → Renderer → UI → Events → Alerts → Overview → Options → Engine.
Every file shares the addon namespace `ns`.

| File | Module | Does |
|---|---|---|
| Core.lua | `ns` | Defaults, saved variables (`HoldfastDB`, schema version 5) and their migrations, `ns.isSecret` / `ns.Readable`, printing |
| UnitRegistry.lua | `ns.Registry` | Nameplate unit token → the game's plate frame (`Add`, `Remove`, `Get`, `Scan`, `Each`) |
| ThreatState.lua | `ns.State` | Role and mode (whose aggro), evaluation of one enemy into a state table, last state per unit, a transition callback |
| Adapters.lua | `ns.Adapters` | Nameplate adapters: EllesmereUI, FlareUI, the game's plate, a generic fallback. Each finds the host frame and bar for a plate (validated), and gives its font and its % box look |
| Renderer.lua | `ns.Renderer` | Finds the host (EllesmereUI / FlareUI / the game's plate), builds and reuses indicator frames, glow styles, the "!" and % placement, hides the game's aggro flare |
| Events.lua | `ns.Events`, `HoldfastAPI` | Transition events (STATE_CHANGED, AGGRO_GAINED / LOST, PET_AGGRO_GAINED / LOST, THREAT_UNSTABLE / SECURE, TARGET_CHANGED, UNIT_UNTRACKABLE), payloads without hidden values, and the public API for other addons |
| Alerts.lua | `ns.Alerts` | Optional sound / on-screen message when an enemy turns red (and orange, if chosen); not on joining the fight; at most one every 2 s |
| Overview.lua | `ns.Overview` | Optional window: enemies on your plates, most dangerous first, with state, owner, % and filters; built and updated only while shown |
| UI.lua | `ns.UI` | The shared settings-window kit (also used by the other addons); FlareUI / EllesmereUI skins |
| Options.lua | — | The settings window and the Esc > Options > AddOns entry |
| Engine.lua | — | Events, the update loop and the slash commands |

### Update flow

1. `ADDON_LOADED` (Holdfast): load settings, scan plates, register the settings entry, register
   the events below. No polling out of combat.
2. `NAME_PLATE_UNIT_ADDED` → `Registry.Add` → restyle and update that unit at once.
   `NAME_PLATE_UNIT_REMOVED` → hide its indicator, forget its state.
   `UNIT_THREAT_LIST_UPDATE` for a nameplate token → that unit, on the next frame (merged: a unit
   named many times in a frame is updated once); for any other token (target, focus, boss…) →
   every plate, next frame.
   `PLAYER_ENTERING_WORLD` → refresh the roster, rescan and update all.
   Everything else (`UNIT_THREAT_SITUATION_UPDATE`, combat start / end, roster, target, pet,
   roles) → every plate once, next frame (`C_Timer.After(0)`). Roster, role and pet events also
   refresh the cached roster.
   Combat start → a 1 s safety check (every plate) until combat ends.
3. Updating a unit: `State.Update(unit)` → (the "only in a group" and preview overrides) →
   `Renderer.Render(plate, state, unit)`. When its state or owner changed, `State.onTransition` →
   `Events.Transition` → the events (alerts and the overview listen to STATE_CHANGED).

### Threat evaluation (ThreatState.lua, `Evaluate`)

- No unit, can't attack, or dead → `none`.
- Mode (`State.Mode`), from "Whose aggro" and "My role": `pet` (your pet), `both` (you and your
  pet), `tanks` (the group's tanks, for healers), `tank` (you, as the tank) or `dps` (you, not the
  tank). `State.Followed` gives the units whose holding it counts: one, two (you and your pet) or
  every group tank (group-finder role; none set → you). "My pet" with no pet out → `none`.
- Roster: your group members and their pets (`partyN` / `partypetN`, `raidN` / `raidpetN`, without
  you and your own pet), with each member's tank role, cached until `GROUP_ROSTER_UPDATE`,
  `PLAYER_ROLES_ASSIGNED`, `UNIT_PET` or a loading screen.
- One pass per enemy over everyone (you, your pet, the roster): each one's
  `UnitThreatSituation`. Engaged: any readable answer (or, if every answer is hidden, the enemy is
  in combat). Who it's attacking: the one with status 2–3 (observed); nobody of yours →
  `unknown` (inferred: someone outside the group, a guardian, or hidden).
- The game hides two things separately (measured in a party, Nov 2026): the threat **state**
  (`UnitThreatSituation` status 0–3, `UnitThreatLeadSituation` 0–3) stays readable; the threat
  **values** (`UnitDetailedThreatSituation`: isTanking, %) are hidden.
- State hidden too → `hidden`: the hidden `isTanking` goes to the renderer, which switches the
  glows with it (two states, as in 5.0).
- State readable:
  - **Tank / pet / you and your pet / the group's tanks:** held by none of the followed → `lost`;
    held by one with status 2 (someone has more threat), or lead 1–2 (someone closing in), or
    (values readable) anyone else at "Warn at" or more → `unstable`; else `secure`. The % is the closest other's (only when readable: hidden values can't be
    compared to find the highest).
  - **Not the tank:** on you → `lost`; status 1 (above the tank, not yet pulling) or (values
    readable) your % at "Warn at" or more → `unstable`; else `secure`. The % is yours (hidden or
    not: a hidden one is drawn by the game).
- Each state also carries `ownership` ("player", "pet", "tank", "member", "member pet",
  "unknown"), `ownerUnit`, `ownerObserved`, `status`, `lead`, `percentage` and `confidence`
  ("values", "state", "hidden", "none"). See the comment above `Evaluate`.
- Pull threshold: not applied by Holdfast. The game's scaled % is already a % of what pulls it
  (110% of the tank's threat in melee range, 130% at range, in Classic); not yet verified on
  Forever.

### Rendering (Renderer.lua)

- Host: the first adapter (Adapters.lua) that finds one: EllesmereUI's plate for the unit when
  shown, FlareUI's parts of the plate, the game's unit frame, or the plate itself. The adapter
  also gives the % font and the % box look, so the renderer has no EllesmereUI / FlareUI code.
- One indicator per host bar and glow style, made once and reused (frames can't be freed). Each
  has three glows (`aggro`, `unstable`, `nothreat`; each a holder frame, an inner frame with an
  alpha bounce animation, the glow textures and a "!"), plus a % box.
- States: `secure` → the `aggro` glow; `unstable` → the `unstable` glow; `lost` → the `nothreat` glow with the "!"; `hidden` →
  both glows shown, each made visible or invisible by the game through
  `SetAlphaFromBoolean(isTanking)`; `none` → nothing.
- Glow styles: border (the plate's own selection-border art), outline, pixel lines, autocast
  sparkles. Pixel and autocast glows join the animation manager (`Renderer.Anim`: one shared
  `OnUpdate`) while shown and leave when hidden; with none showing, its frame is hidden.
- Each indicator is restyled only when a setting changes (`ns.lookGen`, bumped by the settings
  window and the slash commands), its plate shows a new enemy, or it switches role set; and
  redrawn only when its state, shown %, target outline or style changed. A hidden % can't be
  compared: its text is handed to the game again each update (cheap).
- The game's plate: the "!" and % go past the raid marker, elite icon and buff row (hooked once
  per game unit frame to follow them), and the game's "Progressive" aggro flare is hidden
  (hooked once per game unit frame) while "Replace the game's aggro highlight" is on.

## Implemented vs incomplete

| Area | State |
|---|---|
| Tank / not the tank / pet: on you or not | Working, readable and hidden |
| Role from the group finder, manual role, pet following | Working |
| Blizzard, FlareUI and EllesmereUI plates | Working (FlareUI / EllesmereUI found by their own tables, validated, with fallback) |
| Glow styles, colors, strength, flash, interval per glow and per role | Working |
| Replacing the game's flare | Working (now also given back when turned off) |
| Preview on your target | Working |
| Unstable (someone close to taking it / you close to pulling it) | 5.1.0: from the game's states in groups, plus "Warn at" where % is readable |
| Threat % | 5.1.0: optional; readable shown capped at 100, hidden drawn by the game |
| Ownership: you, your pet, a group tank, a member, a member's pet, unknown | 5.2.0 (observed from status 2–3; "unknown" is inferred) |
| Tracking modes: me, my pet, me and my pet, the group's tanks | 5.2.0 |
| Guardians and summons other than your `pet` | Not tracked: the game gives addons no unit token for them (only their nameplates, which are friendly units, not threat holders Holdfast can ask about). An enemy attacking one shows as "unknown" (inferred) |
| Event-driven updates | 5.3.0: events, merged per frame; a 1 s check only in combat |
| Shared animation manager | 5.3.0: one driver, only glows showing |
| Nameplate adapters | 5.3.0: EllesmereUI, FlareUI, Blizzard, generic |
| Performance counters | 5.3.0: `/hf perf` (Milestone 6 adds status, profile, reset) |
| Transition events | 5.4.0: Events.lua, `HoldfastAPI` for other addons |
| Overview window, alerts | 5.4.0: optional, off by default |
| Diagnostics | `/hf status`, `/hf threat [unit]`, `/hf scan`, `/hf debug`, `/hf perf`, `/hf profile [s]`, `/hf reset`, `/hf tank` / `/hf tip` probes. Each answer shows as a value, nil, `<hidden>`, error or n/a; inferred owners are marked |
| Tests | `tests/run_tests.py` (32, logic only, on a mock client), `tests/bench.py` |

## Milestone 1 audit (5.0.1 source)

Severity: **High** = wrong result or an unbounded leak in normal play; **Medium** = wrong in some
setups, wasted resources or a latency bug; **Low** = cosmetic, cleanup or an edge case.

| # | Severity | Finding | Files | Status |
|---|---|---|---|---|
| 1 | High | "Whose aggro: My pet" with no pet out followed **you**: `mode == "pet" and (PetOut() and "pet" or nil) or "player"` falls through to `"player"` when the middle is nil. Should show nothing (as its own comment says). | ThreatState.lua | Fixed |
| 2 | High | A new indicator (a dozen-plus frames) was made each time a plate's host changed (e.g. EllesmereUI shows its plate a moment after the game's appears, or recycles it), and on every glow-style change. Frames are never freed, so this grew through play. | Renderer.lua | Fixed: one per host bar and style, reused |
| 3 | Medium | Duplicate hooks and stale references: each new indicator hooked the same game unit frame again (7 `HookScript`s for the "!" placement and a `hooksecurefunc` for the flare), and each old hook kept its dead indicator and still ran. | Renderer.lua | Fixed: hooked once per game frame; the hook looks up the plate's current indicator |
| 4 | Medium | Five extra "gate" glow sets per indicator (from the removed hidden-% design) were built and styled on every update but could never show: about 2/3 of each indicator's frames and textures, restyled 4 times a second. | Renderer.lua | Fixed: removed |
| 5 | Medium | `UNIT_THREAT_LIST_UPDATE` names an enemy by one token. When it wasn't a nameplate token (e.g. `target`), the update was dropped until the next ticker pass (up to 0.25 s late). | Engine.lua | Fixed: batched update of every plate |
| 6 | Medium | `UnitGroupRolesAssigned` can return a hidden value (its docs: secret when unit identity is restricted); comparing it with `"TANK"` would error in the real client. | ThreatState.lua | Fixed: a hidden role counts as no role |
| 7 | Low | Turning "Replace the game's aggro highlight" off left the game's flare hidden until the game next switched it on. | Renderer.lua | Fixed: given back where the game wants it shown |
| 8 | Low | Role changes in a group (`PLAYER_ROLES_ASSIGNED`) waited for the ticker. | Engine.lua | Fixed: listened to |
| 9 | Low | Settings from a newer version (after going back a version) would be wiped: only versions 3–5 were kept. | Core.lua | Fixed: only versions before 3 start fresh |
| 10 | Low | Dead code: `Cap()`, the `insecure` state in `HAS_AGGRO` (never produced) and the transition flag built from it, `ns.db.enabled` (no such setting), unused locals (`db`, `col`, `rr`, `arg`), a `kind` shadowing `kind`, `issecure()` passed as `includeForbidden`. | Renderer, ThreatState, Engine, Options, UnitRegistry | Fixed |
| 11 | Medium | The unstable glow and the % are unreachable (see above). The never-read `unstableAt` and `showPercent` settings were removed in 5.0.2; Milestone 2 adds the settings it needs. | ThreatState, Renderer, Core | Milestone 2 (new functionality, not a fix) |
| 12 | Medium | Every update restyles every indicator (colors, alpha, durations, the box style, the Questie icon search with a table per call), every plate, 4 times a second, whether or not anything changed. | Renderer.lua | 5.3.0: restyle only on change, redraw only on change |
| 13 | Medium | In hidden mode both glows are shown and the game sets one to alpha 0; with pixel / autocast styles the invisible one's `OnUpdate` still runs every frame. | Renderer.lua | 5.3.0: one shared driver; in hidden mode both glows still animate (the game decides which is seen, so Holdfast can't tell) |
| 14 | Medium | `Engaged` calls `UnitThreatSituation` for every group member (up to 42 in a raid) per enemy per update; in raids, with the ticker, that's thousands of calls a second. | ThreatState.lua | 5.2.0: roster cached; 5.3.0: no ticker, merged events. Still one call per group member per enemy evaluation (needed to know who holds it) |
| 15 | Low | In hidden mode, an enemy in combat with players outside your group still counts as engaged (the game hides whether anyone of yours is on its list), so as the tank it can show red. | ThreatState.lua | Documented; Milestone 3 |
| 16 | Low | The indicator's frame level is set once from the bar; if a nameplate addon raises its bar later, the glow could sit under it. | Renderer.lua | Watch in game |
| 17 | Low | In a raid, `raidN` includes you, so you're asked twice (harmless). | ThreatState.lua | Milestone 3 |

### Secret values (audit 6)

Every value that the docs mark as possibly hidden goes through `ns.isSecret` / `ns.Readable`
before it's compared or tested, with one gap fixed in 5.0.2 (finding 6). The hidden `isTanking`
is only ever handed to `SetAlphaFromBoolean`, which the docs allow for addons with hidden
arguments. The diagnostics print `<hidden>` without reading. No hidden value is stored in saved
variables or printed.

### Nameplate lifecycle (audit 7)

Add → registry + render; remove → hide + forget state; recycling → the same plate frame gets a
new token, and its indicator is reused. Host changes and glow-style changes now reuse indicators
(finding 2). Forbidden plates are skipped. After a loading screen the registry is rebuilt.

### Events and frequency (audit 8)

Ten events plus the role event, a 0.25 s ticker over every plate, and a next-frame batch for
bursts. Per-unit updates for nameplate threat-list changes; everything else is a full pass. The
ticker is the main cost (finding 12); removing it needs Milestone 4's change tracking first.

### Rendering and animation (audit 9)

Per indicator (border style): 3 glows × (2 frames + an animation + 2–4 textures + the "!" frame
and 2 textures), a % box with its art, about 12 frames and 15 textures. Before 5.0.2 it was 8 glow
sets (about 33 frames and 34 textures), and pixel / autocast styles had 8 drivers each.

## Hygiene

No unused code or settings: before each release, `luacheck` must show no unused variables or
functions, and every saved setting must be read somewhere. A removed setting's code goes with it
(an old saved value is simply never read). The only kept exceptions are the
test seams `Renderer.Indicator` / `Renderer.Counts`.

## Testing

### Offline (logic only)

```
pip install lupa
python3 tests/run_tests.py
python3 tests/bench.py [another copy of the addon, to compare]
```

`tests/mock.lua` is a small mock of the client. The tests check the states for tank / not the
tank / pet, readable and hidden answers, the indicator and hook lifecycle, the flare, the event
paths, settings migration and the slash commands. They can't prove how the real client behaves:
the mock's hidden values are tables, and the real client is stricter.

### In game: the gate between milestones

Each milestone ends with an in-game checklist: what to do, and what to send back (screenshots
or chat output). The next milestone starts only once those results are in.

#### Milestone 1 → 2

1. `/reload` with only Holdfast, then with FlareUI's nameplates, then with EllesmereUI's.
2. Solo, tank a mob: green while it's on you; let a pet or a friend take it: red with "!".
3. "Whose aggro: My pet" with no pet out: no glows (this was the 5.0.1 bug).
4. Change the glow style several times, then fight: glows still right, no Lua errors.
5. Untick "Replace the game's aggro highlight" mid-fight in a party: the game's flare comes back
   at once on enemies that have it.
6. In a party, with `/hf debug` on, fight: each state change prints the enemy's line (or type
   `/hf scan` mid-fight for every enemy). Send the chat. Each enemy line shows `status=`, `lead=`, `pct=`, `ofLead=` and `secret: state= values=`. This is
   the data Milestone 2 needs: whether the threat *state* (0–3) stays readable when the threat
   *values* are hidden.

#### Milestone 2 → 3

1. Install 5.1.0, `/reload`. In `/hf`, tick "Threat % beside the nameplate".
2. Solo: fight a mob. Green while it's on you. If you have a pet, let it build threat: orange,
   then red with "!" when it takes the mob (as the tank). Set "My role: Not the tank" and let the
   pet tank: orange once your % passes "Warn at", red once you pull it. The % shows a number.
3. Preview buttons: each of the three looks, with a sample %.
4. In a party, as the tank, with `/hf debug` on: green while you hold, orange when a damage
   dealer closes in (the line shows `lead=1` or `2`, or `status=2`), red with "!" if they pull.
   The % beside the plate shows the closest other's when readable (solo); in a party it stays
   empty for a tank.
5. In a party, not the tank (or "My role: Not the tank"): orange when you're above the tank
   (`status=1`), red when you pull it. The % beside the plate shows a number drawn by the game
   (this checks that a hidden % can be shown).
6. Untick "Replace the game's aggro highlight" mid-fight: the game's flare comes back at once.
7. Send screenshots of 4 and 5 (plate and chat), and any Lua errors.

#### Milestone 3 → 4

1. Install 5.2.0, `/reload`. In a party, as a damage dealer or healer, with `/hf debug` on.
2. Each change line now says who it's attacking: `on tank (party2)`, `on member (party3)`,
   `on member pet (partypet1)`, `on you`, `on your pet`, or `on unknown (inferred)`. Check a few
   against what you see (the mob's target).
3. Set "Whose aggro: The group's tanks": green while a tank holds it, orange when a tank is about
   to lose it, red with "!" when it's on anyone else (you, a damage dealer, a healer).
4. With a pet (if you have a pet class): "Whose aggro: Me and my pet". Green while either of you
   holds it; dismiss or lose the pet mid-fight: it goes back to only you, no errors.
5. `/hf scan` mid-fight once, in a group with roles set (dungeon finder, or roles set by the
   leader). Send it, and screenshots of 2-4, and any Lua errors.
6. Still open from Milestone 2: orange as not the tank (`status=1`), "Warn at" solo, and the game's
   flare coming back when "Replace" is unticked.

#### Milestone 4 → 5

1. Install 5.3.0, `/reload`. Everything should look and behave as in 5.2.0.
2. Fight a large pull (5+ enemies) in a party with the glow style on "Pixel lines" or "Autocast
   sparkles", then type `/hf perf`. Send it: it shows plates tracked, threat evaluations,
   redraws vs unchanged, restyles, the average update time and how many glows are animating.
3. Out of combat, `/hf perf` again: "safety check: off".
4. Change a colour, the strength or the "!" setting mid-fight: every plate takes it at once.
5. With FlareUI's and with EllesmereUI's nameplates: glows and the % in their look, as before
   (`/hf perf` lists "flare" / "eui" under indicators showing).
6. Still open: "The group's tanks", "Me and my pet", "Warn at" solo, and "Replace the game's aggro
   highlight" unticked mid-fight.

In game (5.3.0, a party, Scarlet Monastery, border glows): 152 update passes averaging
0.098 ms; 126 of 152 updates unchanged (not redrawn); the safety check ran only in combat.
Pixel glows, solo pull: in combat 2 plates, 2 glows animating; after it 0 tracked, 0 animating,
safety check off; 75 passes averaging 0.102 ms.

#### Milestone 5 → 6

1. Install 5.4.0, `/reload`. Nothing new shows until you turn it on.
2. `/hf` → Alerts: tick "Sound" and "Message on screen", press Test: the raid-warning sound and
   "Lost aggro" in red near the top of the screen.
3. In a party as not the tank: when a mob turns to you, one sound and "Aggro on you: <name>";
   none when mobs first join a pull; at most one every 2 seconds. Tick "When it turns orange" and
   check "Close to pulling: <name>".
4. `/hf overview`: the window lists the enemies on your plates, red first, then orange, then
   green, with who each is on and the % (drawn by the game in a party). Drag it; `/reload`: it
   stays where you put it. `/hf overview lost` / `me` / `all`: the filter. Close it with ×.
5. Send a screenshot of the overview mid-fight and of an alert, and any Lua errors.
6. Still open: "The group's tanks", "Me and my pet", "Warn at" solo, "Replace" unticked mid-fight.

#### Milestone 6 → release (6.0.0)

1. Install 6.0.0, `/reload`. Type `/hf status`: the version says 6.0.0, and the rest matches your
   settings.
2. Target an enemy and type `/hf threat`; in a fight, `/hf profile 20` and wait for the report.
3. `/hf reset`: it asks; `/hf reset yes` puts everything back (then set your role and style again).
4. The alerts' Test button: "Lost aggro" (no "Unknown"); the settings window: no overlapping text.
5. A normal party run with your usual settings. Any Lua errors?
6. Still never seen in game (fine to ship without, each falls back safely): "The group's tanks",
   "Me and my pet", "Warn at" solo, "Replace the game's aggro highlight" unticked mid-fight, raids.
7. Then "ship": 6.0.0 goes to CurseForge (after 5.0.2's Wednesday release, or instead of it).

### Performance (mock client, `python3 tests/bench.py`)

10 s of a party fight, 20 enemy plates, pixel glows, three threat-list updates a frame:

| | 5.2.0 | 5.3.0 |
|---|---|---|
| Threat evaluations | 3800 | 2820 |
| Restyles + redraws | 3800 each (every update) | 40 restyles, 140 redraws, 2740 unchanged |
| Lua time (mock, mostly the mock itself) | 626–767 ms | ~478 ms |

The mock's times only compare versions; in-game numbers come from `/hf perf`.

## Known limitations (from earlier in-game tests)

- In a party in combat, `UnitDetailedThreatSituation`'s answers (isTanking, status, %) were
  hidden (AggroGlow 3.x, Nov 2026).
- Turning a hidden number into a glow through curves (`C_CurveUtil`, `Curve:Evaluate`) was
  refused for addons.
- The tooltip's "% Threat" line was not readable by addons in a party.
- Measured in a party (5.0.2, `/hf debug`): `UnitThreatSituation` and `UnitThreatLeadSituation`
  readable (`status=0 lead=3`, `status=3 lead=0`), `C_Secrets.ShouldUnitThreatStateBeSecret` false,
  `ShouldUnitThreatValuesBeSecret` true; isTanking and % hidden.
- 5.1.0 in a party, as the tank: secure → lost (`status=0 lead=3`) and back to secure
  (`status=3 lead=3`) from the readable state. `status=3` with `lead=3` ("not first") at the same
  moment contradicts the docs; the lead may lag the status by an update. Holdfast treats only lead
  1–2 as unstable, so this reads as secure.
- 5.1.0 in a party, as the tank: orange seen. lost → unstable (`status=2 lead=1`: on you, someone
  has more threat), unstable → secure (`status=3 lead=0`), secure → lost (`status=1 lead=3`: you
  have the most threat but it's attacking someone else).
- 5.1.0 in a party, not the tank: the hidden % **is drawn by the game** (`SetFormattedText` with a
  hidden value: "24%", "3%" beside the plates, in the safe colour), `secret: values=true`.
- 5.2.0 in a party, not the tank: ownership observed (`on tank (party1)`, the group's tank by
  role); orange as not the tank seen (`lost -> unstable`, `status=1`); the hidden % drawn on
  several plates at once (0%, 62%).
- 5.2.0 `/hf scan` in a party mid-fight: engaged enemy `secure (state) | on tank (party1)`;
  enemies nobody fights `none` (now printed as "not engaged").
- Not measured yet: "Warn at" solo, "The group's tanks" and "Me and my pet" modes, and raids.
