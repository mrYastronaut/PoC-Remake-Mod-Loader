class_name ModCards
extends RefCounted
## Cartas aportadas por mods: <mod>/cards.json (lista de cartas) -> ids estables + indices nuevos.
##
## - internal_id: lo que guardan mazos (.ydc), partidas y repeticiones. Se asigna una vez por
##   "<mod>:<clave>" y se recuerda en mods/slots.json para que no cambie nunca.
##   Se toma de 1999 hacia abajo entre los ids libres; el par id+2000 (variante) tambien debe
##   estar libre, porque index_of(id) usa CARD_IntID[id % 2000] + (id >= 2000).
## - indice: posicion en las tablas del motor (card_id/prop/pack). Se recalcula en cada carga a
##   partir del final de las tablas base; el motor nunca lo guarda en disco.
## Las tablas (CardTables) y la base de datos (CardDB) llaman al mismo plan() con los mismos datos
## base, asi que obtienen exactamente la misma asignacion.

## Tope de indices que admite el motor: CardTables.prop() enmascara con 0x7ff. Las tablas base
## ocupan 1114 (MAX_INDEX base 0x45b), asi que las cartas de mods amplian CardTables.max_index.
const MAX_INDEX := 0x7ff
const FRAGMENT := "cards.json"
const REGISTRY := "slots.json"
## Los ids 0x780-1999 (1920-1999) son especiales en el motor (nunca van a la mano, se eligen
## primero como tributo, comando 0x79), asi que los ids de mods se toman por debajo de 1920.
const MAX_ID := 0x77f
const LANGS := ["spa", "eng", "fra", "ger", "ita", "jpn"]
const ATTRIBUTES := {"none": 0, "light": 1, "dark": 2, "water": 3, "fire": 4, "earth": 5, "wind": 6, "divine": 7}
const KINDS := {"normal": 0, "effect": 1, "fusion": 2, "ritual": 3}
const PACK_BITS := {"yugi": 1, "kaiba": 2, "joey": 4}
const TYPE_TRAP := 21
const TYPE_SPELL := 22

## Carpeta de datos de la que se leen los mods; la fija Assets.reindex() (vacia = sin mods).
## El motor del duelo no depende de los autoloads, por eso se pasa por aqui.
static var active_storage := ""
## Errores de la ultima asignacion (cartas invalidas, tablas llenas...) para mostrarlos en Mods.
static var last_errors: Array = []

static var _key_regex: RegEx = null
static var _image_regex: RegEx = null
static var _password_regex: RegEx = null
static var _effect_regex: RegEx = null


## Id interno dado como entero, "1008" o "0x3f0"; -1 si no es valido.
static func _parse_id(v: Variant) -> int:
	if v is int or v is float:
		return int(v) if float(v) == float(int(v)) else -1
	var s := str(v).strip_edges().to_lower()
	if s.begins_with("0x") and s.substr(2).is_valid_hex_number():
		return s.hex_to_int()
	if s.is_valid_int():
		return s.to_int()
	return -1


## Valida una carta cruda del fragmento. {"ok", "card", "errors"}; `card` sin index/internal_id.
static func parse_card(raw: Variant, mod_games: Array) -> Dictionary:
	if _key_regex == null:
		_key_regex = RegEx.create_from_string("^[a-z0-9_]{1,40}$")
		_image_regex = RegEx.create_from_string("^[a-z0-9_.-]{1,60}\\.(png|webp)$")
		_password_regex = RegEx.create_from_string("^[0-9]{8}$")
		_effect_regex = RegEx.create_from_string("^[a-z][a-z0-9_]{0,39}$")
	var errors: Array = []
	if not raw is Dictionary:
		return {"ok": false, "card": {}, "errors": ["la carta no es un objeto"]}
	var r: Dictionary = raw
	var key := str(r.get("key", ""))
	if _key_regex.search(key) == null:
		errors.append("key invalida (a-z, 0-9 y _, hasta 40)")
	var category := str(r.get("category", "monster"))
	if not ["monster", "spell", "trap"].has(category):
		errors.append("category debe ser monster, spell o trap")
	var names := _texts(r.get("names", null), "names", 60, errors)
	var descriptions := _texts(r.get("descriptions", null), "descriptions", 1000, errors)
	var atk := 0
	var defense := 0
	var level := 0
	var attribute := category
	var type_id := TYPE_SPELL if category == "spell" else TYPE_TRAP
	var kind := "normal"
	if category == "monster":
		atk = _int_in(r, "atk", 0, 5110, errors)
		defense = _int_in(r, "defense", 0, 5110, errors)
		if atk % 10 != 0 or defense % 10 != 0:
			errors.append("atk y defense deben ser multiplos de 10")
		level = _int_in(r, "level", 0, 15, errors)
		attribute = str(r.get("attribute", "none"))
		if not ATTRIBUTES.has(attribute):
			errors.append("attribute desconocido: " + attribute)
		type_id = _int_in(r, "type_id", 1, 24, errors)
		kind = str(r.get("monster_kind", "normal"))
		if not KINDS.has(kind):
			errors.append("monster_kind desconocido: " + kind)
	var games: Array = r.get("games", mod_games)
	var pack := 0
	if games.is_empty():
		errors.append("games no puede estar vacio")
	for g in games:
		if not PACK_BITS.has(str(g)):
			errors.append("juego desconocido: " + str(g))
		else:
			pack |= PACK_BITS[str(g)]
	var image: Variant = r.get("image", null)
	if image != null and (not image is String or _image_regex.search(image) == null):
		errors.append("image debe ser un nombre de archivo .png/.webp sin carpetas")
	var password := str(r.get("password", "00000000"))
	if _password_regex.search(password) == null:
		errors.append("password debe tener 8 digitos")
	var limit := 0
	if r.has("limit"):
		if typeof(r["limit"]) not in [TYPE_INT, TYPE_FLOAT] or int(r["limit"]) != r["limit"] or int(r["limit"]) < 1 or int(r["limit"]) > 3:
			errors.append("limit debe ser 1, 2 o 3 (copias por mazo)")
		else:
			limit = int(r["limit"])
	var reward_weight := 0
	if r.has("reward_weight"):
		if typeof(r["reward_weight"]) not in [TYPE_INT, TYPE_FLOAT] or int(r["reward_weight"]) != r["reward_weight"] or int(r["reward_weight"]) < 1 or int(r["reward_weight"]) > 1000:
			errors.append("reward_weight debe ser un entero de 1 a 1000")
		else:
			reward_weight = int(r["reward_weight"])
	var effect := str(r.get("effect", ""))
	if effect != "" and _effect_regex.search(effect) == null:
		errors.append("effect debe ser una clave a-z, 0-9 y _ (la implementa un script del mod)")
	var revive_by: Array = []
	if r.has("revive_by"):
		if not r["revive_by"] is Array:
			errors.append("revive_by debe ser una lista de ids internos (ej. 1008 = Monster Reborn)")
		else:
			for entry in r["revive_by"]:
				var rid := _parse_id(entry)
				if rid < 1 or rid > 1999:
					errors.append("revive_by: id invalido: " + str(entry))
				elif not revive_by.has(rid):
					revive_by.append(rid)
	if not errors.is_empty():
		return {"ok": false, "card": {}, "errors": errors}
	var card := {
		"key": key, "password": password, "names": names, "descriptions": descriptions,
		"atk": atk, "defense": defense, "level": level, "attribute": attribute,
		"type_id": type_id, "kind_bits": KINDS[kind] if category == "monster" else 0,
		"category": category, "pack": pack, "image": image,
		"games": ["yugi", "kaiba", "joey"].filter(func(g): return games.has(g)),
	}
	if category == "monster":
		card["monster_kind"] = kind
	if effect != "":
		card["effect"] = effect
	if not revive_by.is_empty():
		card["revive_by"] = revive_by
	if limit > 0:
		card["limit"] = limit
	if reward_weight > 0:
		card["reward_weight"] = reward_weight
	return {"ok": true, "card": card, "errors": []}


## card_prop.bin: def/10 (9 bits) | atk/10 (9) | clase (2) | tipo (5) | nivel (4) | atributo (3).
static func pack_prop(card: Dictionary) -> int:
	var attribute := int(ATTRIBUTES.get(str(card["attribute"]), 0)) if str(card["category"]) == "monster" else 0
	return (int(card["defense"]) / 10) | ((int(card["atk"]) / 10) << 9) | (int(card["kind_bits"]) << 18) \
			| (int(card["type_id"]) << 20) | (int(card["level"]) << 25) | (attribute << 29)


## Cartas validas de los mods activos, en orden de carga: [{mod, card}], y los errores.
static func load_fragments(storage_dir: String) -> Dictionary:
	var out: Array = []
	var errors: Array = []
	for mod: Dictionary in ModRegistry.active(storage_dir):
		var path := (mod["dir"] as String).path_join(FRAGMENT)
		if not FileAccess.file_exists(path):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Array:
			errors.append("%s: cards.json no es una lista JSON valida" % mod["id"])
			continue
		var seen := {}
		for raw in json.data:
			var parsed := parse_card(raw, mod["manifest"]["games"])
			var key := str(raw.get("key", "?")) if raw is Dictionary else "?"
			if not parsed["ok"]:
				errors.append("%s:%s: %s" % [mod["id"], key, "; ".join(parsed["errors"])])
			elif seen.has(key):
				errors.append("%s:%s: key repetida" % [mod["id"], key])
			else:
				seen[key] = true
				out.append({"mod": mod["id"], "card": parsed["card"]})
	return {"cards": out, "errors": errors}


## Asigna id e indice. `base_ids`: ids internos en uso; `base_end`: primer indice libre
## tras las tablas base. Devuelve {"cards": [carta completa con index/internal_id/mod],
## "errors": [...]} y guarda mods/slots.json si cambia.
static func plan(base_ids: Dictionary, base_end: int, storage_dir: String) -> Dictionary:
	var loaded := load_fragments(storage_dir)
	var errors: Array = loaded["errors"].duplicate()
	var registry := _read_registry(storage_dir)
	var original := registry.duplicate()
	var base_taken := {}   # id % 2000 ocupado por una carta base (el par id/id+2000 comparte hueco)
	for id in base_ids:
		base_taken[int(id) % 2000] = true
	var reserved := {}     # ids prometidos en el registro, tambien los de mods desactivados
	for key in registry:
		reserved[registry[key]] = true
	var assigned := {}
	var next_index := base_end
	var cards: Array = []
	for entry: Dictionary in loaded["cards"]:
		var full_key := "%s:%s" % [entry["mod"], entry["card"]["key"]]
		var id := int(registry.get(full_key, -1))
		if id < 1 or id > MAX_ID or base_taken.has(id) or assigned.has(id):
			id = _free_id(base_taken, reserved, assigned)
		if id < 0:
			errors.append(full_key + ": no quedan ids internos libres")
			continue
		if next_index > MAX_INDEX:
			errors.append(full_key + ": las tablas del motor estan llenas (maximo %d cartas)" % MAX_INDEX)
			continue
		assigned[id] = true
		reserved[id] = true
		registry[full_key] = id
		var card: Dictionary = (entry["card"] as Dictionary).duplicate(true)
		card["index"] = next_index
		card["internal_id"] = id
		card["mod"] = entry["mod"]
		next_index += 1
		cards.append(card)
	if registry != original:
		_write_registry(storage_dir, registry)
	last_errors = errors
	return {"cards": cards, "errors": errors}


## Amplia las tablas del motor con las cartas de mods. Devuelve cuantas anadio.
static func apply_to_tables(tables: CardTables, storage_dir: String) -> int:
	if storage_dir == "":
		return 0
	var base_ids := {}
	var base_end := 1
	for i in range(1, tables.ids.size()):
		if tables.ids[i] != 0 or (i < tables.props.size() and tables.props[i] != 0) \
				or (i < tables.packs.size() and tables.packs[i] != 0):
			base_ids[tables.ids[i]] = true
			base_end = i + 1
	var planned := plan(base_ids, base_end, storage_dir)
	for message in planned["errors"]:
		push_warning("mods: " + str(message))
	var cards: Array = planned["cards"]
	if cards.is_empty():
		return 0
	var top: int = (cards[cards.size() - 1] as Dictionary)["index"] + 1
	if tables.ids.size() < top: tables.ids.resize(top)
	if tables.props.size() < top: tables.props.resize(top)
	if tables.packs.size() < top: tables.packs.resize(top)
	if tables.int_ids.size() < 2048: tables.int_ids.resize(2048)
	for card: Dictionary in cards:
		var index: int = card["index"]
		tables.ids[index] = card["internal_id"]
		tables.props[index] = pack_prop(card)
		tables.packs[index] = card["pack"]
		tables.int_ids[card["internal_id"]] = index
		if str(card.get("effect", "")) != "":
			tables.mod_effects[int(card["internal_id"])] = str(card["effect"])
		if card.has("revive_by"):
			tables.mod_revive[int(card["internal_id"])] = card["revive_by"]
	tables.max_index = maxi(tables.max_index, top - 1)
	return cards.size()


## Anade las cartas de mods a la lista de CardDB (mismo esquema que cards.json).
static func apply_to_db(cards: Array, storage_dir: String) -> Array:
	if storage_dir == "":
		return []
	var base_ids := {}
	var base_end := 1
	for card: Dictionary in cards:
		var names: Dictionary = card.get("names", {})
		if int(card["internal_id"]) != 0 or str(names.get("eng", "")) != "":
			base_ids[int(card["internal_id"])] = true
			base_end = maxi(base_end, int(card["index"]) + 1)
	var planned := plan(base_ids, base_end, storage_dir)
	return planned["cards"]


## card_prop.bin ampliado con las props de las cartas de mods (el editor lee el archivo crudo).
static func extend_prop_bytes(bytes: PackedByteArray, mod_cards: Array) -> PackedByteArray:
	var out := bytes.duplicate()
	for card: Dictionary in mod_cards:
		var need: int = (int(card["index"]) + 1) * 4
		if out.size() < need:
			out.resize(need)
		out.encode_u32(int(card["index"]) * 4, pack_prop(card))
	return out


static func _free_id(base_taken: Dictionary, reserved: Dictionary, assigned: Dictionary) -> int:
	for id in range(MAX_ID, 0, -1):
		if not base_taken.has(id) and not reserved.has(id) and not assigned.has(id):
			return id
	return -1


static func _int_in(r: Dictionary, field: String, lo: int, hi: int, errors: Array) -> int:
	var v: Variant = r.get(field, null)
	if not (v is int or v is float) or float(v) != float(int(v)) or int(v) < lo or int(v) > hi:
		errors.append("%s debe ser un entero entre %d y %d" % [field, lo, hi])
		return lo
	return int(v)


static func _texts(raw: Variant, field: String, max_len: int, errors: Array) -> Dictionary:
	var out := {}
	if not raw is Dictionary or not (raw as Dictionary).has("eng"):
		errors.append("%s necesita al menos \"eng\"" % field)
		return out
	for lang in raw:
		if not LANGS.has(str(lang)) or not raw[lang] is String:
			errors.append("%s: idioma o texto invalido (%s)" % [field, str(lang)])
		elif (raw[lang] as String).length() > max_len:
			errors.append("%s.%s supera %d caracteres" % [field, str(lang), max_len])
		else:
			out[str(lang)] = raw[lang]
	for lang in LANGS:
		if not out.has(lang) and out.has("eng"):
			out[lang] = out["eng"]
	return out


static func _read_registry(storage_dir: String) -> Dictionary:
	var path := ModRegistry.mods_dir(storage_dir).path_join(REGISTRY)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var out := {}
	for key in json.data:
		if json.data[key] is float or json.data[key] is int:
			out[str(key)] = int(json.data[key])
	return out


static func _write_registry(storage_dir: String, registry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ModRegistry.mods_dir(storage_dir))
	var file := FileAccess.open(ModRegistry.mods_dir(storage_dir).path_join(REGISTRY), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(registry, "  "))
		file.close()
