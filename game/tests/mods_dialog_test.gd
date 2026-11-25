extends SceneTree
## Pantalla Mods sin ventana real: construye el dialogo, comprueba las filas y simula las
## acciones del usuario llamando a los mismos manejadores que las senales de los botones.
## godot --headless --path game --script res://tests/mods_dialog_test.gd -- --storage=<dir vacio> --data=<dir vacio>

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
	var m := {"id": id, "name": id.capitalize(), "version": "1.0", "api": 1}
	m.merge(extra, true)
	return JSON.stringify(m)


func find_all(node: Node, type: String) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child.is_class(type):
			found.append(child)
		found.append_array(find_all(child, type))
	return found


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var paths := root.get_node("Paths")
	var assets := root.get_node("Assets")
	var storage: String = paths.storage_dir
	var mods := storage.path_join("mods")

	write(mods.path_join("alpha/mod.json"), manifest("alpha", {"games": ["yugi"]}))
	write(mods.path_join("alpha/assets/yugi/x.txt"), "A")
	write(mods.path_join("beta/mod.json"), manifest("beta", {"requires": ["alpha"]}))
	write(mods.path_join("broken/mod.json"), "{ no es json")

	var dialog: AcceptDialog = load("res://scenes/launcher/mods_dialog.gd").new()
	root.add_child(dialog)
	await process_frame
	dialog.open()
	await process_frame

	# Un Label con ajuste de linea y sin ancho minimo infla el alto de la ventana (una palabra por
	# linea al calcular el minimo) y los botones quedan fuera de pantalla: todos deben tenerlo.
	var wrapped: Array = find_all(dialog, "Label").filter(func(l): return l.autowrap_mode != TextServer.AUTOWRAP_OFF)
	check(wrapped.size() >= 4, "hay etiquetas con ajuste de linea (%d)" % wrapped.size())
	for label: Label in wrapped:
		check(label.custom_minimum_size.x >= 300.0, "etiqueta con ajuste sin ancho minimo: '%s'" % label.text.left(30))

	var boxes := find_all(dialog._list, "CheckBox")
	check(boxes.size() == 3, "3 filas (hubo %d)" % boxes.size())
	var invalid_boxes := boxes.filter(func(b): return b.disabled)
	check(invalid_boxes.size() == 1, "el mod roto no se puede marcar")
	check(dialog.title == "Mods" and dialog.get_ok_button().text != "", "titulo y boton cerrar")
	check(dialog._path.text.contains("mods"), "muestra la carpeta de mods")

	# Marcar beta activa tambien alpha (dependencia) y lo aplica al indice de archivos.
	dialog._toggled(true, "beta")
	check(ModRegistry.enabled_ids(storage) == ["alpha", "beta"], "beta arrastra alpha")
	check(assets.active_mods.size() == 2 and assets.resolve("yugi/x.txt") != "", "aplicado al instante en Assets")
	var texts: Array = find_all(dialog._list, "Label").map(func(l): return l.text)
	check(texts.any(func(t): return t.begins_with("Active")), "estado Active visible")

	dialog._move("alpha", 1)
	check(ModRegistry.enabled_ids(storage) == ["beta", "alpha"], "mover desde la interfaz")
	texts = find_all(dialog._list, "Label").map(func(l): return l.text)
	check(texts.any(func(t): return t.begins_with("Skipped")), "beta queda Skipped si su dependencia carga despues")

	dialog._toggled(false, "alpha")
	check(assets.resolve("yugi/x.txt") == "", "desactivar quita sus archivos del indice")

	# Idioma: textos traducidos y sin claves sueltas.
	for lang in ["s", "e", "g", "f", "i", "j"]:
		assets.lang = lang
		dialog._refresh()
		check(dialog._hint.text != "" and dialog._install_button.text != "", "textos en " + lang)
	var english: Dictionary = dialog.TEXT["e"]
	for lang in dialog.TEXT:
		check(dialog.TEXT[lang].keys().size() == english.keys().size(), "mismas claves en " + lang)
	assets.lang = "e"
	dialog._refresh()

	# Instalar desde zip: exito, ya instalado (pide confirmacion), error traducido.
	var zip_path := storage.path_join("zips/new.zip")
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var zip := ZIPPacker.new()
	zip.open(zip_path)
	zip.start_file("mod.json")
	zip.write_file(manifest("gamma").to_utf8_buffer())
	zip.close_file()
	zip.close()
	dialog._install(zip_path, false)
	check(DirAccess.dir_exists_absolute(mods.path_join("gamma")), "instalado desde la interfaz")
	check(dialog._status.text.contains("Installed") and not ModRegistry.enabled_ids(storage).has("gamma"), "mensaje de exito y no se activa solo")
	dialog._install(zip_path, false)
	check(dialog._confirm.visible and dialog._pending.get("action") == "replace", "pide confirmar el reemplazo")
	dialog._confirmed()
	check(dialog._status.text.contains("Installed"), "reemplazo confirmado")
	write(storage.path_join("zips/bad.zip"), "no es un zip")
	dialog._install(storage.path_join("zips/bad.zip"), false)
	check(dialog._status.text.begins_with("Could not install"), "error de instalacion mostrado: " + dialog._status.text)

	# Quitar con confirmacion.
	dialog._ask_remove("gamma", "Gamma")
	check(dialog._confirm.visible and dialog._confirm.dialog_text.contains("Gamma"), "confirmacion de quitar")
	dialog._confirmed()
	check(not DirAccess.dir_exists_absolute(mods.path_join("gamma")), "mod quitado")

	# Sin mods: mensaje vacio.
	for id in ["alpha", "beta", "broken"]:
		ModRegistry.remove(storage, id)
	dialog._refresh()
	check(find_all(dialog._list, "CheckBox").is_empty() and find_all(dialog._list, "Label").size() == 1, "lista vacia con mensaje")

	# El medallon existe en los controles del selector y se detecta al pulsarlo.
	var controls: Node2D = load("res://scenes/launcher/launcher_controls.gd").new()
	root.add_child(controls)
	await process_frame
	var center: Vector2 = controls._mods_center()
	check(controls._hit(center) == "mods" and controls._hit(controls._sound_center()) == "sound", "medallon Mods detectable sin pisar el de sonido")
	check(center.x > controls._sound_center().x and center.y == controls._sound_center().y, "colocado junto al de sonido")

	if failures.is_empty():
		print("mods_dialog_test: OK")
		quit(0)
	else:
		printerr("mods_dialog_test: %d fallos" % failures.size())
		quit(1)
