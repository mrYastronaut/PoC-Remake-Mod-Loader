class_name ModInstaller
extends RefCounted
## Instala un mod desde un .zip en <PoC Data>/mods/<id>/ sin salirse nunca de esa carpeta.
## El .zip trae mod.json en la raiz o dentro de una unica carpeta superior.
## Se extrae primero a una carpeta temporal oculta (.installing-<id>) y se renombra al final,
## asi un zip roto o hostil no deja un mod a medias.

const MAX_FILES := 5000
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_TOTAL_BYTES := 256 * 1024 * 1024
const MAX_PATH_LENGTH := 200


## Ruta relativa segura de una entrada del zip ("" si hay que rechazarla):
## sin barras invertidas (se normalizan), rutas absolutas, unidades, ".." ni segmentos vacios.
static func safe_relative(entry: String) -> String:
	var path := entry.replace("\\", "/")
	if path == "" or path.length() > MAX_PATH_LENGTH or path.begins_with("/") or path.contains(":"):
		return ""
	for segment in path.split("/"):
		if segment == "" or segment == "." or segment == "..":
			return ""
	return path


## {"ok": bool, "id": String, "exists": bool, "code": String, "error": String, "files": int}
## `code` es un identificador corto estable (la interfaz lo traduce); `error` es el detalle tecnico.
## `replace`: si el mod ya esta instalado, sustituirlo (la carpeta anterior se restaura si falla).
static func install_zip(storage_dir: String, zip_path: String, replace := false) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _fail("open", "No se pudo abrir el .zip")
	var result := _install(reader, storage_dir, replace)
	reader.close()
	return result


static func _install(reader: ZIPReader, storage_dir: String, replace: bool) -> Dictionary:
	var entries: Array = []
	var manifest_entry := ""
	var seen_manifest := 0
	for raw in reader.get_files():
		var entry := str(raw)
		if entry.ends_with("/"):
			continue
		var rel := safe_relative(entry)
		if rel == "":
			return _fail("path", "El .zip contiene una ruta no permitida: " + entry)
		if "__MACOSX" in rel.split("/") or rel.get_file() == ".DS_Store":
			continue
		entries.append({"entry": entry, "rel": rel})
		if rel == ModRegistry.MANIFEST or (rel.get_file() == ModRegistry.MANIFEST and rel.count("/") == 1):
			manifest_entry = rel
			seen_manifest += 1
	if seen_manifest == 0:
		return _fail("no_manifest", "El .zip no tiene mod.json en la raiz ni en una carpeta superior")
	if seen_manifest > 1:
		return _fail("many_manifests", "El .zip tiene mas de un mod.json")
	var prefix := manifest_entry.trim_suffix(ModRegistry.MANIFEST)
	var json := JSON.new()
	var raw_manifest := ""
	for item: Dictionary in entries:
		if item["rel"] == manifest_entry:
			raw_manifest = reader.read_file(item["entry"]).get_string_from_utf8()
	if json.parse(raw_manifest) != OK or not json.data is Dictionary:
		return _fail("manifest", "mod.json no es un objeto JSON valido")
	var id := str((json.data as Dictionary).get("id", ""))
	var parsed := ModRegistry.parse_manifest(raw_manifest, id)
	if not parsed["ok"]:
		return _fail("manifest", "mod.json invalido: " + "; ".join(parsed["errors"]), id)
	var selected: Array = entries.filter(func(item): return (item["rel"] as String).begins_with(prefix))
	if selected.size() > MAX_FILES:
		return _fail("too_many", "El .zip tiene demasiados archivos (maximo %d)" % MAX_FILES, id)
	var mods := ModRegistry.mods_dir(storage_dir)
	var target := mods.path_join(id)
	if DirAccess.dir_exists_absolute(target) and not replace:
		return {"ok": false, "id": id, "exists": true, "code": "exists", "error": "El mod ya esta instalado", "files": 0}
	var temp := mods.path_join(".installing-" + id)
	if DirAccess.dir_exists_absolute(temp):
		ModRegistry.delete_tree(temp)
	if DirAccess.make_dir_recursive_absolute(temp) != OK:
		return _fail("write", "No se pudo crear la carpeta temporal en " + mods, id)
	var total := 0
	for item: Dictionary in selected:
		var rel: String = (item["rel"] as String).trim_prefix(prefix)
		var bytes := reader.read_file(item["entry"])
		total += bytes.size()
		if bytes.size() > MAX_FILE_BYTES or total > MAX_TOTAL_BYTES:
			ModRegistry.delete_tree(temp)
			return _fail("too_big", "El .zip es demasiado grande (maximo %d MB en total)" % (MAX_TOTAL_BYTES / 1048576), id)
		var destination := temp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			ModRegistry.delete_tree(temp)
			return _fail("write", "No se pudo escribir " + rel, id)
		file.store_buffer(bytes)
		file.close()
	var cards_path := temp.path_join(ModCards.FRAGMENT)
	if FileAccess.file_exists(cards_path):
		var cards_json := JSON.new()
		if cards_json.parse(FileAccess.get_file_as_string(cards_path)) != OK or not cards_json.data is Array:
			ModRegistry.delete_tree(temp)
			return _fail("cards", "cards.json no es una lista JSON valida", id)
	var backup := mods.path_join(".old-" + id)
	if DirAccess.dir_exists_absolute(target):
		if DirAccess.dir_exists_absolute(backup):
			ModRegistry.delete_tree(backup)
		if DirAccess.rename_absolute(target, backup) != OK:
			ModRegistry.delete_tree(temp)
			return _fail("replace", "No se pudo reemplazar el mod existente", id)
	if DirAccess.rename_absolute(temp, target) != OK:
		if DirAccess.dir_exists_absolute(backup):
			DirAccess.rename_absolute(backup, target)
		ModRegistry.delete_tree(temp)
		return _fail("write", "No se pudo mover el mod a su carpeta", id)
	if DirAccess.dir_exists_absolute(backup):
		ModRegistry.delete_tree(backup)
	return {"ok": true, "id": id, "exists": false, "code": "", "error": "", "files": selected.size()}


static func _fail(code: String, message: String, id := "") -> Dictionary:
	return {"ok": false, "id": id, "exists": false, "code": code, "error": message, "files": 0}
