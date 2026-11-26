# Holdfast: Nameplate Threat

**See at a glance who has aggro, right on the enemy's nameplate.**

A glow around each enemy's nameplate shows at a glance whether it's attacking you, in your colors and style. Tanks see whether they're holding it; damage dealers and healers see whether they've pulled it. Built for tanks, damage dealers, healers and pet classes alike.

## Highlights
- **Tank:** green while it's on you (or your pet); red with a "!" when it's on someone else.
- **Not the tank:** green while it's on someone else; red with a "!" once it's on you.
- **Works in dungeons and groups:** even when the game hides threat, it still lets Holdfast use its "is it attacking you" answer, and the glows follow it.
- **Replaces the game's aggro highlight:** on the nameplates it draws, the game's "Progressive" flare is hidden (switch it in the settings). The game's Flash and Health Bar Color options stay yours to use.
- **Every glow is yours to tune:** color, on/off, flash, strength and flash interval, in the style you like: nameplate border, outline, pixel lines or autocast sparkles.
- **Fits your UI:** works on FlareUI's and EllesmereUI's nameplates, in their look. The "!" stays clear of the elite icon, raid marker and enemy buffs.
- **Pet tanking:** follows your Voidwalker or other pet.
- **Smart role:** uses your group-finder role; with none set, it acts like solo.

## Quick start
1. Turn on enemy nameplates (default key **V**).
2. Type `/hf` and check **My role** and **Whose aggro to show**.
3. Use the **Preview** buttons on your target to tune the look.

## Commands
| Command | Does |
|---|---|
| `/hf` | Open settings |
| `/hf icon` | Turn the "!" on or off |
| `/hf debug` | Show what the game says right now (is each enemy on you) |

## Good to know
- Holdfast shows two states only (on you or not): in groups the game hides threat % and how close anyone is too often for more to be reliable.
- The game has its own aggro display (Options > Nameplates > Aggro Display). Holdfast hides its "Progressive" flare where Holdfast draws, so you don't see both; its Flash and Health Bar Color options can be used alongside Holdfast.
- Shown only on enemies fighting you, your pet or your group. "Only in a party or raid" in the settings keeps it off when you're solo (unless your pet tanks).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose): there's a short form for each. The settings window has a "Feedback" button with this link too.

## Recent changes
- **5.0.2:** Fixes from a full code review. "Whose aggro: My pet" with no pet out no longer shows your own aggro. Holdfast reuses its glow frames instead of building new ones whenever a nameplate switches between the game's and FlareUI's / EllesmereUI's drawing or the glow style changes, hooks each nameplate once, and drops five unused glow sets per nameplate: lighter over a long session. A threat update for your target now shows at once, turning off "Replace the game's aggro highlight" brings the game's flare straight back, and group role changes apply at once. The settings window is readable again with EllesmereUI installed, and its look follows EllesmereUI or FlareUI on its own (no style settings). `/hf debug` also shows the game's threat status calls per enemy.
- **5.0.1:** Housekeeping: the aggro diagnostic's helper frame is now named HoldfastProbeFrame (it had a leftover generic name from the AggroGlow days), so it can't clash with another addon's.
- **5.0.0:** Simpler and reliable in dungeons: two states, from the game's "is it attacking you" answer, which addons can still use when the game hides threat. Tank: green while it's on you, red with a "!" when it isn't. Not the tank: green while it's on someone else, red with a "!" once it's on you. The game's own "Progressive" aggro flare is hidden on the nameplates Holdfast draws (switch in the settings). The threat %, the in-between "close" glow, the "Warn at" slider and reading threat from tooltips are gone: in groups the game hides those too often to be reliable.
- **4.1.1:** Fixed: on the game's nameplates, the "!" and % no longer sit on the elite / rare icon, the raid marker or the enemy's buffs (left of the bar): they go past whichever of those is showing, and follow as buffs come and go.
- **4.1.0:** Works on FlareUI's and EllesmereUI's nameplates (they hide the game's, so the glow and % were invisible there): the glow and % now sit on their plates, in their font, with a % box like their level box. New glow styles for everyone (Glows, Glow style): nameplate border, outline, pixel lines or autocast sparkles. The settings window follows EllesmereUI's style too.
- **4.0.4:** No more shaking: the glow, threat % and "!" move smoothly with the nameplate's health bar. The threat % box now wears the same art as the nameplate's level box (and its yellow outline while the mob is your target), and the "!" is sharper and brighter.
- **4.0.3:** Native look: the threat % box on nameplates and the settings use the game's own tooltip border in bronze (without FlareUI style).
- **4.0.2:** Lighter in group combat: bursts of threat updates are handled once per frame.
- **4.0.1:** The "Report a bug / suggest" link box is solid now and stays put over the settings window until you close it.
- **4.0.0:** AggroGlow is now **Holdfast** (another addon shared the old name and folder). New folder and commands (`/hf`); your settings start fresh once. Remove the old AggroGlow folder if it's still there.
- **3.9.1:** New "Report a bug / suggest" button in the settings, linking to a short feedback form.
- **3.9.0:** Simpler glows: holding / lost for tanks; safe / close / on you otherwise. Flash interval per glow; % for non-tanks, capped at 100%, now in a small XP Planner-style box left of the nameplate; "!" (a tinted quest icon) replaces the % at 100%, and marks lost aggro for tanks.
- **3.8.1:** Role and pet settings no longer interfere; no group role set acts like solo.
- **3.8.0:** Separate glows for tank and not-the-tank, with a My role setting.
- **3.7.1:** Pet tanking: orange when you're catching up, red when it's on you.
- **3.7.0:** Threat read from tooltips in combat; % placement options.
