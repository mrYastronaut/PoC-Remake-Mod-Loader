extends SceneTree
## Prueba sintetica (sin datos originales) de la fusion de cartas de mods.
## godot --headless --path game --script res://tests/mod_cards_test.gd -- --storage=<dir vacio> --data=<dir vacio>

var failures: Array = []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FALLO: ", what)


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func monster(key: String, extra := {}) -> Dictionary:
	var c := {"key": key, "names": {"eng": key.capitalize()}, "descriptions": {"eng": "Texto " + key},
			"atk": 4000, "defense": 4000, "level": 10, "attribute": "dark", "type_id": 1,
			"monster_kind": "effect", "image": key + ".png"}
	c.merge(extra, true)
	return c


func base_tables() -> CardTables:
	var t := CardTables.new()
	## Indice 5 = id 1918 y su variante 3918 en el indice 6 (index_of: CARD_IntID[id % 2000] + 1).
	t.ids = PackedInt32Array([0, 10, 11, 12, 1919, 1918, 3918])
	t.props = PackedInt64Array([0, 1, 2, 3, 4, 5, 6])
	t.packs = PackedInt32Array([0, 1, 1, 1, 1, 1, 1])
	t.int_ids.resize(2048)
	for i in range(1, 6):
		t.int_ids[t.ids[i]] = i
	return t


func base_db() -> Array:
	var cards: Array = []
	var t := base_tables()
	for i in range(1, 7):
		cards.append({"index": i, "internal_id": t.ids[i], "names": {"eng": "Base%d" % i}})
	return cards


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var storage: String = root.get_node("Paths").storage_dir
	var mods := storage.path_join("mods")

	# --- parse_card ---
	var ok := ModCards.parse_card(monster("slifer"), ["yugi"])
	check(ok["ok"], "carta valida: " + str(ok["errors"]))
	check(ok["card"]["pack"] == 1 and ok["card"]["games"] == ["yugi"], "pack por defecto = juegos del mod")
	check(ok["card"]["names"]["spa"] == "Slifer", "idiomas ausentes caen a eng")
	check(not ModCards.parse_card(monster("x", {"atk": 4005}), ["yugi"])["ok"], "atk no multiplo de 10")
	check(not ModCards.parse_card(monster("x", {"atk": 5120}), ["yugi"])["ok"], "atk fuera de rango")
	check(not ModCards.parse_card(monster("x", {"level": 16}), ["yugi"])["ok"], "nivel fuera de rango")
	check(not ModCards.parse_card(monster("x", {"attribute": "cosmic"}), ["yugi"])["ok"], "atributo desconocido")
	check(not ModCards.parse_card(monster("x", {"image": "../a.png"}), ["yugi"])["ok"], "imagen con ruta")
	check(not ModCards.parse_card(monster("X!"), ["yugi"])["ok"], "key invalida")
	check(not ModCards.parse_card(monster("x", {"names": {"fra": "x"}}), ["yugi"])["ok"], "names sin eng")
	check(not ModCards.parse_card(monster("x", {"games": ["pegasus"]}), ["yugi"])["ok"], "juego desconocido")
	check(ModCards.parse_card({"key": "magia1", "category": "spell", "names": {"eng": "M"}, "descriptions": {"eng": "d"}}, ["yugi"])["ok"], "magia minima")

	# --- empaquetado de prop: debe leerse igual con CardTables ---
	var card: Dictionary = ok["card"]
	var tables := CardTables.new()
	tables.props = PackedInt64Array([ModCards.pack_prop(card)])
	check(((tables.prop(0) >> 9) & 0x1ff) * 10 == 4000 and (tables.prop(0) & 0x1ff) * 10 == 4000, "atk/def en prop")
	check(((tables.prop(0) >> 25) & 0xf) == 10 and tables.type_of(0) == 1 and (tables.prop(0) >> 29) == 2, "nivel/tipo/atributo en prop")
	check(((tables.prop(0) >> 18) & 3) == 1, "clase efecto en prop")

	# --- mods en disco ---
	write(mods.path_join("gods/mod.json"), JSON.stringify({"id": "gods", "name": "Gods", "version": "1", "api": 1, "games": ["yugi"]}))
	write(mods.path_join("gods/cards.json"), JSON.stringify([
		monster("obelisk"), monster("slifer", {"atk": 0, "defense": 0}),
		monster("obelisk"),                      # key repetida
		monster("broken", {"atk": 4005}),        # invalida
		{"key": "trapdoor", "category": "trap", "names": {"eng": "Trap"}, "descriptions": {"eng": "d"}, "games": ["yugi", "kaiba"]},
	]))
	write(mods.path_join("extra/mod.json"), JSON.stringify({"id": "extra", "name": "Extra", "version": "1", "api": 1}))
	write(mods.path_join("extra/cards.json"), JSON.stringify([monster("ra")]))
	ModRegistry.set_enabled(storage, ["gods"])

	# --- tablas ---
	var t := base_tables()
	var added := ModCards.apply_to_tables(t, storage)
	check(added == 3, "3 cartas anadidas (hubo %d)" % added)
	check(t.id_of(7) == 1917 and t.id_of(8) == 1916 and t.id_of(9) == 1915, "ids de 1919 hacia abajo evitando 1919 y el par 1918/3918 (%d,%d,%d)" % [t.id_of(7), t.id_of(8), t.id_of(9)])
	check(t.index_of(1917) == 7 and t.index_of(1916) == 8 and t.index_of(1915) == 9, "index_of es el inverso de id_of")
	check(t.type_of(7) == 1 and t.type_of(9) == 21, "tipo de carta/trampa")
	check(t.packs[7] == 1 and t.packs[9] == 3, "bits de pack")
	check(t.id_of(5) == 1918 and t.id_of(6) == 3918 and t.index_of(1918) == 5 and t.index_of(3918) == 6, "tablas base intactas")
	check(t.id_of(10) == 0xffff or t.id_of(10) == 0, "mas alla del final no hay carta")
	var reg_path := mods.path_join("slots.json")
	check(FileAccess.file_exists(reg_path), "registro de ids escrito")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(reg_path))
	check(registry.get("gods:obelisk") == 1917 and registry.get("gods:slifer") == 1916, "registro guarda gods:obelisk/slifer")

	# --- base de datos: misma asignacion que las tablas ---
	var db := ModCards.apply_to_db(base_db(), storage)
	check(db.size() == 3, "3 cartas en CardDB")
	for c: Dictionary in db:
		check(t.id_of(c["index"]) == c["internal_id"], "DB y tablas coinciden en %s" % c["key"])
		check(c["mod"] == "gods", "carta marcada con su mod")
	check(db[0]["names"]["eng"] == "Obelisk" and db[0]["monster_kind"] == "effect", "esquema de cards.json")

	# --- estabilidad: otro mod antes no cambia los ids existentes ---
	ModRegistry.set_enabled(storage, ["extra", "gods"])
	var t2 := base_tables()
	check(ModCards.apply_to_tables(t2, storage) == 4, "4 cartas con ambos mods")
	check(t2.index_of(1917) != 0 and t2.id_of(t2.index_of(1917)) == 1917, "obelisk conserva su id")
	check(t2.index_of(1916) != 0 and t2.index_of(1915) != 0, "slifer/trapdoor conservan su id")
	var reg2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(reg_path))
	check(reg2.get("extra:ra") == 1914, "carta nueva toma el siguiente id libre")
	var after := ModCards.apply_to_db(base_db(), storage)
	var t3 := base_tables()
	ModCards.apply_to_tables(t3, storage)
	for c: Dictionary in after:
		check(t3.id_of(c["index"]) == c["internal_id"], "DB/tablas coinciden con 2 mods: %s" % c["key"])

	# --- desactivar mods restaura las tablas base ---
	ModRegistry.set_enabled(storage, [])
	var t4 := base_tables()
	check(ModCards.apply_to_tables(t4, storage) == 0 and t4.ids.size() == 7, "sin mods no se toca nada")

	# --- reactivar recupera el mismo id ---
	ModRegistry.set_enabled(storage, ["gods"])
	var t5 := base_tables()
	ModCards.apply_to_tables(t5, storage)
	check(t5.index_of(1917) == 7, "al reactivar vuelve el mismo id")

	# --- capacidad: tablas casi llenas ---
	var full := base_tables()
	full.ids.resize(ModCards.MAX_INDEX - 1)
	full.props.resize(ModCards.MAX_INDEX - 1)
	full.packs.resize(ModCards.MAX_INDEX - 1)
	full.ids[ModCards.MAX_INDEX - 2] = 500
	check(ModCards.apply_to_tables(full, storage) == 2, "solo caben 2 cartas mas (indices %d y %d)" % [ModCards.MAX_INDEX - 1, ModCards.MAX_INDEX])

	# --- tablas reales: 1114 cartas base, el motor solo tenia hueco para 1 (MAX_INDEX base 0x45b) ---
	var real := CardTables.new()
	real.ids.resize(1115)
	real.props.resize(1115)
	real.packs.resize(1115)
	real.int_ids.resize(2048)
	for i in range(1, 1115):
		real.ids[i] = i
		real.props[i] = 1
		real.packs[i] = 1
		real.int_ids[i] = i
	check(real.max_index == 0x45b, "max_index base = 0x45b")
	check(ModCards.apply_to_tables(real, storage) == 3, "caben 3 cartas con las tablas reales llenas")
	check(real.max_index == 1117, "max_index sube a 1117 (%d)" % real.max_index)
	var real_ok := true
	for i in range(1115, 1118):
		var rid := real.id_of(i)
		real_ok = real_ok and rid != 0xffff and rid < 0x780 and real.index_of(rid) == i
	check(real_ok, "id_of/index_of validos para los indices nuevos y ids < 0x780")
	check(real.id_of(1118) == 0xffff, "mas alla del ultimo indice sigue devolviendo 0xffff")

	# --- prop bytes del editor ---
	var raw := PackedByteArray()
	raw.resize(24)
	var bytes := ModCards.extend_prop_bytes(raw, db)
	check(bytes.size() == (db[2]["index"] + 1) * 4 and bytes.decode_u32(db[0]["index"] * 4) == ModCards.pack_prop(db[0]), "extend_prop_bytes")

	# --- CardDB real (autoload) con un cards.json base sintetico ---
	var data_dir: String = root.get_node("Paths").data_dir
	var base_json: Array = []
	for c: Dictionary in base_db():
		c["pack"] = 1
		c["category"] = "monster"
		c["image"] = null
		base_json.append(c)
	write(data_dir.path_join("common/db/cards.json"), JSON.stringify(base_json))
	ModRegistry.set_enabled(storage, ["gods"])
	root.get_node("Assets").reindex()
	var cdb: Node = root.get_node("CardDB")
	cdb.load_db()
	check(cdb.cards.size() == 9 and cdb.mod_cards.size() == 3, "CardDB: 6 base + 3 de mods (%d/%d)" % [cdb.cards.size(), cdb.mod_cards.size()])
	check(cdb.name_of(1917, "eng") == "Obelisk" and cdb.by_id(1917)["mod"] == "gods", "CardDB.by_id/name_of con carta de mod")
	check(cdb.obtainable_in("yugi").size() == 9 and cdb.obtainable_in("kaiba").size() == 1, "pack: las de mod solo en los juegos declarados")
	check(cdb.is_usable(1917, "joey") and cdb.is_usable(1917, "yugi"), "usable en el juego declarado y en los posteriores")
	check(cdb.by_id(1917)["index"] == 7, "indice en CardDB = indice en tablas")
	ModRegistry.set_enabled(storage, [])
	root.get_node("Assets").reindex()
	cdb.load_db()
	check(cdb.cards.size() == 6 and cdb.by_id(1917).is_empty(), "sin mods CardDB vuelve a las 6 base")

	if failures.is_empty():
		print("mod_cards_test: OK")
		quit(0)
	else:
		printerr("mod_cards_test: %d fallos" % failures.size())
		quit(1)
