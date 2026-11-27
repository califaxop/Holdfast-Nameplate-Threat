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
- **Alerts (optional):** a sound and / or a message on screen when an enemy turns red (you lost it, or it's on you), and if you like when it turns orange. Write your own message for each, choose for each whether the enemy's name goes after it (in white, so it stands out), and test each one. Never more than one every 2 seconds.
- **Threat overview (optional):** a small window listing the enemies on your nameplates, most dangerous first, with who each is attacking and the threat %. Filter it to only red, only orange, attacking you or attacking others.
- **Pet tanking:** follows your Voidwalker or other pet, or you and your pet together.
- **For healers:** "The group's tanks" shows whether a tank holds each enemy (green), is about to lose it (orange), or it's loose on someone else (red).
- **Smart role:** uses your group-finder role; with none set, it acts like solo.
- **Light:** it works from the game's own threat events and only redraws a nameplate when something on it changes.
- **For other addons:** `HoldfastAPI` lets other addons listen to Holdfast's threat changes (aggro gained or lost, unstable, secure, target changed).

## Quick start
1. Turn on enemy nameplates (default key **V**).
2. Type `/hf` and check **My role** and **Whose aggro to show**.
3. Use the **Preview** buttons on your target to tune the look.
4. Optional: turn on **Alerts** and the **Threat overview** in the same window.
5. Something not as expected? `/hf status` and `/hf threat` show what Holdfast sees; **Bugs & Feedback** (top right of the settings) sends it to us.

## Commands
| Command | Does |
|---|---|
| `/hf` | Open settings |
| `/hf overview` | Show or hide the threat overview (`/hf overview lost`, `unstable`, `me`, `others`, `all`: what it lists) |
| `/hf icon` | Turn the "!" on or off |
| `/hf status` | What Holdfast follows and why, its main settings, the nameplates it draws on |
| `/hf threat` | Everything about your target's threat (or `/hf threat focus`) |
| `/hf scan` | What the game says for each enemy now |
| `/hf debug` | The same, at every change while it's on |
| `/hf perf` | How much work Holdfast is doing (`/hf perf reset` to start counting again) |
| `/hf profile` | Count Holdfast's work for 10 seconds (or `/hf profile 30`) and report |
| `/hf report` | Bugs & Feedback: the form's link and a line to paste into it |
| `/hf reset` | Put every setting back to its default (asks first) |

## Good to know
- Orange comes from the game's own threat states in groups (someone closing in on the tank, or you above the tank but not yet pulling it). Solo, where addons can read threat %, it also starts at **Warn at** (default 80% of pulling it).
- The game has its own aggro display (Options > Nameplates > Aggro Display). Holdfast hides its "Progressive" flare where Holdfast draws, so you don't see both; its Flash and Health Bar Color options can be used alongside Holdfast.
- Totems and other guardians can't be asked about by addons: an enemy attacking one shows as "other" (guessed) in the overview.
- Shown only on enemies fighting you, your pet or your group. "Only in a party or raid" in the settings keeps it off when you're solo (unless your pet tanks).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug, have feedback or want a feature? Click **Bugs & Feedback** at the top right of the settings window (or type `/hf report`): it gives you the form's link and, for a bug, a line to paste into it with everything we need. Or [open an issue](https://github.com/califaxop/holdfast-nameplate-threat/issues/new/choose) directly: there's a short form for each.

## Recent changes
- **6.1.0:** "Bugs & Feedback" now sits at the top right of the settings window, next to the ×. It opens a window (like Questie's trace export) with the form's link to copy at the top, for bug reports, feedback and feature requests, and for a bug, one line to paste into the form with your version, the game client, what Holdfast follows, its settings and the glows showing; never your name, realm or guild. Also `/hf report`. The settings window is now solid and comes to the front when opened or clicked: with several addons' settings open, they no longer show through each other.
- **6.0.0:** **Three states again, reliable in groups:** orange when someone is closing in on you (tank) or you're about to pull it (not the tank), from the same threat states the game's own nameplates use, which the game keeps readable in groups. **Optional threat %** beside the nameplate (in groups the game draws the hidden number itself) and "Warn at" for solo. **Knows who each enemy is attacking**: you, your pet, a group tank, another member. **New "Whose aggro" choices:** Me and my pet; The group's tanks (for healers, and groups with two tanks). **Optional alerts** (sound and / or a message on screen, in your own words, when an enemy turns red, or orange) and an optional **threat overview** window (`/hf overview`). **A wider, two-column settings window.** **Lighter:** works from the game's events instead of checking every nameplate four times a second, and only redraws what changed. New diagnostics: `/hf status`, `/hf threat`, `/hf profile`, `/hf perf`, `/hf reset`. Other addons can listen to Holdfast's threat changes (HoldfastAPI). Also: fixes from a full code review ("Whose aggro: My pet" with no pet out no longer shows your own aggro; glow frames and nameplate hooks are reused instead of piling up), and the settings window is readable with EllesmereUI installed and takes EllesmereUI's or FlareUI's look on its own.
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
