# Changelog

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
- The two window-style checkboxes are now one setting, "Window look": Auto (EllesmereUI's look
  when it's installed, else FlareUI's, else the game's) or Plain. Everyone starts on Auto.
- Group role changes update the glows at once.
- Safer: a hidden group role is treated as no role.
- Settings saved by a newer version are kept if you go back a version.
- `/hf debug` also shows the game's threat status, lead and % calls per enemy, and whether the
  game says it's hiding them.
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
