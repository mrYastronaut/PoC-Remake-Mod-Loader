class_name ModScript
extends RefCounted
## Base class for mod scripts: GDScript files shipped inside a mod (mod.json "scripts") that give
## its cards effects the engine does not have built in. A script extends this class, lists the
## cards.json "effect" keys it implements in `effects`, and overrides only the hooks it needs.
## ModDuel calls the hooks; with no scripts loaded the duel engine behaves exactly as before.
##
## Scripts run with the full power of the game: they only load when the player has turned on
## "Allow mods that run code" in the Mods screen (see ModScripts).
## Docs: docs/MODDING.md ("Scripts").
##
## Hooks that return Variant return `null` for "not handled": the engine then runs its original
## behavior for that call.

var duel: ModDuel          ## the running duel (every engine function and `duel.m` memory)
var m: DuelMem             ## shortcut for duel.m
var cards: CardTables      ## shortcut for duel.cards
var mod_id := ""           ## id of the mod this script came from
var effects: Array = []    ## cards.json "effect" keys this script implements


## Called once, right after `duel`, `m` and `cards` are set.
func on_setup() -> void:
	pass


## Once per engine tick (FUN_0053dbf0), after the original step. Use it to watch the field.
func on_tick() -> void:
	pass


## After the engine computed a monster's effective stats (FUN_00546470) for any face-up monster
## in zone `z` (0-4) of player `p`. `out` is the address of the result block: ATK at +4, DEF at
## +8 (read with duel.m.u32, write with duel.m.set_u32). `index` is the card's table index.
func on_stats(_p: int, _z: int, _index: int, _out: int) -> void:
	pass


## A card was placed on the field by a summon command (FUN_00405d10). Normal Summons with
## tributes that go through the engine's summon path arrive here too.
func on_placed(_p: int, _z: int, _index: int) -> void:
	pass


## The first tick of an End Phase, once the phase announcement was issued. Queue anything that
## has to finish before the turn ends with duel.schedule(..., "end_phase").
func on_end_phase() -> void:
	pass


## The card `idx` (table index) of this script's effect in player `p`'s hand: can it be
## summoned? 1 / 0, or null to use the original rule (FUN_0057a490).
func can_summon_from_hand(_p: int, _idx: int) -> Variant:
	return null


## Same for the CPU (player 1) (FUN_0057d060): are there tributes to summon `idx`?
func cpu_can_summon(_idx: int) -> Variant:
	return null


## The human summon flow for one of this script's cards (FUN_0056e6e0, called every tick while
## the action runs). Return the original's return value, or null to run the original.
func human_summon(_mode: int, _alternate: int) -> Variant:
	return null


## The CPU summon flow for one of this script's cards. 0 = no option, 1 = summoned, 2 = flipped
## a tribute. Return null to run the original.
func cpu_summon(_player: int, _hand: int, _fallback: int, _immediate: bool, _defensive: bool) -> Variant:
	return null


# --- helpers ----------------------------------------------------------------------------------

func effect_of(index: int) -> String:
	return str(cards.mod_effects.get(duel.f401a70(index), ""))


func is_mine(index: int) -> bool:
	return index != 0 and effects.has(effect_of(index))


func trace(text: String) -> void:
	duel._trace(text)


func trace_change(key: String, value: Variant, text: String) -> void:
	duel._trace_change(key, value, text)


func place_key(p: int, z: int) -> int:
	return duel.place_key(p, z)


func schedule(delay: int, task: Callable, tag := "") -> void:
	duel.schedule(delay, task, tag)


func pending(tag := "") -> bool:
	return duel.has_pending(tag)
