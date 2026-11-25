class_name ModRegistry
extends RefCounted
## Mods en carpetas sueltas: <PoC Data>/mods/<id>/mod.json (+ assets/, que replica resources/).
## Todo es estatico; el unico estado en disco es mods/enabled.json (lista ordenada de ids).
## Un mod posterior en la lista sobrescribe los archivos de uno anterior.
## Ver docs/MODDING.md. Las mismas reglas las comprueba tools/pocx/mods.py al empaquetar.

const API_VERSION := 1
const MANIFEST := "mod.json"
const ENABLED_FILE := "enabled.json"
const GAMES := ["yugi", "kaiba", "joey"]
## Motores que el lanzador sabe ejecutar hoy. "ocg" queda reservado.
const SUPPORTED_ENGINES := ["faithful"]
const ENGINES := ["faithful", "ocg"]
## Tablas que un mod NO puede reemplazar entero hasta que exista la fusion de cartas.
const PROTECTED_PREFIXES := ["common/bin/", "common/db/"]
const PROTECTED_FILES := ["inventory.json", "voice_manifest.json"]
const MAX_SCRIPTS := 8

static var _id_regex: RegEx = null
static var _script_regex: RegEx = null


static func mods_dir(storage_dir: String) -> String:
	return storage_dir.path_join("mods")


static func valid_id(id: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string("^[a-z0-9][a-z0-9_-]{1,39}$")
	return _id_regex.search(id) != null


## Ruta de un script de mod: scripts/<nombre>.gd (se admiten subcarpetas), sin "..".
static func valid_script_path(path: String) -> bool:
	if _script_regex == null:
		_script_regex = RegEx.create_from_string("^scripts/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\\.gd$")
	return path.length() <= 100 and _script_regex.search(path) != null


## Devuelve {"ok": bool, "manifest": Dictionary, "errors": Array[String]}.
## `folder_name` debe coincidir con el id para impedir suplantar carpetas.
static func parse_manifest(text: String, folder_name: String) -> Dictionary:
	var errors: Array = []
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"ok": false, "manifest": {}, "errors": ["mod.json no es un objeto JSON valido"]}
	var m: Dictionary = json.data
	var id := str(m.get("id", ""))
	if not valid_id(id):
		errors.append("id invalido (a-z, 0-9, _ y -, 2 a 40 caracteres)")
	elif id != folder_name:
		errors.append("la carpeta '%s' no coincide con el id '%s'" % [folder_name, id])
	if str(m.get("name", "")).strip_edges() == "":
		errors.append("falta name")
	if str(m.get("version", "")).strip_edges() == "":
		errors.append("falta version")
	var api: Variant = m.get("api", null)
	if not (api is int or api is float) or int(api) != API_VERSION or float(api) != float(int(api)):
		errors.append("api debe ser %d" % API_VERSION)
	var games: Array = m.get("games", GAMES)
	for g in games:
		if not GAMES.has(str(g)):
			errors.append("juego desconocido: " + str(g))
	if games.is_empty():
		errors.append("games no puede estar vacio")
	var engine := str(m.get("engine", "faithful"))
	if not ENGINES.has(engine):
		errors.append("engine desconocido: " + engine)
	var requires: Array = m.get("requires", [])
	for r in requires:
		if not valid_id(str(r)):
			errors.append("requires contiene un id invalido: " + str(r))
	var scripts_raw: Variant = m.get("scripts", [])
	var scripts: Array = []
	if not scripts_raw is Array:
		errors.append("scripts debe ser una lista de rutas scripts/<nombre>.gd")
	else:
		if (scripts_raw as Array).size() > MAX_SCRIPTS:
			errors.append("scripts admite como mucho %d archivos" % MAX_SCRIPTS)
		for entry in scripts_raw:
			if not entry is String or not valid_script_path(entry):
				errors.append("script invalido (usa scripts/<nombre>.gd): " + str(entry))
			elif not scripts.has(entry):
				scripts.append(entry)
	var clean := {
		"id": id,
		"name": str(m.get("name", "")),
		"version": str(m.get("version", "")),
		"author": str(m.get("author", "")),
		"description": str(m.get("description", "")),
		"api": int(api) if api is int or api is float else 0,
		"games": games.map(func(g): return str(g)),
		"engine": engine,
		"requires": requires.map(func(r): return str(r)),
		"scripts": scripts,
	}
	return {"ok": errors.is_empty(), "manifest": clean, "errors": errors}


## Todos los mods instalados, validos o no: [{id, dir, manifest, ok, errors}].
static func discover(storage_dir: String) -> Array:
	var found: Array = []
	var root := mods_dir(storage_dir)
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	var names: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			names.append(name)
		name = dir.get_next()
	names.sort()
	for folder: String in names:
		var mod_dir := root.path_join(folder)
		var path := mod_dir.path_join(MANIFEST)
		if not FileAccess.file_exists(path):
			continue
		var parsed := parse_manifest(FileAccess.get_file_as_string(path), folder)
		found.append({"id": folder, "dir": mod_dir, "manifest": parsed["manifest"],
				"ok": parsed["ok"], "errors": parsed["errors"]})
	return found


static func enabled_ids(storage_dir: String) -> Array:
	var path := mods_dir(storage_dir).path_join(ENABLED_FILE)
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Array:
		return []
	var ids: Array = []
	for id in json.data:
		if valid_id(str(id)) and not ids.has(str(id)):
			ids.append(str(id))
	return ids


static func set_enabled(storage_dir: String, ids: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(mods_dir(storage_dir))
	var file := FileAccess.open(mods_dir(storage_dir).path_join(ENABLED_FILE), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(ids, "  "))
	file.close()
	return true


## Mods que se aplican, en orden de carga. Descarta (y anota en `skipped`) los que son
## invalidos, de otro motor, o cuyas dependencias no estan activas ANTES en la lista.
static func active(storage_dir: String, skipped: Array = []) -> Array:
	var installed := {}
	for mod: Dictionary in discover(storage_dir):
		installed[mod["id"]] = mod
	var result: Array = []
	var loaded := {}
	for id: String in enabled_ids(storage_dir):
		if not installed.has(id):
			skipped.append({"id": id, "reason": "no esta instalado", "code": "not_installed", "arg": ""})
			continue
		var mod: Dictionary = installed[id]
		if not mod["ok"]:
			skipped.append({"id": id, "reason": "; ".join(mod["errors"]), "code": "invalid", "arg": ""})
			continue
		var manifest: Dictionary = mod["manifest"]
		if not SUPPORTED_ENGINES.has(manifest["engine"]):
			skipped.append({"id": id, "reason": "motor no soportado: " + manifest["engine"], "code": "engine", "arg": manifest["engine"]})
			continue
		var missing := ""
		for dep: String in manifest["requires"]:
			if not loaded.has(dep):
				missing = dep
				break
		if missing != "":
			skipped.append({"id": id, "reason": "falta la dependencia activa: " + missing, "code": "dependency", "arg": missing})
			continue
		loaded[id] = true
		result.append(mod)
	return result


## true si el archivo (ruta relativa a resources/) no puede reemplazarse desde un mod.
static func is_protected(rel_lower: String) -> bool:
	if PROTECTED_FILES.has(rel_lower):
		return true
	for prefix: String in PROTECTED_PREFIXES:
		if rel_lower.begins_with(prefix):
			return true
	return false


## true si el archivo pertenece a un juego que el mod no declara.
static func wrong_game(rel_lower: String, manifest: Dictionary) -> bool:
	var first := rel_lower.get_slice("/", 0)
	return GAMES.has(first) and not (manifest["games"] as Array).has(first)


# --- operaciones de la pantalla Mods ---------------------------------------------------------

## Filas para la interfaz: primero los activados (en orden de carga), despues el resto por id.
## {id, dir, name, version, author, description, games, engine, requires, cards, enabled,
##  status: "active" | "disabled" | "invalid" | "skipped", detail (tecnico), reason_code/reason_arg}
static func rows(storage_dir: String) -> Array:
	var installed := {}
	var order: Array = []
	for mod: Dictionary in discover(storage_dir):
		installed[mod["id"]] = mod
		order.append(mod["id"])
	var skipped: Array = []
	var applied := {}
	for mod: Dictionary in active(storage_dir, skipped):
		applied[mod["id"]] = true
	var reasons := {}
	var codes := {}
	for entry: Dictionary in skipped:
		reasons[entry["id"]] = entry["reason"]
		codes[entry["id"]] = entry

	var enabled := enabled_ids(storage_dir)
	var ids: Array = enabled.filter(func(id): return installed.has(id))
	for id in order:
		if not ids.has(id):
			ids.append(id)
	var out: Array = []
	for id: String in ids:
		var mod: Dictionary = installed[id]
		var manifest: Dictionary = mod["manifest"]
		var status := "disabled"
		var detail := ""
		if not mod["ok"]:
			status = "invalid"
			detail = "; ".join(mod["errors"])
		elif enabled.has(id):
			status = "active" if applied.has(id) else "skipped"
			detail = str(reasons.get(id, ""))
		out.append({
			"id": id, "dir": mod["dir"], "enabled": enabled.has(id), "status": status, "detail": detail,
			"reason_code": str(codes[id]["code"]) if codes.has(id) else "", "reason_arg": str(codes[id]["arg"]) if codes.has(id) else "",
			"name": str(manifest.get("name", "")) if str(manifest.get("name", "")) != "" else id,
			"version": str(manifest.get("version", "")), "author": str(manifest.get("author", "")),
			"description": str(manifest.get("description", "")),
			"games": manifest.get("games", GAMES), "engine": str(manifest.get("engine", "faithful")),
			"requires": manifest.get("requires", []), "cards": card_count(mod["dir"]),
			"scripts": manifest.get("scripts", []),
		})
	return out


static func card_count(mod_dir: String) -> int:
	var path := mod_dir.path_join("cards.json")
	if not FileAccess.file_exists(path):
		return 0
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Array:
		return 0
	return (json.data as Array).size()


## Activa un mod instalado y valido, poniendo antes (en orden) las dependencias instaladas
## que falten. Devuelve false si no existe, es invalido o no se pudo guardar.
static func enable(storage_dir: String, id: String) -> bool:
	var installed := {}
	for mod: Dictionary in discover(storage_dir):
		installed[mod["id"]] = mod
	if not installed.has(id) or not installed[id]["ok"]:
		return false
	var ids := enabled_ids(storage_dir)
	if ids.has(id):
		return true
	return set_enabled(storage_dir, _with_dependencies(ids, id, installed, []))


static func _with_dependencies(ids: Array, id: String, installed: Dictionary, visiting: Array) -> Array:
	if ids.has(id) or visiting.has(id):
		return ids
	visiting.append(id)
	var out := ids.duplicate()
	for dep: String in installed[id]["manifest"]["requires"]:
		if installed.has(dep) and installed[dep]["ok"]:
			out = _with_dependencies(out, dep, installed, visiting)
	if not out.has(id):
		out.append(id)
	return out


## Desactiva un mod. Los que dependan de el siguen activados pero quedan omitidos (con motivo).
static func disable(storage_dir: String, id: String) -> bool:
	var ids := enabled_ids(storage_dir)
	if not ids.has(id):
		return true
	ids.erase(id)
	return set_enabled(storage_dir, ids)


## Mueve un mod activado una posicion (-1 antes, +1 despues) entre los activados instalados.
static func move(storage_dir: String, id: String, delta: int) -> bool:
	var ids := enabled_ids(storage_dir)
	var at := ids.find(id)
	if at < 0 or delta == 0:
		return false
	var step := 1 if delta > 0 else -1
	var to := at + step
	while to >= 0 and to < ids.size() and not DirAccess.dir_exists_absolute(mods_dir(storage_dir).path_join(ids[to])):
		to += step   # salta los ids que ya no estan instalados
	if to < 0 or to >= ids.size():
		return false
	ids.remove_at(at)
	ids.insert(to, id)
	return set_enabled(storage_dir, ids)


## Borra la carpeta de un mod instalado y lo quita de la lista. Solo toca mods/<id>/.
## slots.json se conserva: si se vuelve a instalar, sus cartas recuperan los mismos ids.
static func remove(storage_dir: String, id: String) -> bool:
	if not valid_id(id):
		return false
	var path := mods_dir(storage_dir).path_join(id)
	if not DirAccess.dir_exists_absolute(path):
		return false
	if not delete_tree(path):
		return false
	return disable(storage_dir, id)


static func delete_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	var ok := true
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			ok = delete_tree(child) and ok
		else:
			ok = DirAccess.remove_absolute(child) == OK and ok
		name = dir.get_next()
	return DirAccess.remove_absolute(path) == OK and ok
