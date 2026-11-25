extends ModScript
## Slifer the Sky Dragon ("effect": "slifer" in cards.json).
##
## - ATK/DEF = 1000 per card in its owner's hand (on_stats).
## - Normal Summon with exactly 3 Tributes: availability, human flow (Yes/No, then three clicks),
##   CPU flow. It reuses the engine's three-Tribute path (FUN_0057cd30, the Gate Guardian one).
## - Monsters the opponent summons in Attack Position while Slifer is face-up lose 2000 ATK
##   (permanent per monster) and are destroyed at 0. Monsters that were already on the field, in
##   Defense or face-down, or that arrive by control change are not affected.
## - If it was Special Summoned (Monster Reborn, Premature Burial...), it glows and goes to the
##   Graveyard in the End Phase. A Special Summoned face-down Slifer keeps the mark: once it is
##   flipped face-up it returns at that End Phase.
## - Which cards can revive it is data: "revive_by" in cards.json.

# Duration of the "card_effect" glow in engine steps, then the pauses of the foe sequence:
# glow, the ATK counts down, second glow, destroy.
const FX_GLOW := 17
const FX_PAUSE := 0
const FX_COUNTDOWN := 40

const PER_HAND_CARD := 1000
const FOE_ATK_LOSS := 2000
## The original routines give type 0x18 a base ATK/DEF of 4000.
const TYPE24_BASE := 4000

## Steps of FUN_0056e6e0 (byte 0xa1340d) that belong to the human flow.
const _STEP_ASK := 0x61
const _STEP_PICK := 0x62

var _picks: Array = []           # Tributes picked by the human: [[owner, zone], ...]
var _seen := {}                  # placements of foe monsters already examined
var _debuff := {}                # placement -> ATK lost
var _snap := [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]   # monsters of each field in the last pass
var _normal_for := -1            # player whose Normal Summon of Slifer is being placed
var _special := {}               # placement -> true if it arrived by Special Summon


func _init() -> void:
	effects = ["slifer"]


## The engine value (base 4000 + modifiers) is redone with 1000 per card in hand; field
## modifiers, equips... are kept.
static func stat(engine_value: int, hand_count: int) -> int:
	return maxi(0, engine_value - TYPE24_BASE + PER_HAND_CARD * hand_count)


# --- stats ---------------------------------------------------------------------------------------

func on_stats(p: int, z: int, index: int, out: int) -> void:
	if is_mine(index):
		var hand := m.u8(0xa11946 + (p & 1) * 0xd54)
		var atk := stat(ModEffects.s32(m.u32(out + 4)), hand)
		var defense := stat(ModEffects.s32(m.u32(out + 8)), hand)
		m.set_u32(out + 4, atk)
		m.set_u32(out + 8, defense)
		trace_change("stat%d_%d" % [p & 1, z], atk * 100000 + hand, "slifer p%d z%d: hand %d -> ATK %d DEF %d" % [p & 1, z, hand, atk, defense])
	var lost: int = _debuff.get(place_key(p, z), 0)
	if lost > 0:
		m.set_u32(out + 4, maxi(0, ModEffects.s32(m.u32(out + 4)) - lost))


# --- field helpers -------------------------------------------------------------------------------

func _controls(owner: int) -> bool:
	return _zone_of(owner) >= 0


func _zone_of(owner: int) -> int:
	for z in range(5):
		var zone := DuelMem.zone(owner & 1, z)
		if (m.u8(zone + 6) & 2) != 0 and is_mine(m.u16(zone) & 0xfff):
			return z
	return -1


func _atk_of(p: int, z: int) -> int:
	var tmp := m.local(12)
	duel.f546470(p, z, tmp)
	return ModEffects.s32(m.u32(tmp + 4))


## A monster `index` that was in `owner`'s field in the last pass and is gone: it was taken away
## (control change), not summoned. Compares how many copies there were with how many there are.
func _left_side(owner: int, index: int) -> bool:
	var before := 0
	var now := 0
	for z in range(5):
		if _snap[owner][z] == index:
			before += 1
		if (m.u16(DuelMem.zone(owner, z)) & 0xfff) == index:
			now += 1
	return now < before


# --- scheduled effects ---------------------------------------------------------------------------

## The game's own effect glow ("card_effect"), the same event the engine emits when a card
## activates its effect.
func _glow(p: int, z: int) -> void:
	var index := m.u16(DuelMem.zone(p, z)) & 0xfff
	if is_mine(index):
		duel.present("card_effect", {"p": p, "card": duel.f401a70(index), "loc": 0, "c": z})


func _start_debuff(p: int, z: int, key: int) -> void:
	if place_key(p, z) == key and (m.u16(DuelMem.zone(p, z)) & 0xfff) != 0:
		_debuff[key] = FOE_ATK_LOSS
		trace("slifer: the ATK of the monster of p%d zone %d starts dropping" % [p, z])


## Destroys the monster if it is still the same one. false = the engine is busy, try again.
func _destroy(p: int, z: int, key: int) -> bool:
	if duel.engine_busy():
		return false
	if place_key(p, z) == key and (m.u16(DuelMem.zone(p, z)) & 0xfff) != 0:
		duel.f54e250(p, z, 1)
	return true


# --- foe summons: -2000 ATK ----------------------------------------------------------------------

## Every engine step: new monsters of the opponent of a face-up Slifer that stay in Attack
## Position lose 2000 ATK for good and, if that leaves them at 0, are destroyed. Only summons
## count. It only acts with the engine idle: no summon running and no queued commands.
func on_tick() -> void:
	if duel.engine_busy():
		return
	for owner in range(2):
		var has_slifer := _controls(owner)
		var foe := 1 - owner
		for z in range(5):
			var zone := DuelMem.zone(foe, z)
			var index := m.u16(zone) & 0xfff
			if index == 0:
				continue
			var key := place_key(foe, z)
			if _seen.has(key):
				continue
			_seen[key] = true
			var flags := m.u8(zone + 6)
			if not has_slifer or (flags & 2) == 0 or (flags & 1) != 0:
				continue   # no Slifer, face-down or Defense
			if _left_side(owner, index):
				trace("slifer p%d: the monster of p%d zone %d arrived by control change: no effect" % [owner, foe, z])
				continue
			# The sequence: glow, the ATK drops, (if it reaches 0) second glow, destroy.
			var before := _atk_of(foe, z)
			var after := maxi(0, before - FOE_ATK_LOSS)
			trace("slifer p%d: effect on the monster of p%d zone %d (ATK %d -> %d)" % [owner, foe, z, before, after])
			var s_zone := _zone_of(owner)
			schedule(0, _glow.bind(owner, s_zone))
			schedule(FX_GLOW + FX_PAUSE, _start_debuff.bind(foe, z, key))
			if before > 0 and after <= 0:
				schedule(FX_GLOW + FX_PAUSE + FX_COUNTDOWN, _glow.bind(owner, s_zone))
				schedule((FX_GLOW + FX_PAUSE) * 2 + FX_COUNTDOWN, _destroy.bind(foe, z, key))
	for p in range(2):
		for z in range(5):
			_snap[p][z] = m.u16(DuelMem.zone(p, z)) & 0xfff


# --- Special Summon: back to the Graveyard in the End Phase --------------------------------------

func on_placed(p: int, z: int, index: int) -> void:
	if not is_mine(index):
		return
	if _normal_for == p:
		_normal_for = -1   # its own Normal Summon
	else:
		_special[place_key(p, z)] = true
		trace("slifer p%d: Special Summoned in zone %d (goes to the Graveyard in the End Phase)" % [p, z])


## Each face-up Slifer (either field) that arrived by Special Summon glows and goes to the
## Graveyard; the End Phase waits for it. Face-down ones stay (they keep the mark).
func on_end_phase() -> void:
	_normal_for = -1
	for pl in range(2):
		for z in range(5):
			var zone := DuelMem.zone(pl, z)
			if (m.u8(zone + 6) & 2) == 0 or not is_mine(m.u16(zone) & 0xfff):
				continue
			var key := place_key(pl, z)
			if not _special.get(key, false):
				continue
			trace("slifer p%d zone %d: End Phase, Special Summoned -> Graveyard" % [pl, z])
			schedule(0, _glow.bind(pl, z), "end_phase")
			schedule(FX_GLOW + FX_PAUSE, _destroy.bind(pl, z, key), "end_phase")


# --- Normal Summon with three Tributes -----------------------------------------------------------

## FUN_0057a490: the original rejects every type > 20; Slifer (type 0x18) is accepted with three
## valid Tributes.
func can_summon_from_hand(p: int, idx: int) -> Variant:
	if duel.s16(idx) == 0 or duel.f583e00(idx) != 0:
		return 0
	var kind := duel.f541950(idx)
	if kind == 3 or kind == 2:
		return 0
	if duel.f56e660(p) == 0:
		return 0
	var tributes := duel.f544280(p, 0xffffffff)
	trace_change("avail%d" % (p & 1), tributes, "slifer p%d: valid Tributes %d (needs 3)" % [p & 1, tributes])
	if tributes >= 3:
		return 1
	if p == 0:
		duel.f4437a0(0)   # FUN_004437a0: the original's hint (not enough Tributes)
	return 0


## FUN_0057d060 (the CPU, player 1).
func cpu_can_summon(_idx: int) -> Variant:
	return int(duel.f544280(1, 0xffffffff) >= 3)


## Three packed Tributes -> FUN_0057cd30 (the FUN_0057c0c0 path). It is a Normal Summon, so it
## uses the turn's one (bit 0x10 of the player's block).
func _commit(p: int, hand: int, mode: int, picks: Array) -> void:
	var packed := ModEffects.pack_tributes(picks)
	var zone: int = picks[2][1]
	trace("slifer p%d: summons from hand %d, Tributes %s, zone %d (packed 0x%x, mode %d)" % [p & 1, hand, str(picks), zone, packed, mode])
	_normal_for = p & 1   # the placement that follows is a Normal Summon, not a Special one
	duel.f57cd30(p, hand, zone, packed, mode)
	var flags := 0xa1194c + (p & 1) * 0xd54
	m.set_u8(flags, m.u8(flags) | 0x10)


## FUN_0056e6e0: human summon. Three Tributes are asked with the same dialog and clicks as the
## original.
func human_summon(mode: int, _alternate: int) -> Variant:
	var p := m.u8(0xa1340f) & 1
	var hand := m.u32(0xa13410) & 0xff
	var cancel := (m.u32(0xa114a8) & 0x102) != 0
	var cur_p := m.u32(0xa161a4)
	var cur_loc := m.u32(0xa161a8)
	var cur_i := m.u32(0xa161ac)
	var state := m.u8(0xa1340d)
	match state:
		0:
			_picks.clear()
			duel._l_tribute_question(0x5ad28c, _STEP_ASK)
			return 0
		_STEP_ASK, _STEP_PICK:
			if state == _STEP_ASK:
				if m.u16(0xa16178) == 0:   # context "No"
					duel._l_action_end()
					return 0
				m.set_u8(0xa1340d, _STEP_PICK)
			if cancel:
				duel.f464d20()
				_picks.clear()
				duel._l_tribute_question(0x5ad28c, _STEP_ASK)
				return 0
			if not duel._l_tribute_pick():
				return 0
			var pick := [cur_p & 1, cur_i & 7]
			if _picks.has(pick):
				return 0   # the same click is still held on a Tribute already picked
			duel.f465720(cur_p, cur_loc + cur_i)
			_picks.append(pick)
			trace("slifer: Tribute %d/3 = %s" % [_picks.size(), str(pick)])
			if _picks.size() == 3:
				_commit(p, hand, mode, _picks)
				_picks.clear()
				duel._l_action_end()
			return 0
	return 1


## Like FUN_0057ceb0 (the CPU's Tribute by effect priority, then lowest DEF + double ATK) but
## with several zones excluded, to choose three different Tributes.
func _ai_tribute_excluding(p: int, excluded: Array) -> int:
	p &= 1
	for z in range(5):
		if (m.u16(DuelMem.zone(p, z)) & 0xfff) and not excluded.has(z) \
				and duel.f545620(p, z, 0x403) != 0 and duel.f544210(p, z) != 0:
			return z
	for wanted in [0x2f, 0x23d]:
		for z in range(5):
			var idx := m.u16(DuelMem.zone(p, z)) & 0xfff
			if idx and not excluded.has(z) and duel.s16(duel.f401a70(idx)) == wanted:
				return z
	var best := 32000
	var selected := -1
	var tmp := m.local(12)
	for z in range(5):
		var idx := m.u16(DuelMem.zone(p, z)) & 0xfff
		if idx == 0 or excluded.has(z):
			continue
		var id := duel.s16(duel.f401a70(idx))
		if id != 0x2da and id != 0x536 and duel.f544210(p, z) != 0 and duel.f542280(idx) == 0:
			duel.f546470(p, z, tmp)
			var score := ModEffects.s32(m.u32(tmp + 8)) + ModEffects.s32(m.u32(tmp + 4)) * 2
			if score < best:
				best = score
				selected = z
	return selected


## The CPU's summon emission (0 = no option, 1 = summoned, 2 = flipped a Tribute).
func cpu_summon(player: int, hand: int, fallback: int, _immediate: bool, _defensive: bool) -> Variant:
	var index := m.u16(0xa11fb8 + player * 0xd54 + hand * 4) & 0xfff
	var chosen: Array = []
	for _n in 3:
		var z := _ai_tribute_excluding(player, chosen)
		if z < 0:
			trace("slifer cpu: no three valid Tributes (%s)" % str(chosen))
			return 0
		chosen.append(z)
	for z in chosen:
		if duel.f582190(z) != 0:   # a Tribute with a flip effect: flip it first
			duel.f57cad0(player, z)
			return 2
	var picks: Array = []
	for z in chosen:
		picks.append([player & 1, z])
	_commit(player, hand, int(duel.f581cd0(index, fallback) == 0), picks)
	return 1
