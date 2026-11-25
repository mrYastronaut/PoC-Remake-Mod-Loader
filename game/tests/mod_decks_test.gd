extends SceneTree
## Prueba sin datos originales: parches de mazos de la CPU (ModDecks).
## godot --headless --path game --script res://tests/mod_decks_test.gd -- --storage=<dir vacio> --data=<dir vacio>

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


func base_deck(n := 40) -> Dictionary:
	var main := []
	for i in n:
		main.append(float(100 + i))     # como los .json de pocx: floats
	return {"main": main, "side": [], "fusion": [408.0]}


func mod_at(dir: String, id: String, games := ["yugi"]) -> Dictionary:
	return {"id": id, "dir": dir, "manifest": {"games": games}}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var storage: String = root.get_node("Paths").storage_dir
	var dir := storage.path_join("deckmods/gods")
	var cards := [{"mod": "gods", "key": "obelisk", "internal_id": 1919}, {"mod": "other", "key": "ra", "internal_id": 1918}]

	# --- referencias ---
	check(ModDecks.resolve_ref("obelisk", "gods", cards) == 1919, "clave del mismo mod")
	check(ModDecks.resolve_ref("other:ra", "gods", cards) == 1918, "mod:clave")
	check(ModDecks.resolve_ref("ra", "gods", cards) == -1, "clave de otro mod sin prefijo no resuelve")
	check(ModDecks.resolve_ref(500.0, "gods", cards) == 500 and ModDecks.resolve_ref(500, "gods", cards) == 500, "id numerico")
	check(ModDecks.resolve_ref(1.5, "gods", cards) == -1 and ModDecks.resolve_ref(-1, "gods", cards) == -1 and ModDecks.resolve_ref(4000, "gods", cards) == -1, "ids invalidos")
	check(ModDecks.resolve_ref(null, "gods", cards) == -1, "tipo invalido")

	# --- anadir y quitar ---
	write(dir.path_join("deck_patches.json"), JSON.stringify([
		{"file": "yugi/file/cpu*.json", "remove": {"main": [100, 100]}, "add": {"main": ["obelisk", "obelisk"], "side": [5]}},
	]))
	var mods := [mod_at(dir, "gods")]
	var original := base_deck()
	var errors: Array = []
	var out := ModDecks.apply("yugi/file/cpu01.json", original, mods, cards, errors)
	check(errors.is_empty(), "sin errores: " + str(errors))
	check(out["main"].size() == 41, "quita 1 (la 2.a no existe) y anade 2 = 41 (%d)" % out["main"].size())
	check(out["main"].count(1919) == 2 and not out["main"].has(100.0), "obelisk dos veces; 100 quitado")
	check(out["side"] == [5] and out["fusion"] == [408.0], "side anadido, fusion intacta")
	check(original["main"].size() == 40 and original["main"].has(100.0), "no modifica el original")

	# --- comodines y rutas ---
	check(ModDecks.apply("YUGI/File/CPUkk.json", base_deck(), mods, cards)["main"].has(1919), "sin distinguir mayusculas y * en cpuKK")
	check(not ModDecks.apply("yugi/file/starter_deck.json", base_deck(), mods, cards)["main"].has(1919), "otro archivo no se toca")
	check(not ModDecks.apply("kaiba/file/cpu01.json", base_deck(), mods, cards)["main"].has(1919), "otro juego no se toca")

	# --- mod que no declara el juego ---
	write(dir.path_join("deck_patches.json"), JSON.stringify([{"file": "yugi/file/*", "add": {"main": ["obelisk"]}}]))
	check(not ModDecks.apply("yugi/file/cpu01.json", base_deck(), [mod_at(dir, "gods", ["kaiba"])], cards)["main"].has(1919), "mod de otro juego no aplica")
	check(ModDecks.apply("yugi/file/cpu01.json", base_deck(), [mod_at(dir, "gods", ["yugi", "kaiba"])], cards)["main"].has(1919), "mod con el juego declarado aplica")

	# --- errores: el parche entero se ignora ---
	var cases := {
		"carta desconocida": [{"file": "yugi/*", "add": {"main": ["nope"]}}],
		"zona invalida": [{"file": "yugi/*", "add": {"hand": [1]}}],
		"add no es objeto": [{"file": "yugi/*", "add": [1]}],
		"sin file": [{"add": {"main": [1]}}],
		"main fuera de limites": [{"file": "yugi/*", "add": {"main": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]}}],
		"main bajo el minimo": [{"file": "yugi/*", "remove": {"main": [100]}}],
	}
	for name in cases:
		write(dir.path_join("deck_patches.json"), JSON.stringify(cases[name]))
		var errs: Array = []
		var res := ModDecks.apply("yugi/file/cpu01.json", base_deck(), mods, cards, errs)
		check(errs.size() == 1 and res == base_deck(), "%s: un error y mazo sin cambios (%s)" % [name, str(errs)])

	# --- archivo mal formado y un parche malo no impide el siguiente ---
	write(dir.path_join("deck_patches.json"), "{ no es json")
	var errs2: Array = []
	check(ModDecks.apply("yugi/file/cpu01.json", base_deck(), mods, cards, errs2) == base_deck() and errs2.size() == 1, "json invalido: un error")
	write(dir.path_join("deck_patches.json"), JSON.stringify([
		{"file": "yugi/*", "add": {"main": ["nope"]}}, {"file": "yugi/*", "add": {"main": ["obelisk"]}}]))
	var errs3: Array = []
	var res3 := ModDecks.apply("yugi/file/cpu01.json", base_deck(), mods, cards, errs3)
	check(errs3.size() == 1 and res3["main"].count(1919) == 1, "el parche valido se aplica tras uno malo")

	# --- varios mods, en orden ---
	var dir2 := storage.path_join("deckmods/second")
	write(dir.path_join("deck_patches.json"), JSON.stringify([{"file": "yugi/*", "add": {"main": ["obelisk"]}}]))
	write(dir2.path_join("deck_patches.json"), JSON.stringify([{"file": "yugi/*", "remove": {"main": [1919]}, "add": {"main": ["gods:obelisk", "gods:obelisk"]}}]))
	var multi := ModDecks.apply("yugi/file/cpu01.json", base_deck(), [mod_at(dir, "gods"), mod_at(dir2, "second")], cards)
	check(multi["main"].count(1919) == 2 and multi["main"].size() == 42, "el segundo mod ve el resultado del primero (%d)" % multi["main"].count(1919))
	check(ModDecks.apply("yugi/file/cpu01.json", base_deck(), [{"id": "x", "dir": storage.path_join("deckmods/none"), "manifest": {"games": ["yugi"]}}], cards) == base_deck(), "mod sin deck_patches.json")

	if failures.is_empty():
		print("mod_decks_test: OK")
		quit(0)
	else:
		printerr("mod_decks_test: %d fallos" % failures.size())
		quit(1)
