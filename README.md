# Holdfast: Nameplate Threat

**See at a glance who has aggro, right on the enemy's nameplate.**

A glow around each enemy's nameplate shows at a glance whether it's attacking you, and how safely, in your colors and style. Tanks see whether they're holding it or about to lose it; damage dealers and healers see whether they're about to pull it, or have. Built for tanks, damage dealers, healers and pet classes alike.

## Highlights
- **Tank:** green while it's on you (or your pet); orange when someone is closing in on you; red with a "!" when it's on someone else.
- **Not the tank:** green while it's on someone else; orange when you're about to pull it; red with a "!" once it's on you.
- **Works in dungeons and groups:** it follows the same threat states as the game's own nameplate aggro display, which the game keeps readable in groups.
- **Threat %** beside the nameplate (optional): yours, or, as the tank, the closest other's. In groups the game hides the number from addons, so Holdfast lets the game draw it.
- **Replaces the game's aggro highlight:** on the nameplates it draws, the game's "Progressive" flare is hidden (switch it in the settings). The game's Flash and Health Bar Color options stay yours to use.
- **Every glow is yours to tune:** color, on/off, flash, strength and flash interval, in the style you like: nameplate border, outline, pixel lines or autocast sparkles.
- **Fits your UI:** works on FlareUI's and EllesmereUI's nameplates, in their look. The "!" stays clear of the elite icon, raid marker and enemy buffs.
- **Pet tanking:** follows your Voidwalker or other pet, or you and your pet together.
- **For healers:** "The group's tanks" shows whether a tank holds each enemy (green), is about to lose it (orange), or it's loose on someone else (red).
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
| `/hf debug` | Show what the game says for each enemy now, and at every change while it's on |
| `/hf scan` | Show what the game says for each enemy now |
| `/hf perf` | Show how much work Holdfast is doing (add `reset` to start counting again) |

## Good to know
- Orange comes from the game's own threat states in groups (someone closing in on the tank, or you above the tank but not yet pulling it). Solo, where addons can read threat %, it also starts at **Warn at** (default 80% of pulling it).
- The game has its own aggro display (Options > Nameplates > Aggro Display). Holdfast hides its "Progressive" flare where Holdfast draws, so you don't see both; its Flash and Health Bar Color options can be used alongside Holdfast.
- Shown only on enemies fighting you, your pet or your group. "Only in a party or raid" in the settings keeps it off when you're solo (unless your pet tanks).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose): there's a short form for each. The settings window has a "Feedback" button with this link too.

## Recent changes
- **5.3.0:** Lighter: Holdfast now works from the game's threat events instead of checking every nameplate four times a second (a once-a-second check runs only in combat), merges bursts of events into one update per enemy, and only redraws a nameplate when something on it changes. Moving glows (pixel lines, autocast sparkles) share one animation driver that stops when none are showing. FlareUI and EllesmereUI support now lives in its own module. New `/hf perf` shows the work it's doing.
- **5.2.0:** Knows who each enemy is attacking: you, your pet, a group tank, another member or a member's pet (shown by `/hf debug` and `/hf scan`). Two new "Whose aggro" choices: **Me and my pet** (either of you holding it is good) and **The group's tanks** (any tank holding it is good; for healers, and with more than one tank). Your group is looked up once when it changes instead of on every update.
- **5.1.0:** Three states again, reliable in groups: orange when someone is closing in on you (tank) or you're about to pull it (not the tank), from the same threat states the game's own nameplates use, which the game keeps readable in groups. Optional threat % beside the nameplate (in groups the game draws the hidden number itself), with its distance and box opacity. "Warn at" for where threat % is readable (solo). New "Losing it / close" glow row and preview. `/hf scan` shows each enemy's state and where it came from.
- **5.0.2:** Fixes from a full code review. "Whose aggro: My pet" with no pet out no longer shows your own aggro. Holdfast reuses its glow frames instead of building new ones whenever a nameplate switches between the game's and FlareUI's / EllesmereUI's drawing or the glow style changes, hooks each nameplate once, and drops five unused glow sets per nameplate: lighter over a long session. A threat update for your target now shows at once, turning off "Replace the game's aggro highlight" brings the game's flare straight back, and group role changes apply at once. The settings window is readable again with EllesmereUI installed, and its look follows EllesmereUI or FlareUI on its own (no style settings). `/hf debug` also shows the game's threat status calls per enemy, at each change, and the new `/hf scan` shows them for every enemy at once.
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
