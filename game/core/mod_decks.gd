class_name ModDecks
extends RefCounted
## Parches de mazos de la CPU. Un mod aporta deck_patches.json junto a mod.json:
##   [{"file": "yugi/file/cpu*.json", "remove": {"main": [34]}, "add": {"main": ["test_dragon"]}}]
## - file: ruta relativa a resources/ (sin distinguir mayusculas; * y ? como comodines).
## - remove / add: por zona (main, side, fusion), cartas como id interno (numero), clave de una
##   carta del mismo mod ("obelisk") o "mod:clave". Se quita la primera copia de cada carta
##   listada y despues se anaden las nuevas.
## Se aplican en el orden de carga de los mods. Un parche que dejaria el mazo fuera de limites
## (main 40-80, side y fusion 0-15) se ignora entero con un aviso.
## Funciones puras: reciben los mods y las cartas de mods, sin tocar autoloads.

const FILE := "deck_patches.json"
const ZONES := ["main", "side", "fusion"]
const LIMITS := {"main": [40, 80], "side": [0, 15], "fusion": [0, 15]}


## Devuelve el mazo con los parches aplicados (el original no se modifica).
## `mods`: lista de ModRegistry.active(); `mod_cards`: CardDB.mod_cards.
static func apply(rel_path: String, deck: Dictionary, mods: Array, mod_cards: Array, errors: Array = []) -> Dictionary:
	var out := deck.duplicate(true)
	var rel := rel_path.replace("\\", "/")
	for mod: Dictionary in mods:
		var manifest: Dictionary = mod.get("manifest", {})
		if ModRegistry.wrong_game(rel.to_lower(), manifest):
			continue
		var path: String = (mod["dir"] as String).path_join(FILE)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Array:
			errors.append("%s: %s debe ser una lista" % [mod["id"], FILE])
			continue
		for i in (parsed as Array).size():
			var patch: Variant = parsed[i]
			var label := "%s:%s[%d]" % [mod["id"], FILE, i]
			if not patch is Dictionary or typeof(patch.get("file")) != TYPE_STRING:
				errors.append(label + ": falta \"file\"")
				continue
			if not rel.matchn(str(patch["file"])):
				continue
			var result := _apply_patch(out, patch, str(mod["id"]), mod_cards, label)
			if result.has("error"):
				errors.append(result["error"])
			else:
				out = result["deck"]
	return out


static func _apply_patch(deck: Dictionary, patch: Dictionary, mod_id: String, mod_cards: Array, label: String) -> Dictionary:
	var out := deck.duplicate(true)
	for op in ["remove", "add"]:
		var zones: Variant = patch.get(op, {})
		if not zones is Dictionary:
			return {"error": "%s: \"%s\" debe ser un objeto por zona" % [label, op]}
		for zone in zones:
			if not ZONES.has(zone) or not zones[zone] is Array:
				return {"error": "%s: zona o lista no valida en \"%s\": %s" % [label, op, zone]}
			var cards: Array = out.get(zone, [])
			for ref in zones[zone]:
				var id := resolve_ref(ref, mod_id, mod_cards)
				if id < 0:
					return {"error": "%s: carta desconocida %s" % [label, str(ref)]}
				if op == "remove":
					for i in cards.size():
						if int(cards[i]) == id:
							cards.remove_at(i)
							break
				else:
					cards.append(id)
			out[zone] = cards
	for zone in ZONES:
		var size: int = (out.get(zone, []) as Array).size()
		if size < LIMITS[zone][0] or size > LIMITS[zone][1]:
			return {"error": "%s: %s quedaria con %d cartas (permitido %d-%d); parche ignorado" % [label, zone, size, LIMITS[zone][0], LIMITS[zone][1]]}
	return {"deck": out}


## Numero = id interno; texto = "clave" (del mismo mod) o "mod:clave". -1 si no existe.
static func resolve_ref(ref: Variant, mod_id: String, mod_cards: Array) -> int:
	if typeof(ref) == TYPE_FLOAT or typeof(ref) == TYPE_INT:
		var id := int(ref)
		return id if id == ref and id >= 0 and id < 4000 else -1
	if typeof(ref) != TYPE_STRING:
		return -1
	var text: String = ref
	var owner := mod_id
	var key := text
	if ":" in text:
		owner = text.get_slice(":", 0)
		key = text.get_slice(":", 1)
	for card: Dictionary in mod_cards:
		if str(card.get("mod", "")) == owner and str(card.get("key", "")) == key:
			return int(card["internal_id"])
	return -1
