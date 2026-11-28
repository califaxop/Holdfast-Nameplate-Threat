# Holdfast: API compatibility (WoW: Forever, Interface 16001)

Sources, in order of trust:
1. **In game:** results the user reported from Forever (`/hf debug`, `/hf tank`, `/hf tip`, and the
   AggroGlow 3.x predecessors).
2. **Docs:** the client's generated API documentation (`Blizzard_APIDocumentationGenerated`) and
   Blizzard's own UI code, from the Forever branch of the game's UI source.
3. **Code:** Holdfast's own use, guarded as described.

Verification status:
- **Verified in game**: observed on Forever.
- **Docs**: present in Forever's API docs with this signature; behavior not yet observed.
- **Unverified**: an assumption; noted as such.

"Secret" means a returned value can be hidden from addons: an addon can pass it to some calls,
but can't compare it, test it or do arithmetic on it. `issecretvalue(v)` says whether it is.

## Threat

| API | Signature (docs) | Returns | Secret when | Holdfast uses it for | Status |
|---|---|---|---|---|---|
| `UnitDetailedThreatSituation` | `(unit, mobUnit)` | `isTanking, status, scaledPercentage, rawPercentage, rawThreat` (docs: not nilable; in practice nothing when the unit isn't on the list) | threat **values** restricted (`SecretWhenUnitThreatValuesRestricted`) | Its hidden `isTanking` switches the glows when even the state is hidden; its scaled % is the % (readable: compared with "Warn at"; hidden: drawn by the game) | **Verified in game:** isTanking and % hidden in a party in combat (5.0.2); readable solo |
| `UnitThreatSituation` | `(unit [, mobUnit])` | `status` 0–3, or nil when not on the list | threat **state** restricted (`SecretWhenUnitThreatStateRestricted`) — a separate restriction | Engagement (non-nil); on the followed unit (2–3); not the tank: about to pull (1); tank: someone has more (2) | **Verified in game:** readable in a party in combat (`status=0`, `status=3`, 5.0.2) |
| `UnitThreatLeadSituation` | `(unit, mobUnit)` | 0–3: how far the unit leads the second on threat (always 3 if not first); nil if no mob | threat state restricted | Tank: someone closing in (1–2) | **Verified in game:** readable in a party in combat (`lead=3`, `lead=0`, 5.0.2). Blizzard's nameplates use it for tanks |
| `UnitThreatPercentageOfLead` | `(unit, mobUnit)` | number or nil | threat values restricted | Diagnostics only | **Verified in game:** hidden in a party (5.0.2) |
| `C_Secrets.ShouldUnitThreatStateBeSecret` | `(unit [, mobUnit])` | bool | never | Diagnostics only | **Verified in game:** false in a party (5.0.2) |
| `C_Secrets.ShouldUnitThreatValuesBeSecret` | `(unit, mobUnit)` | bool | never | Diagnostics only | **Verified in game:** true in a party (5.0.2) |
| `GetThreatStatusColor` | `(status)` | r, g, b | — | `/hf tank` probe only | Docs |
| `C_CurveUtil` curves, `Curve:Evaluate` | — | — | — | Not used | **Verified in game:** turning a hidden value into a glow through curves was refused for addons (AggroGlow 3.6) |
| `C_TooltipInfo.GetUnit` | `(unit [, hideStatus])` | tooltip data | lines may be hidden | `/hf tip` probe only | **Verified in game:** no readable "% Threat" line in a party (AggroGlow 3.8) |

Status values (`UnitThreatSituation`): 0 on the list, not near the top; 1 higher threat than the
tank, not tanking (about to pull); 2 tanking, but not the highest threat (about to lose it);
3 tanking securely. Blizzard's code for its nameplate flare: DPS see `UnitThreatSituation`,
tanks see `UnitThreatLeadSituation`, and only in a party (`UnitInParty("player")`).

Pull thresholds: in Classic, an enemy changes target when another unit passes 110% of the
current target's threat in melee range, 130% at range. Not verified on Forever. The scaled %
from `UnitDetailedThreatSituation` has long been described (community API references, not
Forever's docs, which give no description) as already relative to that threshold, reaching 100
when the unit would pull. Milestone 2 must check this in game before relying on it.

## Secret values

| API | Signature | Notes | Status |
|---|---|---|---|
| `issecretvalue` | `(value) -> bool` | Holdfast wraps it as `ns.isSecret`; `ns.Readable(v)` = not nil and not secret. Falls back to "never secret" on a client without it | Docs; used in game since 3.x |
| `Frame:SetAlphaFromBoolean` | `(value, alphaIfTrue = 1, alphaIfFalse = 0)` | Accepts a secret boolean from addons (`SecretArguments = AllowedWhenTainted`). How hidden `isTanking` drives the glows | **Verified in game** (the glows switch in party combat) |
| `Region:SetVertexColorFromBoolean` | `(value, colorIfTrue, colorIfFalse)` | Accepts a secret boolean | Docs; not used yet |
| `FontString:SetFormattedText` / `SetText` | `(format, ...)` / `(text)` | Accept secret arguments from addons (`AllowedWhenTainted`); the game draws the text. How a hidden threat % is shown | **Verified in game:** a hidden threat % is drawn (5.1.0, in a party) |

## Units and groups

| API | Signature | Secret when | Notes | Status |
|---|---|---|---|---|
| `UnitExists`, `UnitCanAttack`, `UnitIsDead`, `UnitAffectingCombat` | `(unit)` / `(unit, other)` | not marked | Still guarded with `ns.Readable` | Docs; used in game |
| `UnitIsUnit` | `(a, b)` | unit comparison restricted | Guarded | Docs |
| `UnitGroupRolesAssigned` | `(unit) -> "TANK" / "HEALER" / "DAMAGER" / "NONE"` | unit identity restricted | Guarded since 5.0.2 (hidden = no role) | Docs |
| `IsInGroup`, `IsInRaid`, `GetNumGroupMembers`, `GetNumSubgroupMembers` | — | — | | Docs; used in game |

## Group units

| Token | Notes | Status |
|---|---|---|
| `partyN` / `partypetN` (N 1–4), `raidN` / `raidpetN` (N 1–40) | Group members and their pets, asked about with `UnitThreatSituation`. `raidN` includes you; skipped with `UnitIsUnit(token, "player")` | Docs (unit tokens); not yet seen in game with Holdfast 5.2.0 |
| Guardians, totems, other summons | No unit token for addons (only their nameplates). Can't be asked about; an enemy on one shows as "unknown" | Docs: no token type for them |

## Nameplates

| API / structure | Notes | Status |
|---|---|---|
| `C_NamePlate.GetNamePlateForUnit(unitToken, includeForbidden = false)` | Returns the plate. Holdfast passes `false` and skips forbidden plates | Docs; used in game |
| `C_NamePlate.GetNamePlates()` | No arguments on Forever | Docs; used in game |
| `plate.namePlateUnitToken`, `plate.UnitFrame` | | Used in game |
| `UnitFrame.HealthBarsContainer.healthBar` (also `UnitFrame.healthBar`) | The bar Holdfast frames | Blizzard_NamePlates.xml; used in game |
| `healthBar.selectedBorder` | Its atlas is copied for the border glow | xml; used in game |
| `UnitFrame.RaidTargetFrame`, `.ClassificationFrame`, `.AurasFrame.BuffListFrame` | Left of the bar; the "!" and % go past them | xml; used in game (4.1.1) |
| `UnitFrame.aggroHighlightBase`, `.aggroHighlightAdditive`, `.aggroHighlightShown`, `:UpdateAggroHighlight()` | The game's "Progressive" flare. Holdfast hides the two textures, hooks the method (`hooksecurefunc`), and reads `aggroHighlightShown` to give the flare back | NamePlateUnitFrame.lua; hiding used in game (5.0.0); giving back: new in 5.0.2, not yet seen in game |

### Other nameplate addons (their own tables, validated before use)

| Addon | What Holdfast reads | Fallback |
|---|---|---|
| EllesmereUI | `EllesmereNameplates_NS.plates[unit]` (a table, shown), its `.health`, `.levelText` / `.hpText` font | The game's plate |
| FlareUI | `FlareUI.Nameplates.PartsFor(plate)` (pcall), its `.root` / `.holder` / `.box` / `.health`, `.level` / `.name` font, `.levelFrame` / `.levelBorder` backdrops | The game's plate |

## Events

| Event | Payload | Holdfast | Status |
|---|---|---|---|
| `NAME_PLATE_UNIT_ADDED` / `_REMOVED` | `unitToken` | Track / untrack a plate | Docs; used in game |
| `UNIT_THREAT_LIST_UPDATE` | `unitTarget` (the enemy; one token, `UniqueEvent`) | Update that plate, or all plates (batched) when the token isn't a nameplate's | Docs; used in game |
| `UNIT_THREAT_SITUATION_UPDATE` | `unitTarget` (whose situation changed) | All plates, batched | Docs; used in game |
| `PLAYER_REGEN_ENABLED` / `_DISABLED`, `GROUP_ROSTER_UPDATE`, `PLAYER_TARGET_CHANGED`, `UNIT_PET`, `PLAYER_ENTERING_WORLD` | | All plates, batched (entering world: rescan) | Docs; used in game |
| `PLAYER_ROLES_ASSIGNED` | — | All plates, batched | Docs; new in 5.0.2 |

## Rendering

| API | Notes | Status |
|---|---|---|
| `Texture:SetAtlas`, `SetDesaturated`, `SetVertexColor`, `SetBlendMode` | Glows and the "!" | Used in game |
| `Region:SetSnapToPixelGrid(false)`, `SetTexelSnappingBias(0)` | Glows glide with the bar instead of jumping a pixel at a time | Docs; used in game (4.0.4) |
| `AnimationGroup` with an `Alpha` animation, `BOUNCE` looping | The flash | Used in game |
| `OnUpdate` scripts | Pixel and autocast glows, one driver each while visible | Used in game |
| `BackdropTemplate` | The % box | Used in game |

## Timing

| API | Notes | Status |
|---|---|---|
| `C_Timer.After(0, fn)` | Next-frame merge of events | Used in game since 4.0.2 |
| `C_Timer.NewTicker(1, fn)` / `:Cancel()` | The in-combat safety check | Docs; used in game (the 0.25 s ticker before 5.3.0) |
| `debugprofilestop()` | Milliseconds, for `/hf perf`'s average update time | Docs (FrameScript) |

## Alerts and overview

| API | Notes | Status |
|---|---|---|
| `PlaySound(soundKitID [, channel])` | `SOUNDKIT.RAID_WARNING` (8959, in Forever's SoundKitConstants) on "Master" | Docs |
| `UnitName(unit)` | Secret when unit name identity is restricted: never compared or read, only handed to `SetFormattedText` | Docs |
| `GetTime()` | The alerts' 2-second gap | Docs |

## Diagnostics

| API | Notes | Status |
|---|---|---|
| `C_AddOns.GetAddOnMetadata(addon, field)` | The version in `/hf status` (falls back to `GetAddOnMetadata`) | Docs |

## Testing an API in game

- `/hf scan` (any time), and `/hf debug` (on: the same, then again at every state change): per enemy, the followed unit's `isTanking` (`on you=`),
  `status=`, `lead=`, `pct=`, `ofLead=`, and `secret: state= values=`. Each shows a value,
  `nil`, `<hidden>`, `error` (the call failed) or `n/a` (not in this client).
- `/hf threat [unit]`: one enemy's state, who it's on, every call's answer and everyone's status on it.
- `/hf tank`: probes on your target, including `SetAlphaFromBoolean` with the status.
- `/hf tip`: whether the tooltip's threat line is readable.

Run each solo, in a party out of combat and in a party in combat, and note which.

## Blizzard UI parts (the settings windows, Settings.lua; source: Classic Era 1.15.9's Blizzard_SharedXML and Blizzard_Settings_Shared)

| Part | Use | Status |
|---|---|---|
| `SettingsFrameTemplate` (`NineSlice.Text` title, close button) | the settings window and its pop-ups | Verified in WoW Forever (Hereabouts 2.1.0) |
| Atlases `Options_InnerFrame`, `Options_CategoryHeader_1`/`_2`, `Options_List_Active`, `Options_List_Hover`, `Options_HorizontalDivider` | the settings window's art (the header atlas is taller than its band, which is at its top; the inner frame's divider is at x 212) | Verified in WoW Forever (Hereabouts 2.1.0) |
| Atlases `checkbox-minimal`, `checkmark-minimal`; `checkmark-minimal-disabled` | checkboxes | Verified in WoW Forever (Hereabouts 2.1.0); the disabled tick: Documentation |
| `MinimalSliderWithSteppersTemplate`, `MinimalSliderWithSteppersMixin` (`Init`, `RegisterCallback(Event.OnValueChanged)`, `Label.Right`, `FormatValue`) | sliders | Verified in WoW Forever (Hereabouts 2.1.0) |
| `ScrollFrameTemplate`, `SearchBoxTemplate`, `UIPanelButtonTemplate`, `InputBoxTemplate` | pages, search, buttons, text boxes | Verified in WoW Forever (Hereabouts 2.1.0) |
| Textures `UI-SpellbookIcon-PrevPage/NextPage-*`, `UI-Common-MouseHilight` | the arrows either side of a choice | Documentation (in the game since vanilla); not yet seen |
| `ColorPickerFrame` (`SetupColorPickerAndShow`, else the older fields) | colour squares | In use before (the older kit) |

