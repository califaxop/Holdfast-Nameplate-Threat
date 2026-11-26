# Holdfast: development notes

Holdfast draws threat glows on enemy nameplates in WoW: Forever (Interface 16001, a Midnight 12.x
client running Classic content). This file maps how the addon runs, records what is done and what
isn't, and tracks the milestone plan. API facts and their verification status live in
[API_COMPATIBILITY.md](API_COMPATIBILITY.md); user-facing changes in [CHANGELOG.md](CHANGELOG.md).

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Audit and stabilize the existing implementation | **Done in 5.0.2, waiting for in-game validation** |
| 2 | Threat classification and percentage engine | Not started |
| 3 | Multi-unit ownership and pet tracking | Not started |
| 4 | Rendering and performance improvements | Not started |
| 5 | Notifications, overview and customization | Not started |
| 6 | Diagnostics, validation and release preparation | Not started |

## Architecture (as it actually runs, 5.0.2)

Load order (Holdfast.toc): Core → UnitRegistry → ThreatState → Renderer → UI → Options → Engine.
Every file shares the addon namespace `ns`.

| File | Module | Does |
|---|---|---|
| Core.lua | `ns` | Defaults, saved variables (`HoldfastDB`, schema version 5) and their migrations, `ns.isSecret` / `ns.Readable`, printing |
| UnitRegistry.lua | `ns.Registry` | Nameplate unit token → the game's plate frame (`Add`, `Remove`, `Get`, `Scan`, `Each`) |
| ThreatState.lua | `ns.State` | Role and mode (whose aggro), evaluation of one enemy into a state table, last state per unit, a transition callback |
| Renderer.lua | `ns.Renderer` | Finds the host (EllesmereUI / FlareUI / the game's plate), builds and reuses indicator frames, glow styles, the "!" and % placement, hides the game's aggro flare |
| UI.lua | `ns.UI` | The shared settings-window kit (also used by the other addons); FlareUI / EllesmereUI skins |
| Options.lua | — | The settings window and the Esc > Options > AddOns entry |
| Engine.lua | — | Events, the update loop and the slash commands |

### Update flow

1. `ADDON_LOADED` (Holdfast): load settings, scan plates, register the settings entry, register
   the events below, start a 0.25 s ticker that updates every plate (a safety net).
2. `NAME_PLATE_UNIT_ADDED` → `Registry.Add` → update that unit.
   `NAME_PLATE_UNIT_REMOVED` → hide its indicator, forget its state.
   `UNIT_THREAT_LIST_UPDATE` for a nameplate token → update that unit; for any other token
   (target, focus, boss…) → one batched update of every plate.
   `PLAYER_ENTERING_WORLD` → rescan and update all.
   Everything else (`UNIT_THREAT_SITUATION_UPDATE`, combat start / end, roster, target, pet,
   roles) → one batched update of every plate on the next frame (`C_Timer.After(0)`).
3. Updating a unit: `State.Update(unit)` → (the "only in a group" and preview overrides) →
   `Renderer.Render(plate, state, unit)`.

### Threat evaluation (ThreatState.lua, `Evaluate`)

- No unit, can't attack, or dead → `none`.
- Mode (`State.Mode`): `pet` (follow your pet), `tank` (you, as the tank) or `dps` (you, not the
  tank), from the "Whose aggro" and "My role" settings. "My pet" with no pet out → `none`.
- Engaged: is the followed unit, you, your pet or anyone in your group on the enemy's threat list
  (`UnitThreatSituation` non-nil)? If every answer is hidden, it counts as engaged while the enemy
  is in combat.
- `UnitDetailedThreatSituation(followed, enemy)` → `isTanking` only:
  - hidden → `hidden`, carrying the hidden `isTanking` to the renderer;
  - tank / pet mode: tanking → `secure`, not → `lost`;
  - dps mode: tanking → `lost`, not → `secure`.

The status, scaled %, raw % and raw threat it also returns are not used, nor are
`UnitThreatLeadSituation` or `UnitThreatPercentageOfLead`.

### Rendering (Renderer.lua)

- Host: EllesmereUI's plate for the unit when shown, else FlareUI's parts of the plate, else the
  game's unit frame. Each gives a parent frame and a bar to frame.
- One indicator per host bar and glow style, made once and reused (frames can't be freed). Each
  has three glows (`aggro`, `unstable`, `nothreat`; each a holder frame, an inner frame with an
  alpha bounce animation, the glow textures and a "!"), plus a % box.
- States: `secure` → the `aggro` glow; `lost` → the `nothreat` glow with the "!"; `hidden` →
  both glows shown, each made visible or invisible by the game through
  `SetAlphaFromBoolean(isTanking)`; `none` → nothing.
- Glow styles: border (the plate's own selection-border art), outline, pixel lines, autocast
  sparkles. Pixel and autocast each run their own `OnUpdate` driver while visible.
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
| **Unstable** (someone close to taking it / you close to pulling it) | **Not reachable.** The glow exists and has settings defaults, but `Evaluate` never returns it and the settings window no longer shows it. `unstableAt` (80) is saved but never read. Milestone 2 |
| **Threat %** | **Not reachable.** The % box and its settings (`showPercent`, `percentGap`, `percentBgAlpha`) exist, but nothing sets its text or shows it. Milestone 2 |
| Ownership beyond "on the followed unit or not" | Not implemented. Milestone 3 |
| Guardians / summons other than `pet` | Not implemented. Milestone 3 |
| Event-driven updates without the ticker | Partly (events + 0.25 s ticker). Milestone 4 |
| Shared animation manager | Not implemented (one `OnUpdate` per visible pixel / autocast glow). Milestone 4 |
| Transition events | One debug callback (`State.onTransition`). Milestone 5 |
| Overview window, notifications | Not implemented. Milestone 5 |
| Diagnostics | `/hf debug` (per-enemy threat calls, value / nil / hidden / error / n/a), `/hf tank`, `/hf tip` probes. Milestone 6 adds scan, status, perf, profile, reset |
| Tests | `tests/run_tests.py` (logic only, on a mock client). Milestone 6 widens them |

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
| 11 | Medium | The unstable glow and the % are unreachable (see above), and `unstableAt` is never read. | ThreatState, Renderer, Core | Milestone 2 (new functionality, not a fix) |
| 12 | Medium | Every update restyles every indicator (colors, alpha, durations, the box style, the Questie icon search with a table per call), every plate, 4 times a second, whether or not anything changed. | Renderer.lua | Milestone 4 |
| 13 | Medium | In hidden mode both glows are shown and the game sets one to alpha 0; with pixel / autocast styles the invisible one's `OnUpdate` still runs every frame. | Renderer.lua | Milestone 4 (animation manager) |
| 14 | Medium | `Engaged` calls `UnitThreatSituation` for every group member (up to 42 in a raid) per enemy per update; in raids, with the ticker, that's thousands of calls a second. | ThreatState.lua | Milestone 3 / 4 |
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

## Testing

### Offline (logic only)

```
pip install lupa
python3 tests/run_tests.py
```

`tests/mock.lua` is a small mock of the client. The tests check the states for tank / not the
tank / pet, readable and hidden answers, the indicator and hook lifecycle, the flare, the event
paths, settings migration and the slash commands. They can't prove how the real client behaves:
the mock's hidden values are tables, and the real client is stricter.

### In game (Milestone 1 validation)

1. `/reload` with only Holdfast, then with FlareUI's nameplates, then with EllesmereUI's.
2. Solo, tank a mob: green while it's on you; let a pet or a friend take it: red with "!".
3. "Whose aggro: My pet" with no pet out: no glows (this was the 5.0.1 bug).
4. Change the glow style several times, then fight: glows still right, no Lua errors.
5. Untick "Replace the game's aggro highlight" mid-fight in a party: the game's flare comes back
   at once on enemies that have it.
6. In a party, in combat, type `/hf debug` (and again to turn it off) and send the chat. Each
   enemy line shows `status=`, `lead=`, `pct=`, `ofLead=` and `secret: state= values=`. This is
   the data Milestone 2 needs: whether the threat *state* (0–3) stays readable when the threat
   *values* are hidden.

## Known limitations (from earlier in-game tests)

- In a party in combat, `UnitDetailedThreatSituation`'s answers (isTanking, status, %) were
  hidden (AggroGlow 3.x, Nov 2026).
- Turning a hidden number into a glow through curves (`C_CurveUtil`, `Curve:Evaluate`) was
  refused for addons.
- The tooltip's "% Threat" line was not readable by addons in a party.
- Not measured yet: `UnitThreatSituation` and `UnitThreatLeadSituation` in a party
  (`/hf debug`, step 6 above).
