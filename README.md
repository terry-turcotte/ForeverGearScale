<p align="center"><img src="media/logo-256.png" alt="Forever Gear Scale logo" width="160"></p>

# Forever Gear Scale

A **WoW Forever** addon that answers "is this piece better for me?" right in the item tooltip.
It is built for **Retribution Paladins only**. It reads your **character sheet and talents**, runs a small Ret damage model on them, and tells you how much **DPS** the item you hover would gain or lose against what you wear. It is a DPS calculator only: Stamina, armor, mana and other defensive or sustain stats are not scored.

The DPS weights are **live**: they are worked out from your current stats, so they change as you gear. Hit is worth nothing once you are at the cap, crit is worth less once Vengeance never drops, and Intellect is worth more with Champion of the Light. Swaps are scored on the full model, not with linear weights, so a piece that takes you over the hit cap only gets credit for the hit that still counts.

It is the in-game version of the *Gear Scale* web page (Ret Paladin), with the same stat ids, scale and verdict rules. On other classes the addon does nothing.

```
Lionheart Helm
...
Gear Scale · Retribution                Upgrade
  DPS score  100 > 320                     +220
  Model                       +5.1 DPS (+1.8%)
  Shift: biggest stat swings
```

## Install

1. Download this repo (**Code → Download ZIP**, or `git clone`) and put it in the **Interface/AddOns** folder of your **WoW Forever** install. That is the Forever game folder, not the Classic Era or retail one. The folder must be named exactly `ForeverGearScale`: a ZIP download unpacks as `ForeverGearScale-main`, so rename it.
2. Restart the game, or `/reload`. Make sure **Forever Gear Scale** is ticked in the AddOns list on the character screen.
3. Hover any piece of gear.

## Usage

| Command | What it does |
|---|---|
| `/fgs status` | What was read from your character (AP, crit, hit, weapon, spell damage, talents), the model's DPS split, average Vengeance stacks, and anything it had to guess |
| `/fgs weights` | DPS points per 1 point of each stat (1 AP = 5), live from your stats; `*` marks the ones you pinned |
| `/fgs weight <stat> <points>` | Pins one stat's weight by hand (e.g. `/fgs weight crit 120`). It stops following the model |
| `/fgs unpin <stat>` | That stat follows the model again |
| `/fgs set target 63` | Target level (default: your level + 3, a raid boss) |
| `/fgs set judge 9` | Seconds between Judgements of Command (default 9) |
| `/fgs set execute 0.2` | Share of the fight spent under 20% health, where Hammer of Wrath is used (default 0.2) |
| `/fgs set vengeance\|champion\|arbiter <rank\|auto>` | Talent rank (Vengeance, Champion of the Light, Sacred Arbiter), if the client can't read it (or to test a build) |
| `/fgs set holystrike 0\|1` | Takes Holy Strike out of the rotation, or puts it back (default: in) |
| `/fgs spells` | The Hammer of Wrath, Holy Strike and Seal of Command numbers read from your spellbook (damage, weapon %, cooldown), with the tooltip text: paste it in a bug report if a number looks wrong |
| `/fgs talents` | Dumps what the talent API returns and the ranks read: paste it in a bug report |
| `/fgs reset` | Unpins everything; fight and talent settings back to default |
| `/fgs export` / `/fgs import <string>` | Copy weights as text: `str=10;agi=8.4;crit=166;…`. Imported stats are pinned. Old 3-axis strings (`str=10/0.3/0;…\|prio=…`) still import; only the DPS number is kept |
| `/fgs on` / `/fgs off` | Shows or hides the tooltip lines |

Hold **Shift** while hovering to see the 4 stats that move the score most, and how many special effects (on-use, procs) were not scored.

---

## 1. Plan

| # | Step | Status |
|---|---|---|
| 1 | Check the Forever addon API: Interface **16001**, modern `C_*` API with Midnight-era restrictions | ✅ |
| 2 | Stat vocabulary and **Ret weight table** matching the web page (other classes removed in 0.2) | ✅ |
| 3 | **Tooltip parser** (EN + FR) from item tooltip text to stat values | ✅ |
| 4 | **Scoring engine**: DPS score, delta, verdict. Defense and Sustain axes removed in 0.2 | ✅ |
| 5 | ~~Class/spec detection~~ removed in 0.2: Paladin only. Replaced by **reading the character sheet and talents** | ✅ |
| 6 | **Tooltip hook**: find the equipped item(s) in the slot, compare, write the result | ✅ |
| 7 | Slash commands: pin weights, fight and talent settings, import/export | ✅ |
| 8 | Offline tests with a stubbed game API + CI | ✅ |
| 9 | **In-game check on Forever**: verify API names, tooltip text and talent info on the live client | ⏳ needs a game client |
| 10 | **Live DPS weights** from a Ret model (Seal of Command, Holy Strike, Judgement, Hammer of Wrath, Vengeance, Champion of the Light) | ✅ |
| 10b | Check the model's spell numbers (Judgement of Command, Holy Strike, Hammer of Wrath) against Forever logs; they are read from spell tooltips since 0.2 | 🔜 |
| 11 | Settings panel (sliders) instead of slash commands only | 🔜 |
| 12 | French UI strings (the parser already reads French tooltips) | 🔜 |
| 13 | Own repository | ✅ |
| 14 | CurseForge packaging and upload (release ZIPs) | ✅ |

## 2. Architecture

It follows the hand-drawn sequence: **codebase ↔ Blizzard API**.

```mermaid
sequenceDiagram
    participant API as Blizzard API (WoW Forever client)
    participant Hook as Tooltip.lua (event)
    participant Stats as ItemStats.lua + Parser.lua
    participant Prof as Profile.lua + Character.lua + Model.lua
    participant Score as Scoring.lua

    API->>Hook: tooltip shows an item (TooltipDataProcessor post-call)
    Hook->>API: item link, equip slot, GetInventoryItemLink (what you wear)
    Hook->>Stats: input: stats from both gears
    Stats->>API: C_TooltipInfo.GetHyperlink(link) → tooltip lines
    Stats-->>Hook: { str = 18, hit = 1, ... } for each side
    Hook->>Prof: pull: character + weights
    Prof->>API: UnitAttackPower, GetCritChance, GetHitModifier, GetSpellBonusDamage, GetTalentInfo...
    Prof-->>Hook: live DPS weights, model DPS change for the swap, your pins
    Hook->>Score: compare(equipped, candidate, weights, model DPS change)
    Score-->>Hook: DPS score both sides, delta, verdict, top swings
    Hook->>API: pull UI to put the response (tooltip:AddDoubleLine)
```

### Files (loaded in this order)

| File | Role | Uses the game API? |
|---|---|---|
| `ForeverGearScale.toc`, `ForeverGearScale_Camelot.toc` | Manifest, `## Interface: 16001`. Same file twice, so the client finds it with either suffix rule | — |
| `Compat.lua` | Wraps the Blizzard calls, with fallbacks to older globals: `C_Item.GetItemInfoInstant`, `C_TooltipInfo.GetHyperlink` (or a hidden scan tooltip), `TooltipUtil.GetDisplayedItem`, `issecretvalue` | yes, only here |
| `Data/Stats.lua` | Stat ids and names, the same as the web page | no |
| `Data/Presets.lua` | **Fallback Ret DPS weights** (`NS.RET`), the web page's numbers, used only for stats the model doesn't cover | no |
| `Parser.lua` | Tooltip text to stats, English and French. Skips set bonuses, flavor text, *Use:* and *Chance on hit:* (counted as "not scored") | no |
| `ItemStats.lua` | Link to stats, with a cache. Removes enchants and gems so the equipped piece isn't favoured by its enchant | through Compat |
| `Model.lua` | **Ret damage model**: attack tables, Seal of Command, Holy Strike, Judgement, Hammer of Wrath, Vengeance stacks. Gives live weights and the exact DPS change of a swap | no |
| `Character.lua` | Reads the character sheet and talents (by name, EN + FR) into a model state. Secret or missing values fall back to the last good reading, then defaults | yes |
| `Scoring.lua` | DPS score, delta, verdict (*Upgrade / Downgrade / Sidegrade*), biggest swings | no |
| `Profile.lua` | Paladin check, then model weights + the Ret table + your pinned stats | yes |
| `Tooltip.lua` | Event hook + rendering. Handles rings and trinkets (best of 2 slots), two-handers (vs main + off hand), empty slots, your own equipped item | yes |
| `Commands.lua` | `/fgs` and import/export | yes |
| `Core.lua` | SavedVariables (`ForeverGearScaleDB`, migrated from 0.1), event wiring (gear, stats, talent changes, Shift key) | yes |

Logic files (`Parser`, `Model`, `Scoring`, `Data/*`) never touch the game API, so they are tested offline. Every Blizzard call goes through `Compat.lua` or is guarded with `pcall`. If Forever renames something, it fails quietly instead of throwing Lua errors.

### Scoring rules

- **DPS score** of an item = Σ (stat value × weight), with the live weights.
- **Delta** comes from the model: DPS with the new piece (your sheet − the equipped piece + the candidate) minus DPS now. The tooltip shows it as points (1 AP = 5 pts) and as real DPS with the % of your current DPS. Pinned stats use their weight instead.
- **Verdict**: *Upgrade* or *Downgrade* when the delta is more than 1% of the score (and at least 3 points), otherwise *Sidegrade*.
- Rings and trinkets are compared with both equipped pieces, and the slot with the best delta is shown ("vs Ring 2"). Hovering what you wear shows what it is worth over an empty slot.

### Scale (weights)

Same anchor as the web page: **1 Attack Power = 5 pts**.

### The Ret model

Each DPS weight is 5 × (DPS gained by 1 point of the stat) ÷ (DPS gained by 1 AP), measured at your current stats. The model covers:

- **Melee attack table** against the target level (default your level + 3): miss (9% cap vs a boss), dodge, glancing blows, crit suppression, weapon skill.
- **White swings** with your weapon DPS and speed, plus Attack Power.
- **Seal of Command**: 7 procs per minute, 70% weapon damage + 20% of spell damage. Slower weapons hit harder per proc, so weapon speed counts on weapon swaps.
- **Holy Strike** on cooldown (10 sec): a melee strike (melee hit and crit) for 50% weapon damage + 42.9% of spell damage as Holy, +20% with **Sacred Arbiter**.
- **Judgement of Command** every 9 sec (spell hit, melee crit): the normal damage, not the "if stunned" one, since bosses are never stunned.
- **Hammer of Wrath** on cooldown (6 sec) in the execute phase (melee hit and crit), counted as instant (Champion of the Light 5/5). Only from **level 44**, when Forever teaches it, and only if it is in your spellbook.
- **Spell numbers are read from your own spell tooltips**: Hammer of Wrath's damage and cooldown, Holy Strike's weapon %, bonus damage and cooldown, and the Judgement of Command damage from Seal of Command (English and French clients). This follows your rank and any Forever change. If none of the spells can be found (another client language, or no spell API), the built-in numbers below are used.
- **Vengeance**: +1% damage per rank per stack, 5 stacks, 30 sec. Every non-periodic hit above can crit and refresh it. The average stack count is solved exactly from your crit chance and hit rate, so crit is worth a lot at low crit and little once the buff never drops.
- **Champion of the Light**: 12% of Intellect per rank as spell damage, so Intellect picks up spell damage's value.
- Strength = 2 AP, 20 Agility = 1% crit, 54 Intellect = 1% spell crit.

Built-in spell values (`Model.CONST`, used only when the tooltips can't be read) are vanilla level-60 or pre-launch guide numbers. If a client's tooltip numbers already include your spell damage, spell damage would be counted twice: compare `/fgs spells` with a tooltip seen without gear. Forever reworked talents and some spells, so check `/fgs status` against your logs and adjust there. Not modelled: mana (running out of it), on-use and proc effects, set bonuses, % stat buffs such as Blessing of Kings.

### Forever API notes (checked November 2026)

- Forever is its own game type (client 1.60.x) with TOC **Interface 16001**. In game, `/dump select(4, GetBuildInfo())` should print `16001`. Sources disagree on the TOC suffix (`_Forever` vs. the internal `_Camelot`), so we ship a plain `.toc` plus `_Camelot.toc`.
- It runs the **modern addon API** (Midnight's), not Classic Era's. Use `C_Item.*`, `C_TooltipInfo.*` and `TooltipDataProcessor.AddTooltipPostCall` instead of the old `GetItemInfo` / `OnTooltipSetItem`. The addon still falls back to the old calls when the new ones are missing.
- Combat data can come back as *secret values*. We skip a tooltip when its item link is secret.
- To check in game: `/fgs debug` prints any error from the tooltip hook to chat.

## Development

```sh
# from this folder
lua5.1 tests/run.lua
```

`tests/run.lua` stubs the WoW API (items, equipped slots, character sheet, talents, tooltips), loads every file in TOC order, and checks the parser (EN/FR, weapon speed), the model (Vengeance chain against a simulation, hit cap, crit falloff, Champion of the Light, weapon speed, Hammer of Wrath from level 44 and only when known), spell tooltip parsing (EN/FR), scoring, reading the character (missing API, secret values), commands, saved-variable migration and the full tooltip flow (upgrade, equipped item, Shift details, rings, two-handers, empty slots). CI (GitHub Actions) runs it on every push and pull request.

### Versions and release tags

Releases follow CurseForge's three release types, read from the git tag name (the same rule the BigWigs packager uses):

| Tag | CurseForge type |
| --- | --- |
| `v0.1.0-alpha.1` | Alpha (contains `alpha`) |
| `v0.1.0-beta.1` | Beta (contains `beta`) |
| `v0.1.0` | Release (anything else) |

The `## Version:` line in both `.toc` files matches the tag without the `v`.

**To cut a release, bump `## Version:` in both `.toc` files and merge to `main`.** No manual tag is needed: `.github/workflows/release.yml` runs on every push to `main`, and when the version has no tag yet it creates `v<version>` on that commit and releases it. Pushes that don't change the version release nothing. Pushing a `v*` tag by hand also works.

The workflow:

1. runs the syntax check and the tests;
2. checks the tag name and that both `.toc` versions match it (`.github/scripts/package.sh`, which you can also run locally);
3. builds `ForeverGearScale-<version>.zip` (a `ForeverGearScale/` folder with the `.toc` files, Lua files, `Data/`, README and LICENSE);
4. creates the tag if it came from a version bump, then a GitHub release with that zip and a changelog built from the commits since the previous tag. Alpha and beta releases are marked as pre-releases;
5. uploads the zip to CurseForge with the matching release type, but only once these are set under *Settings → Secrets and variables → Actions*:
   - secret `CF_API_KEY`: a CurseForge API token (legacy.curseforge.com → Account → API tokens);
   - variable `CF_PROJECT_ID`: the project's numeric id;
   - variable `CF_GAME_VERSION_IDS`: comma-separated CurseForge game version ids for the Forever client.

   Without `CF_PROJECT_ID`, that step is skipped and only the GitHub release is made.

This addon started in the guild website repo ([patriotesazeroth-web](https://github.com/terry-turcotte/patriotesazeroth-web)) and was split out with its history.

## Logo

`media/logo.svg` is the source of the logo, with PNG exports at 512, 256 and 64 px; use `logo-512.png` as the CurseForge project logo. It is original artwork: a balance scale in a cog, with three bars (from the 0.1 versions, which scored DPS, Defense and Sustain). The lettering is [Cinzel](https://github.com/NDISCOVER/Cinzel) (SIL Open Font License), converted to outlines. `media/make_logo.py` regenerates the SVG. The `media/` folder is not included in the release zip.

In the game's AddOns list, both `.toc` files use a game icon (`## IconTexture: Interface\Icons\INV_Misc_Gear_01`), so no Blizzard file is copied into the addon. Clients without `IconTexture` support ignore the line.

## License

[MIT](LICENSE)
