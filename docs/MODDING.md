# Modding (preview, API 1)

Mods are loose folders. Nothing in the original games is modified; a mod only adds or
overrides files in the launcher's resource index at startup.

```
PoC Data/mods/
  enabled.json            ["base-pack", "yugis-gods"]   (load order; later wins)
  yugis-gods/
    mod.json
    assets/               mirrors PoC Data/resources/  (e.g. assets/yugi/card/slifer.png)
```

## mod.json

| Field | Required | Notes |
|---|---|---|
| `id` | yes | `a-z 0-9 _ -`, 2-40 chars, **must equal the folder name** |
| `name`, `version` | yes | Display strings |
| `api` | yes | Must be `1` |
| `games` | no | Subset of `yugi`, `kaiba`, `joey`. Default: all. Files under another game's folder are rejected |
| `engine` | no | `faithful` (default). `ocg` is reserved and skipped for now |
| `requires` | no | Mod ids that must be enabled **earlier** in `enabled.json` |
| `scripts` | no | Up to 8 GDScript files, `scripts/<name>.gd` (subfolders allowed). See *Scripts* below. They only load when the player turns on **Allow mods that run code** |
| `author`, `description` | no | |

## Rules the loader enforces

- Invalid manifests, missing dependencies and unsupported engines are skipped, never fatal.
- Paths are matched case-insensitively, like the base index.
- `common/bin/*`, `common/db/*`, `inventory.json` and `voice_manifest.json` cannot be replaced
  by a mod yet. Card tables will be **merged** in a later step instead of overwritten.
- `Assets.mod_overrides`, `Assets.mod_rejected` and `Assets.mod_skipped` report what happened.

## The Mods screen (launcher)

The **package button** at the bottom-left of the launcher, next to the gear and the speaker, opens it.
A gold dot on the button means at least one mod is active.

- **Tick** a mod to enable it, untick to disable. Changes apply immediately; no restart needed.
  Enabling a mod also enables the installed mods it `requires`, placed before it.
- **Arrows** change the load order (later mods override earlier ones). A mod whose dependency
  loads *after* it shows as *Skipped* with the reason.
- **Install .zip…** accepts a zip with `mod.json` at its root or inside a single top-level
  folder. Installing never enables the mod by itself. If the id is already installed you are
  asked before it is replaced.
- **Trash** deletes the mod's folder (after confirmation). `slots.json` is kept, so reinstalling
  gives its cards the same ids.
- **Open folder** opens `PoC Data/mods/` in your file manager (hidden on Android, which shows
  the path instead).

The installer refuses a zip as a whole if any entry has an absolute path, a drive letter,
backslashes that normalise into `..`, or `..` segments; it extracts to a hidden temporary
folder first, limits the size (64 MB per file, 256 MB, 5,000 files) and only then moves it into
place. Mods in this step contain data only (cards and files), no code.

## Cards (`cards.json`, next to `mod.json`)

A list of cards. Example: `docs/examples/dummy-card-mod/`.

| Field | Notes |
|---|---|
| `key` | `a-z 0-9 _`, unique inside the mod. The card is identified as `<mod id>:<key>` |
| `names`, `descriptions` | `{ "eng": "...", "spa": "..." }`; `eng` required, other languages fall back to it. Name ≤ 60 chars |
| `category` | `monster` (default), `spell`, `trap` |
| `atk`, `defense` | Multiples of 10, 0-5110 (the table stores them in 9 bits) |
| `level` | 0-15 |
| `attribute` | `none light dark water fire earth wind`. **No `divine` yet** (see limits) |
| `type_id` | 1-20 (1 Dragon, 2 Zombie ... 20 Reptile; same list as the original) |
| `monster_kind` | `normal effect fusion ritual` |
| `games` | Where the card can be obtained. Default: the mod's `games` |
| `image` | File name (`.png`/`.webp`, no folders) placed in `assets/common/card/` **and** `assets/common/mini/`. `null` = card back |
| `password` | 8 digits, optional |

**Ids.** Each card gets a stable internal id the first time it loads, remembered in
`PoC Data/mods/slots.json` (`"<mod>:<key>"` → id). Ids are taken from 1919 downwards (1920-1999 is a special range in the engine), skipping
base cards and their `id+2000` variants. Decks, saves and replays store this id, so it never
changes; **do not delete `slots.json`**. The table *index* is recomputed on every load.
Cards are appended after the last base card; the base tables use 1,114 indices and mods can extend them up to index 0x7ff (2,047).

**Owning mod cards.** The deck editor lists only cards that have art *and* at least one copy in
the save. A mod card therefore starts hidden. The collection is `system.json` → `collection`
(`"<id>": copies`); `--unlock-all` grants 3 copies of every card with art, mod cards included.
Mod cards are kept out of the native `system.dat` block that the game validates at start-up, so
they survive that step (`core/mod_save.gd`), but they are not written to an exported `system.dat`
and are dropped when one is imported.

**Effects are not part of this step.** A card added this way behaves as a plain monster
(or does nothing, for spells/traps) until the effect hook exists.

## Limits to know about

- Divine attribute needs UI icons and a prop-table value that the original never used. Use
  `dark`/`light` as a stand-in for now.
- Deck-editor *name* sorting uses a precomputed table (`card_sort*.bin`); mod cards sort first.
- Where mod cards show up is decided by `games` (pack bits), exactly like base cards.
- Code that changes the enabled mods must call `Assets.reindex()` then `CardDB.load_db()`;
  the Mods screen does both.

## Tooling

```
python -m pocx.mods validate path/to/yugis-gods     # run from tools/ or with PYTHONPATH=tools
python -m pocx.mods inspect "PoC Data/resources" game/duel   # table capacity, free ids, image sizes
godot --headless --path game --script res://tests/mod_registry_test.gd -- --storage=<empty dir> --data=<empty dir>
godot --headless --path game --script res://tests/mod_cards_test.gd    -- --storage=<empty dir> --data=<empty dir>
godot --headless --path game --script res://tests/mod_manager_test.gd  -- --storage=<empty dir> --data=<empty dir>
godot --headless --path game --script res://tests/mods_dialog_test.gd  -- --storage=<empty dir> --data=<empty dir>
```

## Not implemented yet

LAN mod-version handshake, divine attribute icon, name-sort ranks for mod cards, installing from a
folder or URL, and the `ocg` engine.

## Scripts (card effects)

A card asks for an effect with `"effect": "<key>"` in `cards.json` (`a-z 0-9 _`). The effect itself
is a **GDScript file inside the mod**, listed in `mod.json`:

```json
"scripts": ["scripts/slifer.gd"]
```

The repo has no card-specific code: `game/core/mod_script.gd` (`ModScript`) is the base class and
`game/duel/core/mod_duel.gd` (`ModDuel`) forwards the engine points where effects happen to the
scripts of the active mods. With no scripts the duel engine behaves exactly as before.

```gdscript
extends ModScript

func _init() -> void:
	effects = ["my_effect"]      # the cards.json "effect" keys this script implements

func on_stats(p: int, z: int, index: int, out: int) -> void:
	if is_mine(index):           # a card with one of my effect keys
		m.set_u32(out + 4, 3000) # ATK lives at out + 4, DEF at out + 8
```

Hooks (override only what you need; the ones returning `Variant` return `null` for "not handled",
and the engine then runs the original code):

| hook | when |
|---|---|
| `on_setup()` | once, after `duel`, `m` (memory) and `cards` are set |
| `on_tick()` | every engine step (`FUN_0053dbf0`) |
| `on_stats(p, z, index, out)` | after the engine computed the stats of a face-up monster |
| `on_placed(p, z, index)` | a card was placed on the field by a summon |
| `on_end_phase()` | first tick of an End Phase; queue work with tag `"end_phase"` and the phase waits for it |
| `can_summon_from_hand(p, idx)`, `cpu_can_summon(idx)` | summon availability for your cards |
| `human_summon(mode, alternate)`, `cpu_summon(...)` | the summon flows for your cards |

Helpers: `duel.schedule(delay, callable, tag)` (a callable that returns `false` runs again 5 ticks
later), `duel.has_pending(tag)`, `duel.engine_busy()`, `duel.place_key(p, z)`, `trace(text)`, and
every engine function on `duel` (`duel.f54e250(p, z, 1)` destroys the monster in a zone,
`duel.present("card_effect", {...})` plays the effect glow). Pass `--mod-trace` after `--` on the
command line to see `trace()` output.

If a hook you need does not exist, add it to `ModDuel` once: every mod can use it afterwards.

**Revive cards.** `"revive_by": [1008, "0x487"]` in `cards.json` lists the original cards (internal
ids, integers or hex strings) that may Special Summon the card from the Graveyard. This needs no
script: the original list only offers monsters of type < 0x15, and `ModDuel` adds mod cards that
name the revive card. Known ids: `0x3f0` Monster Reborn (both Graveyards), `0x447` Call of the
Haunted, `0x487` The Shallow Grave, `0x488` Premature Burial, `0x45c` Spear Cretin, `0x5f0`
Gilasaurus (own Graveyard).

**Security.** A script can do anything the game can. The Mods screen has **Allow mods that run
code**, off by default (stored in `mods/settings.json`); with it off, scripts never load and the
cards of those mods have no effect. Only install script mods from authors you trust.
`python -m pocx.mods validate <folder>` checks the manifest, that the script files exist, and
warns that the mod runs code.

The example mod is `docs/examples/slifer-sky-dragon/` (also released as `slifer-sky-dragon.zip`):
1000 ATK/DEF per card in hand, a 3-Tribute Normal Summon (human and CPU), -2000 ATK on monsters
the opponent summons in Attack Position (destroyed at 0), and a Special Summoned Slifer returns
to the Graveyard in the End Phase (a face-down one only once it is flipped up). Pair it with
`"limit": 1`. Use `type_id` 24 (the engine's "?" type, base 4000/4000, level 10) and `level` 10.
Not implemented for it: the "cannot be negated / no activation" rules.

Test scenarios (`game/scenarios/`, run with `godot --path game -- --scenario=<name> --mod-trace`,
with the mod installed and code allowed): `slifer_player`, `slifer_cpu`, `slifer_battle`,
`slifer_foe_summon`, `slifer_reborn` (Dark Hole, Monster Reborn, end the turn) and
`revive_ids_check` (identifies the revive card ids).

## Deck patches

A mod can change what the CPU opponent plays without replacing the original deck files. Put a
`deck_patches.json` next to `mod.json`:

```json
[
  {
    "file": "yugi/file/cpu*.json",
    "remove": { "main": [34] },
    "add":    { "main": ["test_dragon", "test_dragon", "test_dragon"] }
  }
]
```

- `file`: path relative to `resources/`, case-insensitive, `*` and `?` as wildcards. The opponent
  deck is picked per duel (by collection percentage and win streak), so use a wildcard to cover
  every variant: Yugi `yugi/file/cpu*.json`, Kaiba `kaiba/file/*.json`, Joey `joey/file/cpu_*.json`
  and `joey/file/ful_*.json`.
- `remove` / `add`: per zone (`main`, `side`, `fusion`). A card is an internal id (number), the key
  of a card from the same mod (`"obelisk"`), or `"mod:key"`. The first copy of each listed card is
  removed, then the new cards are appended.
- Patches run in mod load order. A patch that would leave a zone out of range (main 40-80, side
  and fusion 0-15) or names an unknown card is ignored whole, with a warning in the log.
- The mod's `games` list applies: a patch for `yugi/...` only runs if the mod declares `yugi`.
- Only the CPU deck is patched. The player's own deck is never touched.

## Copy limit (`limit`)

`"limit": 1` (1, 2 or 3) in a card entry caps the copies per deck, in every game and whether or
not the LIMITED option is on. It feeds `NativeCardLimits.copy_limit`, the function the deck editor
already uses for Change of Heart, Raigeki and Monster Reborn. A deck that already holds more copies
is not trimmed automatically.

## Reward drops (`reward_weight`)

Beating the CPU gives random cards drawn uniformly from the cards obtainable in that game (1 per
duel; the code gives 3 for a match). A mod card whose `games` include that game is part of that pool
automatically, with the same chance as any other card. `"reward_weight": N` (1 to 1000) makes it
appear N times in the draw, so a pool of about 800 cards plus a weight of 40 gives roughly 5% per
drawn card. A card with `"limit": 1` that the player already owns is removed from the draw.
