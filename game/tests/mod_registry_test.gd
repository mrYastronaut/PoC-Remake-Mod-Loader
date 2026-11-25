extends SceneTree
## Prueba sin datos originales: crea mods sinteticos y comprueba descubrimiento, orden,
## dependencias, filtros y superposicion de assets.
## godot --headless --path game --script res://tests/mod_registry_test.gd -- --storage=<dir vacio> --data=<dir vacio>

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


func manifest(id: String, extra := {}) -> String:
	var m := {"id": id, "name": id.capitalize(), "version": "1.0.0", "api": 1}
	m.merge(extra, true)
	return JSON.stringify(m)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var paths := root.get_node("Paths")
	var assets := root.get_node("Assets")
	var storage: String = paths.storage_dir
	var data: String = paths.data_dir
	var mods := storage.path_join("mods")

	# Base: un archivo que los mods pueden reemplazar.
	write(data.path_join("common/shared.txt"), "base")
	write(data.path_join("common/db/cards.json"), "[]")

	write(mods.path_join("alpha/mod.json"), manifest("alpha", {"games": ["yugi"]}))
	write(mods.path_join("alpha/assets/yugi/card/god.txt"), "alpha-god")
	write(mods.path_join("alpha/assets/kaiba/card/nope.txt"), "wrong game")
	write(mods.path_join("alpha/assets/common/db/cards.json"), "[\"hack\"]")
	write(mods.path_join("alpha/assets/common/shared.txt"), "alpha")
	write(mods.path_join("alpha/assets/common/Mixed_Case.TXT"), "alpha-case")

	write(mods.path_join("beta/mod.json"), manifest("beta", {"requires": ["alpha"]}))
	write(mods.path_join("beta/assets/common/shared.txt"), "beta")

	write(mods.path_join("needy/mod.json"), manifest("needy", {"requires": ["ghost"]}))
	write(mods.path_join("ocgmod/mod.json"), manifest("ocgmod", {"engine": "ocg"}))
	write(mods.path_join("wrongname/mod.json"), manifest("someone-else"))
	write(mods.path_join("badapi/mod.json"), manifest("badapi", {"api": 2}))
	write(mods.path_join("../escape/mod.json"), manifest("escape"))

	# Validacion pura del manifiesto.
	check(ModRegistry.valid_id("yugis-gods"), "id valido")
	check(not ModRegistry.valid_id("../x"), "id con ruta rechazado")
	check(not ModRegistry.valid_id("A"), "id corto/mayuscula rechazado")
	check(not ModRegistry.parse_manifest("no es json", "x")["ok"], "json roto")
	check(not ModRegistry.parse_manifest(manifest("alpha"), "otra")["ok"], "carpeta distinta del id")
	check(not ModRegistry.parse_manifest(manifest("a1", {"games": ["pegasus"]}), "a1")["ok"], "juego desconocido")
	check(not ModRegistry.parse_manifest(manifest("a1", {"games": []}), "a1")["ok"], "games vacio")
	check(ModRegistry.parse_manifest(manifest("a1"), "a1")["ok"], "manifiesto minimo valido")

	var discovered := ModRegistry.discover(storage)
	var by_id := {}
	for m: Dictionary in discovered:
		by_id[m["id"]] = m
	check(by_id.has("alpha") and by_id["alpha"]["ok"], "alpha descubierto")
	check(by_id.has("wrongname") and not by_id["wrongname"]["ok"], "wrongname invalido")
	check(by_id.has("badapi") and not by_id["badapi"]["ok"], "badapi invalido")

	# Sin lista de activados no se aplica nada.
	assets.reindex()
	check(assets.active_mods.is_empty(), "nada activo por defecto")
	check(assets.resolve("yugi/card/god.txt") == "", "asset de mod ausente si no esta activo")

	# beta antes que alpha: su dependencia no esta cargada aun.
	ModRegistry.set_enabled(storage, ["beta", "alpha", "needy", "ocgmod", "wrongname", "badapi", "ghost"])
	assets.reindex()
	var ids: Array = assets.active_mods.map(func(m): return m["id"])
	check(ids == ["alpha"], "solo alpha activo, fue " + str(ids))
	var reasons := {}
	for s: Dictionary in assets.mod_skipped:
		reasons[s["id"]] = s["reason"]
	check(reasons.has("beta"), "beta omitido por dependencia no cargada aun")
	check(reasons.has("needy") and reasons.has("ocgmod") and reasons.has("ghost"), "needy/ocgmod/ghost omitidos")
	check(reasons.has("wrongname") and reasons.has("badapi"), "invalidos omitidos")

	# Orden correcto: alpha, luego beta. El ultimo gana y se registran los reemplazos.
	ModRegistry.set_enabled(storage, ["alpha", "beta"])
	assets.reindex()
	check(assets.active_mods.size() == 2, "alpha y beta activos")
	check(FileAccess.get_file_as_string(assets.resolve("common/shared.txt")) == "beta", "beta sobrescribe a alpha")
	check(FileAccess.get_file_as_string(assets.resolve("yugi/card/god.txt")) == "alpha-god", "asset nuevo de alpha")
	check(FileAccess.get_file_as_string(assets.resolve("common/mixed_case.txt")) == "alpha-case", "indice sin distinguir mayusculas")
	check(FileAccess.get_file_as_string(assets.resolve("common/db/cards.json")) == "[]", "tabla protegida intacta")
	check(assets.resolve("kaiba/card/nope.txt") == "", "juego no declarado rechazado")
	var reasons_rej: Array = assets.mod_rejected.map(func(r): return r["reason"])
	check(reasons_rej.has("tabla protegida") and reasons_rej.has("juego no declarado"), "rechazos registrados")
	var replaced: Array = assets.mod_overrides.filter(func(o): return o["path"] == "common/shared.txt")
	check(replaced.size() == 2 and replaced[0]["replaced"] == "base" and replaced[1]["replaced"] == "alpha", "reemplazos trazados")

	# Quitar los mods devuelve el estado base.
	ModRegistry.set_enabled(storage, [])
	assets.reindex()
	check(FileAccess.get_file_as_string(assets.resolve("common/shared.txt")) == "base", "base restaurada")

	# --- scripts en mod.json ---
	check(ModRegistry.parse_manifest(manifest("s1", {"scripts": ["scripts/a.gd", "scripts/sub/b_c.gd"]}), "s1")["ok"], "scripts validos")
	check(ModRegistry.parse_manifest(manifest("s1"), "s1")["manifest"]["scripts"] == [], "sin scripts: lista vacia")
	for bad_script in ["a.gd", "scripts/../x.gd", "scripts/a.txt", "/scripts/a.gd", "scripts\\a.gd", "scripts/a b.gd", "scripts/.gd"]:
		check(not ModRegistry.parse_manifest(manifest("s1", {"scripts": [bad_script]}), "s1")["ok"], "script invalido rechazado: " + bad_script)
	check(not ModRegistry.parse_manifest(manifest("s1", {"scripts": "scripts/a.gd"}), "s1")["ok"], "scripts debe ser una lista")
	var many: Array = []
	for i in 9:
		many.append("scripts/s%d.gd" % i)
	check(not ModRegistry.parse_manifest(manifest("s1", {"scripts": many}), "s1")["ok"], "mas de 8 scripts rechazado")

	# --- ModScripts: permiso del jugador, scripts activos y carga ---
	write(mods.path_join("scr1/mod.json"), manifest("scr1", {"scripts": ["scripts/a.gd"]}))
	write(mods.path_join("scr1/scripts/a.gd"), "extends ModScript\nfunc _init() -> void:\n\teffects = [\"t\"]\n")
	write(mods.path_join("scr1/scripts/bad.gd"), "this is not gdscript\n")
	write(mods.path_join("scr1/scripts/other.gd"), "extends RefCounted\n")
	ModRegistry.set_enabled(storage, ["scr1"])
	check(not ModScripts.allowed(storage), "los scripts estan desactivados por defecto")
	check(ModScripts.active_scripts(storage).is_empty(), "sin permiso no hay scripts activos")
	check(ModScripts.set_allowed(storage, true) and ModScripts.allowed(storage), "el jugador permite los scripts")
	var active_scripts := ModScripts.active_scripts(storage)
	check(active_scripts.size() == 1 and active_scripts[0]["mod"] == "scr1" and str(active_scripts[0]["path"]).ends_with("scr1/scripts/a.gd"), "con permiso: el script del mod activo (%s)" % str(active_scripts))
	var loaded := ModScripts.instantiate(str(active_scripts[0]["path"]))
	check(loaded != null and loaded.effects == ["t"], "el script se compila y es un ModScript")
	check(ModScripts.instantiate(mods.path_join("scr1/scripts/bad.gd")) == null, "un script que no compila se rechaza")
	check(ModScripts.instantiate(mods.path_join("scr1/scripts/other.gd")) == null, "un script que no extiende ModScript se rechaza")
	check(ModScripts.instantiate(mods.path_join("scr1/scripts/missing.gd")) == null, "un script que no existe se rechaza")
	ModRegistry.set_enabled(storage, [])
	check(ModScripts.active_scripts(storage).is_empty(), "un mod desactivado no aporta scripts")
	ModScripts.set_allowed(storage, false)
	ModRegistry.remove(storage, "scr1")

	if failures.is_empty():
		print("mod_registry_test: OK")
		quit(0)
	else:
		printerr("mod_registry_test: %d fallos" % failures.size())
		quit(1)
