extends SceneTree
## Prueba sin datos originales: las cartas de mods se apartan y se devuelven intactas.
## godot --headless --path game --script res://tests/mod_save_test.gd -- --storage=<dir vacio> --data=<dir vacio>

var failures: Array = []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FALLO: ", what)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var ids := ModSave.ids_of([{"internal_id": 1919}, {"internal_id": 1918}])
	check(ids.size() == 2 and ids.has(1919) and ids.has(1918), "ids_of")

	var split := ModSave.split_counts({"1": 3, "1919": 3, "500": 2, "1918": 1}, ids)
	check(split["mod"] == {"1919": 3, "1918": 1} and split["rest"] == {"1": 3, "500": 2}, "split_counts separa por id")
	check(ModSave.split_counts({}, ids)["mod"].is_empty(), "split_counts vacio")
	check(ModSave.split_counts({"1": 3}, {})["rest"] == {"1": 3}, "sin mods todo queda en rest")

	# Los mazos guardados en JSON traen floats (34.0): se conservan tal cual.
	var deck := {"main": [34.0, 1919.0, 21.0, 1919.0], "side": [1918.0], "fusion": [408.0]}
	var stripped := ModSave.strip_deck(deck, ids)
	check(stripped["count"] == 3, "strip_deck cuenta 3 cartas de mods (%d)" % stripped["count"])
	check(stripped["deck"] == {"main": [34.0, 21.0], "side": [], "fusion": [408.0]}, "strip_deck deja solo cartas base")
	check(deck["main"].size() == 4, "strip_deck no modifica el original")
	var back := ModSave.restore_deck(stripped["deck"], stripped["removed"])
	check(back["main"].size() == 4 and back["side"] == [1918.0] and back["fusion"] == [408.0], "restore_deck devuelve las cartas")
	var sorted_main: Array = back["main"].duplicate()
	sorted_main.sort()
	check(sorted_main == [21.0, 34.0, 1919.0, 1919.0], "restore_deck conserva las copias")

	var none := ModSave.strip_deck({"main": [1.0, 2.0], "side": [], "fusion": []}, ids)
	check(none["count"] == 0 and ModSave.restore_deck(none["deck"], none["removed"]) == none["deck"], "sin cartas de mods no cambia nada")
	check(ModSave.strip_deck({}, ids)["deck"].is_empty(), "mazo vacio")

	if failures.is_empty():
		print("mod_save_test: OK")
		quit(0)
	else:
		printerr("mod_save_test: %d fallos" % failures.size())
		quit(1)
