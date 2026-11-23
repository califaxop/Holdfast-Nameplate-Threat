# Holdfast: Nameplate Threat

**See how much threat you're generating, right on the enemy's nameplate.**

A glow around each enemy's nameplate shows where you stand at a glance. Holdfast reads the same threat states as the game's own aggro display (Options > Nameplates > Aggro Display) and draws them its way, in your colors and style. Tanks see whether they're holding it; damage dealers and healers see how close they are to pulling it. Built for tanks, damage dealers, healers and pet classes alike.

## Highlights
- **Tank:** holding it; someone closing in on you (the game's own "lead" state); lost it, with a "!".
- **Not the tank:** safe; about to pull it, with a "!"; on you, with "AGGRO" in a box beside the nameplate.
- **Works in dungeons and groups:** the game's threat states are hidden less often than threat %, and even when they are hidden, Holdfast has the game turn them into the right glow without reading them.
- **Replaces the game's aggro highlight:** on the nameplates it draws, the game's "Progressive" flare is hidden (switch it in the settings). The game's Flash and Health Bar Color options stay yours to use.
- **Every glow is yours to tune:** color, on/off, flash, strength and flash interval, in the style you like: nameplate border, outline, pixel lines or autocast sparkles.
- **Fits your UI:** works on FlareUI's and EllesmereUI's nameplates, in their look. The "!" stays clear of the elite icon, raid marker and enemy buffs.
- **Pet tanking:** follows your Voidwalker or other pet: holding, someone catching up, or lost.
- **Smart role:** uses your group-finder role; with none set, it acts like solo.

## Quick start
1. Turn on enemy nameplates (default key **V**).
2. Type `/hf` and check **My role** and **Whose aggro to show**.
3. Use the **Preview** buttons on your target to tune the look.

## Commands
| Command | Does |
|---|---|
| `/hf` | Open settings |
| `/hf debug` | Show the threat states the game gives right now |

## Good to know
- Holdfast no longer shows a threat %: in groups the game hides it too often to be reliable. The three states (safe / close / on you, or holding / close / lost) come from the game itself.
- When even the states are hidden and the client can't turn them into glows, Holdfast falls back to "on you or not".

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose): there's a short form for each. The settings window has a "Feedback" button with this link too.

## Recent changes
- **5.0.0:** Holdfast now restyles the game's own threat display: it reads the same threat states as the game's aggro highlight (for tanks, how far ahead of the next highest you are; for everyone else, how close you are to pulling it) and draws them with your glows. Not the tank: a "!" when you're about to pull it, and "AGGRO" in a box beside the nameplate when it's on you; the tank: a "!" when you've lost it. The in-between state is back in dungeons and groups, even when the game hides threat. The game's "Progressive" flare is hidden where Holdfast draws (switch in the settings). The threat %, its settings and the "Warn at" slider are gone: in groups the game hides them too often to be reliable.
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
