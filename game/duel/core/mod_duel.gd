class_name ModDuel
extends DuelCmds
## Mod hook layer, between the ported engine (DuelCmds) and Duel.
##
## A mod can ship scripts (ModScript, mod.json "scripts") that give its cards effects. ModDuel
## loads the scripts of the active mods (CardTables.mod_scripts) and forwards the engine points
## where effects happen to them: stats (f546470), the main step (f53dbf0), summons (f57a490,
## f57d060, f56e6e0, _o_summon_from_hand), card placement (f405d10) and the End Phase (f576350).
## A card asks for an effect with "effect": "<key>" in cards.json (CardTables.mod_effects); the
## script that lists that key handles it. With no scripts and no mod cards every override calls
## `super` straight away, so a duel without mods behaves exactly as before.
##
## Generic, data-driven: "revive_by" in cards.json lists the original cards (internal ids) that
## may Special Summon the card from the Graveyard (f56ba50). The original filter only lists
## monsters of type < 0x15 and leaves out the special types.
##
## With --mod-trace on the command line (after `--`) scripts can print what they do.

## Vanilla revive cards and the Graveyards their list scans: 1 = own, 2 = both.
const REVIVE_SCOPE := {0x3f0: 2, 0x447: 1, 0x45c: 1, 0x487: 1, 0x488: 1, 0x5f0: 1}

var _trace_on := -1
var _trace_seen := {}
var _scripts: Array = []        # ModScript instances, in load order
var _by_effect := {}            # effect key -> ModScript
var _tick := 0
var _tasks: Array = []          # {"at", "task", "tag"} (see schedule)
var _eot_started := false       # End Phase: on_end_phase already ran for this phase


func _init(tables: CardTables) -> void:
	super(tables)
	for entry: Dictionary in tables.mod_scripts:
		var script := ModScripts.instantiate(str(entry["path"]))
		if script == null:
			continue
		script.duel = self
		script.m = m
		script.cards = cards
		script.mod_id = str(entry["mod"])
		_scripts.append(script)
		for key in script.effects:
			_by_effect[str(key)] = script
		script.on_setup()


func _trace(text: String) -> void:
	if _trace_on < 0:
		_trace_on = int(OS.get_cmdline_user_args().has("--mod-trace"))
	if _trace_on == 1:
		print("[mod-trace] ", text)


## Only traces when the value of `key` changes, so the log is not flooded.
func _trace_change(key: String, value: Variant, text: String) -> void:
	if _trace_on == 0 or _trace_seen.get(key) == value:
		return
	_trace_seen[key] = value
	_trace(text)


## Effect key of the card with that table index ("" if none).
func _mod_effect(index: int) -> String:
	index &= 0xfff
	if index == 0 or cards.mod_effects.is_empty():
		return ""
	return str(cards.mod_effects.get(f401a70(index), ""))


## The script that implements the effect of the card with that table index (null if none).
func script_for(index: int) -> ModScript:
	if _scripts.is_empty():
		return null
	return _by_effect.get(_mod_effect(index))


# --- helpers for scripts ----------------------------------------------------------------------

## Key of the current placement of the monster in zone z of p (the u16 stamp at +4 changes with
## every placement, so a new monster in the same zone is another key).
func place_key(p: int, z: int) -> int:
	return ((p & 1) << 24) | (z << 16) | m.u16(DuelMem.zone(p & 1, z) + 4)


## The engine is busy: a summon is running or commands are queued.
func engine_busy() -> bool:
	return (m.u8(0xa15bee) & 1) != 0 or m.u16(DuelMem.QUEUE_COUNT) != 0


## Runs `task` after `delay` engine ticks. If it returns false it runs again 5 ticks later.
## While a task with a given tag is pending, has_pending(tag) is true; tag "end_phase" also holds
## the End Phase back until it finishes.
func schedule(delay: int, task: Callable, tag := "") -> void:
	_tasks.append({"at": _tick + delay, "task": task, "tag": tag})


func has_pending(tag := "") -> bool:
	for item: Dictionary in _tasks:
		if tag == "" or item["tag"] == tag:
			return true
	return false


func _run_tasks() -> void:
	var i := 0
	while i < _tasks.size():
		var item: Dictionary = _tasks[i]
		if item["at"] > _tick:
			i += 1
			continue
		if item["task"].call() == false:
			item["at"] = _tick + 5
			i += 1
			continue
		_tasks.remove_at(i)


# --- engine points forwarded to scripts ----------------------------------------------------------

## FUN_00546470: effective monster of zone z of p.
func f546470(p: int, z: int, out: int) -> int:
	var result := super.f546470(p, z, out)
	if _scripts.is_empty() or z >= 5:
		return result
	var index := m.u16(out) & 0xfff
	if index == 0 or (m.u8(DuelMem.zone(p & 1, z) + 6) & 2) == 0:
		return result   # face-down: the original leaves the base values
	for script: ModScript in _scripts:
		script.on_stats(p & 1, z, index, out)
	return result


## FUN_0053dbf0: main engine step (once per native tick).
func f53dbf0() -> int:
	var result := super.f53dbf0()
	if _scripts.is_empty():
		return result
	_tick += 1
	for script: ModScript in _scripts:
		script.on_tick()
	_run_tasks()
	return result


## FUN_0057a490: can the card idx be summoned from the hand?
func f57a490(p: int, idx: int) -> int:
	var script := script_for(idx)
	if script != null:
		var answer: Variant = script.can_summon_from_hand(p, idx)
		if answer != null:
			return int(answer)
	return super.f57a490(p, idx)


## FUN_0057d060 (the CPU, player 1): are there tributes to summon the card idx?
func f57d060(idx: int) -> int:
	var script := script_for(idx)
	if script != null:
		var answer: Variant = script.cpu_can_summon(idx)
		if answer != null:
			return int(answer)
	return super.f57d060(idx)


## FUN_0056e6e0: human summon from the hand.
func f56e6e0(mode: int, alternate: int) -> int:
	var script := script_for(m.u16(0xa13404))
	if script != null:
		var answer: Variant = script.human_summon(mode, alternate)
		if answer != null:
			return int(answer)
	return super.f56e6e0(mode, alternate)


## The CPU summon emission (0 = no option, 1 = summoned, 2 = flipped a tribute).
func _o_summon_from_hand(player: int, hand: int, fallback: int, immediate: bool, defensive: bool) -> int:
	var index := m.u16(0xa11fb8 + player * 0xd54 + hand * 4) & 0xfff
	var script := script_for(index)
	if script != null and not immediate:
		var answer: Variant = script.cpu_summon(player, hand, fallback, immediate, defensive)
		if answer != null:
			return int(answer)
	return super._o_summon_from_hand(player, hand, fallback, immediate, defensive)


## 0x71 FUN_00405d10: summon of a card into a zone. Step 4 places it and finishes.
func f405d10() -> int:
	if _scripts.is_empty():
		return super.f405d10()
	var placing := step() == 4
	var p := cmd_player()
	var dst := cmd_a() >> 12
	var index := f401ad0(cmd_b() & 0xfff) & 0xfff
	var result := super.f405d10()
	if placing:
		for script: ModScript in _scripts:
			script.on_placed(p, dst, index)
	return result


## FUN_00576350: End Phase. After the phase announcement (state 0) and before the original's
## end-of-turn effects, scripts get on_end_phase once; the phase waits for tasks tagged
## "end_phase".
func f576350() -> int:
	if _scripts.is_empty():
		return super.f576350()
	if m.u8(0xa133fc) == 0:
		_eot_started = false
		return super.f576350()
	if not _eot_started:
		_eot_started = true
		for script: ModScript in _scripts:
			script.on_end_phase()
	if has_pending("end_phase"):
		return 0
	return super.f576350()


# --- revive cards ---------------------------------------------------------------------------------

func _grave_has_revivable(cid: int, scope: int, p: int) -> bool:
	for pl in ([p & 1] if scope == 1 else [0, 1]):
		var q: int = pl * PS
		for i in m.u8(0xa11948 + q):
			var id := f401a70(m.u16(0xa12238 + q + i * 4) & 0xfff)
			if (cards.mod_revive.get(id, []) as Array).has(cid):
				return true
	return false


## FUN_0056ba50: list of cards an effect can pick. The revive cards only list monsters of type
## < 0x15, which leaves out mod monsters of a special type. A mod card that names this card in
## "revive_by" is added in Graveyard order, with the same final filters as the original.
func f56ba50(p: int, card_id: int, a3: int) -> int:
	var count := super.f56ba50(p, card_id, a3)
	if cards.mod_revive.is_empty():
		return count
	var cid := card_id & 0xffff
	var scope: int = REVIVE_SCOPE.get(cid, 0)
	if scope == 0 or not _grave_has_revivable(cid, scope, p):
		return count
	var kept: Array = []
	for k in count:
		kept.append(m.u32(E_LIST + k * 4))
	m.set_u16(E_COUNT, 0)
	var filtered := f542fb0(p) == 0
	for pl in ([p & 1] if scope == 1 else [0, 1]):
		var pq: int = pl * PS
		for gi in m.u8(0xa11948 + pq):
			var at := 0xa12238 + pq + gi * 4
			var entry := m.u32(at)
			var ix := entry & 0xfff
			var pos := kept.find(entry)
			if pos >= 0:
				kept.remove_at(pos)
				_e_add(at, 4)
				continue
			var id := f401a70(ix)
			if not (cards.mod_revive.get(id, []) as Array).has(cid):
				continue
			if f56b9e0(pl, gi) == 0 or (entry & 0x20000) != 0 or f583e00(ix) != 0:
				continue
			if filtered and f541ce0(id) != 0:
				continue
			_e_add(at, 4)
	_trace("revive 0x%x: the list offers %d cards (with mod monsters from the Graveyard)" % [cid, m.u16(E_COUNT)])
	return m.u16(E_COUNT)
