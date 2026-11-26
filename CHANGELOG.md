# Changelog

## 6.0.0 (Milestone 6: diagnostics, validation, release)

Everything from the test versions 5.1.0-5.4.0 below (milestones 2-5, never released on their
own), plus:

- `/hf status`: version, whose aggro and role (and what they resolve to now), glow style, %,
  Warn at, alerts, overview, the nameplate adapters in use and which UI addons were found,
  solo / party / raid, combat, and what the client lets addons do.
- `/hf threat [unit]`: one enemy (your target by default): its state and confidence, who it's
  on, every threat call's answer, and everyone's status on it.
- `/hf profile [seconds]`: count Holdfast's work for that long (default 10 s) and report.
- `/hf reset`: every setting back to its default, after `/hf reset yes`.
- Fixed: the alerts' Test button showed "Lost aggro: Unknown"; the overview shows "other*" (not
  "?*") for an enemy on someone outside your group, such as a totem; two overlapping labels in
  the settings window.
- Tests for a group without roles, a healer, several enemies at once and a recycled nameplate
  (32 offline tests).

## 5.4.0 (Milestone 5: notifications, overview, customization)

- Transition events (Events.lua): STATE_CHANGED, AGGRO_GAINED, AGGRO_LOST, PET_AGGRO_GAINED,
  PET_AGGRO_LOST, THREAT_UNSTABLE, THREAT_SECURE, TARGET_CHANGED, UNIT_UNTRACKABLE. Payloads
  carry the state, who it's on (observed or inferred), the role and confidence, and the % only
  when readable. A change of owner alone now counts as a change.
- `HoldfastAPI` for other addons: `RegisterCallback(event, fn)`, `UnregisterCallback(handle)`,
  `GetState(unit)`, `Events`.
- Alerts (off by default): sound (the game's raid warning) and / or a message on screen, on red,
  and optionally on orange; not when an enemy first joins the fight; at most one every 2 s.
  A Test button in the settings.
- Threat overview (off by default; `/hf overview [all | unstable | lost | me | others]`): the
  enemies on your plates, most dangerous first, with state, who it's on, the % (a hidden one drawn
  by the game) and an asterisk when who it's on is inferred. Movable; remembers where it was.
  Built only when first shown; its half-second refresh runs only while it's shown.

## 5.3.0 (Milestone 4: rendering and performance)

- Event-driven: the 0.25 s ticker over every plate is gone. Threat-list updates are merged per
  enemy per frame; changes for everyone (situation, combat, target, roster, roles, pets) are
  merged into one pass per frame. A 1 s safety check runs only while you're in combat.
- Each nameplate is restyled only after a setting change (or a new enemy on it), and redrawn
  only when its state, shown %, target outline or style changes. A hidden % is passed to the
  game again each update, without comparing it.
- Animation manager: pixel-line and autocast glows share one `OnUpdate`, joined while shown;
  with none showing it stops.
- Nameplate adapters (Adapters.lua): EllesmereUI, FlareUI, the game's plate, and a generic
  fallback; each validated before use, with the next one tried if it fails.
- `/hf perf`: plates tracked, indicators by adapter, threat evaluations, redraws vs unchanged,
  restyles, average update time, glows animating, safety check.
- `/hf icon` and `/hf aggro` restyle the plates at once.
- Offline: `tests/bench.py` (5.2.0 vs 5.3.0 on the mock: 3800 vs 140 redraws in 10 s with 20
  plates).

## 5.2.0 (Milestone 3: who it's attacking, and pet tracking)

- Ownership: each enemy's state says who it's attacking - you, your pet, a group tank, another
  member, a member's pet - from whoever has threat status 2-3 (observed), or "unknown" when
  nobody in your group does (inferred: someone outside it, a guardian, or hidden).
- "Whose aggro" modes: Me, My pet, **Me and my pet**, **The group's tanks** (every group-finder
  tank; with no tank roles set, you), and Auto.
- The group (members, their pets, their tank roles) is looked up once when it changes
  (roster, roles, pets, loading screens), not on every update; you're no longer asked about twice
  in a raid.
- Your pet: summoned, dismissed, died or replaced, the glows follow at once (`UNIT_PET`).
- `/hf debug` and `/hf scan` say who each enemy is on.
- Guardians and summons other than your pet can't be asked about by addons (no unit token):
  an enemy on one shows as "unknown".

## 5.1.0 (Milestone 2: classification and percentage)

- Three states: secure (green), unstable (orange), lost (red with "!"), plus hidden, none and
  unknown internally. Tank: orange when the game's lead state says someone is closing in (1-2)
  or someone already has more threat (status 2). Not the tank: orange when you're above the tank
  but not yet pulling it (status 1). Both from the threat *state*, which Forever keeps readable
  in groups (`/hf debug` in a party: `secret: state=false values=true`).
- Where threat % is readable (solo), orange also starts at "Warn at" (default 80% of pulling it):
  your own % (not the tank), or the closest other's (the tank).
- Threat % beside the nameplate (off by default), with its distance and box opacity. A hidden %
  is handed to the game to draw (`SetFormattedText`), never read.
- Each state now carries ownership (on the followed unit / someone else, inferred), the game's
  status and lead, the % and a confidence ("values", "state", "hidden", "none").
- Settings: the "Losing it / Close" glow row (show, flash, strength, interval, colour, per role),
  a third preview button, the % options and "Warn at".
- `/hf scan` and `/hf debug` show each state's confidence.

## 5.0.2 (Milestone 1: audit and fixes)

- Fixed: "Whose aggro: My pet" with no pet out showed your own aggro instead of nothing.
- Fixed: Holdfast no longer builds a new set of glow frames each time a nameplate switches
  between the game's and EllesmereUI's / FlareUI's drawing, or the glow style changes; it reuses
  the ones it made. Before, these piled up over a play session.
- Fixed: hooks on the game's nameplates are set once per nameplate (they were added again with
  each new set of frames, and the old ones kept running).
- Lighter: removed five unused glow sets per nameplate left over from an older design.
- Fixed: a threat update the game sends for your target (rather than its nameplate) now
  updates the glows at once instead of up to a quarter second later.
- Fixed: turning off "Replace the game's aggro highlight" brings the game's flare back at once.
- Fixed: with EllesmereUI installed and its window style off, the settings window's text was
  unreadable (EllesmereUI's quest tracker shrinks the game's tracker fonts, which the window
  borrowed). The window no longer uses a font another addon has shrunk.
- No window-style settings any more: the settings window takes EllesmereUI's look when it's
  installed, else FlareUI's, else the game's, on its own.
- Group role changes update the glows at once.
- Safer: a hidden group role is treated as no role.
- Settings saved by a newer version are kept if you go back a version.
- `/hf debug` also shows the game's threat status, lead and % calls per enemy, and whether the
  game says it's hiding them, at every state change while it's on. New `/hf scan`: the same for
  every enemy at once.
- New: DEVELOPMENT.md, API_COMPATIBILITY.md, CHANGELOG.md and offline tests (`tests/`).

## 5.0.1

- The aggro diagnostic's helper frame is named `HoldfastProbeFrame` (was a generic leftover
  name from AggroGlow).

## 5.0.0

- Two states from the game's "is it attacking you" answer, which addons can use even when the
  game hides threat. Tank: green while it's on you, red with a "!" when it isn't. Not the tank:
  green while it's on someone else, red with a "!" once it's on you.
- The game's "Progressive" aggro flare is hidden on the nameplates Holdfast draws (setting).
- Removed the threat %, the "close" glow, "Warn at" and tooltip reading (the game hides them
  too often in groups).

Earlier versions: see "Recent changes" in README.md.
