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
| `UnitDetailedThreatSituation` | `(unit, mobUnit)` | `isTanking, status, scaledPercentage, rawPercentage, rawThreat` (docs: not nilable; in practice nothing when the unit isn't on the list) | threat **values** restricted (`SecretWhenUnitThreatValuesRestricted`) | `isTanking` only (on the followed unit or not) | **Verified in game:** all hidden in a party in combat; readable solo |
| `UnitThreatSituation` | `(unit [, mobUnit])` | `status` 0–3, or nil when not on the list | threat **state** restricted (`SecretWhenUnitThreatStateRestricted`) — a separate restriction | Engagement: is anyone of yours on the list (non-nil) | Docs. In a party: **not measured** (`/hf debug` shows `status=`) |
| `UnitThreatLeadSituation` | `(unit, mobUnit)` | 0–3: how far the unit leads the second on threat (always 3 if not first); nil if no mob | threat state restricted | Not used (diagnostics only) | Docs. Blizzard's nameplates use it for tanks. Not measured |
| `UnitThreatPercentageOfLead` | `(unit, mobUnit)` | number or nil | threat values restricted | Not used (diagnostics only) | Docs. Not measured |
| `C_Secrets.ShouldUnitThreatStateBeSecret` | `(unit [, mobUnit])` | bool | never | Not used (diagnostics only) | Docs. Not measured |
| `C_Secrets.ShouldUnitThreatValuesBeSecret` | `(unit, mobUnit)` | bool | never | Not used (diagnostics only) | Docs. Not measured |
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

## Units and groups

| API | Signature | Secret when | Notes | Status |
|---|---|---|---|---|
| `UnitExists`, `UnitCanAttack`, `UnitIsDead`, `UnitAffectingCombat` | `(unit)` / `(unit, other)` | not marked | Still guarded with `ns.Readable` | Docs; used in game |
| `UnitIsUnit` | `(a, b)` | unit comparison restricted | Guarded | Docs |
| `UnitGroupRolesAssigned` | `(unit) -> "TANK" / "HEALER" / "DAMAGER" / "NONE"` | unit identity restricted | Guarded since 5.0.2 (hidden = no role) | Docs |
| `IsInGroup`, `IsInRaid`, `GetNumGroupMembers`, `GetNumSubgroupMembers` | — | — | | Docs; used in game |

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

## Testing an API in game

- `/hf debug` (then again to stop): per enemy, the followed unit's `isTanking` (`on you=`),
  `status=`, `lead=`, `pct=`, `ofLead=`, and `secret: state= values=`. Each shows a value,
  `nil`, `<hidden>`, `error` (the call failed) or `n/a` (not in this client).
- `/hf tank`: probes on your target, including `SetAlphaFromBoolean` with the status.
- `/hf tip`: whether the tooltip's threat line is readable.

Run each solo, in a party out of combat and in a party in combat, and note which.
