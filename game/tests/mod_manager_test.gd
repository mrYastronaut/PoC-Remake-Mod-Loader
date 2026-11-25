extends SceneTree
## Operaciones de la pantalla Mods (activar, ordenar, quitar) e instalador de .zip, con zips
## sinteticos, incluidos los que intentan escribir fuera de mods/ (zip-slip).
## godot --headless --path game --script res://tests/mod_manager_test.gd -- --storage=<dir vacio> --data=<dir vacio>

var failures: Array = []
var storage := ""
var mods := ""


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


func make_zip(path: String, files: Dictionary) -> String:
	var zip := ZIPPacker.new()
	zip.open(path)
	for name in files:
		zip.start_file(name)
		var content: Variant = files[name]
		zip.write_file(content if content is PackedByteArray else str(content).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return path


func ids_of(rows: Array) -> Array:
	return rows.map(func(r): return r["id"])


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	storage = root.get_node("Paths").storage_dir
	mods = storage.path_join("mods")
	var tmp := storage.path_join("zips")
	DirAccess.make_dir_recursive_absolute(tmp)

	# ---------------- operaciones del registro ----------------
	write(mods.path_join("alpha/mod.json"), manifest("alpha", {"description": "base", "author": "yo"}))
	write(mods.path_join("alpha/cards.json"), JSON.stringify([{"key": "a"}, {"key": "b"}]))
	write(mods.path_join("alpha/assets/common/x.txt"), "x")
	write(mods.path_join("beta/mod.json"), manifest("beta", {"requires": ["alpha"]}))
	write(mods.path_join("gamma/mod.json"), manifest("gamma", {"engine": "nope"}))
	write(mods.path_join("delta/mod.json"), manifest("delta"))

	var rows := ModRegistry.rows(storage)
	check(ids_of(rows) == ["alpha", "beta", "delta", "gamma"], "filas por id si no hay activados: " + str(ids_of(rows)))
	check(rows[0]["status"] == "disabled" and rows[0]["cards"] == 2 and rows[0]["author"] == "yo", "fila alpha desactivada con 2 cartas")
	check(rows[3]["status"] == "invalid" and rows[3]["detail"] != "", "gamma invalido con motivo")

	check(not ModRegistry.enable(storage, "gamma"), "no se activa un mod invalido")
	check(not ModRegistry.enable(storage, "ghost"), "no se activa un mod no instalado")
	check(ModRegistry.enable(storage, "beta"), "activar beta")
	check(ModRegistry.enabled_ids(storage) == ["alpha", "beta"], "beta arrastra su dependencia delante: " + str(ModRegistry.enabled_ids(storage)))
	check(ModRegistry.enable(storage, "beta") and ModRegistry.enabled_ids(storage) == ["alpha", "beta"], "activar dos veces no duplica")

	rows = ModRegistry.rows(storage)
	check(ids_of(rows) == ["alpha", "beta", "delta", "gamma"] and rows[0]["status"] == "active" and rows[1]["status"] == "active", "alpha y beta activos")

	check(ModRegistry.disable(storage, "alpha"), "desactivar alpha")
	rows = ModRegistry.rows(storage)
	check(rows[0]["id"] == "beta" and rows[0]["status"] == "skipped" and "alpha" in rows[0]["detail"], "beta omitido por falta de alpha: " + str(rows[0]))

	ModRegistry.enable(storage, "alpha")   # ahora alpha queda DETRAS de beta
	check(ModRegistry.enabled_ids(storage) == ["beta", "alpha"], "orden tras reactivar")
	check(ModRegistry.rows(storage)[0]["status"] == "skipped", "beta sigue omitido: su dependencia carga despues")
	check(ModRegistry.move(storage, "alpha", -1), "mover alpha antes")
	check(ModRegistry.enabled_ids(storage) == ["alpha", "beta"], "orden tras mover")
	check(ModRegistry.rows(storage)[1]["status"] == "active", "beta activo al corregir el orden")
	check(not ModRegistry.move(storage, "alpha", -1), "no se mueve por encima del primero")
	check(not ModRegistry.move(storage, "beta", 1), "no se mueve por debajo del ultimo")
	check(not ModRegistry.move(storage, "delta", 1), "no se mueve uno desactivado")

	# ids fantasma (mod desinstalado a mano) no estorban al mover
	ModRegistry.set_enabled(storage, ["alpha", "ghost", "beta"])
	check(ModRegistry.move(storage, "alpha", 1), "mover saltando el fantasma")
	check(ModRegistry.enabled_ids(storage) == ["ghost", "beta", "alpha"], "orden con fantasma: " + str(ModRegistry.enabled_ids(storage)))
	check(ids_of(ModRegistry.rows(storage)).slice(0, 2) == ["beta", "alpha"], "el fantasma no sale en las filas")

	# quitar
	write(mods.path_join("slots.json"), "{\"alpha:a\": 1910}")
	check(not ModRegistry.remove(storage, "../escape") and not ModRegistry.remove(storage, "nada"), "remove rechaza ids invalidos o ausentes")
	check(ModRegistry.remove(storage, "alpha"), "quitar alpha")
	check(not DirAccess.dir_exists_absolute(mods.path_join("alpha")), "carpeta de alpha borrada")
	check(FileAccess.file_exists(mods.path_join("slots.json")), "slots.json se conserva")
	check(not ModRegistry.enabled_ids(storage).has("alpha"), "alpha fuera de la lista")
	check(DirAccess.dir_exists_absolute(mods.path_join("beta")), "beta intacto")

	# ---------------- instalador ----------------
	check(ModInstaller.safe_relative("a/b.png") == "a/b.png", "ruta normal")
	for bad in ["../x", "a/../../x", "/abs", "C:/x", "a//b", "a\\..\\b", "..", "./x", ""]:
		check(ModInstaller.safe_relative(bad) == "", "ruta rechazada: '%s'" % bad)

	var good := make_zip(tmp.path_join("good.zip"), {
		"mod.json": manifest("zeta", {"games": ["yugi"]}), "cards.json": "[]", "assets/common/a.txt": "A", "__MACOSX/._x": "junk"})
	var r := ModInstaller.install_zip(storage, good)
	check(r["ok"] and r["id"] == "zeta" and r["files"] == 3, "instala zip con mod.json en la raiz: " + str(r))
	check(FileAccess.get_file_as_string(mods.path_join("zeta/assets/common/a.txt")) == "A", "contenido extraido")
	check(not FileAccess.file_exists(mods.path_join("zeta/__MACOSX/._x")), "basura de macOS ignorada")
	check(ModRegistry.discover(storage).any(func(m): return m["id"] == "zeta" and m["ok"]), "el mod instalado se descubre")

	var nested := make_zip(tmp.path_join("nested.zip"), {
		"my-pack/mod.json": manifest("eta"), "my-pack/assets/common/b.txt": "B", "readme.txt": "fuera del mod"})
	r = ModInstaller.install_zip(storage, nested)
	check(r["ok"] and r["id"] == "eta" and FileAccess.file_exists(mods.path_join("eta/assets/common/b.txt")), "carpeta superior unica")
	check(not FileAccess.file_exists(mods.path_join("eta/readme.txt")), "lo de fuera de la carpeta no se instala")

	var again := ModInstaller.install_zip(storage, good)
	check(not again["ok"] and again["exists"], "ya instalado sin replace")
	var changed := make_zip(tmp.path_join("changed.zip"), {"mod.json": manifest("zeta", {"version": "2.0.0"}), "assets/common/new.txt": "N"})
	r = ModInstaller.install_zip(storage, changed, true)
	check(r["ok"] and FileAccess.file_exists(mods.path_join("zeta/assets/common/new.txt")), "replace instala la nueva version")
	check(not FileAccess.file_exists(mods.path_join("zeta/assets/common/a.txt")), "replace no deja archivos de la version anterior")
	check(not DirAccess.dir_exists_absolute(mods.path_join(".old-zeta")) and not DirAccess.dir_exists_absolute(mods.path_join(".installing-zeta")), "sin carpetas temporales")

	# zip-slip y rutas peligrosas: rechazo total, nada escrito fuera ni a medias
	var outside := storage.path_join("evil.txt")
	var attacks := {
		"slip": {"mod.json": manifest("theta"), "../evil.txt": "pwn"},
		"slip2": {"mod.json": manifest("theta"), "assets/../../evil.txt": "pwn"},
		"absolute": {"mod.json": manifest("theta"), "/etc/evil.txt": "pwn"},
		"backslash": {"mod.json": manifest("theta"), "..\\evil.txt": "pwn"},
		"drive": {"mod.json": manifest("theta"), "C:/evil.txt": "pwn"},
	}
	for key in attacks:
		r = ModInstaller.install_zip(storage, make_zip(tmp.path_join(key + ".zip"), attacks[key]))
		check(not r["ok"], "ataque %s rechazado" % key)
		check(not FileAccess.file_exists(outside) and not DirAccess.dir_exists_absolute(mods.path_join("theta")), "ataque %s no escribio nada" % key)

	check(not ModInstaller.install_zip(storage, make_zip(tmp.path_join("nomanifest.zip"), {"a.txt": "x"}))["ok"], "sin mod.json")
	check(not ModInstaller.install_zip(storage, make_zip(tmp.path_join("two.zip"), {"mod.json": manifest("iota"), "x/mod.json": manifest("kappa")}))["ok"], "dos mod.json")
	check(not ModInstaller.install_zip(storage, make_zip(tmp.path_join("badid.zip"), {"mod.json": manifest("../x")}))["ok"], "id con ruta")
	check(not ModInstaller.install_zip(storage, make_zip(tmp.path_join("badapi.zip"), {"mod.json": manifest("lambda", {"api": 9})}))["ok"], "api incorrecta")
	check(not ModInstaller.install_zip(storage, make_zip(tmp.path_join("badcards.zip"), {"mod.json": manifest("mu"), "cards.json": "{}"}))["ok"], "cards.json no es lista")
	check(not DirAccess.dir_exists_absolute(mods.path_join("mu")) and not DirAccess.dir_exists_absolute(mods.path_join(".installing-mu")), "fallo tardio no deja restos")
	check(not ModInstaller.install_zip(storage, tmp.path_join("no-existe.zip"))["ok"], "zip inexistente")
	write(tmp.path_join("garbage.zip"), "esto no es un zip")
	check(not ModInstaller.install_zip(storage, tmp.path_join("garbage.zip"))["ok"], "archivo que no es zip")

	var big := PackedByteArray()
	big.resize(ModInstaller.MAX_FILE_BYTES + 1)
	big.fill(65)
	r = ModInstaller.install_zip(storage, make_zip(tmp.path_join("big.zip"), {"mod.json": manifest("nu"), "assets/big.bin": big}))
	check(not r["ok"] and not DirAccess.dir_exists_absolute(mods.path_join("nu")) and not DirAccess.dir_exists_absolute(mods.path_join(".installing-nu")), "archivo gigante rechazado sin restos")

	if failures.is_empty():
		print("mod_manager_test: OK")
		quit(0)
	else:
		printerr("mod_manager_test: %d fallos" % failures.size())
		quit(1)
